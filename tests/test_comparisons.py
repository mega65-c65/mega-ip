"""Checks that must look at every byte, and timer intervals.

Written from tests/mutate.py survivors: these loops and branches were only
exercised with values that differ in the first byte (or not at all), so a
mutant that stopped after one byte, or flipped a timer branch, went
unnoticed.
"""

import struct
import unittest

import net
from stack import ACK, FIN, PSH, SYN, Peer, Stack
from test_dhcp import wait_for_dhcp


def ping(s, p, dst_mac):
    icmp = struct.pack('!BBHHH', 8, 0, 0, 1, 1) + b'x'
    icmp = icmp[:2] + struct.pack('!H', net.checksum(icmp)) + icmp[4:]
    s.deliver(net.ethernet(dst_mac, p.mac, net.ETH_IPV4,
                           net.ipv4(p.ip, s.peek('LOCAL_IP', 4), net.PROTO_ICMP, icmp)))
    s.poll()
    return s.sent()


def one_byte_off(b, i):
    b = bytearray(b)
    b[i] ^= 0x01
    return bytes(b)


class EveryByteCompared(unittest.TestCase):
    def test_destination_mac(self):
        s = Stack.ready()
        p = Peer(s)
        s.deliver(p.arp_request_for_stack())
        s.poll()
        s.sent()
        self.assertEqual(len(ping(s, p, s.mac)), 1)                 # control
        for i in range(6):
            with self.subTest(byte=i):
                self.assertEqual(ping(s, p, one_byte_off(s.mac, i)), [])

    def test_peer_mac_copied_in_full(self):
        """Frames to the peer carry all six bytes of its MAC, also when an
        earlier peer's MAC differs in every byte."""
        s = Stack.ready()
        first = Peer(s, ip=(192, 168, 1, 60), mac=bytes([0x02, 0x11, 0x22, 0x33, 0x44, 0x55]))
        first.connect_stack()
        s.call('ETH_TCP_FORCE_CLOSE')
        s.call('ETH_TCP_LISTEN_START', 0, 80)
        c = Peer(s, ip=(192, 168, 1, 61), mac=bytes([0x0A, 0x9B, 0xCC, 0xDD, 0xEE, 0xF0]),
                 port=5000)
        synack = c.open_to_listener(80)
        self.assertEqual(bytes(synack.dst), c.mac)
        c.send(PSH | ACK, b'x')
        s.poll()
        for f in s.sent():
            self.assertEqual(bytes(f.dst), c.mac)

    def test_peer_mac_restored_after_a_frame_to_another_host(self):
        """A reply to another host overwrites the TX frame's destination; the
        next segment to the peer must restore all six bytes."""
        s = Stack.ready()
        p = Peer(s, mac=bytes([0x02, 0x11, 0x22, 0x33, 0x44, 0x55]))
        p.connect_stack()
        other = Peer(s, ip=(192, 168, 1, 88), mac=bytes([0x0A, 0x9B, 0xCC, 0xDD, 0xEE, 0xF0]))
        s.deliver(other.arp_request_for_stack())
        s.poll()
        s.sent()                                              # the ARP reply
        self.assertEqual(len(ping(s, other, s.mac)), 1)       # TX frame now to `other`
        p.send(PSH | ACK, b'after')
        s.poll()
        acks = [f for f in s.sent() if f.tcp]
        self.assertEqual(bytes(acks[-1].dst), p.mac)

    def test_dns_reply_destination_ip(self):
        from stack import DNS_STATE_WAIT, dns_state, start_lookup
        for i in range(4):
            with self.subTest(byte=i):
                s = Stack.ready()
                dns, q = start_lookup(s)
                s.deliver(net.dns_reply(q, (6, 6, 6, 6), dns.mac, dns.ip, s.mac,
                                        dst_ip=one_byte_off(s.peek('LOCAL_IP', 4), i)))
                s.poll()
                self.assertEqual(dns_state(s), DNS_STATE_WAIT)

    def segment_from(self, s, p, src_ip, dst_ip):
        t = net.tcp(src_ip, dst_ip, p.port, p.local_port, p.seq, p.ack, PSH | ACK, b'spoof')
        return net.ethernet(s.mac, p.mac, net.ETH_IPV4, net.ipv4(src_ip, dst_ip, net.PROTO_TCP, t))

    def test_segment_source_ip(self):
        for i in range(4):
            with self.subTest(byte=i):
                s = Stack.ready()
                p = Peer(s)
                p.connect_stack()
                s.deliver(self.segment_from(s, p, one_byte_off(bytes(p.ip), i),
                                            s.peek('LOCAL_IP', 4)))
                s.poll()
                self.assertEqual(s.read_received(), b'')
                self.assertEqual(s.state, 'ESTABLISHED')

    def test_segment_destination_ip(self):
        for i in range(4):
            with self.subTest(byte=i):
                s = Stack.ready()
                p = Peer(s)
                p.connect_stack()
                s.deliver(self.segment_from(s, p, bytes(p.ip),
                                            one_byte_off(s.peek('LOCAL_IP', 4), i)))
                s.poll()
                self.assertEqual(s.read_received(), b'')

    def dhcp_until_request(self):
        s = Stack.ready()
        s.call('ETH_DHCP_START')
        xid, _ = wait_for_dhcp(s, net.DHCP_DISCOVER)
        s.deliver(net.dhcp_reply(xid, s.mac, net.DHCP_OFFER, (192, 168, 1, 100), (192, 168, 1, 1)))
        wait_for_dhcp(s, net.DHCP_REQUEST)
        return s, xid

    def test_dhcp_ack_client_hardware_address(self):
        for i in range(6):
            with self.subTest(byte=i):
                s, xid = self.dhcp_until_request()
                s.deliver(net.dhcp_reply(xid, one_byte_off(s.mac, i), net.DHCP_ACK,
                                         (192, 168, 1, 100), (192, 168, 1, 1)))
                s.poll(2)
                self.assertEqual(tuple(s.peek('LOCAL_IP', 4)), (0, 0, 0, 0))

    def test_subnet_mask_contiguity_in_every_byte(self):
        for mask, ok in (((255, 255, 255, 254), True), ((255, 255, 255, 1), False),
                         ((255, 255, 0, 255), False), ((255, 0, 255, 0), False),
                         ((0, 255, 255, 255), False), ((255, 255, 254, 0), True)):
            with self.subTest(mask=mask):
                s, xid = self.dhcp_until_request()
                s.deliver(net.dhcp_reply(xid, s.mac, net.DHCP_ACK, (192, 168, 1, 100),
                                         (192, 168, 1, 1), mask=mask))
                s.poll(2)
                bound = tuple(s.peek('LOCAL_IP', 4)) == (192, 168, 1, 100)
                self.assertEqual(bound, ok)


