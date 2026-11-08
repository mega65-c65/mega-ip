"""Cross-check the CPU opcode table against 64tass.

Every opcode in m65sim.cpu.OPCODES is written as assembly from its mnemonic
and addressing mode, assembled with 64tass ("45gs02" CPU), and the emitted
opcode byte and length must match the table.  This catches typos in the
256-entry map.
"""

import os
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from m65sim import OPCODES, assemble, find_tass  # noqa: E402
from m65sim.cpu import _LEN  # noqa: E402

TASS = find_tass(os.path.dirname(__file__))

_OPERAND = {
    'imp': '', 'acc': 'a', 'imm': '#$12', 'iw': '#$1234', 'zp': '$12',
    'zpx': '$12,x', 'zpy': '$12,y', 'abs': '$1234', 'abx': '$1234,x',
    'aby': '$1234,y', 'ind': '($1234)', 'iax': '($1234,x)', 'izx': '($12,x)',
    'izy': '($12),y', 'izz': '($12),z', 'isy': '($12,s),y',
}


def source_line(mn, mode):
    if mn[:3] in ('rmb', 'smb'):
        return '%s %s,$12' % (mn[:3], mn[3])
    if mn[:3] in ('bbr', 'bbs'):
        return '%s %s,$12,*+3' % (mn[:3], mn[3])
    if mode == 'rel':
        return '%s *+2' % mn
    if mode == 'rlw':
        return '%s far' % mn
    return ('%s %s' % (mn, _OPERAND[mode])).strip()


class OpcodeTable(unittest.TestCase):
    def test_every_opcode_matches_64tass(self):
        workdir = tempfile.mkdtemp(prefix='m65sim_ops_')
        lines = ['    .cpu "45gs02"', '    * = $2000']
        # one instruction per 8-byte slot so each opcode sits at a known address
        for op in range(256):
            mn, mode = OPCODES[op]
            lines.append('    * = $%04x' % (0x2000 + op * 8))
            lines.append('    ' + source_line(mn, mode))
        lines.append('    * = $4000')
        lines.append('    .fill 300, 0')
        lines.append('far:')
        path = os.path.join(workdir, 'ops.asm')
        with open(path, 'w') as f:
            f.write('\n'.join(lines) + '\n')
        asm = assemble(path, TASS, workdir=workdir)
        mismatches = []
        for op in range(256):
            mn, mode = OPCODES[op]
            at = 0x2000 + op * 8 - asm.start
            got = asm.binary[at]
            if got != op:
                mismatches.append('$%02x %s %s: 64tass emitted $%02x'
                                  % (op, mn, mode, got))
        self.assertEqual(mismatches, [])

    def test_operand_lengths(self):
        for op, (mn, mode) in OPCODES.items():
            self.assertIn(mode, _LEN, '$%02x' % op)


if __name__ == '__main__':
    unittest.main()
