"""Structure-aware fuzzing of the DNS and DHCP reply parsers.

The general fuzzer in test_malformed.py mostly produces frames that fail a
checksum or an ID check before any parser sees them.  These build replies
that pass those checks (right DNS ID and port, right DHCP XID and client
address, valid checksums) but have random structure, so they reach the
parsers' bounds checks and error paths.

After every reply: no CPU/DMA error, no hang, balanced stack; every 50
replies, nothing written outside the stack's memory.  Plus an oracle:
- DNS: a lookup that completes returns the data of an A record with
  RDLENGTH 4 that was in the reply; the parser never invents an address
  or takes one from a malformed record.
- DHCP: the stack only binds from a reply that is a DHCPACK with a
  non-zero contiguous subnet mask, and binds to that reply's yiaddr.
At the end a normal lookup / lease must still work.

    MEGAIP_FUZZ=<n>          replies per test (default 300)
    MEGAIP_FUZZ_SEED=<int>   base seed (default 1)
"""

import os
import random
import struct
import unittest

import net
from stack import Peer, Stack, dns_result, dns_state
from test_dhcp import IP_A, SERVER_A, wait_for_dhcp
from test_malformed import outside_allowed
from m65sim import CpuError, DmaError, StopRun   # noqa: E402  (after stack)

REPLIES = int(os.environ.get('MEGAIP_FUZZ', '300'))
SEED = int(os.environ.get('MEGAIP_FUZZ_SEED', '1'))
POLL_LIMIT = 400_000
DNS_WAIT, DNS_DONE = 1, 2


class ParserFuzz(unittest.TestCase):
    def poll(self, seed, i, frame):
        try:
            self.s.call('ETH_STATUS_POLL', max_instructions=POLL_LIMIT)
        except (CpuError, DmaError, StopRun) as e:
            self.fail('seed %d case %d: %s\nframe: %s' % (seed, i, e, frame.hex()))

    def check_memory(self, seed, i):
        now = outside_allowed(self.s.m)
        changed = sorted('%05x' % (k << 12) for k in set(now) | set(self.protected)
                         if now.get(k, bytes(4096)) != self.protected.get(k, bytes(4096)))
        self.assertEqual(changed, [], 'seed %d by case %d: wrote outside the stack (%s)'
                         % (seed, i, changed))


# ---- DNS ---------------------------------------------------------------------

def random_label(rng):
    n = rng.choice([0, 1, 3, 5, 7, 63, 64, 70, rng.randrange(1, 64)])
    return bytes([n]) + bytes(rng.choice(b'abcxyz019-') for _ in range(min(n, 70)))


def random_name(rng, msg_len):
    """A domain name: labels, optionally ending in a pointer (valid, to self,
    forward, past the end) instead of the root label."""
    out = b''.join(random_label(rng) for _ in range(rng.randrange(0, 4)))
    end = rng.randrange(6)
    if end == 0:
        out += b'\x00'
    elif end == 1:
        out += b'\xc0\x0c'                                   # question name
    elif end == 2:
        out += struct.pack('!H', 0xC000 | rng.randrange(0, 0x4000))   # anywhere
    elif end == 3:
        out += struct.pack('!H', 0xC000 | msg_len)          # points at itself
    elif end == 4:
        out += bytes([rng.choice([0x40, 0x80, 0xFF])])      # reserved label types
    else:
        out += b'\x00'
    return out


def random_record(rng, msg_len):
    name = b'\xc0\x0c' if rng.random() < 0.5 else random_name(rng, msg_len)
    rtype = rng.choice([1, 1, 1, 5, 5, 2, 28, rng.randrange(65536)])
    rclass = 1 if rng.random() < 0.9 else rng.randrange(65536)
    if rtype == 1:
        rdata = bytes(rng.getrandbits(8) for _ in range(rng.choice([4, 4, 4, 0, 3, 6, 16])))
    elif rtype == 5:
        rdata = random_name(rng, msg_len + len(name) + 10)
    else:
        rdata = bytes(rng.getrandbits(8) for _ in range(rng.randrange(0, 20)))
    rdlength = len(rdata)
    if rng.random() < 0.15:                                  # lie about RDLENGTH
        rdlength = rng.choice([0, rdlength + 1, rdlength + 50, 0xFFFF, max(0, rdlength - 1)])
    return name + struct.pack('!HHIH', rtype, rclass, rng.getrandbits(32), rdlength) + rdata


