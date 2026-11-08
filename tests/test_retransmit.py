"""Retransmission, retry limits and timers.

Time passes with Stack.run_frames(), which polls several times per frame as
a MEGA65 program would.  Tests check counts, sequence numbers, states and
events rather than exact frame numbers, and read retry limits from the
assembly so they follow the source.
"""

import unittest

from stack import ACK, FIN, PSH, SYN, Peer, Stack

EV_RST, EV_LOCAL_CLOSE, EV_TIMEWAIT_DONE, EV_TX_TIMEOUT = 0x01, 0x04, 0x08, 0x20
CONN_FAILED = 0x02


def collect(sent_list, pred):
    """on_frame callback that appends (frame index, frame) for matches."""
    frame = [0]

    def on_frame(sent):
        for f in sent:
            if pred(f):
                sent_list.append((frame[0], f))
    return on_frame, frame


def start_connect(s, p):
    s.call('ETH_SET_REMOTE_IP', *p.ip)
    s.call('ETH_SET_REMOTE_PORT', p.port >> 8, p.port & 0xFF)
    s.call('ETH_TCP_CONNECT_START')


class DataRetransmit(unittest.TestCase):
    def setUp(self):
        self.s = Stack.ready()
        self.p = Peer(self.s)
        self.p.connect_stack()
        self.s.send_data(b'abc')
        self.s.poll()
        self.first = [f for f in self.s.sent() if f.tcp and f.tcp['payload']][0]

    def run_until_closed(self, frames=2000):
        retx = []
        frame = [0]

        def on_frame(sent):
            retx.extend((frame[0], f) for f in sent if f.tcp and f.tcp['payload'])

        def until():
            frame[0] += 1
            return self.s.state != 'ESTABLISHED'
        events, _ = self.s.run_frames(frames, on_frame=on_frame, until=until)
        return retx, events

    def test_lost_segment_is_resent_then_times_out(self):
        retx, events = self.run_until_closed()
        limit = self.s.asm['TCP_TX_MAX_RETRIES']
        self.assertEqual(len(retx), limit)
        for _, f in retx:
            self.assertEqual(f.tcp['seq'], self.first.tcp['seq'])
            self.assertEqual(f.tcp['payload'], b'abc')
        self.assertEqual(self.s.state, 'CLOSED')
        self.assertTrue(events & EV_TX_TIMEOUT)

    def test_resends_are_evenly_spaced(self):
        retx, _ = self.run_until_closed()
        frames = [n for n, _ in retx]
        gaps = [b - a for a, b in zip(frames, frames[1:])]
        expected = self.s.asm['TCP_TX_RETRY_TICKS']
        for g in gaps:
            self.assertAlmostEqual(g, expected, delta=3)

    def test_ack_stops_retransmission(self):
        s, p = self.s, self.p
        retx = []
        on_frame, _ = collect(retx, lambda f: f.tcp and f.tcp['payload'])
        s.run_frames(60, on_frame=on_frame)                  # one resend
        self.assertEqual(len(retx), 1)
        p.ack = self.first.tcp['seq'] + 3
        p.send(ACK)
        retx.clear()
        s.run_frames(300, on_frame=on_frame)
        self.assertEqual(retx, [])
        self.assertEqual(s.call('ETH_TCP_TX_IDLE').a, 1)
        self.assertEqual(s.state, 'ESTABLISHED')

    def test_queued_data_follows_the_ack(self):
        s, p = self.s, self.p
        s.send_data(b'def')                                  # waits: stop-and-wait
        s.poll()
        self.assertEqual([f for f in s.sent() if f.tcp and f.tcp['payload']], [])
        p.ack = self.first.tcp['seq'] + 3
        p.send(ACK)
        s.poll()
        data = [f for f in s.sent() if f.tcp and f.tcp['payload']]
        self.assertEqual(len(data), 1)
        self.assertEqual(data[0].tcp['payload'], b'def')
        self.assertEqual(data[0].tcp['seq'], self.first.tcp['seq'] + 3)


