"""terminal.bas, run on the BASIC subset interpreter (tests/basic65.py).

Bytes from the host go through the receive loop (lines 1470-1580) exactly
as the program runs it.  The stack calls are stubs:

    SYS $4201E  next received byte -> A (translated as in ASCII mode)
    SYS $42024  status poll -> A = 0
    SYS $4201B  send A$ (recorded, translated to ASCII)
"""

import os
import unittest

from basic65 import Basic, BasicError, Stop, load, petscii, tokenize

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
RECEIVE_LOOP = 1470
ESC = '\x1b'


def source():
    src_root = os.environ.get('MEGAIP_ROOT', ROOT)
    return load(os.path.join(src_root, 'basic', 'terminal.bas'))


def to_petscii(b):
    """CHAR_TRANSLATE in ASCII mode."""
    if 0x41 <= b <= 0x5A:
        return b | 0x80
    if 0x61 <= b <= 0x7A:
        return b & 0xDF
    return b


def to_ascii(c):
    """PETSCII_TO_ASCII, for what the program sends."""
    if 0xC1 <= c <= 0xDA:
        return c & 0x7F
    if 0x41 <= c <= 0x5A:
        return c | 0x20
    return c


class Terminal(Basic):
    def __init__(self, incoming=b''):
        super().__init__(source())
        self.incoming = list(incoming)
        self.sent = []
        self.pos = (0, 0)

    def sys(self, addr, args):
        if addr == 0x4201E:
            if not self.incoming:
                raise Stop
            self.regs[0] = to_petscii(self.incoming.pop(0))
        elif addr == 0x42024:
            self.regs[0] = 0
        elif addr == 0x4201B:
            self.sent.append(bytes(to_ascii(ord(c)) for c in self.getvar('a$')))
        else:
            raise BasicError('SYS $%x not stubbed' % addr)

    def cursor(self, x, y):
        self.pos = (x, y)

    def rcursor(self):
        return self.pos

    def receive(self, data):
        self.incoming += list(data.encode('latin-1') if isinstance(data, str) else data)
        self.run(RECEIVE_LOOP)
        return self.printed


def shown(data):
    """What the screen gets for bytes from the host."""
    return Terminal().receive(data)


def p(text):
    return petscii(text)


class Interpreter(unittest.TestCase):
    """The interpreter itself, on lines like the program's."""

    def run_lines(self, text, start=10, **variables):
        lines = {}
        for raw in text.strip().splitlines():
            num, rest = raw.strip().split(' ', 1)
            lines[int(num)] = tokenize(rest)
        b = Basic(lines)
        b.run(start, **variables)
        return b

    def test_crunched_keywords(self):
        b = self.run_lines('''
            10 s=0:fort=1to4:s=s+t:nextt
            20 ifs=10thenr=1
            30 end''')
        self.assertEqual((b.getvar('s'), b.getvar('r')), (10, 1))

    def test_if_else_and_blocks(self):
        b = self.run_lines('''
            10 if 1=2 then a=1:else a=2
            20 if 1=1 then begin
            30 :b=1
            40 bend
            50 if 1=2 then begin
            60 :c=1
            70 bend
            80 end''')
        self.assertEqual([b.getvar(v) for v in 'abc'], [2, 1, 0])

    def test_gosub_return_and_strings(self):
        b = self.run_lines('''
            10 gosub 100:end
            100 a$=mid$(str$(42),2)+";"+left$("abc",2)+right$("xyz",1):return''')
        self.assertEqual(b.getvar('a$'), p('42;abz'))

    def test_array_without_dim_holds_eleven(self):
        with self.assertRaises(BasicError):
            self.run_lines('10 a(11)=1')

    def test_every_program_loads(self):
        for name in ('irc', 'terminal', 'webserver'):
            with self.subTest(name=name):
                self.assertGreater(len(load(os.path.join(ROOT, 'basic', name + '.bas'))), 50)


class Printing(unittest.TestCase):
    def test_plain_text(self):
        self.assertEqual(shown('Hi'), p('Hi'))


class Sgr(unittest.TestCase):
    """ESC [ ... m: every parameter counts, in order."""

    def test_colour_after_bold(self):
        self.assertEqual(shown(ESC + '[1;31mX'), p('{red}X'))

    def test_reset(self):
        self.assertEqual(shown(ESC + '[0m'), p('{rvof}{wht}'))
        self.assertEqual(shown(ESC + '[m'), p('{rvof}{wht}'))

    def test_reverse_on_and_off(self):
        self.assertEqual(shown(ESC + '[7mX' + ESC + '[27m'), p('{rvon}X{rvof}'))

    def test_several_parameters(self):
        self.assertEqual(shown(ESC + '[0;7;32m'), p('{rvof}{wht}{rvon}{grn}'))

    def test_background_is_ignored(self):
        self.assertEqual(shown(ESC + '[31;42m'), p('{red}'))

    def test_extended_colour_is_skipped(self):
        """38;5;n and 38;2;r;g;b: the numbers after 38 are not SGR codes."""
        self.assertEqual(shown(ESC + '[38;5;31m'), '')
        self.assertEqual(shown(ESC + '[48;2;0;0;7;32m'), '')


class EscapeParser(unittest.TestCase):
    def test_escape_and_one_character(self):
        """ESC 7, ESC c and the like: the next '[' is plain text again."""
        self.assertEqual(shown(ESC + '7[INFO] ok'), p('[INFO] ok'))

    def test_character_set_selection_is_not_shown(self):
        self.assertEqual(shown(ESC + '(B' + ESC + ')0ok'), p('ok'))

    def test_an_interrupted_sequence_does_not_carry_over(self):
        """ESC [ 3 then ESC [ 1 m is bold (1), not red (31)."""
        self.assertEqual(shown(ESC + '[3' + ESC + '[1m'), '')

    def test_final_bytes_beyond_the_letters(self):
        """ESC [ 5 @ (insert characters) ends at the '@': the X is text."""
        self.assertEqual(shown(ESC + '[5@X'), p('X'))
        self.assertEqual(shown(ESC + '[2~X'), p('X'))

    def test_more_parameters_than_the_array_holds(self):
        params = ';'.join(str(n) for n in range(1, 13))
        self.assertEqual(shown(ESC + '[' + params + ';31m'), p('{rvon}{red}'))

    def test_a_sequence_that_never_ends_is_dropped(self):
        self.assertTrue(shown(ESC + '[' + '1' * 40 + 'hi').endswith(p('hi')))


class DeviceStatusReport(unittest.TestCase):
    def ask(self, request, col=9, row=4):
        t = Terminal()
        t.pos = (col, row)
        t.receive('x' + ESC + request)          # x: the program reads the cursor
        return t.sent

    def test_cursor_position_is_row_then_column(self):
        self.assertEqual(self.ask('[6n', col=9, row=4), [b'\x1b[5;10R'])
        self.assertEqual(self.ask('[6n', col=0, row=0), [b'\x1b[1;1R'])

    def test_status_request_answers_ok(self):
        self.assertEqual(self.ask('[5n'), [b'\x1b[0n'])

    def test_other_requests_get_no_reply(self):
        self.assertEqual(self.ask('[n'), [])


if __name__ == '__main__':
    unittest.main()
