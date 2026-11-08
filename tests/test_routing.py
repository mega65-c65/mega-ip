"""Routing, frame filtering, mixed traffic and the send queue."""

import struct
import unittest

import net
from stack import ACK, PSH, SYN, Peer, Responder, Stack, dns_state

GATEWAY_MAC = bytes([2, 0, 0, 0, 0, 1])


def connect_to(s, ip, port=80):
    s.call('ETH_SET_REMOTE_IP', *ip)
    s.call('ETH_SET_REMOTE_PORT', port >> 8, port & 0xFF)
    s.call('ETH_TCP_CONNECT_START')


class Routing(unittest.TestCase):
    def first_arp_target(self, s):
        s.call('ETH_CONNECT_POLL')
        arps = [f for f in s.sent() if f.arp and f.arp['op'] == 1]
        self.assertTrue(arps)
        return tuple(arps[0].arp['tpa'])

    def test_off_subnet_goes_via_gateway(self):
        s = Stack.ready()
        connect_to(s, (8, 8, 4, 4))
        self.assertEqual(self.first_arp_target(s), Stack.GATEWAY)

    def test_on_subnet_goes_direct(self):
        s = Stack.ready()
        connect_to(s, (192, 168, 1, 77))
        self.assertEqual(self.first_arp_target(s), (192, 168, 1, 77))

    def test_wider_mask_makes_host_local(self):
        s = Stack.ready()
        s.call('ETH_SET_SUBNET_MASK', 255, 255, 0, 0)
        connect_to(s, (192, 168, 5, 5))
        self.assertEqual(self.first_arp_target(s), (192, 168, 5, 5))

    def test_off_subnet_frames_use_gateway_mac_and_remote_ip(self):
        s = Stack.ready()
        gw = Peer(s, ip=Stack.GATEWAY, mac=GATEWAY_MAC)
        connect_to(s, (8, 8, 4, 4))
        syn = None
        for _ in range(10):
            s.call('ETH_CONNECT_POLL')
            for f in s.sent():
                if f.arp and f.arp['op'] == 1:
                    s.deliver(gw.arp_reply_to(f))
                elif f.tcp and f.tcp['flags'] & SYN:
                    syn = f
            if syn:
                break
        self.assertIsNotNone(syn)
        self.assertEqual(bytes(syn.dst), GATEWAY_MAC)
        self.assertEqual(tuple(syn.ip['dst']), (8, 8, 4, 4))


class Filtering(unittest.TestCase):
    def ping_frame(self, s, p, dst_mac):
        icmp = struct.pack('!BBHHH', 8, 0, 0, 1, 1) + b'x'
        icmp = icmp[:2] + struct.pack('!H', net.checksum(icmp)) + icmp[4:]
        return net.ethernet(dst_mac, p.mac, net.ETH_IPV4,
                            net.ipv4(p.ip, s.peek('LOCAL_IP', 4), net.PROTO_ICMP, icmp))

    def setUp(self):
        self.s = Stack.ready()
        self.p = Peer(self.s)
        self.s.deliver(self.p.arp_request_for_stack())
        self.s.poll()
        self.s.sent()

    def test_frames_to_our_mac_are_processed(self):
        self.s.deliver(self.ping_frame(self.s, self.p, self.s.mac))
        self.s.poll()
        self.assertEqual(len(self.s.sent()), 1)

    def test_multicast_frames_are_ignored(self):
        mc = b'\x01\x00\x5e\x00\x00\x01'
        for listening in (False, True):
            with self.subTest(listening=listening):
                if listening:
                    self.s.call('ETH_TCP_LISTEN_START', 0, 80)
                self.s.deliver(self.ping_frame(self.s, self.p, mc))
                self.s.poll()
                self.assertEqual(self.s.sent(), [])

    def test_arp_request_for_another_host_is_ignored(self):
        body = net.arp(1, self.p.mac, self.p.ip, bytes(6), (192, 168, 1, 99))
        self.s.deliver(net.ethernet(net.BROADCAST, self.p.mac, net.ETH_ARP, body))
        self.s.poll()
        self.assertEqual(self.s.sent(), [])


