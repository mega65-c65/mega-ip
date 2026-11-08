"""The public API contract: BASIC programs hard-code the $420xx SYS addresses
documented in README.MD, so they must not move.

Checks the README table, src/api.asm and the assembled jump table against one
expected mapping, and the fixed memory layout around them.
"""

import os
import re
import unittest

from stack import BANK4, ROOT, assembly

# SYS address -> routine, as documented.  Changing an entry here is an ABI
# change for every BASIC program that uses the library.
EXPECTED = {
    0x42000: 'ETH_INIT', 0x42003: 'ETH_SET_GATEWAY_IP', 0x42006: 'ETH_SET_LOCAL_IP',
    0x42009: 'ETH_SET_LOCAL_PORT', 0x4200C: 'ETH_SET_REMOTE_IP',
    0x4200F: 'ETH_SET_REMOTE_PORT', 0x42012: 'ETH_SET_SUBNET_MASK',
    0x42015: 'ETH_SET_CHAR_XLATE', 0x42018: 'ETH_TCP_SEND',
    0x4201B: 'ETH_TCP_SEND_STRING', 0x4201E: 'RBUF_GET', 0x42021: 'ETH_TCP_DISCONNECT',
    0x42024: 'ETH_STATUS_POLL', 0x42027: 'ETH_TCP_CONNECT_START',
    0x4202A: 'ETH_CONNECT_POLL', 0x4202D: 'ETH_CONNECT_CANCEL', 0x42030: 'ETH_DNS_LOOKUP',
    0x42033: 'ETH_GET_DNS_RESULT_IP', 0x42036: 'ETH_GET_DNS_STATE',
    0x42039: 'ETH_TCP_LISTEN_START', 0x4203C: 'ETH_TCP_LISTEN_STOP',
    0x4203F: 'ETH_ACCEPT_POLL', 0x42042: 'ETH_DHCP_START', 0x42045: 'ETH_DHCP_POLL',
    0x42048: 'ETH_GET_DHCP_STATE', 0x4204B: 'ETH_SET_PRIMARY_DNS',
    0x4204E: 'ETH_GET_LOCAL_IP', 0x42051: 'ETH_GET_GATEWAY_IP',
    0x42054: 'ETH_GET_SUBNET_MASK', 0x42057: 'ETH_GET_PRIMARY_DNS',
    0x4205A: 'ETH_GET_REMOTE_IP', 0x4205D: 'ETH_TCP_FORCE_CLOSE',
    0x42060: 'ETH_GET_ABI_INFO', 0x42063: 'ETH_DNS_START_ASTR', 0x42066: 'ETH_TCP_TX_IDLE',
}

# Fixed layout (CPU addresses in bank 4); see src/eth.asm
API_BASE, STATE_BLOCK_BASE = 0x2000, 0x2100
ML_EXTENSION_TABLE_BASE, ML_CALL_STAGING_BASE, BANK_TOP = 0x7600, 0x77C0, 0x8000


def read(path):
    with open(os.path.join(ROOT, path)) as f:
        return f.read()


class JumpTable(unittest.TestCase):
    def test_readme_documents_exactly_the_expected_addresses(self):
        text = read('README.MD')
        section = text.split('## Public jump table', 1)[1].split('\n## ', 1)[0]
        table = section.split('| Address | Purpose |')[0]      # stop at the ML table
        documented = {int(m, 16) for m in re.findall(r'^\| `\$(42[0-9a-fA-F]{3})`', table, re.M)}
        self.assertEqual(sorted(documented), sorted(EXPECTED))

    def test_api_asm_lists_the_routines_in_order(self):
        jumps = re.findall(r'^\s*jmp\s+(\w+)', read('src/api.asm'), re.M)
        self.assertEqual(jumps, [EXPECTED[a] for a in sorted(EXPECTED)])

    def test_assembled_entries_jump_to_their_routines(self):
        asm = assembly()
        bad = []
        for sys_addr, label in sorted(EXPECTED.items()):
            at = sys_addr - BANK4 - asm.start
            op, lo, hi = asm.binary[at:at + 3]
            if op != 0x4C or (lo | hi << 8) != asm[label]:
                bad.append('$%05x: expected jmp %s ($%04x), found %02x %02x %02x'
                           % (sys_addr, label, asm[label], op, lo, hi))
        self.assertEqual(bad, [])


class Layout(unittest.TestCase):
    def ranges(self):
        return [(int(a, 16), int(b, 16)) for a, b in
                re.findall(r'Data:\s+\d+\s+\$([0-9a-f]+)-\$([0-9a-f]+)', assembly().output)]

    def test_jump_table_fits_below_state_block(self):
        api = [r for r in self.ranges() if r[0] == API_BASE]
        self.assertEqual(len(api), 1)
        self.assertLess(api[0][1], STATE_BLOCK_BASE)

    def test_runtime_stays_below_ml_extension_table(self):
        runtime = [r for r in self.ranges() if r[0] == STATE_BLOCK_BASE]
        self.assertEqual(len(runtime), 1)
        self.assertLess(runtime[0][1], ML_EXTENSION_TABLE_BASE,
                        'runtime ends at $%04x' % runtime[0][1])

    def test_fixed_tables_present_and_in_bank(self):
        starts = [r[0] for r in self.ranges()]
        self.assertIn(ML_EXTENSION_TABLE_BASE, starts)
        self.assertIn(ML_CALL_STAGING_BASE, starts)
        self.assertLess(max(r[1] for r in self.ranges()), BANK_TOP)

    def test_state_block_starts_with_local_ip(self):
        # The original BASIC-facing data block layout starts at $2100.
        self.assertEqual(assembly()['LOCAL_IP'], STATE_BLOCK_BASE)


if __name__ == '__main__':
    unittest.main()
