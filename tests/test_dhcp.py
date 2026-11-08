"""DHCP client tests for the mega-ip stack."""

import unittest

import net
from stack import Stack

SERVER_A, SERVER_B = (192, 168, 1, 1), (192, 168, 1, 2)
IP_A, IP_B = (192, 168, 1, 100), (192, 168, 1, 200)


def wait_for_dhcp(s, msg_type, max_frames=2000):
    """Let frames pass (polling) until the stack sends `msg_type`."""
    found = []

    def watch(sent):
        for f in sent:
            if f.udp and f.udp['dport'] == 67:
                xid, t, opts = net.dhcp_fields(f)
                if t == msg_type and not found:
                    found.append((xid, opts))

    s.run_frames(max_frames, on_frame=watch, until=lambda: bool(found))
    if not found:
        raise AssertionError('stack never sent DHCP message type %d' % msg_type)
    return found[0]


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

    def test_ack_without_server_id_accepted_from_selected_server_ip(self):
        s, xid = self.start()
        s.deliver(net.dhcp_reply(xid, s.mac, net.DHCP_OFFER, IP_A, SERVER_A))
        wait_for_dhcp(s, net.DHCP_REQUEST)
        s.deliver(net.dhcp_reply(xid, s.mac, net.DHCP_ACK, IP_A, SERVER_A,
                                 send_server_id=False))
        s.poll(3)
        self.assertEqual(tuple(s.peek('LOCAL_IP', 4)), IP_A)

    def test_ack_without_server_id_from_another_ip_is_rejected(self):
        s, xid = self.start()
        s.deliver(net.dhcp_reply(xid, s.mac, net.DHCP_OFFER, IP_A, SERVER_A))
        wait_for_dhcp(s, net.DHCP_REQUEST)
        s.deliver(net.dhcp_reply(xid, s.mac, net.DHCP_ACK, IP_A, SERVER_A,
                                 send_server_id=False, src_ip=SERVER_B))
        s.poll(3)
        self.assertNotEqual(tuple(s.peek('LOCAL_IP', 4)), IP_A)

    def test_initial_ack_without_mask_is_rejected(self):
        s, xid = self.start()
        s.deliver(net.dhcp_reply(xid, s.mac, net.DHCP_OFFER, IP_A, SERVER_A))
        wait_for_dhcp(s, net.DHCP_REQUEST)
        s.deliver(net.dhcp_reply(xid, s.mac, net.DHCP_ACK, IP_A, SERVER_A, mask=None))
        s.poll(3)
        self.assertNotEqual(tuple(s.peek('LOCAL_IP', 4)), IP_A)

    def test_non_contiguous_mask_is_rejected(self):
        s, xid = self.start()
        s.deliver(net.dhcp_reply(xid, s.mac, net.DHCP_OFFER, IP_A, SERVER_A))
        wait_for_dhcp(s, net.DHCP_REQUEST)
        s.deliver(net.dhcp_reply(xid, s.mac, net.DHCP_ACK, IP_A, SERVER_A,
                                 mask=(255, 0, 255, 0)))
        s.poll(3)
        self.assertNotEqual(tuple(s.peek('LOCAL_IP', 4)), IP_A)

    def test_busy_transmitter_retries_discover(self):
        s = Stack.ready()
        s.eth.tx_busy = True             # each busy send waits out the TX timeout,
        s.call('ETH_DHCP_START')         # so keep it busy for one attempt only
        s.poll()
        self.assertEqual(s.sent(), [])
        s.eth.tx_busy = False
        wait_for_dhcp(s, net.DHCP_DISCOVER, max_frames=600)

    def test_poll_and_state_calls(self):
        s = Stack.ready()
        s.call(0x2042)                                       # SYS $42042: start
        xid, _ = wait_for_dhcp(s, net.DHCP_DISCOVER)
        self.assertEqual(s.call(0x2045).a, DHCP_DISCOVER_SENT)   # $42045: poll
        s.deliver(net.dhcp_reply(xid, s.mac, net.DHCP_OFFER, IP_A, SERVER_A))
        wait_for_dhcp(s, net.DHCP_REQUEST)
        s.deliver(net.dhcp_reply(xid, s.mac, net.DHCP_ACK, IP_A, SERVER_A))
        self.assertEqual(s.call(0x2045).a, DHCP_BOUND)
        self.assertEqual(s.call(0x2048).a, DHCP_BOUND)           # $42048: state


DHCP_DISCOVER_SENT, DHCP_REQUEST_SENT, DHCP_BOUND = 1, 3, 4


