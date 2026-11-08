"""Test harness for the mega-ip stack on the m65sim simulator.

Assembles src/eth.asm once per test run, loads it into bank 4 ($42000, seen
by the CPU at $2000-$7FFF as under BASIC's MAP), and calls routines by label.
`Peer` plays the remote host on the LAN.
"""

import copy
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools', 'sim'))

from m65sim import Machine, assemble, find_tass  # noqa: E402

import net  # noqa: E402
from net import ACK, FIN, PSH, RST, SYN  # noqa: E402,F401

BANK4 = 0x40000
_ASSEMBLY = None
_READY = None


def assembly():
    """Assemble src/eth.asm from this repo, or from $MEGAIP_ROOT (e.g. an
    older checkout, to confirm a test fails without its fix)."""
    global _ASSEMBLY
    if _ASSEMBLY is None:
        src_root = os.environ.get('MEGAIP_ROOT', ROOT)
        _ASSEMBLY = assemble(os.path.join(src_root, 'src', 'eth.asm'), find_tass(ROOT))
    return _ASSEMBLY


TCP_STATES = {0x00: 'CLOSED', 0x02: 'SYN_SENT', 0x03: 'SYN_RECEIVED', 0x04: 'ESTABLISHED',
              0x05: 'FIN_WAIT_1', 0x06: 'FIN_WAIT_2', 0x07: 'CLOSE_WAIT',
              0x09: 'LAST_ACK', 0x0A: 'TIME_WAIT'}


