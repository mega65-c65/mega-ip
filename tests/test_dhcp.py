"""DHCP client tests for the mega-ip stack."""

import unittest

import net
from stack import Stack

SERVER_A, SERVER_B = (192, 168, 1, 1), (192, 168, 1, 2)
IP_A, IP_B = (192, 168, 1, 100), (192, 168, 1, 200)


def dhcp_sent(s):
    return [f for f in s.sent() if f.udp and f.udp['dport'] == 67]


def wait_for_dhcp(s, msg_type, max_rounds=400):
    """Poll, letting frames pass, until the stack sends `msg_type`."""
    for _ in range(max_rounds):
        s.poll()
        for f in dhcp_sent(s):
            xid, t, opts = net.dhcp_fields(f)
            if t == msg_type:
                return xid, opts
        s.m.advance_frames(5)
    raise AssertionError('stack never sent DHCP message type %d' % msg_type)


class DhcpClient(unittest.TestCase):
    def start(self):
        s = Stack.ready()
        s.call('ETH_DHCP_START')
        xid, _ = wait_for_dhcp(s, net.DHCP_DISCOVER)
        return s, xid

    def test_offer_request_ack_binds(self):
        s, xid = self.start()
        s.deliver(net.dhcp_reply(xid, s.mac, net.DHCP_OFFER, IP_A, SERVER_A))
        _, opts = wait_for_dhcp(s, net.DHCP_REQUEST)
        self.assertEqual(tuple(opts[50]), IP_A)
        self.assertEqual(tuple(opts[54]), SERVER_A)
        s.deliver(net.dhcp_reply(xid, s.mac, net.DHCP_ACK, IP_A, SERVER_A))
        s.poll(3)
        self.assertEqual(tuple(s.peek('LOCAL_IP', 4)), IP_A)
        self.assertEqual(tuple(s.peek('GATEWAY_IP', 4)), SERVER_A)

    def test_late_offer_does_not_change_resent_request(self):
        """30667e3: a second server's late OFFER doesn't redirect the REQUEST."""
        s, xid = self.start()
        s.deliver(net.dhcp_reply(xid, s.mac, net.DHCP_OFFER, IP_A, SERVER_A))
        wait_for_dhcp(s, net.DHCP_REQUEST)
        s.deliver(net.dhcp_reply(xid, s.mac, net.DHCP_OFFER, IP_B, SERVER_B))
        s.poll()
        _, opts = wait_for_dhcp(s, net.DHCP_REQUEST)       # retry, ACK was "lost"
        self.assertEqual(tuple(opts[50]), IP_A)
        self.assertEqual(tuple(opts[54]), SERVER_A)
        s.deliver(net.dhcp_reply(xid, s.mac, net.DHCP_ACK, IP_A, SERVER_A))
        s.poll(3)
        self.assertEqual(tuple(s.peek('LOCAL_IP', 4)), IP_A)

    def test_ack_from_other_server_is_rejected(self):
        s, xid = self.start()
        s.deliver(net.dhcp_reply(xid, s.mac, net.DHCP_OFFER, IP_A, SERVER_A))
        wait_for_dhcp(s, net.DHCP_REQUEST)
        s.deliver(net.dhcp_reply(xid, s.mac, net.DHCP_ACK, IP_B, SERVER_B))
        s.poll(3)
        self.assertNotEqual(tuple(s.peek('LOCAL_IP', 4)), IP_B)


if __name__ == '__main__':
    unittest.main()
