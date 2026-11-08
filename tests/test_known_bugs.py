"""Tests for defects found in code review that are not fixed yet.

Each defect test is marked @unittest.expectedFailure with the reason, so the
suite (and build.bat) stays green while the bug is known.  When a fix lands
the test passes, unittest reports an "unexpected success" and the run fails:
remove the marker then.  Each defect has a control test showing the same
path works in the ordinary case, so a failure here points at the defect and
not at the harness.
"""

import unittest

import net
from stack import ACK, FIN, PSH, SYN, Peer, Stack

DNS_STATE_WAIT, DNS_STATE_DONE = 1, 2


def start_lookup(s, host='example.com'):
    """Start a DNS lookup and answer the resolver's ARP; return (resolver, query)."""
    dns = Peer(s, ip=(192, 168, 1, 53), mac=b'\x02\x00\x00\x00\x00\x53')
    s.call('ETH_SET_PRIMARY_DNS', *dns.ip)
    s.set_host(host)
    s.call('DNS_RESOLVE_START')
    for _ in range(200):
        s.poll()
        for f in s.sent():
            if f.arp and f.arp['op'] == 1 and tuple(f.arp['tpa']) == dns.ip:
                s.deliver(dns.arp_reply_to(f))
            elif f.udp and f.udp['dport'] == 53:
                return dns, f
        s.m.advance_frames(2)
    raise AssertionError('no DNS query sent')


def dns_state(s):
    return s.call('ETH_GET_DNS_STATE').a


class OutOfOrderSlot(unittest.TestCase):
    """The OOO slot keeps one future segment until the gap before it fills."""

    def deliver_out_of_order(self, rcv_nxt):
        s = Stack.ready()
        p = Peer(s)
        p.seq = (rcv_nxt - 1) & 0xFFFFFFFF          # SYN takes one number
        p.connect_stack()
        first, second = b'A' * 32, b'B' * 16
        s.deliver(p.segment(PSH | ACK, second, seq=(rcv_nxt + 32) & 0xFFFFFFFF))
        s.poll(2)
        s.deliver(p.segment(PSH | ACK, first, seq=rcv_nxt))
        s.poll(2)
        return s.read_received(), first + second

    def test_control_gap_filled_mid_sequence_space(self):
        got, want = self.deliver_out_of_order(0x00100000)
        self.assertEqual(got, want)

    @unittest.expectedFailure
    def test_gap_filled_across_sequence_wrap(self):
        """eth.asm TCP_OOO_TRY_FLUSH compares sequence numbers as unsigned
        bytes, so a future segment just past the 2^32 wrap looks stale and is
        dropped (the peer has to retransmit it)."""
        got, want = self.deliver_out_of_order(0xFFFFFFE0)
        self.assertEqual(got, want)


class FinWait1Data(unittest.TestCase):
    """Data that arrives after we sent our FIN, before the peer ACKs it."""

    def test_control_data_with_fin_ack(self):
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        s.call('ETH_TCP_DISCONNECT')
        fin = [f for f in s.sent() if f.tcp and f.tcp['flags'] & FIN][0]
        p.ack = fin.tcp['seq'] + 1                 # ACKs our FIN
        p.send(PSH | ACK, b'hi')
        s.poll()
        self.assertEqual(s.read_received(), b'hi')

    @unittest.expectedFailure
    def test_data_before_peer_acks_our_fin(self):
        """eth.asm FIN_WAIT_1 drops in-sequence data whose ACK doesn't yet
        cover our FIN (bne _done after TCP_SEQ_CMP_SEG_ACK_LOCAL_ISN), without
        ACKing it."""
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        s.call('ETH_TCP_DISCONNECT')
        fin = [f for f in s.sent() if f.tcp and f.tcp['flags'] & FIN][0]
        p.ack = fin.tcp['seq']                     # peer hasn't seen the FIN yet
        p.send(PSH | ACK, b'hi')
        s.poll()
        self.assertEqual(s.read_received(), b'hi')
        acks = [f for f in s.sent() if f.tcp]
        self.assertTrue(acks and acks[-1].tcp['ack'] == p.seq)


class SynReceivedDataAck(unittest.TestCase):
    """The client's handshake ACK may already carry data."""

    def test_control_pure_ack_then_data(self):
        s = Stack.ready()
        s.call('ETH_TCP_LISTEN_START', 0x00, 80)
        p = Peer(s, port=5000)
        p.open_to_listener(80)
        p.send(ACK)
        s.poll()
        self.assertEqual(s.state, 'ESTABLISHED')
        p.send(PSH | ACK, b'GET /')
        s.poll()
        self.assertEqual(s.read_received(), b'GET /')

    @unittest.expectedFailure
    def test_first_ack_carries_data(self):
        """eth.asm SYN_RECEIVED accepts only a pure ACK; a final ACK with data
        (common when the pure ACK was lost) is dropped."""
        s = Stack.ready()
        s.call('ETH_TCP_LISTEN_START', 0x00, 80)
        p = Peer(s, port=5000)
        p.open_to_listener(80)
        p.send(PSH | ACK, b'GET /')
        s.poll()
        self.assertEqual(s.state, 'ESTABLISHED')
        self.assertEqual(s.read_received(), b'GET /')


class DnsReplyDestination(unittest.TestCase):
    def test_control_reply_to_us_resolves(self):
        s = Stack.ready()
        dns, query = start_lookup(s)
        s.deliver(net.dns_reply(query, (93, 184, 216, 34), dns.mac, dns.ip, s.mac))
        s.poll()
        self.assertEqual(dns_state(s), DNS_STATE_DONE)
        c = s.call('ETH_GET_DNS_RESULT_IP')
        self.assertEqual((c.a, c.x, c.y, c.z), (93, 184, 216, 34))

    @unittest.expectedFailure
    def test_reply_to_another_ip_is_ignored(self):
        """ipv4.asm/dns.asm never check the IPv4 destination of a UDP reply,
        so a frame to our MAC but another IP is accepted as the answer."""
        s = Stack.ready()
        dns, query = start_lookup(s)
        s.deliver(net.dns_reply(query, (6, 6, 6, 6), dns.mac, dns.ip, s.mac,
                                dst_ip=(192, 168, 1, 99)))
        s.poll()
        self.assertEqual(dns_state(s), DNS_STATE_WAIT)


class EmptyAstrLookup(unittest.TestCase):
    def test_control_named_lookup_starts(self):
        s = Stack.ready()
        s.set_astr('example.com')
        self.assertEqual(s.call('ETH_DNS_START_ASTR').a, 1)

    @unittest.expectedFailure
    def test_empty_astr_does_not_reuse_previous_host(self):
        """COPY_ASTR_TO_DNS_HOST returns early on an empty A$ and leaves the
        previous name in host_str, so the lookup silently starts for it."""
        s = Stack.ready()
        s.set_host('previous.example')
        s.set_astr('')
        self.assertEqual(s.call('ETH_DNS_START_ASTR').a, 0)


if __name__ == '__main__':
    unittest.main()