class Stack:
    MY_IP = (192, 168, 1, 50)
    GATEWAY = (192, 168, 1, 1)
    MASK = (255, 255, 255, 0)

    def __init__(self):
        self.asm = assembly()
        self.m = Machine(cpu_map=[(0x2000, 0x7FFF, BANK4 + 0x2000)])
        self.m.load_flat(BANK4 + self.asm.start, self.asm.binary)
        self.eth = self.m.eth
        self.mac = bytes(self.eth.mac)

    # ---- low level -----------------------------------------------------
    def addr(self, name):
        return name if isinstance(name, int) else self.asm[name]

    def call(self, name, a=0, x=0, y=0, z=0, **kw):
        return self.m.call(self.addr(name), a, x, y, z, **kw)

    def peek(self, name, n=1, offset=0):
        base = self.addr(name) + offset
        data = bytes(self.m.read(base + i) for i in range(n))
        return data[0] if n == 1 else data

    def poke(self, name, data, offset=0):
        base = self.addr(name) + offset
        for i, b in enumerate(bytes(data) if not isinstance(data, int) else [data]):
            self.m.write(base + i, b)

    def word_be(self, name, n=4):
        return int.from_bytes(self.peek(name, n), 'big')

    # ---- stack API -------------------------------------------------------
    # Raster timing.  ETH_INIT busy-waits ~4 s of raster lines for the PHY,
    # so it runs with very short lines.  Afterwards a line is long enough
    # that a poll spans only a few lines, as at 40 MHz; otherwise the
    # frame-paced timers would see the raster wrap more than once per frame.
    INIT_INSTRUCTIONS_PER_LINE = 2
    INSTRUCTIONS_PER_LINE = 400

    def init(self, ip=None, gateway=None, mask=None):
        self.m.instructions_per_line = self.INIT_INSTRUCTIONS_PER_LINE
        self.call('ETH_INIT')
        self.m.instructions_per_line = self.INSTRUCTIONS_PER_LINE
        self.call('ETH_SET_LOCAL_IP', *(ip or self.MY_IP))
        self.call('ETH_SET_GATEWAY_IP', *(gateway or self.GATEWAY))
        self.call('ETH_SET_SUBNET_MASK', *(mask or self.MASK))
        self.eth.take_sent()
        return self

    def poll(self, times=1):
        a = 0
        for _ in range(times):
            a = self.call('ETH_STATUS_POLL').a
        return a

    def run_frames(self, frames, polls_per_frame=2, until=None, on_frame=None):
        """Let `frames` video frames pass, polling `polls_per_frame` times per
        frame as a program on the MEGA65 would.  The frame-paced timers notice
        a new frame when the raster has gone back since the last poll, so they
        need at least two polls per frame.

        `on_frame(sent)` gets the frames transmitted at each poll; `until()`
        stops early when it returns true.  Returns (events seen OR'd together,
        frames run).
        """
        step = self.m.instructions_per_line * self.m.lines_per_frame // polls_per_frame
        events = 0
        for n in range(1, frames + 1):
            for _ in range(polls_per_frame):
                self.m.time_offset += step
                events |= self.poll()
                sent = self.sent()
                if on_frame:
                    on_frame(sent)
            if until and until():
                return events, n
        return events, frames

    @property
    def state(self):
        return TCP_STATES.get(self.peek('TCP_STATE'), hex(self.peek('TCP_STATE')))

    def deliver(self, frame):
        return self.eth.receive(frame)

    def sent(self):
        return [net.Parsed(f) for f in self.eth.take_sent()]

    @classmethod
    def ready(cls):
        """A stack that has run ETH_INIT and has an address, gateway and mask.
        ETH_INIT waits ~4 s of raster lines, so one initialised machine is
        kept and deep-copied for each test."""
        global _READY
        if _READY is None:
            _READY = cls().init()
        return copy.deepcopy(_READY)

    BLOCK_BUFFER = 0x20000          # bank 2, unused by the stack

    def read_received(self, method='block'):
        """Drain the RX ring and return the bytes.

        'block' uses ETH_RBUF_GET_BLOCK (ML table, up to 255 bytes a call),
        which is fast; 'byte' uses RBUF_GET, the BASIC byte reader ($4201e:
        C=0 byte in A, C=1 empty)."""
        out = bytearray()
        if method == 'byte':
            while True:
                c = self.call('RBUF_GET')
                if c.p & 1:
                    return bytes(out)
                out.append(c.a)
        while True:
            dest = self.BLOCK_BUFFER
            n = self.call('ETH_RBUF_GET_BLOCK', dest & 0xFF, (dest >> 8) & 0xFF,
                          dest >> 16, 255).a
            out += self.m.dump_flat(dest, n)
            if n < 255:
                return bytes(out)

    def set_astr(self, text):
        """Make BASIC's A$ hold `text` (descriptor at $FD60, data in bank 1)."""
        data = text.encode('ascii') if isinstance(text, str) else bytes(text)
        self.m.write_flat(0xFD60, len(data))
        self.m.write_flat(0xFD61, 0x00)
        self.m.write_flat(0xFD62, 0xF0)
        self.m.load_flat(0x1F000, data)

    def set_host(self, name):
        """Put a NUL-terminated hostname in host_str (as a previous lookup would)."""
        self.poke('host_str', name.encode('ascii') + b'\x00')

    def send_data(self, payload):
        """Queue `payload` like ETH_TCP_SEND does from BASIC; returns carry."""
        self.poke('TCP_DATA_PAYLOAD', payload)
        self.poke('TCP_DATA_PAYLOAD_SIZE', [len(payload) & 0xFF, len(payload) >> 8])
        return self.call('ETH_TCP_SEND').p & 1


