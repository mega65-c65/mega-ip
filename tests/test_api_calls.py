"""Behaviour of the public entry points, called by address exactly as BASIC
(SYS $420xx) and ML programs ($476xx) call them.  test_api.py checks that
the addresses don't move; this checks what they do."""

import unittest

import net
from stack import ACK, PSH, SYN, Peer, Responder, Stack, dns_state

SYS = {   # BASIC SYS address -> CPU address in bank 4
    'init': 0x2000, 'set_gateway': 0x2003, 'set_local_ip': 0x2006,
    'set_local_port': 0x2009, 'set_remote_ip': 0x200C, 'set_remote_port': 0x200F,
    'set_mask': 0x2012, 'set_xlate': 0x2015, 'send_payload': 0x2018,
    'send_astr': 0x201B, 'get_byte': 0x201E, 'disconnect': 0x2021, 'poll': 0x2024,
    'connect_start': 0x2027, 'connect_poll': 0x202A, 'connect_cancel': 0x202D,
    'dns_lookup_astr': 0x2030, 'dns_result': 0x2033, 'dns_state': 0x2036,
    'listen_start': 0x2039, 'listen_stop': 0x203C, 'accept_poll': 0x203F,
    'dhcp_start': 0x2042, 'dhcp_poll': 0x2045, 'dhcp_state': 0x2048,
    'set_dns': 0x204B, 'get_local_ip': 0x204E, 'get_gateway': 0x2051,
    'get_mask': 0x2054, 'get_dns': 0x2057, 'get_remote_ip': 0x205A,
    'force_close': 0x205D, 'abi': 0x2060, 'dns_start_astr': 0x2063, 'tx_idle': 0x2066,
}
ML = {    # ML extension table, bank 4 $7600+
    'send_byte': 0x7600, 'dns_lookup_buffer': 0x7603, 'init_ml_safe': 0x7606,
    'dns_start_buffer': 0x760F, 'dns_start_buffer_bank1': 0x7618, 'staged': 0x761B,
    'get_byte': 0x761E, 'get_block': 0x7621,
}
RESERVED = [0x7609, 0x760C, 0x7612, 0x7615, 0x7624, 0x7627, 0x762A, 0x762D]
CONN_CONNECTED, CONN_FAILED, CONN_IN_PROGRESS, CONN_ARP_WAIT, CONN_SYN_SENT = 1, 2, 4, 8, 16


def regs4(r):
    return (r.a, r.x, r.y, r.z)


def connected(xlate=0):
    s = Stack.ready()
    p = Peer(s)
    p.connect_stack()
    s.call(SYS['set_xlate'], xlate)
    return s, p


def data_sent(s):
    return [f.tcp['payload'] for f in s.sent() if f.tcp and f.tcp['payload']]


class Configuration(unittest.TestCase):
    def test_setters_and_getters_round_trip(self):
        s = Stack.ready()
        for setter, getter, value in (('set_local_ip', 'get_local_ip', (10, 1, 2, 3)),
                                      ('set_gateway', 'get_gateway', (10, 1, 2, 254)),
                                      ('set_mask', 'get_mask', (255, 255, 0, 0)),
                                      ('set_dns', 'get_dns', (9, 9, 9, 9)),
                                      ('set_remote_ip', 'get_remote_ip', (1, 2, 3, 4))):
            with self.subTest(setter=setter):
                s.call(SYS[setter], *value)
                self.assertEqual(regs4(s.call(SYS[getter])), value)

    def test_ports_are_stored_high_byte_first(self):
        s = Stack.ready()
        s.call(SYS['set_local_port'], 0xC0, 0x01)
        s.call(SYS['set_remote_port'], 0x00, 23)
        self.assertEqual(s.peek('LOCAL_PORT', 2), b'\xc0\x01')
        self.assertEqual(s.peek('REMOTE_PORT', 2), b'\x00\x17')

    def test_abi_info(self):
        r = Stack.ready().call(SYS['abi'])
        self.assertEqual((r.a, r.x), (1, 0))
        self.assertTrue(r.y & 1)
        self.assertTrue(r.z & 1)


