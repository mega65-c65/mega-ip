"""Malformed input and fuzzing.

Bad frames must be dropped without changing connection state or sending
anything.  The fuzzer then feeds seeded random and mutated frames to a
connected stack and checks, after every frame, that the code doesn't crash,
hang, unbalance the stack or write outside its own memory, and finally that
the stack still works.

    MEGAIP_FUZZ=<frames>     frames per fuzz test (default 400)
    MEGAIP_FUZZ_SEED=<int>   base seed (default 1)

A fuzz failure names the seed and case number; rerun with that seed to
reproduce it exactly.
"""

import os
import random
import struct
import unittest

import net
from net import ACK, FIN, PSH, RST, SYN
from stack import Peer, Stack                     # puts tools/sim on sys.path
from m65sim import CpuError, DmaError, StopRun   # noqa: E402

FUZZ_FRAMES = int(os.environ.get('MEGAIP_FUZZ', '400'))
FUZZ_SEED = int(os.environ.get('MEGAIP_FUZZ_SEED', '1'))
POLL_LIMIT = 400_000          # instructions; a normal poll uses < 20,000

# Flat memory the stack may write: zero page and stack, its own bank 4
# image, the bank 5 receive ring and OOO slot, and the buffer the harness
# passes to ETH_RBUF_GET_BLOCK.  The ethernet buffers are I/O, not memory.
ALLOWED_WRITES = [(0x00000, 0x001FF), (0x42000, 0x47FFF), (0x50000, 0x515FF),
                  (Stack.BLOCK_BUFFER, Stack.BLOCK_BUFFER + 0xFF)]


def outside_allowed(m):
    """{page: bytes} of every memory page with the ALLOWED_WRITES bytes
    blanked, so only writes outside the stack's own memory show up."""
    out = {}
    for key, page in m.pages.items():
        base = key << 12
        data = bytearray(page)
        for lo, hi in ALLOWED_WRITES:
            a, b = max(lo, base), min(hi, base + 0xFFF)
            if a <= b:
                data[a - base:b - base + 1] = bytes(b - a + 1)
        out[key] = bytes(data)
    return out


def snapshot(s):
    return dict(state=s.state, rcv=s.peek('REMOTE_ISN', 4), snd=s.peek('LOCAL_ISN', 4),
                head=s.peek('RBUF_HEAD_LO', 2), ooo=s.peek('TCP_OOO_VALID'))


