"""Remaining items from the code review, each confirmed or ruled out here."""

import struct
import unittest

import net
from stack import Peer, Stack, start_lookup
from test_dhcp import wait_for_dhcp


def cached_entries(s):
    cache = s.peek('ARP_CACHE', 88)
    return [cache[i:i + 11] for i in range(0, 88, 11) if cache[i]]


class ArpReplyValidation(unittest.TestCase):
    """Confirmed and fixed: ARP_UPDATE_CACHE now checks the ARP header."""

    def reply(self, s, p, htype=1, ptype=0x0800, hlen=6, plen=4):
        body = struct.pack('!HHBBH', htype, ptype, hlen, plen, 2) + p.mac \
            + bytes(p.ip) + bytes(6) + bytes(s.peek('LOCAL_IP', 4)) + bytes(4)
        s.deliver(net.ethernet(s.mac, p.mac, net.ETH_ARP, body))
        s.poll()

    def test_valid_reply_is_cached(self):
        s = Stack.ready()
        p = Peer(s)
        self.reply(s, p)
        self.assertEqual([bytes(e[1:5]) for e in cached_entries(s)], [bytes(p.ip)])

    def test_malformed_headers_are_not_cached(self):
        for field, kw in (('hlen', dict(hlen=8, plen=6)), ('plen', dict(plen=16)),
                          ('ptype', dict(ptype=0x0806)), ('htype', dict(htype=6))):
            with self.subTest(field=field):
                s = Stack.ready()
                self.reply(s, Peer(s), **kw)
                self.assertEqual(cached_entries(s), [])

    def test_unsolicited_valid_reply_is_cached(self):
        """Recorded as current behaviour: a valid reply we didn't ask for is
        still cached (as many small stacks do)."""
        s = Stack.ready()
        p = Peer(s)
        self.reply(s, p)
        self.assertEqual(len(cached_entries(s)), 1)


class DnsClientPort(unittest.TestCase):
    """Ruled out: the DNS client port stays in $C000-$DFFF, also for the
    follow-up query after a CNAME, when the port counter wraps."""

    def test_ports_stay_high_across_wrap(self):
        for hi in (0x1F, 0xFE, 0xFF):
            with self.subTest(hi=hi):
                s = Stack.ready()
                s.poke('DNS_CLIENT_PORT_HI', hi)
                s.poke('DNS_CLIENT_PORT_LO', 0xF0)
                dns, q = start_lookup(s, 'www.example.com')
                self.assertGreaterEqual(q.udp['sport'], 0xC000)
                target = b'\x03web\xc0\x10'
                cname = b'\xc0\x0c' + struct.pack('!HHIH', 5, 1, 60, len(target)) + target
                p = q.udp['payload']
                msg = p[0:2] + struct.pack('!HHHHH', 0x8180, 1, 1, 0, 0) + p[12:] + cname
                me = s.peek('LOCAL_IP', 4)
                u = net.udp(dns.ip, me, 53, q.udp['sport'], msg)
                s.deliver(net.ethernet(s.mac, dns.mac, net.ETH_IPV4,
                                       net.ipv4(dns.ip, me, net.PROTO_UDP, u)))
                s.poll()
                found = []
                s.run_frames(200, on_frame=lambda sent: found.extend(
                    f for f in sent if f.udp and f.udp['dport'] == 53),
                    until=lambda: bool(found))
                self.assertTrue(found)
                self.assertGreaterEqual(found[0].udp['sport'], 0xC000)
                self.assertLess(found[0].udp['sport'], 0xE000)


class DhcpOptionPosition(unittest.TestCase):
    """Confirmed limitation, not fixed: the option parser indexes options
    with an 8-bit register, so options starting more than 255 bytes into
    the options field are not seen.  Servers put the message type first, so
    this is unlikely to matter; fixing it means reworking the parser."""

    def offer(self, xid, mac, padding):
        bootp = struct.pack('!BBBB4sHH4s4s4s4s', 2, 1, 6, 0, bytes(xid), 0, 0x8000,
                            bytes(4), bytes([192, 168, 1, 100]), bytes([192, 168, 1, 1]),
                            bytes(4)) + bytes(mac) + bytes(10) + bytes(192)
        opts = bytes([99, 130, 83, 99]) + bytes(padding) + bytes(
            [53, 1, 2, 54, 4, 192, 168, 1, 1, 1, 4, 255, 255, 255, 0, 3, 4, 192, 168, 1, 1, 255])
        u = net.udp((192, 168, 1, 1), (255, 255, 255, 255), 67, 68, bootp + opts)
        return net.ethernet(net.BROADCAST, bytes([2, 0, 0, 0, 0, 1]), net.ETH_IPV4,
                            net.ipv4((192, 168, 1, 1), (255, 255, 255, 255), net.PROTO_UDP, u))

    def request_after_offer(self, padding):
        s = Stack.ready()
        s.call('ETH_DHCP_START')
        xid, _ = wait_for_dhcp(s, net.DHCP_DISCOVER)
        s.deliver(self.offer(xid, s.mac, padding))
        try:
            wait_for_dhcp(s, net.DHCP_REQUEST, max_frames=300)
            return True
        except AssertionError:
            return False

    def test_control_options_after_padding_within_255(self):
        self.assertTrue(self.request_after_offer(200))

    @unittest.expectedFailure
    def test_options_past_byte_255(self):
        self.assertTrue(self.request_after_offer(260))


class RbufPut(unittest.TestCase):
    """Ruled out: RBUF_PUT changes Z, but nothing calls it."""

    def test_rbuf_put_is_unused(self):
        import os
        import re
        from stack import ROOT
        callers = []
        for name in os.listdir(os.path.join(ROOT, 'src')):
            if name.endswith('.asm'):
                with open(os.path.join(ROOT, 'src', name)) as f:
                    text = f.read()
                callers += re.findall(r'^\s*(?:jsr|jmp)\s+RBUF_PUT\b', text, re.M)
        self.assertEqual(callers, [])


if __name__ == '__main__':
    unittest.main()
