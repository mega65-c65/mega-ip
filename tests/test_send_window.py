"""The send ring and sliding window: several segments in flight, the peer's
window, Nagle's rule for short segments, go-back-N after a timeout, the ML
byte API, and the MSS option on SYN and SYN-ACK."""

import unittest

from stack import ACK, PSH, SYN, Peer, Stack

EV_TX_TIMEOUT = 0x20
ML_SEND_BYTE = 0x7600


def connected(window=4096):
    s = Stack.ready()
    p = Peer(s)
    p.connect_stack()
    if window != 4096:
        p.send(ACK, window=window)
        s.poll()
        s.sent()
    return s, p


def data(frames):
    return [f for f in frames if f.tcp and f.tcp['payload']]


def tick(s):
    """Half a frame passes, then a poll (as Stack.run_frames does)."""
    s.m.time_offset += s.m.instructions_per_line * s.m.lines_per_frame // 2
    return s.poll()


def queue(s, payload):
    """Queue bytes in chunks of at most one segment (ETH_TCP_SEND's limit)."""
    step = s.asm['TCP_PAYLOAD_MAX']
    for i in range(0, len(payload), step):
        assert s.send_data(payload[i:i + step]) == 0, 'queue refused at %d' % i


class Receiver:
    """The peer as a receiving host: keeps the bytes that arrive in order,
    and ACKs them (or not)."""

    def __init__(self, s, p):
        self.s, self.p = s, p
        self.start = p.ack
        self.got = bytearray()

    @property
    def expected(self):
        return self.start + len(self.got)

    def take(self, frames, ack=True, window=4096):
        for f in data(frames):
            if f.tcp['seq'] == self.expected:
                self.got += f.tcp['payload']
        if ack:
            self.p.ack = self.expected
            self.p.send(ACK, window=window)

    def run(self, polls=400, window=4096):
        for _ in range(polls):
            self.s.poll()
            self.take(self.s.sent(), window=window)
            if self.s.call('ETH_TCP_TX_IDLE').a:
                return


class SlidingWindow(unittest.TestCase):
    def test_several_segments_go_out_before_any_ack(self):
        s, p = connected()
        want = bytes(range(256)) * 4                     # 1 KB: 4 full segments and 84 bytes
        queue(s, want)
        s.poll()
        segs = data(s.sent())
        full = s.asm['TCP_PAYLOAD_MAX']
        self.assertEqual([len(f.tcp['payload']) for f in segs], [full] * 4)
        seq = segs[0].tcp['seq']
        for f in segs:                                   # contiguous, no repeats
            self.assertEqual(f.tcp['seq'], seq)
            seq += len(f.tcp['payload'])
        self.assertEqual(b''.join(f.tcp['payload'] for f in segs), want[:4 * full])
        p.ack = seq                                      # the short rest follows the ACK
        p.send(ACK)
        s.poll()
        self.assertEqual([f.tcp['payload'] for f in data(s.sent())], [want[4 * full:]])

    def test_in_flight_never_exceeds_the_peer_window(self):
        s, p = connected(window=500)
        r = Receiver(s, p)
        queue(s, bytes(2000))
        top = 0
        for _ in range(200):
            s.poll()
            frames = s.sent()
            acked = r.expected                           # what the stack knows is ACKed
            for f in data(frames):
                end = f.tcp['seq'] + len(f.tcp['payload'])
                self.assertLessEqual(end - acked, 500)
                top = max(top, end - acked)
            r.take(frames, window=500)
            if s.call('ETH_TCP_TX_IDLE').a:
                break
        self.assertEqual(len(r.got), 2000)
        self.assertGreater(top, s.asm['TCP_PAYLOAD_MAX'])     # more than one segment

    def test_in_flight_never_exceeds_the_tx_window(self):
        s, p = connected(window=60000)
        queue(s, bytes(s.asm['TX_RING_SIZE']))
        s.poll()
        flight = sum(len(f.tcp['payload']) for f in data(s.sent()))
        self.assertLessEqual(flight, s.asm['TCP_TX_WINDOW'])
        self.assertGreater(flight, 1000)

    def test_bulk_transfer_through_the_ring_wrap(self):
        s, p = connected()
        r = Receiver(s, p)
        want = bytes((i * 7) & 0xFF for i in range(6000))      # 3 laps of the ring
        pos = 0
        for _ in range(600):
            while pos < len(want) and s.send_data(want[pos:pos + 200]) == 0:
                pos += 200
            s.poll()
            r.take(s.sent())
            if pos >= len(want) and s.call('ETH_TCP_TX_IDLE').a:
                break
        self.assertEqual(bytes(r.got), want)

    def test_an_ack_frees_room_for_more(self):
        s, p = connected(window=470)                     # two full segments
        queue(s, bytes(1000))
        s.poll()
        first = data(s.sent())
        self.assertEqual(len(first), 2)
        p.ack = first[0].tcp['seq'] + len(first[0].tcp['payload'])
        p.send(ACK, window=470)
        s.poll()
        more = data(s.sent())
        self.assertEqual(len(more), 1)
        self.assertEqual(more[0].tcp['seq'], first[1].tcp['seq'] + len(first[1].tcp['payload']))