class MalformedFrames(unittest.TestCase):
    def setUp(self):
        self.s = Stack.ready()
        self.p = Peer(self.s)
        self.p.connect_stack()

    def data_frame(self, payload=b'data'):
        return bytearray(self.p.segment(PSH | ACK, payload))

    def assert_ignored(self, frame, note=''):
        s = self.s
        before = snapshot(s)
        s.deliver(bytes(frame))
        s.poll(2)
        self.assertEqual(snapshot(s), before, note)
        self.assertEqual(s.sent(), [], note)
        self.assertEqual(s.read_received(), b'', note)

    def test_control_valid_frame_is_accepted(self):
        self.s.deliver(bytes(self.data_frame()))
        self.s.poll()
        self.assertEqual(self.s.read_received(), b'data')

    def test_bad_tcp_checksum(self):
        f = self.data_frame()
        f[50] ^= 0xFF
        self.assert_ignored(f)

    def test_bad_ip_header_checksum(self):
        f = self.data_frame()
        f[24] ^= 0xFF
        self.assert_ignored(f)

    def test_ip_header_length_below_5(self):
        f = self.data_frame()
        f[14] = 0x44
        self.assert_ignored(net.refix_checksums(f))

    def test_ip_version_not_4(self):
        f = self.data_frame()
        f[14] = 0x65
        self.assert_ignored(net.refix_checksums(f))

    def test_ip_total_length_beyond_frame(self):
        f = self.data_frame()
        f[16:18] = struct.pack('!H', 1400)
        self.assert_ignored(net.refix_checksums(f))

    def test_ip_total_length_below_header(self):
        f = self.data_frame()
        f[16:18] = struct.pack('!H', 12)
        self.assert_ignored(net.refix_checksums(f))

    def test_fragments(self):
        for frag in (0x2000, 0x0010, 0x2010):      # MF, offset, both
            f = self.data_frame()
            f[20:22] = struct.pack('!H', frag)
            self.assert_ignored(net.refix_checksums(f), 'frag=%04x' % frag)

    def test_tcp_data_offset_past_segment(self):
        f = self.data_frame()
        f[46] = 0xF0                                # 60-byte header, 24-byte segment
        self.assert_ignored(net.refix_checksums(f))

    def test_tcp_data_offset_below_5(self):
        f = self.data_frame()
        f[46] = 0x40
        self.assert_ignored(net.refix_checksums(f))

    def test_crc_error_flag(self):
        s = self.s
        before = snapshot(s)
        s.eth.receive(bytes(self.data_frame()), crc_error=True)
        s.poll(2)
        self.assertEqual(snapshot(s), before)
        self.assertEqual(s.read_received(), b'')

    def test_runt_frame(self):
        self.assert_ignored(bytes(self.data_frame())[:16])

    def test_oversize_frame(self):
        self.assert_ignored(self.p.segment(PSH | ACK, b'x' * 1700))

    def test_other_unicast_mac(self):
        f = self.data_frame()
        f[0:6] = b'\x02\x99\x99\x99\x99\x99'
        self.assert_ignored(f)

    def test_unknown_ethertype(self):
        f = self.data_frame()
        f[12:14] = b'\x86\xdd'                      # IPv6
        self.assert_ignored(f)

    def test_wrong_local_port_gets_rst_only(self):
        s, p = self.s, self.p
        before = snapshot(s)
        s.deliver(net.ethernet(s.mac, p.mac, net.ETH_IPV4, net.ipv4(
            p.ip, s.peek('LOCAL_IP', 4), net.PROTO_TCP,
            net.tcp(p.ip, s.peek('LOCAL_IP', 4), p.port, 4321, 5, 0, SYN))))
        s.poll()
        sent = s.sent()
        self.assertEqual(snapshot(s), before)
        self.assertEqual(len(sent), 1, sent)
        self.assertTrue(sent[0].tcp['flags'] & RST)
        self.assertEqual(sent[0].tcp['sport'], 4321)