class SendAndReceive(unittest.TestCase):
    def test_send_astr_raw(self):
        s, p = connected(xlate=0)
        s.set_astr('Hello')
        s.call(SYS['send_astr'])
        s.poll()
        self.assertEqual(data_sent(s), [b'Hello'])

    def test_send_astr_translates_petscii_to_ascii(self):
        s, p = connected(xlate=1)
        s.set_astr(bytes([0xC8, 0x45, 0x4C, 0x4C, 0x4F]) + b' 1!')   # PETSCII "Hello 1!"
        s.call(SYS['send_astr'])
        s.poll()
        self.assertEqual(data_sent(s), [b'Hello 1!'])

    def test_send_astr_longer_than_one_segment_is_cut(self):
        s, p = connected()
        s.set_astr(b'x' * 255)
        s.call(SYS['send_astr'])
        s.poll()
        self.assertEqual(data_sent(s), [b'x' * s.asm['TCP_PAYLOAD_MAX']])

    def test_send_astr_when_closed_sends_nothing(self):
        s = Stack.ready()
        s.set_astr('Hello')
        s.call(SYS['send_astr'])
        s.poll()
        self.assertEqual(s.sent(), [])

    def test_get_byte_translates_ascii_to_petscii(self):
        s, p = connected(xlate=1)
        p.send(PSH | ACK, b'Hi z!')
        s.poll()
        got = []
        while True:
            r = s.call(SYS['get_byte'])
            if r.carry:
                break
            got.append(r.a)
        self.assertEqual(got, [0xC8, 0x49, 0x20, 0x5A, 0x21])

    def test_get_byte_raw_when_not_translating(self):
        s, p = connected(xlate=0)
        p.send(PSH | ACK, b'Hi')
        s.poll()
        self.assertEqual(s.read_received(method='byte'), b'Hi')

    def test_block_reader_returns_raw_bytes_even_when_translating(self):
        """The ML block reader copies the ring as-is; translation applies only
        to the BASIC byte reader.  (Recorded as current behaviour.)"""
        s, p = connected(xlate=1)
        p.send(PSH | ACK, b'Hi')
        s.poll()
        self.assertEqual(s.read_received(method='block'), b'Hi')


class Connect(unittest.TestCase):
    def test_connect_poll_reports_progress(self):
        s = Stack.ready()
        p = Peer(s)
        s.call(SYS['set_remote_ip'], *p.ip)
        s.call(SYS['set_remote_port'], 0, p.port)
        self.assertEqual(s.call(SYS['connect_start']).a, CONN_IN_PROGRESS | CONN_ARP_WAIT)
        seen = []
        for _ in range(20):
            seen.append(s.call(SYS['connect_poll']).a)
            for f in s.sent():
                if f.arp and f.arp['op'] == 1:
                    s.deliver(p.arp_reply_to(f))
                elif f.tcp and f.tcp['flags'] & SYN:
                    p.local_port, p.ack = f.tcp['sport'], f.tcp['seq'] + 1
                    s.deliver(p.segment(SYN | ACK))
                    p.seq += 1
        self.assertIn(CONN_IN_PROGRESS | CONN_SYN_SENT, seen)
        self.assertEqual(seen[-1], CONN_CONNECTED)

    def test_connect_cancel_resets_with_next_sequence_number(self):
        s = Stack.ready()
        p = Peer(s)
        s.call(SYS['set_remote_ip'], *p.ip)
        s.call(SYS['set_remote_port'], 0, p.port)
        s.call(SYS['connect_start'])
        syn = None
        for _ in range(20):
            s.call(SYS['connect_poll'])
            for f in s.sent():
                if f.arp and f.arp['op'] == 1:
                    s.deliver(p.arp_reply_to(f))
                elif f.tcp and f.tcp['flags'] & SYN:
                    syn = f
            if syn:
                break
        s.call(SYS['connect_cancel'])
        rst = [f for f in s.sent() if f.tcp and f.tcp['flags'] & 0x04]
        self.assertEqual(len(rst), 1)
        # A peer in SYN-RECEIVED expects SEQ = ISS+1; ISS itself is ignored.
        self.assertEqual(rst[0].tcp['seq'], (syn.tcp['seq'] + 1) & 0xFFFFFFFF)
        self.assertEqual(s.state, 'CLOSED')
        self.assertEqual(s.call(SYS['connect_poll']).a & CONN_IN_PROGRESS, 0)


