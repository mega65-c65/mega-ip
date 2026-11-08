"""ICMP echo (ping) replies."""

import struct
import unittest

import net
from stack import Peer, Stack


def ping(s, p, payload=b'pingdata', icmp_type=8, bad_checksum=False, dst=None,
         ident=0x1234, seq=7):
    body = struct.pack('!BBHHH', icmp_type, 0, 0, ident, seq) + payload
    csum = net.checksum(body) ^ (0xFFFF if bad_checksum else 0)
    body = body[:2] + struct.pack('!H', csum) + body[4:]
    dst = dst or s.peek('LOCAL_IP', 4)
    s.deliver(net.ethernet(s.mac, p.mac, net.ETH_IPV4,
                           net.ipv4(p.ip, dst, net.PROTO_ICMP, body)))
    s.poll()
    return s.sent()


class Echo(unittest.TestCase):
    def setUp(self):
        self.s = Stack.ready()
        self.p = Peer(self.s)
        self.s.deliver(self.p.arp_request_for_stack())   # stack learns our MAC
        self.s.poll()
        self.s.sent()

    def reply_icmp(self, frame):
        return frame.raw[14 + 20:14 + frame.ip['total']]

    def test_echo_reply(self):
        sent = ping(self.s, self.p)
        self.assertEqual(len(sent), 1)
        r = sent[0]
        self.assertEqual(bytes(r.dst), self.p.mac)
        self.assertEqual(tuple(r.ip['dst']), self.p.ip)
        self.assertEqual(tuple(r.ip['src']), Stack.MY_IP)
        self.assertTrue(r.ip['header_ok'])
        icmp = self.reply_icmp(r)
        self.assertEqual(net.checksum(icmp), 0)
        self.assertEqual(icmp[0], 0)                       # echo reply
        self.assertEqual(icmp[4:8], struct.pack('!HH', 0x1234, 7))
        self.assertEqual(icmp[8:], b'pingdata')

    def test_large_echo_reply_intact(self):
        payload = bytes(range(256)) * 4
        sent = ping(self.s, self.p, payload=payload)
        self.assertEqual(len(sent), 1)
        icmp = self.reply_icmp(sent[0])
        self.assertEqual(net.checksum(icmp), 0)
        self.assertEqual(icmp[8:], payload)

    def test_odd_length_payload(self):
        sent = ping(self.s, self.p, payload=b'odd')
        self.assertEqual(net.checksum(self.reply_icmp(sent[0])), 0)

    def test_no_reply_for_bad_checksum(self):
        self.assertEqual(ping(self.s, self.p, bad_checksum=True), [])

    def test_no_reply_for_another_ip(self):
        self.assertEqual(ping(self.s, self.p, dst=(192, 168, 1, 99)), [])

    def test_no_reply_for_other_icmp_types(self):
        for t in (0, 3, 11):
            with self.subTest(type=t):
                self.assertEqual(ping(self.s, self.p, icmp_type=t), [])


if __name__ == '__main__':
    unittest.main()
