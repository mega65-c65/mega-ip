"""Segments as real hosts send them: TCP options, timestamps, overlapping
retransmissions, keepalive probes, a peer's zero window."""

import unittest

import net
from net import LINUX_SYN_OPTIONS, TIMESTAMP_OPTIONS
from stack import ACK, PSH, SYN, Peer, Stack


def connect_with_synack_options(s, p, options):
    s.call('ETH_SET_REMOTE_IP', *p.ip)
    s.call('ETH_SET_REMOTE_PORT', 0, p.port)
    s.call('ETH_TCP_CONNECT_START')
    sent = []
    for _ in range(20):
        s.call('ETH_CONNECT_POLL')
        for f in s.sent():
            sent.append(f)
            if f.arp and f.arp['op'] == 1:
                s.deliver(p.arp_reply_to(f))
            elif f.tcp and f.tcp['flags'] & SYN:
                p.local_port, p.ack = f.tcp['sport'], f.tcp['seq'] + 1
                s.deliver(p.segment(SYN | ACK, options=options))
                p.seq += 1
        if s.state == 'ESTABLISHED':
            break
    return sent


class TcpOptions(unittest.TestCase):
    def test_connect_to_peer_sending_linux_syn_ack_options(self):
        s = Stack.ready()
        p = Peer(s)
        sent = connect_with_synack_options(s, p, LINUX_SYN_OPTIONS)
        self.assertEqual(s.state, 'ESTABLISHED')
        final = [f for f in sent if f.tcp and f.tcp['flags'] == ACK]
        self.assertTrue(final, 'no final handshake ACK')
        self.assertEqual(final[-1].tcp['ack'], p.seq)

    def test_our_syn_has_no_options_we_cant_honour(self):
        """We send a plain 20-byte header, so peers never turn on window
        scaling, SACK or timestamps for us."""
        s = Stack.ready()
        p = Peer(s)
        sent = connect_with_synack_options(s, p, LINUX_SYN_OPTIONS)
        syn = [f for f in sent if f.tcp and f.tcp['flags'] & SYN][0]
        self.assertEqual(syn.raw[14 + 20 + 12] >> 4, 5)

    def test_accept_client_syn_with_options(self):
        s = Stack.ready()
        s.call('ETH_TCP_LISTEN_START', 0, 80)
        c = Peer(s, port=5000)
        c.local_port = 80
        s.deliver(c.arp_request_for_stack())
        s.poll()
        s.sent()
        c.send(SYN, options=LINUX_SYN_OPTIONS)
        s.poll()
        synack = [f for f in s.sent() if f.tcp and f.tcp['flags'] & SYN]
        self.assertEqual(len(synack), 1)
        c.ack = synack[0].tcp['seq'] + 1
        c.send(PSH | ACK, b'GET /')
        s.poll()
        self.assertEqual(s.state, 'ESTABLISHED')
        self.assertEqual(s.read_received(), b'GET /')

    def test_data_with_timestamp_options(self):
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        p.send(PSH | ACK, b'hello', options=TIMESTAMP_OPTIONS)
        s.poll()
        self.assertEqual(s.read_received(), b'hello')
        self.assertEqual([f for f in s.sent() if f.tcp][-1].tcp['ack'], p.seq)

    def test_pure_ack_with_options_is_quiet(self):
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        p.send(ACK, options=TIMESTAMP_OPTIONS)
        s.poll()
        self.assertEqual(s.sent(), [])


class SegmentSizes(unittest.TestCase):
    def test_segment_lengths_around_byte_boundaries(self):
        """TCP lengths whose low byte is below the 20-byte minimum header
        (256-275) are valid; the minimum-length check must look at the high
        byte too."""
        for payload_len in (1, 235, 236, 240, 255, 256, 1000):
            with self.subTest(payload=payload_len):
                s = Stack.ready()
                p = Peer(s)
                p.connect_stack()
                data = bytes((i * 13) & 0xFF for i in range(payload_len))
                p.send(PSH | ACK, data)
                s.poll()
                self.assertEqual(s.read_received(), data)


class Retransmissions(unittest.TestCase):
    def test_overlapping_retransmission_delivers_only_new_bytes(self):
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        base = p.seq
        p.send(PSH | ACK, b'abcdef')
        s.poll()
        s.sent()
        s.deliver(p.segment(PSH | ACK, b'cdefghij', seq=base + 2))
        s.poll()
        self.assertEqual(s.read_received(), b'abcdefghij')
        self.assertEqual([f for f in s.sent() if f.tcp][-1].tcp['ack'], base + 10)

    def test_full_duplicate_is_acked_not_delivered(self):
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        base = p.seq
        p.send(PSH | ACK, b'abc')
        s.poll()
        self.assertEqual(s.read_received(), b'abc')
        s.sent()
        s.deliver(p.segment(PSH | ACK, b'abc', seq=base))
        s.poll()
        self.assertEqual(s.read_received(), b'')
        self.assertEqual([f for f in s.sent() if f.tcp][-1].tcp['ack'], base + 3)


class Keepalive(unittest.TestCase):
    def test_zero_length_probe_is_acked(self):
        """Linux and Windows probe an idle connection with SEG.SEQ =
        RCV.NXT-1 and no data; without an answer they drop the connection."""
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        s.deliver(p.segment(ACK, seq=p.seq - 1))
        s.poll()
        acks = [f for f in s.sent() if f.tcp]
        self.assertEqual(len(acks), 1)
        self.assertEqual(acks[0].tcp['ack'], p.seq)
        self.assertEqual(s.state, 'ESTABLISHED')

    def test_one_byte_probe_is_acked_and_not_delivered(self):
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        s.deliver(p.segment(ACK, b'\x00', seq=p.seq - 1))
        s.poll()
        acks = [f for f in s.sent() if f.tcp]
        self.assertEqual(acks[-1].tcp['ack'], p.seq)
        self.assertEqual(s.read_received(), b'')


class PeerWindow(unittest.TestCase):
    @unittest.expectedFailure
    def test_connection_survives_a_long_zero_window(self):
        """Known limitation: the stack ignores the peer's window.  It keeps
        sending into a zero window and counts each resend as a retry, so a
        peer that stays at window 0 for a few seconds (busy, or opening with
        Win=0 as some servers do) gets the connection closed with
        EV_TX_TIMEOUT.  RFC 793 needs a persist timer that probes without
        giving up.  Fixing it means tracking SND.WND."""
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        p.send(ACK, window=0)
        s.poll()
        s.send_data(b'abc')
        s.poll()
        s.run_frames(800)                      # ~16 s at window 0
        self.assertEqual(s.state, 'ESTABLISHED')


if __name__ == '__main__':
    unittest.main()
