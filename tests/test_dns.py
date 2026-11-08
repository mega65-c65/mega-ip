"""DNS client: answers, CNAMEs, malformed and mismatched replies, timeout."""

import struct
import unittest

import net
from stack import (DNS_STATE_DONE, DNS_STATE_FAIL, DNS_STATE_WAIT, Stack, dns_result,
                   dns_state, start_lookup)


def a_record(ip, name=b'\xc0\x0c'):
    return name + struct.pack('!HHIH', 1, 1, 60, 4) + bytes(ip)


def reply(s, dns, query, answers=b'', count=1, flags=0x8180, ident=None, sport=53):
    """Deliver a DNS response to `query` with `answers` after the question."""
    q = query.udp['payload']
    msg = (q[0:2] if ident is None else ident) + \
        struct.pack('!HHHHH', flags, 1, count, 0, 0) + q[12:] + answers
    me = s.peek('LOCAL_IP', 4)
    u = net.udp(dns.ip, me, sport, query.udp['sport'], msg)
    s.deliver(net.ethernet(s.mac, dns.mac, net.ETH_IPV4, net.ipv4(dns.ip, me, net.PROTO_UDP, u)))
    s.poll()


def answers_offset(query):
    return 12 + len(query.udp['payload'][12:])


class Answers(unittest.TestCase):
    def test_query_format(self):
        s = Stack.ready()
        _, q = start_lookup(s, 'www.example.com')
        p = q.udp['payload']
        self.assertEqual(struct.unpack('!HHHH', p[4:12]), (1, 0, 0, 0))
        self.assertEqual(p[12:], b'\x03www\x07example\x03com\x00\x00\x01\x00\x01')
        self.assertEqual(p[2] & 0x01, 1)                     # recursion desired

    def test_a_record(self):
        s = Stack.ready()
        dns, q = start_lookup(s)
        reply(s, dns, q, a_record((93, 184, 216, 34)))
        self.assertEqual(dns_state(s), DNS_STATE_DONE)
        self.assertEqual(dns_result(s), (93, 184, 216, 34))

    def test_cname_and_a_in_one_reply(self):
        s = Stack.ready()
        dns, q = start_lookup(s, 'www.example.com')
        target = b'\x03web\xc0\x10'                          # web.example.com
        cname = b'\xc0\x0c' + struct.pack('!HHIH', 5, 1, 60, len(target)) + target
        a = a_record((1, 2, 3, 4), struct.pack('!H', 0xC000 | (answers_offset(q) + 12)))
        reply(s, dns, q, cname + a, count=2)
        self.assertEqual(dns_state(s), DNS_STATE_DONE)
        self.assertEqual(dns_result(s), (1, 2, 3, 4))

    def test_cname_only_is_followed(self):
        s = Stack.ready()
        dns, q = start_lookup(s, 'www.example.com')
        target = b'\x03web\xc0\x10'
        cname = b'\xc0\x0c' + struct.pack('!HHIH', 5, 1, 60, len(target)) + target
        reply(s, dns, q, cname)
        found = []
        s.run_frames(300, on_frame=lambda sent: found.extend(
            f for f in sent if f.udp and f.udp['dport'] == 53), until=lambda: bool(found))
        self.assertTrue(found, 'no follow-up query for the CNAME target')
        self.assertEqual(found[0].udp['payload'][12:],
                         b'\x03web\x07example\x03com\x00\x00\x01\x00\x01')
        s.deliver(net.dns_reply(found[0], (4, 3, 2, 1), dns.mac, dns.ip, s.mac))
        s.poll()
        self.assertEqual(dns_state(s), DNS_STATE_DONE)
        self.assertEqual(dns_result(s), (4, 3, 2, 1))


class Failures(unittest.TestCase):
    def check_fails(self, **kw):
        s = Stack.ready()
        dns, q = start_lookup(s)
        answers = kw.pop('answers', None)
        if callable(answers):
            answers = answers(q)
        reply(s, dns, q, answers if answers is not None else b'', **kw)
        self.assertEqual(dns_state(s), DNS_STATE_FAIL)

    def test_nxdomain(self):
        self.check_fails(flags=0x8183, count=0)

    def test_no_answers(self):
        self.check_fails(count=0)

    def test_truncated_flag(self):
        self.check_fails(answers=a_record((1, 1, 1, 1)), flags=0x8380)

    def test_record_runs_past_end(self):
        self.check_fails(answers=b'\xc0\x0c' + struct.pack('!HHIH', 1, 1, 60, 4) + b'\x01\x02')

    def test_compression_pointer_loop_fails_quickly(self):
        def looping(q):
            self_ptr = struct.pack('!H', 0xC000 | answers_offset(q))
            return self_ptr + struct.pack('!HHIH', 1, 1, 60, 4) + bytes(4)
        s = Stack.ready()
        dns, q = start_lookup(s)
        reply(s, dns, q, looping(q))         # call() would raise if it hung
        self.assertEqual(dns_state(s), DNS_STATE_FAIL)

    def test_no_reply_times_out(self):
        s = Stack.ready()
        dns, q = start_lookup(s)
        queries = [q]
        s.run_frames(5000, on_frame=lambda sent: queries.extend(
            f for f in sent if f.udp and f.udp['dport'] == 53),
            until=lambda: dns_state(s) != DNS_STATE_WAIT)
        self.assertEqual(dns_state(s), DNS_STATE_FAIL)
        self.assertEqual(len(queries), s.asm['DNS_MAX_RETRIES'])


class Mismatched(unittest.TestCase):
    def test_wrong_id_ignored(self):
        s = Stack.ready()
        dns, q = start_lookup(s)
        reply(s, dns, q, a_record((9, 9, 9, 9)), ident=b'\xbe\xef')
        self.assertEqual(dns_state(s), DNS_STATE_WAIT)
        reply(s, dns, q, a_record((5, 6, 7, 8)))
        self.assertEqual(dns_result(s), (5, 6, 7, 8))

    def test_wrong_source_port_ignored(self):
        s = Stack.ready()
        dns, q = start_lookup(s)
        reply(s, dns, q, a_record((9, 9, 9, 9)), sport=5353)
        self.assertEqual(dns_state(s), DNS_STATE_WAIT)

    def test_reply_from_other_server_ignored(self):
        s = Stack.ready()
        dns, q = start_lookup(s)
        other = type(dns)(s, ip=(192, 168, 1, 54), mac=bytes([2, 0, 0, 0, 0, 0x54]))
        reply(s, other, q, a_record((9, 9, 9, 9)))
        self.assertEqual(dns_state(s), DNS_STATE_WAIT)

    def test_each_lookup_uses_a_new_port(self):
        s = Stack.ready()
        _, q1 = start_lookup(s)
        s.call('ETH_TCP_FORCE_CLOSE')                # clears DNS state
        _, q2 = start_lookup(s)
        self.assertNotEqual(q1.udp['sport'], q2.udp['sport'])


if __name__ == '__main__':
    unittest.main()