class Nagle(unittest.TestCase):
    def test_short_segment_waits_while_data_is_in_flight(self):
        s, p = connected()
        s.send_data(b'first')
        s.poll()
        sent = data(s.sent())
        self.assertEqual([f.tcp['payload'] for f in sent], [b'first'])
        s.send_data(b'sec')
        s.send_data(b'ond')
        s.poll()
        self.assertEqual(data(s.sent()), [])
        p.ack = sent[0].tcp['seq'] + 5
        p.send(ACK)
        s.poll()
        self.assertEqual([f.tcp['payload'] for f in data(s.sent())], [b'second'])

    def test_full_segment_goes_while_data_is_in_flight(self):
        s, p = connected()
        s.send_data(b'x')
        s.poll()
        s.sent()
        full = s.asm['TCP_PAYLOAD_MAX']
        s.send_data(b'y' * full)
        s.poll()
        self.assertEqual([len(f.tcp['payload']) for f in data(s.sent())], [full])


class SendByte(unittest.TestCase):
    def test_bytes_queued_one_at_a_time_leave_in_one_segment(self):
        s, p = connected()
        for b in b'hello, world':
            r = s.call(ML_SEND_BYTE, b)
            self.assertEqual((r.a, r.carry), (1, 0))
        self.assertEqual(data(s.sent()), [])             # nothing until the poll
        s.poll()
        self.assertEqual([f.tcp['payload'] for f in data(s.sent())], [b'hello, world'])

    def test_send_byte_refused_when_the_ring_is_full(self):
        s, p = connected(window=0)
        for i in range(s.asm['TX_RING_SIZE']):
            self.assertEqual(s.call(ML_SEND_BYTE, i & 0xFF).a, 1)
        r = s.call(ML_SEND_BYTE, 0x55)
        self.assertEqual((r.a, r.carry), (0, 1))


class GoBackN(unittest.TestCase):
    def test_lost_segment_resent_with_everything_after_it(self):
        s, p = connected()
        r = Receiver(s, p)
        want = bytes((i * 13) & 0xFF for i in range(1000))
        queue(s, want)
        s.poll()
        segs = data(s.sent())
        self.assertGreater(len(segs), 2)
        r.take(segs[:1])                                 # the 2nd is lost: only the 1st arrives
        lost_seq = segs[1].tcp['seq']
        resent = []
        for _ in range(3000):
            tick(s)
            frames = s.sent()
            resent += [f for f in data(frames) if f.tcp['seq'] == lost_seq]
            r.take(frames)
            if s.call('ETH_TCP_TX_IDLE').a:
                break
        self.assertTrue(resent, 'the lost segment was never sent again')
        self.assertEqual(bytes(r.got), want)
        self.assertEqual(s.state, 'ESTABLISHED')

    def test_no_progress_times_out_after_the_retries(self):
        s, p = connected()
        queue(s, bytes(1000))
        s.poll()
        first = data(s.sent())[0].tcp['seq']
        resends = []

        def on_frame(sent):
            resends.extend(f for f in data(sent) if f.tcp['seq'] == first)
        events, _ = s.run_frames(3000, on_frame=on_frame,
                                 until=lambda: s.state != 'ESTABLISHED')
        self.assertEqual(s.state, 'CLOSED')
        self.assertTrue(events & EV_TX_TIMEOUT)
        self.assertEqual(len(resends), s.asm['TCP_TX_MAX_RETRIES'])

    def test_progress_restarts_the_retry_count(self):
        """A slow peer that ACKs a segment per timeout never runs out of
        retries."""
        s, p = connected()
        r = Receiver(s, p)
        want = bytes(range(256)) * 8                     # 2 KB, 9 segments
        queue(s, want)
        for _ in range(20000):
            tick(s)
            segs = data(s.sent())
            if segs:                                     # take only the first of a burst
                r.take(segs[:1])
            if s.call('ETH_TCP_TX_IDLE').a or s.state != 'ESTABLISHED':
                break
        self.assertEqual(s.state, 'ESTABLISHED')
        self.assertEqual(bytes(r.got), want)


