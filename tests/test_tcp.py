"""TCP, ARP and transmit-path tests for the mega-ip stack.

Each test runs the real assembled eth.bin on the m65sim simulator, with a
scripted peer host on the LAN.  Tests named after a commit guard that fix.
"""

import unittest

from stack import ACK, FIN, PSH, Peer, Stack

EV_LOCAL_CLOSE = 0x04


class Basics(unittest.TestCase):
    def test_init_sets_receive_filter(self):
        s = Stack.ready()
        self.assertEqual(s.eth.ctrl3 & 0x31, 0x11)      # broadcast on, not promiscuous

    def test_answers_arp_for_own_address(self):
        s = Stack.ready()
        p = Peer(s)
        s.deliver(p.arp_request_for_stack())
        s.poll()
        sent = s.sent()
        self.assertEqual(len(sent), 1)
        self.assertEqual(sent[0].arp['op'], 2)
        self.assertEqual(bytes(sent[0].arp['sha']), s.mac)
        self.assertEqual(bytes(sent[0].dst), p.mac)

    def test_connect_and_receive_data(self):
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        p.send(PSH | ACK, b'hello')
        s.poll()
        acks = [f for f in s.sent() if f.tcp]
        self.assertEqual(acks[-1].tcp['ack'], p.seq)
        self.assertTrue(acks[-1].tcp['checksum_ok'])
        self.assertTrue(acks[-1].ip['header_ok'])
        self.assertEqual(s.read_received(), b'hello')

    def test_send_data(self):
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        s.send_data(b'abc')
        s.poll()
        data = [f for f in s.sent() if f.tcp and f.tcp['payload']]
        self.assertEqual(data[0].tcp['payload'], b'abc')
        self.assertEqual(data[0].tcp['ack'], p.seq)


class CloseUsesSavedPeerMac(unittest.TestCase):
    """b96ef37: closing states use the saved peer MAC, not the ARP cache."""

    def clear_arp_cache(self, s):
        s.poke('ARP_CACHE', bytes(88))

    def test_passive_close_fin_without_arp_entry(self):
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        self.clear_arp_cache(s)
        p.send(FIN | ACK)
        s.poll()
        self.assertEqual(s.state, 'CLOSE_WAIT')
        s.sent()
        s.call('ETH_TCP_DISCONNECT')
        s.poll()
        sent = s.sent()
        self.assertFalse([f for f in sent if f.arp], 'should not need ARP: %r' % sent)
        fins = [f for f in sent if f.tcp and f.tcp['flags'] & FIN]
        self.assertEqual(len(fins), 1, sent)
        self.assertEqual(bytes(fins[0].dst), p.mac)
        self.assertEqual(s.state, 'LAST_ACK')

    def test_active_close_final_ack_without_arp_entry(self):
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        s.call('ETH_TCP_DISCONNECT')
        fin = [f for f in s.sent() if f.tcp and f.tcp['flags'] & FIN][0]
        p.ack = fin.tcp['seq'] + 1
        p.send(ACK)
        s.poll()
        self.assertEqual(s.state, 'FIN_WAIT_2')
        self.clear_arp_cache(s)
        p.send(FIN | ACK)
        s.poll()
        self.assertEqual(s.state, 'TIME_WAIT')
        acks = [f for f in s.sent() if f.tcp]
        self.assertEqual(acks[-1].tcp['ack'], p.seq)
        self.assertEqual(bytes(acks[-1].dst), p.mac)


class FinWait2(unittest.TestCase):
    """e793137: FIN_WAIT_2 reaches TIME_WAIT even if the ACK can't be built."""

    def test_reaches_time_wait_when_build_fails(self):
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        s.call('ETH_TCP_DISCONNECT')
        fin = [f for f in s.sent() if f.tcp and f.tcp['flags'] & FIN][0]
        p.ack = fin.tcp['seq'] + 1
        p.send(ACK)
        s.poll()
        self.assertEqual(s.state, 'FIN_WAIT_2')
        s.poke('TCP_PEER_MAC_VALID', 0)            # force the ACK build to fail
        s.poke('ARP_CACHE', bytes(88))
        p.send(FIN | ACK)
        s.poll()
        self.assertEqual(s.state, 'TIME_WAIT')