class Listen(unittest.TestCase):
    def test_accept_poll(self):
        s = Stack.ready()
        s.call(SYS['listen_start'], 0, 80)
        self.assertEqual(s.call(SYS['accept_poll']).a, 0)
        p = Peer(s, port=5000)
        p.open_to_listener(80)
        p.send(ACK)
        s.poll()
        self.assertEqual(s.call(SYS['accept_poll']).a & 1, 1)

    def test_listen_stop_refuses_connections(self):
        s = Stack.ready()
        s.call(SYS['listen_start'], 0, 80)
        s.call(SYS['listen_stop'])
        p = Peer(s, port=5000)
        p.local_port = 80
        s.deliver(p.arp_request_for_stack())
        s.poll()
        s.sent()
        p.send(SYN)
        s.poll()
        replies = [f for f in s.sent() if f.tcp]
        self.assertEqual(len(replies), 1)
        self.assertTrue(replies[0].tcp['flags'] & 0x04)        # RST
        self.assertEqual(s.state, 'CLOSED')


class Dns(unittest.TestCase):
    def setUp(self):
        self.s = Stack.ready()
        self.resolver = Peer(self.s, ip=(192, 168, 1, 53), mac=bytes([2, 0, 0, 0, 0, 0x53]))
        self.s.call(SYS['set_dns'], *self.resolver.ip)

    def answer(self, answers):
        self.s.eth.on_transmit = Responder(self.s, resolver=self.resolver, answers=answers)

    def blocking(self):
        # A blocking call polls in a tight loop, so short raster lines still
        # give many polls per frame and the wait passes in fewer instructions.
        self.s.m.instructions_per_line = 20

    def test_blocking_lookup_from_astr(self):
        self.answer({'example.com': (93, 184, 216, 34)})
        self.s.set_astr('example.com')
        self.blocking()
        r = self.s.call(SYS['dns_lookup_astr'], max_instructions=3_000_000)
        self.assertEqual(r.a, 1)
        self.assertEqual(regs4(self.s.call(SYS['get_remote_ip'])), (93, 184, 216, 34))
        self.assertEqual(regs4(self.s.call(SYS['dns_result'])), (93, 184, 216, 34))

    def test_non_blocking_lookup_from_astr(self):
        self.answer({'example.com': (1, 2, 3, 4)})
        self.s.set_astr('example.com')
        self.assertEqual(self.s.call(SYS['dns_start_astr']).a, 1)
        self.s.run_frames(200, until=lambda: dns_state(self.s) != 1)
        self.assertEqual(self.s.call(SYS['dns_state']).a, 2)
        self.assertEqual(regs4(self.s.call(SYS['dns_result'])), (1, 2, 3, 4))

    def put_name(self, addr, name):
        self.s.m.load_flat(addr, name.encode('ascii'))

    def test_ml_blocking_lookup_from_buffer(self):
        self.answer({'example.org': (5, 6, 7, 8)})
        self.put_name(0x21000, 'example.org')
        self.blocking()
        r = self.s.call(ML['dns_lookup_buffer'], 0x00, 0x10, 0x02, 11,
                        max_instructions=3_000_000)
        self.assertEqual(r.a, 1)
        self.assertEqual(regs4(self.s.call(SYS['get_remote_ip'])), (5, 6, 7, 8))

    def test_ml_start_from_buffer(self):
        self.answer({'example.net': (7, 7, 7, 7)})
        self.put_name(0x21000, 'example.net')
        self.assertEqual(self.s.call(ML['dns_start_buffer'], 0x00, 0x10, 0x02, 11).a, 1)
        self.s.run_frames(200, until=lambda: dns_state(self.s) != 1)
        self.assertEqual(regs4(self.s.call(SYS['dns_result'])), (7, 7, 7, 7))

    def test_ml_start_from_bank1_workspace(self):
        self.answer({'host.lan': (8, 8, 4, 4)})
        self.put_name(0x13000, 'host.lan')
        self.assertEqual(self.s.call(ML['dns_start_buffer_bank1'], 0x00, 0x30, 8).a, 1)
        self.s.run_frames(200, until=lambda: dns_state(self.s) != 1)
        self.assertEqual(regs4(self.s.call(SYS['dns_result'])), (8, 8, 4, 4))

    def test_ml_bank1_buffer_outside_workspace_is_rejected(self):
        for hi in (0x10, 0x1F, 0xF8):              # DOS area, $1Fxx, colour RAM
            with self.subTest(hi=hi):
                self.assertEqual(self.s.call(ML['dns_start_buffer_bank1'], 0x00, hi, 8).a, 0)
        self.assertEqual(self.s.sent(), [])


