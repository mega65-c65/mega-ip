"""Timers must run however the program polls.

A program that polls exactly once per video frame, always at the same
raster line (e.g. from a raster-synchronised main loop), must still see
retransmits, connect retries and timeouts.  The timers used to notice a new
frame only when the raster had gone back since the previous poll, which
never happens at a fixed line.
"""

import unittest

from stack import ACK, FIN, PSH, SYN, Peer, Stack, dns_state, start_lookup

CONN_FAILED = 0x02


def poll_at_fixed_line(s, frames, line=100, on_poll=None, until=None):
    """Poll once per frame, each time at raster `line`."""
    m = s.m
    frame_len = m.instructions_per_line * m.lines_per_frame
    for n in range(frames):
        target = (m.frame + 1) * frame_len + line * m.instructions_per_line
        m.time_offset += target - m.time
        assert m.raster_line == line
        events = s.poll()
        if on_poll:
            on_poll(s.sent(), events)
        if until and until():
            return n + 1
    return frames


class FixedLinePolling(unittest.TestCase):
    def test_data_retransmit(self):
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        s.send_data(b'abc')
        s.poll()
        s.sent()
        resent = []
        poll_at_fixed_line(s, 200, on_poll=lambda sent, e: resent.extend(
            f for f in sent if f.tcp and f.tcp['payload']))
        self.assertGreaterEqual(len(resent), 2)

    def test_connect_retries_and_fails(self):
        s = Stack.ready()
        p = Peer(s)
        s.call('ETH_SET_REMOTE_IP', *p.ip)
        s.call('ETH_SET_REMOTE_PORT', 0, p.port)
        s.call('ETH_TCP_CONNECT_START')
        status = [0]

        def on_poll(sent, events):
            status[0] |= s.call('ETH_CONNECT_POLL').a
            for f in sent + s.sent():
                if f.arp and f.arp['op'] == 1:
                    s.deliver(p.arp_reply_to(f))
        poll_at_fixed_line(s, 3000, on_poll=on_poll, until=lambda: status[0] & CONN_FAILED)
        self.assertTrue(status[0] & CONN_FAILED)

    def test_time_wait_counts_down(self):
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        s.call('ETH_TCP_DISCONNECT')
        fin = [f for f in s.sent() if f.tcp and f.tcp['flags'] & FIN][0]
        p.ack = fin.tcp['seq'] + 1
        p.send(FIN | ACK)
        s.poll()
        before = s.peek('TIME_WAIT_COUNTER_LO') | (s.peek('TIME_WAIT_COUNTER_HI') << 8)
        poll_at_fixed_line(s, 60)
        after = s.peek('TIME_WAIT_COUNTER_LO') | (s.peek('TIME_WAIT_COUNTER_HI') << 8)
        self.assertAlmostEqual(before - after, 60 // s.asm['TIME_WAIT_TICK_FRAMES'], delta=1)

    def test_dns_retries(self):
        s = Stack.ready()
        start_lookup(s)
        queries = []
        poll_at_fixed_line(s, 400, on_poll=lambda sent, e: queries.extend(
            f for f in sent if f.udp and f.udp['dport'] == 53))
        self.assertGreaterEqual(len(queries), 1)

    def test_retransmit_interval_matches_constant(self):
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        s.send_data(b'abc')
        s.poll()
        s.sent()
        frames = []
        count = [0]

        def on_poll(sent, events):
            count[0] += 1
            frames.extend(count[0] for f in sent if f.tcp and f.tcp['payload'])
        poll_at_fixed_line(s, 200, on_poll=on_poll)
        gaps = [b - a for a, b in zip(frames, frames[1:])]
        self.assertTrue(gaps)
        for g in gaps:
            self.assertAlmostEqual(g, s.asm['TCP_TX_RETRY_TICKS'], delta=2)


if __name__ == '__main__':
    unittest.main()
