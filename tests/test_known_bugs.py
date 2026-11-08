"""Defects found in code review, each with a control test.

All of these were confirmed here first as expected failures and are now
fixed, so the tests guard against regressions.  To record a newly found
bug, add a test marked @unittest.expectedFailure with the reason: the
suite (and build.bat) stays green while it is known, and when a fix lands
the test reports an unexpected success and the run fails, prompting removal
of the marker in the same commit as the fix.  Each defect has a control
test showing the same path works in the ordinary case, so a failure here
points at the defect and not at the harness.
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

    def test_gap_filled_across_sequence_wrap(self):
        """A future segment just past the 2^32 wrap is kept until the gap
        fills (TCP_OOO_TRY_FLUSH used to compare unsigned and drop it)."""
        got, want = self.deliver_out_of_order(0xFFFFFFE0)
        self.assertEqual(got, want)

    def test_passed_segment_frees_slot_across_wrap(self):
        """A saved segment that RCV.NXT passes across the wrap is released as
        stale, so the slot can hold the next out-of-order segment (an
        unsigned compare kept it as 'future' forever)."""
        s = Stack.ready()
        p = Peer(s)
        start = 0xFFFFFFE0
        p.seq = start - 1
        p.connect_stack()
        s.deliver(p.segment(PSH | ACK, b'x' * 16, seq=0xFFFFFFF0))   # saved
        s.poll(2)
        s.deliver(p.segment(PSH | ACK, b'A' * 64, seq=start))         # covers it
        s.poll(2)
        self.assertEqual(s.peek('TCP_OOO_VALID'), 0)
        s.deliver(p.segment(PSH | ACK, b'C' * 8, seq=0x40))           # next gap
        s.poll(2)
        s.deliver(p.segment(PSH | ACK, b'B' * 32, seq=0x20))
        s.poll(2)
        self.assertEqual(s.read_received(), b'A' * 64 + b'B' * 32 + b'C' * 8)


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

    def test_data_before_peer_acks_our_fin(self):
        """In-sequence data whose ACK doesn't yet cover our FIN is taken and
        ACKed, staying in FIN_WAIT_1 (it used to be dropped silently)."""
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
        self.assertEqual(s.state, 'FIN_WAIT_1')

    def test_simultaneous_close(self):
        """The peer's FIN arrives before it ACKs ours: ACK it and finish in
        TIME_WAIT."""
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        s.call('ETH_TCP_DISCONNECT')
        fin = [f for f in s.sent() if f.tcp and f.tcp['flags'] & FIN][0]
        p.ack = fin.tcp['seq']
        p.send(FIN | ACK)
        s.poll()
        acks = [f for f in s.sent() if f.tcp]
        self.assertTrue(acks and acks[-1].tcp['ack'] == p.seq)
        self.assertEqual(s.state, 'TIME_WAIT')

    def test_ack_beyond_snd_nxt_is_ignored(self):
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        s.call('ETH_TCP_DISCONNECT')
        fin = [f for f in s.sent() if f.tcp and f.tcp['flags'] & FIN][0]
        p.ack = fin.tcp['seq'] + 5
        p.send(PSH | ACK, b'hi')
        s.poll()
        self.assertEqual(s.read_received(), b'')
        self.assertEqual(s.state, 'FIN_WAIT_1')


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

    def test_first_ack_carries_data(self):
        """A final handshake ACK that carries data completes the handshake and
        delivers the data (it used to be dropped)."""
        s = Stack.ready()
        s.call('ETH_TCP_LISTEN_START', 0x00, 80)
        p = Peer(s, port=5000)
        p.open_to_listener(80)
        p.send(PSH | ACK, b'GET /')
        s.poll()
        self.assertEqual(s.state, 'ESTABLISHED')
        self.assertEqual(s.read_received(), b'GET /')
        acks = [f for f in s.sent() if f.tcp]
        self.assertTrue(acks and acks[-1].tcp['ack'] == p.seq)

    def test_first_ack_carries_fin(self):
        s = Stack.ready()
        s.call('ETH_TCP_LISTEN_START', 0x00, 80)
        p = Peer(s, port=5000)
        p.open_to_listener(80)
        p.send(FIN | ACK)
        s.poll()
        self.assertEqual(s.state, 'CLOSE_WAIT')
        self.assertEqual(s.peek('TCP_ACCEPT_FLAGS') & 1, 1)

    def test_ack_with_wrong_ack_number_is_ignored(self):
        s = Stack.ready()
        s.call('ETH_TCP_LISTEN_START', 0x00, 80)
        p = Peer(s, port=5000)
        p.open_to_listener(80)
        p.send(PSH | ACK, b'GET /', ack=p.ack + 7)
        s.poll()
        self.assertEqual(s.state, 'SYN_RECEIVED')
        self.assertEqual(s.read_received(), b'')


class DnsReplyDestination(unittest.TestCase):
    def test_control_reply_to_us_resolves(self):
        s = Stack.ready()
        dns, query = start_lookup(s)
        s.deliver(net.dns_reply(query, (93, 184, 216, 34), dns.mac, dns.ip, s.mac))
        s.poll()
        self.assertEqual(dns_state(s), DNS_STATE_DONE)
        c = s.call('ETH_GET_DNS_RESULT_IP')
        self.assertEqual((c.a, c.x, c.y, c.z), (93, 184, 216, 34))

    def test_reply_to_another_ip_is_ignored(self):
        """A DNS answer sent to our MAC but another IPv4 address is ignored
        (DNS_UDP_IN used to check only the source)."""
        s = Stack.ready()
        dns, query = start_lookup(s)
        s.deliver(net.dns_reply(query, (6, 6, 6, 6), dns.mac, dns.ip, s.mac,
                                dst_ip=(192, 168, 1, 99)))
        s.poll()
        self.assertEqual(dns_state(s), DNS_STATE_WAIT)
        # the real answer still resolves afterwards
        s.deliver(net.dns_reply(query, (93, 184, 216, 34), dns.mac, dns.ip, s.mac))
        s.poll()
        self.assertEqual(dns_state(s), DNS_STATE_DONE)


class EmptyAstrLookup(unittest.TestCase):
    def test_control_named_lookup_starts(self):
        s = Stack.ready()
        s.set_astr('example.com')
        self.assertEqual(s.call('ETH_DNS_START_ASTR').a, 1)

    def test_empty_astr_does_not_reuse_previous_host(self):
        """An empty A$ doesn't start a lookup (COPY_ASTR_TO_DNS_HOST used to
        leave the previous name in host_str)."""
        s = Stack.ready()
        s.set_host('previous.example')
        s.set_astr('')
        self.assertEqual(s.call('ETH_DNS_START_ASTR').a, 0)
        self.assertEqual(s.sent(), [])

    def test_blocking_lookup_with_empty_astr_fails_at_once(self):
        s = Stack.ready()
        s.set_host('previous.example')
        s.set_astr('')
        c = s.call('ETH_DNS_LOOKUP', max_instructions=50_000)
        self.assertEqual(c.a, 0)
        self.assertEqual(s.sent(), [])


if __name__ == '__main__':
    unittest.main()