def bound(lease=3600):
    """A stack holding a lease on IP_A from SERVER_A; returns (stack, xid)."""
    s = Stack.ready()
    s.call('ETH_DHCP_START')
    xid, _ = wait_for_dhcp(s, net.DHCP_DISCOVER)
    s.deliver(net.dhcp_reply(xid, s.mac, net.DHCP_OFFER, IP_A, SERVER_A, lease=lease))
    wait_for_dhcp(s, net.DHCP_REQUEST)
    s.deliver(net.dhcp_reply(xid, s.mac, net.DHCP_ACK, IP_A, SERVER_A, lease=lease))
    s.poll(2)
    assert s.call('ETH_GET_DHCP_STATE').a == DHCP_BOUND
    return s, xid


def renew_seconds(s):
    return s.peek('DHCP_RENEW_SECS_LO') | (s.peek('DHCP_RENEW_SECS_HI') << 8)


class Renewal(unittest.TestCase):
    def test_renewal_is_scheduled_at_half_the_lease(self):
        for lease, expected in ((3600, 1800), (100, 60), (0x01000000, 0xFFFF)):
            with self.subTest(lease=lease):
                s, _ = bound(lease)
                self.assertEqual(s.peek('DHCP_RENEW_ACTIVE'), 1)
                self.assertEqual(renew_seconds(s), expected)

    def test_bound_timer_counts_seconds(self):
        s, _ = bound(3600)
        before = renew_seconds(s)
        per_second = 10 * s.asm['DHCP_TICK_FRAMES']
        s.run_frames(5 * per_second)
        self.assertAlmostEqual(before - renew_seconds(s), 5, delta=1)

    def renew(self, s):
        s.poke('DHCP_RENEW_SECS_LO', 2)                      # skip most of T1
        s.poke('DHCP_RENEW_SECS_HI', 0)
        xid, opts = wait_for_dhcp(s, net.DHCP_REQUEST,
                                  max_frames=10 * 10 * s.asm['DHCP_TICK_FRAMES'])
        return xid, opts

    def test_renewal_request_asks_for_the_current_lease(self):
        s, _ = bound()
        xid, opts = self.renew(s)
        self.assertEqual(tuple(opts[50]), IP_A)
        self.assertEqual(tuple(opts[54]), SERVER_A)
        self.assertEqual(s.call('ETH_GET_DHCP_STATE').a, DHCP_REQUEST_SENT)
        self.assertEqual(s.peek('DHCP_REQUEST_IS_RENEW'), 1)
        self.assertEqual(tuple(s.peek('LOCAL_IP', 4)), IP_A)  # still usable

    def test_renewal_ack_without_mask_keeps_current_mask(self):
        s, _ = bound()
        xid, _ = self.renew(s)
        s.deliver(net.dhcp_reply(xid, s.mac, net.DHCP_ACK, IP_A, SERVER_A, mask=None,
                                 lease=7200))
        s.poll(2)
        self.assertEqual(s.call('ETH_GET_DHCP_STATE').a, DHCP_BOUND)
        self.assertEqual(tuple(s.peek('SUBNET_MASK', 4)), (255, 255, 255, 0))
        self.assertEqual(renew_seconds(s), 3600)              # rescheduled
        self.assertEqual(s.peek('DHCP_REQUEST_IS_RENEW'), 0)

    def test_renewal_nak_drops_lease_and_rediscovers(self):
        s, _ = bound()
        xid, _ = self.renew(s)
        s.deliver(net.dhcp_reply(xid, s.mac, net.DHCP_NAK, (0, 0, 0, 0), SERVER_A))
        s.poll()
        self.assertEqual(tuple(s.peek('LOCAL_IP', 4)), (0, 0, 0, 0))
        wait_for_dhcp(s, net.DHCP_DISCOVER)

    def test_connection_survives_renewal(self):
        from stack import ACK, PSH, Peer
        s, _ = bound()
        p = Peer(s, ip=(192, 168, 1, 77))
        p.connect_stack()
        xid, _ = self.renew(s)
        p.send(PSH | ACK, b'during renewal')
        s.deliver(net.dhcp_reply(xid, s.mac, net.DHCP_ACK, IP_A, SERVER_A))
        s.poll(2)
        self.assertEqual(s.state, 'ESTABLISHED')
        self.assertEqual(s.read_received(), b'during renewal')
        self.assertEqual(s.call('ETH_GET_DHCP_STATE').a, DHCP_BOUND)


if __name__ == '__main__':
    unittest.main()
