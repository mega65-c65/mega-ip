"""RST handling in each TCP state."""

import unittest

from stack import ACK, FIN, PSH, RST, SYN, Peer, Stack

EV_RST = 0x01
CONN_FAILED = 0x02


def established():
    s = Stack.ready()
    p = Peer(s)
    p.connect_stack()
    return s, p


def to_state(state):
    """A connection driven into `state`; returns (stack, peer)."""
    s, p = established()
    if state == 'CLOSE_WAIT':
        p.send(FIN | ACK)
        s.poll()
    elif state in ('FIN_WAIT_1', 'FIN_WAIT_2'):
        s.call('ETH_TCP_DISCONNECT')
        if state == 'FIN_WAIT_2':
            fin = [f for f in s.sent() if f.tcp and f.tcp['flags'] & FIN][0]
            p.ack = fin.tcp['seq'] + 1
            p.send(ACK)
            s.poll()
    elif state == 'LAST_ACK':
        p.send(FIN | ACK)
        s.poll()
        s.call('ETH_TCP_DISCONNECT')
        s.poll()
    s.sent()
    assert s.state == state, (state, s.state)
    return s, p


class RstInSynchronizedStates(unittest.TestCase):
    def test_in_window_rst_closes(self):
        for state in ('ESTABLISHED', 'CLOSE_WAIT', 'FIN_WAIT_1', 'FIN_WAIT_2', 'LAST_ACK'):
            with self.subTest(state=state):
                s, p = to_state(state)
                p.send(RST)
                events = s.poll()
                self.assertEqual(s.state, 'CLOSED')
                self.assertTrue(events & EV_RST)
                self.assertEqual(s.sent(), [])          # never answer a RST

    def test_out_of_window_rst_is_ignored(self):
        for offset in (100000, -100000, 0x7FFFFFFF):
            with self.subTest(offset=offset):
                s, p = established()
                p.send(RST, seq=(p.seq + offset) & 0xFFFFFFFF)
                events = s.poll()
                self.assertEqual(s.state, 'ESTABLISHED')
                self.assertFalse(events & EV_RST)

    def test_connection_works_after_ignored_rst(self):
        s, p = established()
        p.send(RST, seq=p.seq + 100000)
        s.poll()
        p.send(PSH | ACK, b'ok')
        s.poll()
        self.assertEqual(s.read_received(), b'ok')


class RstDuringHandshake(unittest.TestCase):
    def syn_sent(self):
        s = Stack.ready()
        p = Peer(s)
        s.call('ETH_SET_REMOTE_IP', *p.ip)
        s.call('ETH_SET_REMOTE_PORT', 0, p.port)
        s.call('ETH_TCP_CONNECT_START')
        for _ in range(30):
            s.call('ETH_CONNECT_POLL')
            for f in s.sent():
                if f.arp and f.arp['op'] == 1:
                    s.deliver(p.arp_reply_to(f))
                elif f.tcp and f.tcp['flags'] & SYN:
                    p.local_port = f.tcp['sport']
                    return s, p, f
        raise AssertionError('no SYN')

    def test_rst_ack_for_our_syn_fails_connect(self):
        s, p, syn = self.syn_sent()
        s.deliver(p.segment(RST | ACK, seq=0, ack=syn.tcp['seq'] + 1))
        status = s.call('ETH_CONNECT_POLL').a
        self.assertTrue(status & CONN_FAILED)
        self.assertEqual(s.state, 'CLOSED')

    def test_rst_ack_with_wrong_ack_is_ignored(self):
        s, p, syn = self.syn_sent()
        s.deliver(p.segment(RST | ACK, seq=0, ack=syn.tcp['seq'] + 77))
        status = s.call('ETH_CONNECT_POLL').a
        self.assertFalse(status & CONN_FAILED)
        self.assertEqual(s.state, 'SYN_SENT')

    def test_rst_in_syn_received_drops_half_open_keeps_listening(self):
        s = Stack.ready()
        s.call('ETH_TCP_LISTEN_START', 0x00, 80)
        p = Peer(s, port=5000)
        p.open_to_listener(80)
        p.send(RST)
        s.poll()
        self.assertEqual(s.state, 'CLOSED')
        self.assertEqual(s.peek('TCP_LISTEN_ENABLED'), 1)


class StrayRst(unittest.TestCase):
    def test_rst_to_unknown_port_draws_no_reply(self):
        s = Stack.ready()
        p = Peer(s)
        p.local_port = 4444
        s.deliver(p.arp_request_for_stack())
        s.poll()
        s.sent()
        p.send(RST)
        s.poll()
        self.assertEqual(s.sent(), [])


if __name__ == '__main__':
    unittest.main()