class GracefulDisconnect(unittest.TestCase):
    """f17cc02: the FIN waits for unacknowledged data."""

    def test_idle_connection_sends_fin_at_once(self):
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        s.call('ETH_TCP_DISCONNECT')
        self.assertEqual(s.state, 'FIN_WAIT_1')
        self.assertTrue([f for f in s.sent() if f.tcp and f.tcp['flags'] & FIN])

    def test_fin_waits_for_data_ack(self):
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        s.send_data(b'abc')
        s.poll()
        data = [f for f in s.sent() if f.tcp and f.tcp['payload']][0]
        s.call('ETH_TCP_DISCONNECT')
        s.poll()
        self.assertFalse([f for f in s.sent() if f.tcp and f.tcp['flags'] & FIN])
        self.assertEqual(s.state, 'ESTABLISHED')
        self.assertEqual(s.peek('TCP_CLOSE_PENDING'), 1)
        # peer ACKs the data -> FIN goes out after it
        p.ack = data.tcp['seq'] + 3
        p.send(ACK)
        s.poll()
        fins = [f for f in s.sent() if f.tcp and f.tcp['flags'] & FIN]
        self.assertEqual(len(fins), 1)
        self.assertEqual(fins[0].tcp['seq'], data.tcp['seq'] + 3)
        self.assertEqual(s.state, 'FIN_WAIT_1')
        self.assertEqual(s.peek('TCP_CLOSE_PENDING'), 0)

    def test_force_close_cancels_pending_close(self):
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        s.send_data(b'abc')
        s.poll()
        s.call('ETH_TCP_DISCONNECT')
        s.call('ETH_TCP_FORCE_CLOSE')
        self.assertEqual(s.peek('TCP_CLOSE_PENDING'), 0)
        self.assertEqual(s.state, 'CLOSED')


class LastAck(unittest.TestCase):
    """d76f281: LAST_ACK goes to CLOSED when our FIN is ACKed."""

    def test_passive_close_ends_closed(self):
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        p.send(FIN | ACK)
        s.poll()
        s.sent()
        s.call('ETH_TCP_DISCONNECT')
        s.poll()
        fin = [f for f in s.sent() if f.tcp and f.tcp['flags'] & FIN][0]
        self.assertEqual(s.state, 'LAST_ACK')
        p.ack = fin.tcp['seq'] + 1
        p.send(ACK)
        events = s.poll()
        self.assertEqual(s.state, 'CLOSED')
        self.assertTrue(events & EV_LOCAL_CLOSE)


class ListenStart(unittest.TestCase):
    """d7566b4: LISTEN_START doesn't change ports under a live connection."""

    def test_listen_while_connected_keeps_local_port(self):
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        before = s.peek('LOCAL_PORT', 2)
        s.call('ETH_TCP_LISTEN_START', 0x00, 80)
        self.assertEqual(s.peek('LOCAL_PORT', 2), before)
        self.assertEqual(s.peek('TCP_ACCEPT_FLAGS'), 2)

    def test_listen_when_closed_sets_ports(self):
        s = Stack.ready()
        s.call('ETH_TCP_LISTEN_START', 0x00, 80)
        self.assertEqual(s.peek('LOCAL_PORT', 2), b'\x00\x50')
        self.assertEqual(s.peek('TCP_LISTEN_ENABLED'), 1)


