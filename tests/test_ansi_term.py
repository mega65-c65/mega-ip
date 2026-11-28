"""ANSI-TERM routines run on the simulator, with the KERNAL calls they make
replaced by stubs that count their calls and return what a test sets."""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'tools', 'sim'))

from m65sim import Machine, assemble, find_tass  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
_ASSEMBLY = None

KERNAL = {'SETNAM': 0xFFBD, 'SETLFS': 0xFFBA, 'OPEN': 0xFFC0, 'CLOSE': 0xFFC3,
          'CHKIN': 0xFFC6, 'CHKOUT': 0xFFC9, 'CLRCHN': 0xFFCC, 'CHRIN': 0xFFCF,
          'CHROUT': 0xFFD2, 'READST': 0xFFB7, 'GETIN': 0xFFE4}
STUBS = 0xF000                 # stub code, 16 bytes per KERNAL call
COUNTS = 0xF200                # one call counter per KERNAL call


def assembly():
    global _ASSEMBLY
    if _ASSEMBLY is None:
        src_root = os.environ.get('MEGAIP_ROOT', ROOT)
        _ASSEMBLY = assemble(os.path.join(src_root, 'basic', 'ansi-term.asm'), find_tass(ROOT))
    return _ASSEMBLY


class Term:
    def __init__(self):
        self.asm = assembly()
        assert self.asm.end <= STUBS
        self.m = Machine()
        self.m.load_flat(self.asm.start, self.asm.binary)
        self.names = sorted(KERNAL)
        for name in self.names:
            self.kernal(name)

    def kernal(self, name, carry=0, a=None):
        """Make KERNAL call `name` return with C=`carry` and, if `a` is
        given, A=`a` (with Z and N set from it, as LDA does)."""
        n = self.names.index(name)
        stub = STUBS + 16 * n
        code = [0xEE, (COUNTS + n) & 0xFF, (COUNTS + n) >> 8]      # inc count
        if a is not None:
            code += [0xA9, a & 0xFF]                                # lda #a
        code += [0x38 if carry else 0x18, 0x60]                     # sec/clc, rts
        self.m.load_flat(stub, bytes(code))
        self.m.load_flat(KERNAL[name], bytes([0x4C, stub & 0xFF, stub >> 8]))

    def calls(self, name):
        return self.m.read(COUNTS + self.names.index(name))

    def call(self, label, **regs):
        return self.m.call(self.asm[label], **regs)

    def peek(self, label):
        return self.m.read(self.asm[label])

    def poke(self, label, value):
        self.m.write(self.asm[label], value)


class PhonebookSave(unittest.TestCase):
    """PHONEBOOK_SAVE: C=1 when the file can't be written, so the user sees
    'save failed' instead of 'saved'."""

    def save(self, t):
        t.poke('PHONE_COUNT', 0)
        return t.call('PHONEBOOK_SAVE').carry

    def test_saves(self):
        t = Term()
        t.kernal('READST', a=0)
        self.assertEqual(self.save(t), 0)
        self.assertEqual(t.calls('CHKOUT'), 1)
        self.assertEqual(t.calls('CLOSE'), 1)

    def test_open_error(self):
        t = Term()
        t.kernal('OPEN', carry=1)
        t.kernal('READST', a=0)
        self.assertEqual(self.save(t), 1)
        self.assertEqual(t.calls('CHKOUT'), 0)
        self.assertEqual(t.calls('CLOSE'), 1)          # the file number is free again

    def test_device_not_present(self):
        t = Term()
        t.kernal('READST', a=0x80)
        self.assertEqual(self.save(t), 1)
        self.assertEqual(t.calls('CLOSE'), 1)

    def test_chkout_error(self):
        t = Term()
        t.kernal('READST', a=0)
        t.kernal('CHKOUT', carry=1)
        self.assertEqual(self.save(t), 1)
        self.assertEqual(t.calls('CLOSE'), 1)


class NewSession(unittest.TestCase):
    def test_cursor_keys_mode_resets(self):
        """A host that set application cursor keys (ESC [ ? 1 h) doesn't
        leave them set for the next host."""
        t = Term()
        t.poke('ANSI_CURSOR_APP_MODE', 1)
        t.call('ASCII_START_SCREEN')
        self.assertEqual(t.peek('ANSI_CURSOR_APP_MODE'), 0)


if __name__ == '__main__':
    unittest.main()