class ConnectRetries(unittest.TestCase):
    def test_syn_retried_then_connect_fails(self):
        s = Stack.ready()
        p = Peer(s)
        start_connect(s, p)
        syns, status = [], [0]

        def on_frame(sent):
            # Poll the connect at every status poll: its timer counts a frame
            # only when the raster has gone back since the previous call.
            status[0] |= s.call('ETH_CONNECT_POLL').a
            for f in sent + s.sent():
                if f.arp and f.arp['op'] == 1:
                    s.deliver(p.arp_reply_to(f))
                elif f.tcp and f.tcp['flags'] & SYN:
                    syns.append(f)

        s.run_frames(5000, on_frame=on_frame, until=lambda: status[0] & CONN_FAILED)
        self.assertTrue(status[0] & CONN_FAILED)
        self.assertEqual(len(syns), 1 + s.asm['CONNECT_SYN_MAX_RETRIES'])
        self.assertEqual(len({f.tcp['seq'] for f in syns}), 1)
        self.assertEqual(s.state, 'CLOSED')

    def test_unanswered_arp_fails_the_connect(self):
        s = Stack.ready()
        p = Peer(s)
        start_connect(s, p)
        arps, a = 0, 0
        for _ in range(2000):            # ARP retries count connect polls
            a = s.call('ETH_CONNECT_POLL').a
            arps += sum(1 for f in s.sent() if f.arp and f.arp['op'] == 1)
            if a & CONN_FAILED:
                break
        self.assertTrue(a & CONN_FAILED)
        self.assertEqual(arps, 1 + s.asm['ARP_MAX_RETRIES'])

    def test_synack_retried_then_half_open_dropped(self):
        s = Stack.ready()
        s.call('ETH_TCP_LISTEN_START', 0x00, 80)
        p = Peer(s, port=5000)
        first = p.open_to_listener(80)
        synacks = []
        on_frame, _ = collect(synacks, lambda f: f.tcp and f.tcp['flags'] & SYN)
        s.run_frames(5000, on_frame=on_frame, until=lambda: s.state != 'SYN_RECEIVED')
        self.assertEqual(s.state, 'CLOSED')
        self.assertGreater(len(synacks), 0)
        for _, f in synacks:
            self.assertEqual(f.tcp['seq'], first.tcp['seq'])
        self.assertEqual(s.peek('TCP_LISTEN_ENABLED'), 1)     # still listening
        self.assertEqual(s.peek('TCP_ACCEPT_FLAGS') & 1, 0)

    def test_listener_accepts_again_after_half_open_dropped(self):
        s = Stack.ready()
        s.call('ETH_TCP_LISTEN_START', 0x00, 80)
        Peer(s, port=5000).open_to_listener(80)
        s.run_frames(5000, until=lambda: s.state != 'SYN_RECEIVED')
        p = Peer(s, port=5001)
        p.open_to_listener(80)
        p.send(ACK)
        s.poll()
        self.assertEqual(s.state, 'ESTABLISHED')


class CloseTimers(unittest.TestCase):
    def test_fin_retried_then_closed(self):
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        s.call('ETH_TCP_DISCONNECT')
        first = [f for f in s.sent() if f.tcp and f.tcp['flags'] & FIN][0]
        fins = []
        on_frame, _ = collect(fins, lambda f: f.tcp and f.tcp['flags'] & FIN)
        events, _ = s.run_frames(5000, on_frame=on_frame,
                                 until=lambda: s.state == 'CLOSED')
        self.assertEqual(s.state, 'CLOSED')
        self.assertEqual(len(fins), s.asm['TCP_TX_MAX_RETRIES'])
        for _, f in fins:
            self.assertEqual(f.tcp['seq'], first.tcp['seq'])
        # Note: an unacknowledged FIN still ends with EV_LOCAL_CLOSE, the
        # same event as a clean close (see the review notes).
        self.assertTrue(events & EV_LOCAL_CLOSE)

    def time_wait(self):
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        s.call('ETH_TCP_DISCONNECT')
        fin = [f for f in s.sent() if f.tcp and f.tcp['flags'] & FIN][0]
        p.ack = fin.tcp['seq'] + 1
        p.send(FIN | ACK)
        s.poll()
        self.assertEqual(s.state, 'TIME_WAIT')
        return s, p

    def time_wait_counter(self, s):
        return s.peek('TIME_WAIT_COUNTER_LO') | (s.peek('TIME_WAIT_COUNTER_HI') << 8)

    def test_time_wait_lasts_about_a_minute(self):
        s, _ = self.time_wait()
        frames = self.time_wait_counter(s) * s.asm['TIME_WAIT_TICK_FRAMES']
        self.assertGreaterEqual(frames, 30 * 50)       # 30-120 s at 50 Hz
        self.assertLessEqual(frames, 120 * 50)

    def test_time_wait_counts_one_tick_per_tick_frames(self):
        s, _ = self.time_wait()
        before = self.time_wait_counter(s)
        s.run_frames(60)
        ticks = before - self.time_wait_counter(s)
        self.assertAlmostEqual(ticks, 60 // s.asm['TIME_WAIT_TICK_FRAMES'], delta=1)

    def test_time_wait_ends_closed(self):
        s, _ = self.time_wait()
        s.poke('TIME_WAIT_COUNTER_LO', 2)             # skip most of the wait
        s.poke('TIME_WAIT_COUNTER_HI', 0)
        events, frames = s.run_frames(100, until=lambda: s.state == 'CLOSED')
        self.assertEqual(s.state, 'CLOSED')
        self.assertTrue(events & EV_TIMEWAIT_DONE)
        self.assertLessEqual(frames, 3 * s.asm['TIME_WAIT_TICK_FRAMES'] + 1)

    def test_retransmitted_fin_in_time_wait_is_acked(self):
        s, p = self.time_wait()
        s.sent()
        p.send(FIN | ACK, seq=p.seq - 1)              # peer didn't see our ACK
        s.poll()
        acks = [f for f in s.sent() if f.tcp]
        self.assertTrue(acks)
        self.assertEqual(acks[-1].tcp['ack'], p.seq)
        self.assertEqual(s.state, 'TIME_WAIT')


if __name__ == '__main__':
    unittest.main()
