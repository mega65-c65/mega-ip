"""Many connections on one stack: state must not leak from one to the next.

Every other test starts from a freshly initialised stack; these run several
sessions back to back, as the terminal, IRC and web server programs do.
"""

import unittest

from stack import ACK, FIN, PSH, Peer, Stack

SESSIONS = 4


def clean_slate(test, s):
    """State that must be reset before a new connection is used."""
    test.assertEqual(s.peek('TCP_OOO_VALID'), 0, 'out-of-order slot left valid')
    test.assertEqual(s.peek('TCP_CLOSE_PENDING'), 0, 'close still pending')
    test.assertEqual(s.call('ETH_TCP_TX_IDLE').a, 1, 'TX not idle')


def close(s, p, how):
    """End the session `how`: 'active', 'passive' or 'force'."""
    if how == 'force':
        s.call('ETH_TCP_FORCE_CLOSE')
    elif how == 'active':
        s.call('ETH_TCP_DISCONNECT')
        fin = [f for f in s.sent() if f.tcp and f.tcp['flags'] & FIN][0]
        p.ack = fin.tcp['seq'] + 1
        p.send(FIN | ACK)
        s.poll()
        assert s.state == 'TIME_WAIT', s.state
    else:
        p.send(FIN | ACK)
        s.poll()
        s.call('ETH_TCP_DISCONNECT')
        s.poll()
        fin = [f for f in s.sent() if f.tcp and f.tcp['flags'] & FIN][0]
        p.ack = fin.tcp['seq'] + 1
        p.send(ACK)
        s.poll()
        assert s.state == 'CLOSED', s.state
    s.sent()


class ClientSessions(unittest.TestCase):
    def test_back_to_back_sessions(self):
        s = Stack.ready()
        ports = []
        for i in range(SESSIONS):
            how = ('active', 'passive', 'force')[i % 3]
            with self.subTest(session=i, previous_close=how):
                p = Peer(s, ip=(192, 168, 1, 70 + i), mac=bytes([2, 0, 0, 0, 1, i]))
                p.connect_stack()
                clean_slate(self, s)
                ports.append(p.local_port)
                msg = ('request %d' % i).encode()
                s.send_data(msg)
                s.poll()
                sent = [f for f in s.sent() if f.tcp and f.tcp['payload']]
                self.assertEqual(sent[0].tcp['payload'], msg)
                self.assertEqual(bytes(sent[0].dst), p.mac)
                p.ack = sent[0].tcp['seq'] + len(msg)
                reply = ('reply %d' % i).encode()
                p.send(PSH | ACK, reply)
                s.poll()
                self.assertEqual(s.read_received(), reply)
                close(s, p, how)
        self.assertEqual(len(set(ports)), SESSIONS, 'local ports reused: %r' % ports)

    def test_unread_data_does_not_reach_next_connection(self):
        """Bytes left unread from one connection must not be the first bytes
        the next connection's reader sees."""
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        p.send(PSH | ACK, b'left over')
        s.poll()
        close(s, p, 'passive')
        p2 = Peer(s, ip=(192, 168, 1, 78))
        p2.connect_stack()
        p2.send(PSH | ACK, b'fresh')
        s.poll()
        self.assertEqual(s.read_received(), b'fresh')

    def test_data_with_fin_is_readable_after_close(self):
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        p.send(PSH | FIN | ACK, b'last words')
        s.poll()
        self.assertEqual(s.state, 'CLOSE_WAIT')
        s.call('ETH_TCP_DISCONNECT')
        s.poll()
        self.assertEqual(s.read_received(), b'last words')

    def test_reconnect_from_time_wait(self):
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        first_port = p.local_port
        close(s, p, 'active')
        p2 = Peer(s, ip=(192, 168, 1, 79))
        p2.connect_stack()
        self.assertNotEqual(p2.local_port, first_port)
        clean_slate(self, s)

    def test_reconnect_after_tx_timeout(self):
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        s.send_data(b'lost')
        s.poll()
        s.run_frames(3000, until=lambda: s.state != 'ESTABLISHED')
        self.assertEqual(s.state, 'CLOSED')
        p2 = Peer(s, ip=(192, 168, 1, 80))
        p2.connect_stack()
        clean_slate(self, s)
        p2.send(PSH | ACK, b'ok')
        s.poll()
        self.assertEqual(s.read_received(), b'ok')


class ServerSessions(unittest.TestCase):
    """The web server's loop: listen, accept, read a request, answer, close,
    force-close and listen again."""

    def serve_one(self, s, client_port, server_closes_first):
        s.call('ETH_TCP_LISTEN_START', 0, 80)
        c = Peer(s, ip=(192, 168, 1, 90), port=client_port)
        c.open_to_listener(80)
        c.send(PSH | ACK, b'GET / HTTP/1.0\r\n\r\n')
        s.poll()
        self.assertEqual(s.state, 'ESTABLISHED')

        self.assertEqual(s.read_received(), b'GET / HTTP/1.0\r\n\r\n')
        s.send_data(b'HTTP/1.0 200 OK\r\n\r\n')
        s.poll()
        resp = [f for f in s.sent() if f.tcp and f.tcp['payload']]
        self.assertEqual(resp[0].tcp['dport'], client_port)
        c.ack = resp[0].tcp['seq'] + len(resp[0].tcp['payload'])
        c.send(ACK)
        s.poll()
        if server_closes_first:
            close(s, c, 'active')
            s.call('ETH_TCP_FORCE_CLOSE')       # as the web server does
        else:
            close(s, c, 'passive')              # ends CLOSED: listen at once

    def test_server_closes_first_repeatedly(self):
        s = Stack.ready()
        for i in range(SESSIONS):
            with self.subTest(session=i):
                self.serve_one(s, 6000 + i, server_closes_first=True)

    def test_client_closes_first_repeatedly(self):
        s = Stack.ready()
        for i in range(SESSIONS):
            with self.subTest(session=i):
                self.serve_one(s, 7000 + i, server_closes_first=False)

    def test_unread_request_does_not_reach_next_client(self):
        s = Stack.ready()
        s.call('ETH_TCP_LISTEN_START', 0, 80)
        c = Peer(s, port=5000)
        c.open_to_listener(80)
        c.send(PSH | ACK, b'never read')
        s.poll()
        close(s, c, 'passive')
        s.call('ETH_TCP_LISTEN_START', 0, 80)
        c2 = Peer(s, port=5001)
        c2.open_to_listener(80)
        c2.send(PSH | ACK, b'second')
        s.poll()
        self.assertEqual(s.read_received(), b'second')


if __name__ == '__main__':
    unittest.main()