def random_dns_reply(rng, query):
    q = query.udp['payload']
    flags = 0x8180 if rng.random() < 0.8 else rng.getrandbits(16)
    counts = [1 if rng.random() < 0.85 else rng.randrange(4)] + \
             [rng.choice([0, 1, 1, 2, 3, 10, 255]) for _ in range(3)]
    question = q[12:] if rng.random() < 0.9 else random_name(rng, 12) + b'\x00\x01\x00\x01'
    msg = q[0:2] + struct.pack('!HHHHH', flags, *counts) + question
    for _ in range(rng.randrange(0, 6)):
        msg += random_record(rng, len(msg))
    if rng.random() < 0.15:                                  # cut it short
        msg = msg[:rng.randrange(2, len(msg) + 1)]
    return msg, a_record_data(msg)


A_HEADER = bytes([0, 1, 0, 1])          # type A, class IN


def a_record_data(msg):
    """Every 4 bytes in `msg` that follow a type A, class IN, RDLENGTH 4
    record header.  Taken from the bytes on the wire, not from how the
    reply was built (a short RDATA plus a lying RDLENGTH can still form a
    valid A record with the next bytes)."""
    out = set()
    i = msg.find(A_HEADER)
    while i != -1:
        if msg[i + 8:i + 10] == bytes([0, 4]) and i + 14 <= len(msg):
            out.add(msg[i + 10:i + 14])
        i = msg.find(A_HEADER, i + 1)
    return out


class DnsReplyFuzz(ParserFuzz):
    def setUp(self):
        self.s = Stack.ready()
        self.dns = Peer(self.s, ip=(192, 168, 1, 53), mac=bytes([2, 0, 0, 0, 0, 0x53]))
        self.s.call('ETH_SET_PRIMARY_DNS', *self.dns.ip)
        self.s.deliver(self.dns.arp_reply_to(net.Parsed(net.ethernet(
            self.dns.mac, self.s.mac, net.ETH_ARP,
            net.arp(1, self.s.mac, self.s.peek('LOCAL_IP', 4), bytes(6), self.dns.ip)))))
        self.s.poll()
        self.query = None
        self.protected = outside_allowed(self.s.m)

    def watch_queries(self):
        for f in self.s.sent():
            if f.udp and f.udp['dport'] == 53:
                self.query = f

    def start(self, host='www.example.com'):
        self.s.set_host(host)
        self.s.call('DNS_RESOLVE_START')
        for _ in range(50):
            self.s.poll()
            self.watch_queries()
            if self.query:
                return
            self.s.run_frames(1)
        raise AssertionError('no DNS query')

    def deliver(self, payload):
        me = self.s.peek('LOCAL_IP', 4)
        u = net.udp(self.dns.ip, me, 53, self.query.udp['sport'], payload)
        frame = net.ethernet(self.s.mac, self.dns.mac, net.ETH_IPV4,
                             net.ipv4(self.dns.ip, me, net.PROTO_UDP, u))
        self.s.deliver(frame)
        return frame

    def test_fuzz_dns_replies(self):
        rng = random.Random(SEED)
        self.start()
        done = 0
        for i in range(REPLIES):
            payload, a_records = random_dns_reply(rng, self.query)
            frame = self.deliver(payload)
            self.poll(SEED, i, frame)
            self.watch_queries()                             # follow CNAME re-queries
            state = dns_state(self.s)
            if state == DNS_DONE:
                done += 1
                result = bytes(dns_result(self.s))
                self.assertIn(result, a_records,
                              'seed %d case %d: resolved to %s, not an A record in the reply'
                              '\nframe: %s' % (SEED, i, result.hex(), frame.hex()))
            if state != DNS_WAIT:
                self.query = None
                self.start()
            if i % 50 == 49:
                self.check_memory(SEED, i)
        self.check_memory(SEED, REPLIES)
        # a normal lookup still works
        self.query = None
        self.start('example.com')
        self.s.deliver(net.dns_reply(self.query, (93, 184, 216, 34), self.dns.mac,
                                     self.dns.ip, self.s.mac))
        self.s.poll()
        self.assertEqual(dns_state(self.s), DNS_DONE)
        self.assertEqual(dns_result(self.s), (93, 184, 216, 34))
        self.assertGreater(done, 0, 'no fuzz reply ever completed a lookup')


# ---- DHCP ----------------------------------------------------------------------

def contiguous(mask):
    m = int.from_bytes(bytes(mask), 'big')
    return m != 0 and ((~m) & 0xFFFFFFFF) & (((~m) & 0xFFFFFFFF) + 1) == 0


