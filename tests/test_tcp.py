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
        self.assertEqual(s.read_received(method='byte'), b'hello')     # RBUF_GET

    def test_block_and_byte_readers_agree(self):
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        data = bytes(range(256)) * 2
        p.send(PSH | ACK, data[:200])
        p.send(PSH | ACK, data[200:400])
        s.poll()
        self.assertEqual(s.read_received(method='block'), data[:400])
        p.send(PSH | ACK, data[400:512])
        s.poll()
        self.assertEqual(s.read_received(method='byte'), data[400:512])

    def test_send_data(self):
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        s.send_data(b'abc')
        s.poll()
        data = [f for f in s.sent() if f.tcp and f.tcp['payload']]
        self.assertEqual(data[0].tcp['payload'], b'abc')
        self.assertEqual(data[0].tcp['ack'], p.seq)


class SequenceWrap(unittest.TestCase):
    """Sequence numbers wrap at 2^32 in both directions."""

    def test_receive_across_wrap(self):
        s = Stack.ready()
        p = Peer(s)
        p.seq = 0xFFFFFFF0 - 1                      # RCV.NXT = $FFFFFFF0
        p.connect_stack()
        p.send(PSH | ACK, b'a' * 20)                # crosses 2^32
        p.send(PSH | ACK, b'b' * 20)
        s.poll()
        self.assertEqual(s.read_received(), b'a' * 20 + b'b' * 20)
        acks = [f for f in s.sent() if f.tcp]
        self.assertEqual(acks[-1].tcp['ack'], p.seq & 0xFFFFFFFF)

    def test_send_across_wrap(self):
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        s.poke('LOCAL_ISN', (0xFFFFFFFE).to_bytes(4, 'big'))   # SND.NXT
        s.send_data(b'wxyz')
        s.poll()
        data = [f for f in s.sent() if f.tcp and f.tcp['payload']]
        self.assertEqual(data[0].tcp['seq'], 0xFFFFFFFE)
        p.ack = 0x00000002                           # ACK past the wrap
        p.send(ACK)
        s.poll()
        self.assertEqual(s.call('ETH_TCP_TX_IDLE').a, 1)
        self.assertEqual(s.peek('LOCAL_ISN', 4), b'\x00\x00\x00\x02')
        s.send_data(b'next')
        s.poll()
        data = [f for f in s.sent() if f.tcp and f.tcp['payload']]
        self.assertEqual(data[0].tcp['seq'], 2)


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

    def fill_tx_frame(self, s, marker, length=60):
        frame = bytes([marker]) * length
        s.poke('ETH_TX_FRAME_DEST_MAC', frame + bytes([0xEE]))   # $EE after the frame
        s.poke('ETH_TX_LEN_LSB', length & 0xFF)
        s.poke('ETH_TX_LEN_MSB', length >> 8)
        return frame

    def test_odd_length_frame_is_padded_to_even(self):
        """A real MEGA65 never got odd-length frames through (meganet
        f2fb01b): an odd frame goes out one byte longer, padded with 0."""
        for length in (61, 95, 255, 257):
            with self.subTest(length=length):
                s = Stack.ready()
                frame = self.fill_tx_frame(s, 0x22, length)
                s.call('ETH_PACKET_SEND')
                self.assertEqual(s.eth.take_sent(), [frame + b'\x00'])

    def test_even_length_frame_is_unchanged(self):
        for length in (60, 96, 256):
            with self.subTest(length=length):
                s = Stack.ready()
                frame = self.fill_tx_frame(s, 0x22, length)
                s.call('ETH_PACKET_SEND')
                self.assertEqual(s.eth.take_sent(), [frame])

    def test_odd_tcp_segment_keeps_its_ip_length(self):
        """MegaNet's sign-up case: 41 bytes of data make a 95-byte frame.  It
        goes out as 96 bytes; the IP length stays 81 and checksums hold."""
        s = Stack.ready()
        p = Peer(s)
        p.connect_stack()
        s.send_data(bytes(range(41)))
        s.poll()
        data = [f for f in s.sent() if f.tcp and f.tcp['payload']]   # sent() checks even length
        self.assertEqual(len(data[0].raw), 96)
        self.assertEqual(data[0].ip['total'], 20 + 20 + 41)
        self.assertEqual(data[0].tcp['payload'], bytes(range(41)))
        self.assertTrue(data[0].tcp['checksum_ok'])

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

    def pend(self, s, frame):
        s.poke('ACK_REPLY_PACKET', frame)
        s.poke('ACK_REPLY_LEN_L', len(frame))
        s.poke('ACK_REPLY_LEN_H', 0)
        s.poke('ACK_REPLY_PENDING', 1)

    def test_defer_sends_pending_frame_first(self):
        """b114607 + order fix: a full slot is sent before the new frame is
        queued, so frames leave in the order they were built."""
        s = Stack.ready()
        pending = bytes([0x33]) * 60
        self.pend(s, pending)
        new = self.fill_tx_frame(s, 0x44)
        s.call('DEFER_CURRENT_TX')
        self.assertEqual(s.eth.take_sent(), [pending])        # older one first
        self.assertEqual(s.peek('ACK_REPLY_PACKET', 60), new)
        self.assertEqual(s.peek('ACK_REPLY_PENDING'), 1)
        self.assertEqual(s.peek('ETH_TX_FRAME_DEST_MAC', 60), new)   # untouched
        s.call('ETH_PROCESS_DEFERRED')
        self.assertEqual(s.eth.take_sent(), [new])

    def test_short_pending_frame_is_padded_from_the_slot(self):
        s = Stack.ready()
        self.pend(s, bytes([0x66]) * 42)                       # e.g. an ARP request
        new = self.fill_tx_frame(s, 0x77)
        s.call('DEFER_CURRENT_TX')
        self.assertEqual(s.eth.take_sent(), [bytes([0x66]) * 42 + bytes(18)])
        self.assertEqual(s.peek('ETH_TX_FRAME_DEST_MAC', 60), new)
        self.assertEqual(s.peek('ETH_TX_LEN_LSB'), 60)

    def test_defer_with_busy_transmitter_replaces_slot(self):
        s = Stack.ready()
        self.pend(s, bytes([0x33]) * 60)
        new = self.fill_tx_frame(s, 0x44)
        s.eth.tx_busy = True
        s.call('DEFER_CURRENT_TX')
        self.assertEqual(s.eth.sent, [])
        self.assertEqual(s.peek('ACK_REPLY_PACKET', 60), new)
        self.assertEqual(s.peek('ACK_REPLY_PENDING'), 1)

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