class ArpAging(unittest.TestCase):
    """26cd031: ARP entries age by video frames, not by polls."""

    def first_entry_ttl(self, s):
        return s.peek('ARP_CACHE')

    def test_many_quick_polls_do_not_expire_entries(self):
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()                       # fills the cache via ARP
        self.assertEqual(self.first_entry_ttl(s), 0xFF)
        start_frame = s.m.frame
        for _ in range(15300):                  # the old code expired after this
            s.call('ARP_CACHE_PURGE')
        frames = s.m.frame - start_frame
        ttl = self.first_entry_ttl(s)
        self.assertGreater(ttl, 0)
        self.assertEqual(ttl, max(0, 0xFF - frames // 50))

    def test_entries_expire_after_ttl_frames(self):
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        for _ in range(0xFF * 50 // 200 + 2):
            s.m.advance_frames(200)
            s.call('ARP_CACHE_PURGE')
        self.assertEqual(self.first_entry_ttl(s), 0)


class TransmitPath(unittest.TestCase):
    """6b35448 and b114607."""

    def fill_tx_frame(self, s, marker):
        frame = bytes([marker]) * 60
        s.poke('ETH_TX_FRAME_DEST_MAC', frame)
        s.poke('ETH_TX_LEN_LSB', 60)
        s.poke('ETH_TX_LEN_MSB', 0)
        return frame

    def test_busy_transmitter_is_not_overwritten(self):
        s = Stack.ready()
        s.eth.tx_buffer[:4] = b'BUSY'
        s.eth.tx_busy = True
        self.fill_tx_frame(s, 0x11)
        c = s.call('ETH_PACKET_SEND')
        self.assertEqual(c.p & 1, 1)                     # failed: TX busy
        self.assertEqual(bytes(s.eth.tx_buffer[:4]), b'BUSY')
        self.assertEqual(s.eth.sent, [])

    def test_send_when_idle(self):
        s = Stack.ready()
        frame = self.fill_tx_frame(s, 0x22)
        c = s.call('ETH_PACKET_SEND')
        self.assertEqual(c.p & 1, 0)
        self.assertEqual(s.eth.take_sent(), [frame])

    def test_defer_does_not_overwrite_pending_frame(self):
        s = Stack.ready()
        pending = bytes([0x33]) * 60
        s.poke('ACK_REPLY_PACKET', pending)
        s.poke('ACK_REPLY_LEN_L', 60)
        s.poke('ACK_REPLY_LEN_H', 0)
        s.poke('ACK_REPLY_PENDING', 1)
        new = self.fill_tx_frame(s, 0x44)
        s.call('DEFER_CURRENT_TX')
        self.assertEqual(s.eth.take_sent(), [new])            # sent directly
        self.assertEqual(s.peek('ACK_REPLY_PACKET', 60), pending)
        self.assertEqual(s.peek('ACK_REPLY_PENDING'), 1)
        s.call('ETH_PROCESS_DEFERRED')
        self.assertEqual(s.eth.take_sent(), [pending])        # then the old one

    def test_defer_into_empty_slot(self):
        s = Stack.ready()
        new = self.fill_tx_frame(s, 0x55)
        s.call('DEFER_CURRENT_TX')
        self.assertEqual(s.eth.sent, [])
        self.assertEqual(s.peek('ACK_REPLY_PACKET', 60), new)
        self.assertEqual(s.peek('ACK_REPLY_PENDING'), 1)


class Timing(unittest.TestCase):
    """686ff59: ETH_WAIT_100MS waits 1600 raster lines."""

    def test_wait_100ms_raster_lines(self):
        s = Stack.ready()
        # The loop counts raster changes it sees, so give each line enough
        # instructions to be seen exactly once (as at 40 MHz).
        s.m.instructions_per_line = 50
        s.m.time_offset = -s.m.cpu.instructions      # start on a line boundary
        t0 = s.m.time
        s.call('ETH_WAIT_100MS')
        lines = (s.m.time - t0) // s.m.instructions_per_line
        self.assertGreaterEqual(lines, 1600)
        self.assertLess(lines, 1610)


if __name__ == '__main__':
    unittest.main()