class MixedTraffic(unittest.TestCase):
    def setUp(self):
        self.s = Stack.ready()
        self.p = Peer(self.s)
        self.p.connect_stack()

    def test_arp_request_during_transfer(self):
        s, p = self.s, self.p
        other = Peer(s, ip=(192, 168, 1, 88), mac=bytes([2, 0, 0, 0, 0, 0x88]))
        p.send(PSH | ACK, b'part1')
        s.deliver(other.arp_request_for_stack())
        p.send(PSH | ACK, b'part2')
        s.poll()
        sent = s.sent()
        arp = [f for f in sent if f.arp]
        self.assertEqual(len(arp), 1)
        self.assertEqual(bytes(arp[0].dst), other.mac)
        self.assertEqual(s.read_received(), b'part1part2')
        self.assertEqual([f for f in sent if f.tcp][-1].tcp['ack'], p.seq)

    def test_ping_during_transfer(self):
        s, p = self.s, self.p
        icmp = struct.pack('!BBHHH', 8, 0, 0, 1, 1) + b'x'
        icmp = icmp[:2] + struct.pack('!H', net.checksum(icmp)) + icmp[4:]
        p.send(PSH | ACK, b'data')
        s.deliver(net.ethernet(s.mac, p.mac, net.ETH_IPV4,
                               net.ipv4(p.ip, s.peek('LOCAL_IP', 4), net.PROTO_ICMP, icmp)))
        s.poll()
        sent = s.sent()
        self.assertEqual(len([f for f in sent if f.ip and f.ip['proto'] == 1]), 1)
        self.assertEqual(s.read_received(), b'data')

    def test_dns_lookup_while_connected(self):
        s, p = self.s, self.p
        resolver = Peer(s, ip=(192, 168, 1, 53), mac=bytes([2, 0, 0, 0, 0, 0x53]))
        s.eth.on_transmit = Responder(s, resolver=resolver,
                                      answers={'example.com': (1, 2, 3, 4)})
        s.call('ETH_SET_PRIMARY_DNS', *resolver.ip)
        s.set_host('example.com')
        s.call('DNS_RESOLVE_START')
        p.send(PSH | ACK, b'while resolving')
        s.run_frames(200, until=lambda: dns_state(s) != 1)
        self.assertEqual(dns_state(s), 2)
        self.assertEqual(s.read_received(), b'while resolving')
        self.assertEqual(s.state, 'ESTABLISHED')
        self.assertEqual(tuple(s.peek('REMOTE_IP', 4)), p.ip)   # connection untouched


class SendQueue(unittest.TestCase):
    def test_queue_fills_then_refuses(self):
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        results = [s.send_data(bytes([0x30 + i]) * 100) for i in range(4)]
        self.assertEqual(results, [0, 0, 0, 1])        # 1 in flight + 200 queued
        self.assertEqual(s.peek('TXQ_COUNT'), 200)

    def test_queued_data_delivered_in_order_once(self):
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        want = b''
        for i in range(3):
            chunk = bytes([0x41 + i]) * 100
            self.assertEqual(s.send_data(chunk), 0)
            want += chunk
        got, next_seq = b'', None
        for _ in range(10):
            s.poll()
            for f in s.sent():
                if f.tcp and f.tcp['payload']:
                    if next_seq is not None:          # contiguous, no repeats
                        self.assertEqual(f.tcp['seq'], next_seq)
                    got += f.tcp['payload']
                    next_seq = f.tcp['seq'] + len(f.tcp['payload'])
                    p.ack = next_seq
                    p.send(ACK)
            if s.call('ETH_TCP_TX_IDLE').a:
                break
        self.assertEqual(got, want)


if __name__ == '__main__':
    unittest.main()