def random_options(rng):
    """(options bytes, dict of well-formed option values) - random order,
    lengths, padding, missing END."""
    out, seen = b'', {}
    for _ in range(rng.randrange(0, 12)):
        kind = rng.random()
        if kind < 0.1:
            out += b'\x00' * rng.randrange(1, 4)             # pad
            continue
        code = rng.choice([53, 53, 54, 1, 1, 3, 6, 51, 12, rng.randrange(1, 255)])
        if code == 53:
            value = bytes([rng.choice([2, 5, 5, 6, 1, 3, rng.randrange(256)])])
        elif code in (54, 1, 3, 6):
            if code == 1 and rng.random() < 0.6:
                value = rng.choice([b'\xff\xff\xff\x00', b'\xff\xff\x00\x00',
                                    b'\xff\x00\xff\x00', b'\x00\x00\x00\x00'])
            else:
                value = bytes(rng.getrandbits(8) for _ in range(4))
        elif code == 51:
            value = struct.pack('!I', rng.getrandbits(32))
        else:
            value = bytes(rng.getrandbits(8) for _ in range(rng.randrange(0, 12)))
        if rng.random() < 0.15:                              # wrong length
            value = value[:rng.randrange(0, len(value) + 1)] + \
                bytes(rng.getrandbits(8) for _ in range(rng.randrange(0, 3)))
        length = len(value)
        if rng.random() < 0.05:
            length = rng.choice([0xFF, len(value) + 20])     # runs past the end
        out += bytes([code, length]) + value
        if length == len(value) and code not in seen:
            seen[code] = value
    if rng.random() < 0.85:
        out += b'\xff'
    return out, seen


def random_dhcp_reply(rng, xid, mac):
    yiaddr = bytes([192, 168, 1, rng.randrange(1, 255)])
    op = 2 if rng.random() < 0.95 else rng.randrange(256)
    bootp = struct.pack('!BBBB4sHH4s4s4s4s', op, 1, 6, 0, bytes(xid), 0, 0x8000, bytes(4),
                        yiaddr, bytes(SERVER_A), bytes(4))
    bootp += bytes(mac) + bytes(10) + bytes(192)
    magic = b'\x63\x82\x53\x63' if rng.random() < 0.95 else bytes(4)
    opts, seen = random_options(rng)
    payload = bootp + magic + opts
    if rng.random() < 0.1:
        payload = payload[:rng.randrange(200, len(payload) + 1)]
    u = net.udp(SERVER_A, (255, 255, 255, 255), 67, 68, payload)
    frame = net.ethernet(net.BROADCAST, bytes([2, 0, 0, 0, 0, 1]), net.ETH_IPV4,
                         net.ipv4(SERVER_A, (255, 255, 255, 255), net.PROTO_UDP, u))
    valid_ack = (op == 2 and magic == b'\x63\x82\x53\x63' and seen.get(53) == b'\x05'
                 and 1 in seen and contiguous(seen[1]))
    return frame, yiaddr, valid_ack


class DhcpReplyFuzz(ParserFuzz):
    def setUp(self):
        self.s = Stack.ready()
        self.protected = outside_allowed(self.s.m)

    def restart(self):
        self.s.call('ETH_DHCP_START')
        xid, _ = wait_for_dhcp(self.s, net.DHCP_DISCOVER)
        return xid

    def test_fuzz_dhcp_replies(self):
        rng = random.Random(SEED + 2000)
        xid = self.restart()
        bound = 0
        for i in range(REPLIES):
            if rng.random() < 0.25:                          # reach REQUEST_SENT too
                self.s.deliver(net.dhcp_reply(xid, self.s.mac, net.DHCP_OFFER, IP_A, SERVER_A))
                self.s.poll()
                self.s.sent()
            frame, yiaddr, valid_ack = random_dhcp_reply(rng, xid, self.s.mac)
            self.s.deliver(frame)
            self.poll(SEED + 2000, i, frame)
            self.s.sent()
            if self.s.call('ETH_GET_DHCP_STATE').a == 4:      # BOUND
                bound += 1
                self.assertTrue(valid_ack, 'seed %d case %d: bound from a reply that is '
                                'not a valid ACK\nframe: %s' % (SEED + 2000, i, frame.hex()))
                self.assertEqual(self.s.peek('LOCAL_IP', 4), yiaddr)
                xid = self.restart()
            if i % 50 == 49:
                self.check_memory(SEED + 2000, i)
        self.check_memory(SEED + 2000, REPLIES)
        # a normal exchange still works
        xid = self.restart()
        self.s.deliver(net.dhcp_reply(xid, self.s.mac, net.DHCP_OFFER, IP_A, SERVER_A))
        wait_for_dhcp(self.s, net.DHCP_REQUEST)
        self.s.deliver(net.dhcp_reply(xid, self.s.mac, net.DHCP_ACK, IP_A, SERVER_A))
        self.s.poll(2)
        self.assertEqual(tuple(self.s.peek('LOCAL_IP', 4)), IP_A)


if __name__ == '__main__':
    unittest.main()