class RetryIntervals(unittest.TestCase):
    def intervals(self, s, flag, until):
        times, frame = [], [0]

        def on_frame(sent):
            times.extend(frame[0] for f in sent if f.tcp and f.tcp['flags'] & flag)

        def stop():
            frame[0] += 1
            return until()
        s.run_frames(3000, on_frame=on_frame, until=stop)
        # first retransmit counts from the original send (frame 0)
        return [b - a for a, b in zip([0] + times, times)]

    def test_fin_retry_interval(self):
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        s.call('ETH_TCP_DISCONNECT')
        s.sent()
        gaps = self.intervals(s, FIN, lambda: s.state == 'CLOSED')
        self.assertTrue(gaps)
        for g in gaps:
            self.assertAlmostEqual(g, s.asm['TCP_TX_RETRY_TICKS'], delta=2)

    def test_synack_retry_interval(self):
        s = Stack.ready()
        s.call('ETH_TCP_LISTEN_START', 0, 80)
        Peer(s, port=5000).open_to_listener(80)
        gaps = self.intervals(s, SYN, lambda: s.state != 'SYN_RECEIVED')
        self.assertTrue(gaps)
        for g in gaps:
            self.assertAlmostEqual(g, s.asm['CONNECT_SYN_RETRY_TICKS'], delta=2)


class WindowUpdateThreshold(unittest.TestCase):
    def test_update_only_after_window_grows_by_threshold(self):
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        for _ in range(7):                      # 3500 bytes: window shrinks to 595
            p.send(PSH | ACK, b'z' * 500)
            s.poll()
        last = [f for f in s.sent() if f.tcp][-1].tcp['window']
        grow = s.asm['WINUPDATE_GROW_LO'] | (s.asm['WINUPDATE_GROW_HI'] << 8)
        s.call('ETH_RBUF_GET_BLOCK', 0, 0, 2, grow - 1)
        s.poll()
        self.assertEqual(s.sent(), [])           # grown by less than the threshold
        s.call('ETH_RBUF_GET_BLOCK', 0, 0, 2, 1)
        s.poll()
        updates = [f for f in s.sent() if f.tcp]
        self.assertEqual(len(updates), 1)
        self.assertEqual(updates[0].tcp['window'], last + grow)
        s.poll()
        self.assertEqual(s.sent(), [])           # no repeats


class LongHostName(unittest.TestCase):
    def test_astr_longer_than_the_name_buffer_is_rejected(self):
        s = Stack.ready()
        s.set_astr('a' * 60 + '.' + 'b' * 60 + '.' + 'c' * 60 + '.com')
        self.assertEqual(s.call(0x2063).a, 0)
        s.poll()
        self.assertEqual(s.sent(), [])


if __name__ == '__main__':
    unittest.main()