class Fuzz(unittest.TestCase):
    """Seeded fuzzing of the receive path on a connected stack."""

    def setUp(self):
        self.s = Stack.ready()
        self.p = Peer(self.s)
        self.p.connect_stack()
        self.build_base_frames()

    def reconnect(self):
        """Random FINs and RSTs close the connection; reopen it so later cases
        exercise ESTABLISHED again."""
        self.s.call('ETH_TCP_FORCE_CLOSE')
        self.s.sent()
        self.p = Peer(self.s)
        self.p.connect_stack()
        self.build_base_frames()

    def build_base_frames(self):
        self.base_frames = [
            bytes(self.p.segment(PSH | ACK, b'hello')),
            bytes(self.p.segment(ACK)),
            bytes(self.p.segment(FIN | ACK)),
            self.p.arp_request_for_stack(),
            self.p.arp_reply_to(net.Parsed(self.p.arp_request_for_stack())),
            net.dhcp_reply(b'\x12\x34\x56\x78', self.s.mac, net.DHCP_OFFER,
                           (192, 168, 1, 9), (192, 168, 1, 1)),
            net.ethernet(self.s.mac, self.p.mac, net.ETH_IPV4, net.ipv4(
                self.p.ip, self.s.peek('LOCAL_IP', 4), net.PROTO_ICMP,
                b'\x08\x00\xf7\xff' + bytes(4) + b'ping')),
        ]

    def generate(self, rng):
        kind = rng.randrange(6)
        if kind == 0:                                   # random bytes
            n = rng.randrange(14, 160)
            dst = rng.choice([self.s.mac, net.BROADCAST])
            return dst + bytes(rng.getrandbits(8) for _ in range(n - 6))
        base = bytearray(rng.choice(self.base_frames))
        if kind in (1, 2):                              # flip bytes after the MAC
            for _ in range(rng.randrange(1, 5)):
                i = rng.randrange(12, len(base))
                base[i] = rng.getrandbits(8)
            return net.refix_checksums(base) if kind == 2 else bytes(base)
        if kind == 3:                                   # truncate or extend
            n = rng.randrange(14, len(base) + 40)
            return bytes(base[:n]) + bytes(rng.getrandbits(8)
                                           for _ in range(max(0, n - len(base))))
        if kind == 4:                                   # valid TCP, random fields
            p = self.p
            flags = rng.getrandbits(8) & 0x3F
            payload = bytes(rng.getrandbits(8) for _ in range(rng.randrange(0, 80)))
            return p.segment(flags, payload, seq=rng.getrandbits(32),
                             ack=rng.getrandbits(32), window=rng.getrandbits(16))
        # valid UDP to the DHCP or DNS client ports with a random payload
        sport, dport = rng.choice([(67, 68), (53, rng.getrandbits(16))])
        payload = bytes(rng.getrandbits(8) for _ in range(rng.randrange(0, 400)))
        u = net.udp(self.p.ip, self.s.peek('LOCAL_IP', 4), sport, dport, payload)
        return net.ethernet(self.s.mac, self.p.mac, net.ETH_IPV4, net.ipv4(
            self.p.ip, self.s.peek('LOCAL_IP', 4), net.PROTO_UDP, u))

    def run_fuzz(self, seed, frames, setup=None):
        s = self.s
        if setup:
            setup(s)
        rng = random.Random(seed)
        protected = outside_allowed(s.m)
        for i in range(frames):
            frame = self.generate(rng)
            s.deliver(frame)
            try:
                s.call('ETH_STATUS_POLL', max_instructions=POLL_LIMIT)
            except (CpuError, DmaError, StopRun) as e:
                self.fail('seed %d case %d: %s\nframe: %s' % (seed, i, e, frame.hex()))
            s.sent()
            s.read_received()
            if i % 100 == 99 and s.state != 'ESTABLISHED' and not setup:
                self.reconnect()
            if i % 50 == 49 or i == frames - 1:
                now = outside_allowed(s.m)
                changed = sorted('%05x' % (k << 12) for k in set(now) | set(protected)
                                 if now.get(k, bytes(4096)) != protected.get(k, bytes(4096)))
                self.assertEqual(changed, [], 'seed %d by case %d: stack wrote outside '
                                 'its memory (pages %s)' % (seed, i, changed))
        self.assert_still_works()

    def assert_still_works(self):
        s = self.s
        s.call('ETH_TCP_FORCE_CLOSE')
        s.sent()
        p = Peer(s, ip=(192, 168, 1, 200), mac=b'\x02\x00\x00\x00\x00\xc8', port=8023)
        p.connect_stack()
        p.send(PSH | ACK, b'still alive')
        s.poll()
        self.assertEqual(s.read_received(), b'still alive')

    def test_fuzz_connected(self):
        self.run_fuzz(FUZZ_SEED, FUZZ_FRAMES)

    def test_fuzz_while_dns_lookup_waits(self):
        def dns_waiting(s):
            s.call('ETH_SET_PRIMARY_DNS', *self.p.ip)
            s.set_host('example.com')
            s.call('DNS_RESOLVE_START')
        self.run_fuzz(FUZZ_SEED + 1000, FUZZ_FRAMES // 2, setup=dns_waiting)


if __name__ == '__main__':
    unittest.main()