class MlTable(unittest.TestCase):
    def test_send_byte(self):
        s, p = connected()
        r = s.call(ML['send_byte'], 0x41)
        self.assertEqual((r.a, r.carry), (1, 0))
        s.poll()
        self.assertEqual(data_sent(s), [b'A'])

    def test_send_byte_when_closed_fails(self):
        r = Stack.ready().call(ML['send_byte'], 0x41)
        self.assertEqual((r.a, r.carry), (0, 1))

    def test_get_byte(self):
        s, p = connected()
        p.send(PSH | ACK, b'Z')
        s.poll()
        r = s.call(ML['get_byte'])
        self.assertEqual((r.x, r.a), (1, ord('Z')))
        self.assertEqual(s.call(ML['get_byte']).x, 0)

    def test_get_block_counts_and_limits(self):
        s, p = connected()
        p.send(PSH | ACK, b'0123456789')
        s.poll()
        r = s.call(ML['get_block'], 0x00, 0x00, 0x02, 4)     # at most 4 bytes
        self.assertEqual(r.a, 4)
        self.assertEqual(s.m.dump_flat(0x20000, 4), b'0123')
        self.assertEqual(s.read_received(), b'456789')

    def test_reserved_slots_return_zero(self):
        s = Stack.ready()
        for addr in RESERVED:
            with self.subTest(addr=hex(addr)):
                self.assertEqual(regs4(s.call(addr, 9, 9, 9, 9)), (0, 0, 0, 0))

    def test_staged_dispatcher_passes_and_returns_registers(self):
        s = Stack.ready()
        s.poke('ML_CALL_TARGET_LO', SYS['set_local_ip'] & 0xFF)
        s.poke('ML_CALL_TARGET_HI', SYS['set_local_ip'] >> 8)
        s.poke('ML_CALL_ARG_A', [10, 20, 30, 40])            # A X Y Z
        s.call(ML['staged'])
        self.assertEqual(tuple(s.peek('LOCAL_IP', 4)), (10, 20, 30, 40))
        s.poke('ML_CALL_TARGET_LO', SYS['get_local_ip'] & 0xFF)
        s.poke('ML_CALL_TARGET_HI', SYS['get_local_ip'] >> 8)
        r = s.call(ML['staged'])
        self.assertEqual(regs4(r), (10, 20, 30, 40))
        self.assertEqual(tuple(s.peek('ML_CALL_RET_A', 4)), (10, 20, 30, 40))

    def test_ml_safe_init_resets_session_keeps_address(self):
        s, p = connected()
        s.call(ML['init_ml_safe'])
        self.assertEqual(s.state, 'CLOSED')
        self.assertEqual(tuple(s.peek('LOCAL_IP', 4)), Stack.MY_IP)
        self.assertEqual(s.eth.ctrl3 & 0x11, 0x11)


if __name__ == '__main__':
    unittest.main()
