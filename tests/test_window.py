"""Receive ring, advertised window and window updates, and the NIC ring."""

import unittest

from stack import ACK, PSH, Peer, Stack

RING_SIZE = 4096 - 1           # one byte stays free to tell full from empty


def connected():
    s = Stack.ready()
    p = Peer(s)
    p.connect_stack()
    return s, p


class ReceiveWindow(unittest.TestCase):
    def test_window_starts_at_cap(self):
        s, p = connected()
        p.send(PSH | ACK, b'x')
        s.poll()
        ack = [f for f in s.sent() if f.tcp][-1]
        cap = s.asm['TCP_RECV_WINDOW_CAP_LO'] | (s.asm['TCP_RECV_WINDOW_CAP_HI'] << 8)
        self.assertEqual(ack.tcp['window'], cap)

    def test_window_never_exceeds_free_space(self):
        s, p = connected()
        start = p.seq
        for _ in range(12):
            p.send(PSH | ACK, b'z' * 400)
            s.poll()
            for f in s.sent():
                if f.tcp:
                    free = RING_SIZE - (f.tcp['ack'] - start)
                    self.assertLessEqual(f.tcp['window'], free)

    def test_full_ring_advertises_zero_and_drops_excess(self):
        s, p = connected()
        start = p.seq
        for _ in range(6):
            p.send(PSH | ACK, b'z' * 1000)
            s.poll()
        last = [f for f in s.sent() if f.tcp][-1]
        self.assertEqual(last.tcp['ack'] - start, RING_SIZE)
        self.assertEqual(last.tcp['window'], 0)
        self.assertEqual(len(s.read_received()), RING_SIZE)

    def test_reading_sends_window_update(self):
        s, p = connected()
        for _ in range(6):
            p.send(PSH | ACK, b'z' * 1000)
            s.poll()
        s.sent()
        s.read_received()
        s.poll()
        updates = [f for f in s.sent() if f.tcp]
        self.assertTrue(updates, 'no window update after the app read the ring')
        self.assertGreater(updates[-1].tcp['window'], 0)

    def test_data_intact_through_ring_wrap(self):
        s, p = connected()
        sent, got = bytearray(), bytearray()
        for i in range(5):                     # 5 KB: past the 4 KB ring's wrap
            chunk = bytes((i * 7 + k) & 0xFF for k in range(1000))
            p.send(PSH | ACK, chunk)
            sent += chunk
            s.poll()
            got += s.read_received()
        self.assertEqual(bytes(got), bytes(sent))


class NicRing(unittest.TestCase):
    def test_burst_of_waiting_frames_all_processed(self):
        s, p = connected()
        chunks = [bytes([0x41 + i]) * 50 for i in range(3)]
        for c in chunks:                       # three frames waiting at once
            p.send(PSH | ACK, c)
        s.poll()
        self.assertEqual(s.read_received(), b''.join(chunks))
        acks = [f for f in s.sent() if f.tcp]
        self.assertEqual(acks[-1].tcp['ack'], p.seq)

    def test_frames_dropped_by_nic_are_recovered_by_retransmit(self):
        s, p = connected()
        frames = [p.segment(PSH | ACK, bytes([0x61 + i]) * 40, seq=p.seq + 40 * i)
                  for i in range(5)]
        for f in frames:
            s.deliver(f)                       # NIC holds 3; the rest are dropped
        self.assertGreater(s.eth.dropped, 0)
        s.poll()
        for f in frames:                       # peer retransmits everything
            s.deliver(f)
            s.poll()
        expected = b''.join(bytes([0x61 + i]) * 40 for i in range(5))
        self.assertEqual(s.read_received(), expected)


if __name__ == '__main__':
    unittest.main()