class PeerWindowUpdates(unittest.TestCase):
    def test_zero_window_holds_data_until_it_opens(self):
        s, p = connected(window=0)
        s.send_data(b'waiting')
        s.run_frames(200)
        self.assertEqual(data(s.sent()), [])
        self.assertEqual(s.state, 'ESTABLISHED')
        p.send(ACK, window=4096)                         # the window update
        s.poll()
        self.assertEqual([f.tcp['payload'] for f in data(s.sent())], [b'waiting'])

    def test_small_window_sends_a_short_segment_when_nothing_is_in_flight(self):
        s, p = connected(window=10)
        s.send_data(b'0123456789abcdef')
        s.poll()
        self.assertEqual([f.tcp['payload'] for f in data(s.sent())], [b'0123456789'])

    def test_window_from_the_handshake(self):
        """The SYN-ACK's window counts from the start: no ACK needed first."""
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()                                # SYN-ACK window 4096
        queue(s, bytes(1000))
        s.poll()
        self.assertGreater(len(data(s.sent())), 1)


class Mss(unittest.TestCase):
    def test_active_syn_announces_the_mss(self):
        s = Stack.ready()
        p = Peer(s)
        s.call('ETH_SET_REMOTE_IP', *p.ip)
        s.call('ETH_SET_REMOTE_PORT', 0, p.port)
        s.call('ETH_TCP_CONNECT_START')
        syn = None
        for _ in range(20):
            s.call('ETH_CONNECT_POLL')
            for f in s.sent():
                if f.arp and f.arp['op'] == 1:
                    s.deliver(p.arp_reply_to(f))
                elif f.tcp and f.tcp['flags'] & SYN:
                    syn = f
            if syn:
                break
        self.assertIsNotNone(syn)
        self.assertEqual(syn.tcp['payload'], b'')        # options, not data
        self.assertEqual(syn.raw[14 + 40:14 + 44], b'\x02\x04' + s.asm['TCP_MSS'].to_bytes(2, 'big'))
        self.assertEqual(syn.ip['total'], 44)

    def test_syn_ack_announces_the_mss_and_data_starts_at_seq_plus_one(self):
        s = Stack.ready()
        s.call('ETH_TCP_LISTEN_START', 0, 80)
        c = Peer(s, port=5000)
        synack = c.open_to_listener(80)
        self.assertEqual(synack.raw[14 + 20 + 12] >> 4, 6)
        self.assertEqual(synack.raw[14 + 40:14 + 44], b'\x02\x04\x05\xb4')
        c.send(ACK)
        s.poll()
        self.assertEqual(s.state, 'ESTABLISHED')
        s.send_data(b'hi')
        s.poll()
        seg = data(s.sent())[0]
        self.assertEqual(seg.tcp['seq'], synack.tcp['seq'] + 1)

    def test_later_segments_have_plain_headers(self):
        s, p = connected()
        s.send_data(b'abc')
        s.poll()
        seg = data(s.sent())[0]
        self.assertEqual(seg.raw[14 + 20 + 12] >> 4, 5)
        self.assertEqual(seg.tcp['payload'], b'abc')

    def test_full_size_segments_are_received(self):
        s, p = connected()
        mss = s.asm['TCP_MSS']
        chunks = [bytes([0x41 + i]) * mss for i in range(2)]   # a full window
        for c in chunks:
            p.send(PSH | ACK, c)
        s.poll()
        self.assertEqual(s.read_received(), b''.join(chunks))
        acks = [f for f in s.sent() if f.tcp]
        self.assertEqual(acks[-1].tcp['ack'], p.seq)

    def test_window_cap_is_two_full_segments(self):
        s, _ = connected()
        cap = s.asm['TCP_RECV_WINDOW_CAP_LO'] | (s.asm['TCP_RECV_WINDOW_CAP_HI'] << 8)
        self.assertEqual(cap, 2 * s.asm['TCP_MSS'])


if __name__ == '__main__':
    unittest.main()