class Peer:
    """A host on the LAN that answers ARP and speaks TCP to the stack."""

    def __init__(self, stack, ip=(192, 168, 1, 77), mac=b'\x02\x00\x00\x00\x00\x77',
                 port=23):
        self.s = stack
        self.ip, self.mac, self.port = tuple(ip), bytes(mac), port
        self.seq = 1000
        self.ack = 0
        self.local_port = None

    # ARP
    def arp_reply_to(self, request):
        a = request.arp
        body = net.arp(2, self.mac, self.ip, a['sha'], a['spa'])
        return net.ethernet(a['sha'], self.mac, net.ETH_ARP, body)

    def arp_request_for_stack(self):
        body = net.arp(1, self.mac, self.ip, bytes(6), self.s.peek('LOCAL_IP', 4))
        return net.ethernet(net.BROADCAST, self.mac, net.ETH_ARP, body)

    # TCP
    def segment(self, flags, payload=b'', seq=None, ack=None, window=4096):
        t = net.tcp(self.ip, self.s.peek('LOCAL_IP', 4), self.port, self.local_port,
                    self.seq if seq is None else seq, self.ack if ack is None else ack,
                    flags, payload, window)
        ip = net.ipv4(self.ip, self.s.peek('LOCAL_IP', 4), net.PROTO_TCP, t)
        return net.ethernet(self.s.mac, self.mac, net.ETH_IPV4, ip)

    def send(self, flags, payload=b'', **kw):
        frame = self.segment(flags, payload, **kw)
        self.s.deliver(frame)
        if 'seq' not in kw:
            self.seq += len(payload) + (1 if flags & (SYN | FIN) else 0)
        return frame

    def open_to_listener(self, listen_port):
        """Send a SYN to a listening stack and return its SYN-ACK frame."""
        s = self.s
        self.local_port = listen_port
        s.deliver(self.arp_request_for_stack())       # let it learn our MAC
        s.poll()
        s.sent()
        self.send(SYN)
        s.poll()
        synacks = [f for f in s.sent() if f.tcp and f.tcp['flags'] & SYN]
        if not synacks:
            raise AssertionError('no SYN-ACK from listener (state %s)' % s.state)
        self.ack = synacks[0].tcp['seq'] + 1
        return synacks[0]

    def connect_stack(self):
        """Drive an active open from the stack to this peer to ESTABLISHED."""
        s = self.s
        s.call('ETH_SET_REMOTE_IP', *self.ip)
        s.call('ETH_SET_REMOTE_PORT', self.port >> 8, self.port & 0xFF)
        s.call('ETH_TCP_CONNECT_START')
        for _ in range(50):
            s.call('ETH_CONNECT_POLL')
            for f in s.sent():
                if f.arp and f.arp['op'] == 1 and tuple(f.arp['tpa']) == self.ip:
                    s.deliver(self.arp_reply_to(f))
                elif f.tcp and f.tcp['flags'] & SYN:
                    self.local_port = f.tcp['sport']
                    self.ack = f.tcp['seq'] + 1
                    s.deliver(self.segment(SYN | ACK))
                    self.seq += 1
            if s.state == 'ESTABLISHED':
                s.sent()            # drop the handshake ACK
                return
        raise AssertionError('connect did not reach ESTABLISHED (state %s)' % s.state)


# ---- DNS -------------------------------------------------------------------
DNS_STATE_IDLE, DNS_STATE_WAIT, DNS_STATE_DONE, DNS_STATE_FAIL = 0, 1, 2, 3


def start_lookup(s, host='example.com'):
    """Start a DNS lookup of `host` against a resolver on the LAN, answering
    its ARP; returns (resolver Peer, the stack's query frame)."""
    dns = Peer(s, ip=(192, 168, 1, 53), mac=bytes([2, 0, 0, 0, 0, 0x53]))
    s.call('ETH_SET_PRIMARY_DNS', *dns.ip)
    s.set_host(host)
    s.call('DNS_RESOLVE_START')
    found = []

    def watch(sent):
        for f in sent:
            if f.arp and f.arp['op'] == 1 and tuple(f.arp['tpa']) == dns.ip:
                s.deliver(dns.arp_reply_to(f))
            elif f.udp and f.udp['dport'] == 53 and not found:
                found.append(f)

    s.run_frames(500, on_frame=watch, until=lambda: bool(found))
    if not found:
        raise AssertionError('no DNS query sent')
    return dns, found[0]


def dns_state(s):
    return s.call('ETH_GET_DNS_STATE').a


def dns_result(s):
    r = s.call('ETH_GET_DNS_RESULT_IP')
    return (r.a, r.x, r.y, r.z)
