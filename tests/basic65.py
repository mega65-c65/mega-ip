"""A small BASIC 65 interpreter for testing the BASIC programs' logic.

It runs lines straight from a petcat-style source file (basic/*.bas): the
statements and functions those programs use, with BASIC's rules for
keywords crunched into names (`fort=0topc`), IF/THEN/ELSE, BEGIN/BEND
blocks, FOR/NEXT, GOSUB/RETURN, and arrays of 11 elements without DIM.
Anything else raises BasicError rather than being guessed at.

Strings are PETSCII: in source text a-z are $41-$5A, A-Z are $C1-$DA and
{name} is a control code.  Machine calls are hooks: a test subclasses
Basic and overrides sys(), get(), ti() and so on.
"""

import re


class BasicError(Exception):
    pass


class Stop(Exception):
    """Raised by a hook (or END) to finish run()."""


CONTROL = {
    'wht': 5, 'red': 28, 'grn': 30, 'blu': 31, 'orng': 129, 'blk': 144,
    'brn': 149, 'lred': 150, 'gry1': 151, 'gry2': 152, 'lgrn': 153,
    'lblu': 154, 'gry3': 155, 'pur': 156, 'yel': 158, 'cyn': 159,
    'rvon': 18, 'rvof': 146, 'up': 145, 'down': 17, 'rght': 29, 'left': 157,
    'clr': 147, 'home': 19, '$a0': 160, 'CTRL-W': 23,
    'f1': 133, 'f3': 134, 'f5': 135, 'f7': 136,
}

KEYWORDS = sorted('''rcursor cursor movspr sprite return gosub goto print input sleep
    begin bend then else next step rreg left$ right$ mid$ str$ chr$ val len asc
    and not for sys get rem end if or to int'''.split(), key=len, reverse=True)

FUNCTIONS = {'val', 'len', 'asc', 'mid$', 'left$', 'right$', 'str$', 'chr$', 'int'}
ARRAY_SIZE = 11                # a BASIC array used without DIM: 0..10


def petscii(text):
    """Source text of a string literal -> a str of PETSCII codes."""
    out = []
    i = 0
    while i < len(text):
        c = text[i]
        if c == '{':
            j = text.index('}', i)
            name = text[i + 1:j]
            if name not in CONTROL:      # one the tests don't need: a stand-in
                CONTROL[name] = 0xE000 + len(CONTROL)
            out.append(chr(CONTROL[name]))
            i = j + 1
            continue
        if 'a' <= c <= 'z':
            out.append(chr(ord(c) - 0x20))
        elif 'A' <= c <= 'Z':
            out.append(chr(ord(c) + 0x80))
        else:
            out.append(c)
        i += 1
    return ''.join(out)


def tokenize(text):
    toks = []
    i = 0
    n = len(text)
    while i < n:
        c = text[i]
        if c == ' ':
            i += 1
            continue
        if c == '"':
            j = text.find('"', i + 1)
            j = n if j < 0 else j
            toks.append(('str', petscii(text[i + 1:j])))
            i = j + 1
            continue
        kw = next((k for k in KEYWORDS if text.startswith(k, i)), None)
        if kw:
            toks.append(('kw', kw))
            i += len(kw)
            if kw == 'rem':
                break
            continue
        if c == '$' and i + 1 < n and text[i + 1] in '0123456789abcdefABCDEF':
            m = re.match(r'\$([0-9a-fA-F]+)', text[i:])
            toks.append(('num', int(m.group(1), 16)))
            i += len(m.group(0))
            continue
        if c.isdigit() or (c == '.' and i + 1 < n and text[i + 1].isdigit()):
            m = re.match(r'\d*\.?\d*', text[i:])
            v = float(m.group(0))
            toks.append(('num', int(v) if v == int(v) else v))
            i += len(m.group(0))
            continue
        if c.isalpha():
            j = i + 1
            while j < n and text[j].isalnum() and not any(text.startswith(k, j) for k in KEYWORDS):
                j += 1
            if j < n and text[j] in '$%':
                j += 1
            toks.append(('id', text[i:j].lower()))
            i = j
            continue
        two = text[i:i + 2]
        if two in ('<>', '<=', '>='):
            toks.append(('op', two))
            i += 2
            continue
        if c in '=<>+-*/(),;:':
            toks.append(('op', c))
        else:
            toks.append(('other', c))  # unsupported: an error only if it runs
        i += 1
    return toks


def load(path):
    """{line number: tokens} from a petcat-style source file."""
    lines = {}
    with open(path, encoding='latin-1') as f:
        for raw in f:
            m = re.match(r'\s*(\d+)\s?(.*)$', raw.rstrip('\r\n'))
            if m:
                lines[int(m.group(1))] = tokenize(m.group(2))
    return lines


def basic_str(v):
    """STR$(): a leading space for a non-negative number."""
    s = '%d' % v if v == int(v) else repr(v)
    return s if v < 0 else ' ' + s


def basic_val(s):
    m = re.match(r'\s*([+-]?\s*\d*\.?\d+(?:e[+-]?\d+)?)', s.replace(' ', ''), re.I)
    if not m:
        return 0
    v = float(m.group(1))
    return int(v) if v == int(v) else v


def truth(b):
    return -1 if b else 0


class Basic:
    def __init__(self, lines, max_steps=200000):
        self.numbers = sorted(lines)
        self.lines = [lines[k] for k in self.numbers]
        self.index = {k: i for i, k in enumerate(self.numbers)}
        self.vars = {}
        self.arrays = {}
        self.out = []                 # PETSCII printed, as one str per PRINT
        self.max_steps = max_steps
        self.regs = [0, 0, 0, 0]       # what RREG reads (A, X, Y, Z)

    # ---- hooks ------------------------------------------------------------
    def sys(self, addr, args):
        raise BasicError('SYS $%x not stubbed' % addr)

    def get(self):
        return ''

    def ti(self):
        return 0

    def cursor(self, x, y):
        pass

    def rcursor(self):
        return (0, 0)

    @property
    def printed(self):
        return ''.join(self.out)

    # ---- variables ----------------------------------------------------------
    def getvar(self, name):
        if name == 'ti':
            return self.ti()
        return self.vars.get(name, '' if name.endswith('$') else 0)

    def setvar(self, name, v):
        self.vars[name] = self._typed(name, v)

    def _typed(self, name, v):
        if name.endswith('$') != isinstance(v, str):
            raise BasicError('?TYPE MISMATCH assigning %r to %s' % (v, name))
        return v

    def element(self, name, index, value=None):
        index = int(index)
        if not 0 <= index < ARRAY_SIZE:
            raise BasicError('?BAD SUBSCRIPT %s(%d)' % (name, index))
        a = self.arrays.setdefault(name, {})
        if value is None:
            return a.get(index, '' if name.endswith('$') else 0)
        a[index] = self._typed(name, value)

    # ---- token cursor ------------------------------------------------------
    def peek(self):
        toks = self.lines[self.li]
        return toks[self.i] if self.i < len(toks) else ('eol', None)

    def take(self):
        t = self.peek()
        self.i += 1
        return t

    def accept(self, kind, value):
        if self.peek() == (kind, value):
            self.i += 1
            return True
        return False

    def expect(self, kind, value):
        if not self.accept(kind, value):
            raise BasicError('line %d: expected %r, got %r'
                             % (self.numbers[self.li], value, self.peek()))

    def jump(self, number):
        if number not in self.index:
            raise BasicError('?UNDEF\'D STATEMENT %d' % number)
        self.li, self.i = self.index[number], 0

    # ---- expressions -------------------------------------------------------
    def expr(self):
        v = self.and_expr()
        while self.accept('kw', 'or'):
            v = int(v) | int(self.and_expr())
        return v

    def and_expr(self):
        v = self.not_expr()
        while self.accept('kw', 'and'):
            v = int(v) & int(self.not_expr())
        return v

    def not_expr(self):
        if self.accept('kw', 'not'):
            return ~int(self.not_expr())
        return self.relation()

    def relation(self):
        v = self.additive()
        while self.peek()[0] == 'op' and self.peek()[1] in ('=', '<>', '<', '>', '<=', '>='):
            op = self.take()[1]
            w = self.additive()
            if isinstance(v, str) != isinstance(w, str):
                raise BasicError('?TYPE MISMATCH comparing %r %s %r' % (v, op, w))
            v = truth({'=': v == w, '<>': v != w, '<': v < w, '>': v > w,
                       '<=': v <= w, '>=': v >= w}[op])
        return v

    def additive(self):
        v = self.term()
        while self.peek() in (('op', '+'), ('op', '-')):
            op = self.take()[1]
            w = self.term()
            if op == '+':
                if isinstance(v, str) != isinstance(w, str):
                    raise BasicError('?TYPE MISMATCH %r + %r' % (v, w))
                v = v + w
            else:
                v = v - w
        return v

    def term(self):
        v = self.unary()
        while self.peek() in (('op', '*'), ('op', '/')):
            op = self.take()[1]
            w = self.unary()
            v = v * w if op == '*' else v / w
        return v

    def unary(self):
        if self.accept('op', '-'):
            return -self.unary()
        if self.accept('op', '+'):
            return self.unary()
        return self.primary()

    def args(self):
        self.expect('op', '(')
        out = [self.expr()]
        while self.accept('op', ','):
            out.append(self.expr())
        self.expect('op', ')')
        return out

    def primary(self):
        kind, v = self.take()
        if kind in ('num', 'str'):
            return v
        if (kind, v) == ('op', '('):
            r = self.expr()
            self.expect('op', ')')
            return r
        if kind == 'kw' and v in FUNCTIONS:
            a = self.args()
            if v == 'val':
                return basic_val(a[0])
            if v == 'len':
                return len(a[0])
            if v == 'asc':
                if not a[0]:
                    raise BasicError('?ILLEGAL QUANTITY asc("")')
                return ord(a[0][0])
            if v == 'chr$':
                if not 0 <= a[0] <= 255:
                    raise BasicError('?ILLEGAL QUANTITY chr$(%r)' % a[0])
                return chr(int(a[0]))
            if v == 'str$':
                return basic_str(a[0])
            if v == 'int':
                return int(a[0] // 1)
            if v == 'left$':
                return a[0][:int(a[1])]
            if v == 'right$':
                return a[0][len(a[0]) - int(a[1]):] if a[1] else ''
            if v == 'mid$':
                start = int(a[1]) - 1
                if start < 0:
                    raise BasicError('?ILLEGAL QUANTITY mid$ start %r' % a[1])
                return a[0][start:start + int(a[2])] if len(a) > 2 else a[0][start:]
        if kind == 'id':
            if self.peek() == ('op', '('):
                (index,) = self.args()
                return self.element(v, index)
            return self.getvar(v)
        raise BasicError('line %d: unexpected %r' % (self.numbers[self.li], (kind, v)))

    # ---- statements ---------------------------------------------------------
    def run(self, line, **variables):
        """Run from `line` until END, a Stop from a hook, or a RETURN with
        no GOSUB (the end of a subroutine called this way)."""
        for k, v in variables.items():
            self.setvar(k, v)
        self.for_stack = []
        self.gosub_stack = []
        self.jump(line)
        steps = 0
        try:
            while True:
                steps += 1
                if steps > self.max_steps:
                    raise BasicError('no end after %d statements (at line %d)'
                                     % (self.max_steps, self.numbers[self.li]))
                if self.li >= len(self.lines):
                    return
                kind, v = self.peek()
                if kind == 'eol':
                    self.li, self.i = self.li + 1, 0
                    continue
                if (kind, v) == ('op', ':'):
                    self.i += 1
                    continue
                if self.statement():
                    return
        except Stop:
            return

    def skip_line(self):
        self.li, self.i = self.li + 1, 0

    def skip_block(self):
        """After a false IF ... THEN BEGIN: on past the matching BEND."""
        depth = 1
        while True:
            kind, v = self.peek()
            if kind == 'eol':
                self.li, self.i = self.li + 1, 0
                if self.li >= len(self.lines):
                    raise BasicError('BEGIN without BEND')
                continue
            self.i += 1
            if (kind, v) == ('kw', 'begin'):
                depth += 1
            elif (kind, v) == ('kw', 'bend'):
                depth -= 1
                if depth == 0:
                    return

    def statement(self):
        """Run one statement; True when run() should end."""
        kind, v = self.take()
        if kind == 'kw':
            handler = getattr(self, 'st_' + v.rstrip('$'), None)
            if handler is None:
                raise BasicError('statement %s not supported' % v.upper())
            return handler()
        if kind == 'id':
            if self.peek() == ('op', '('):
                (index,) = self.args()
                self.expect('op', '=')
                self.element(v, index, self.expr())
            else:
                self.expect('op', '=')
                self.setvar(v, self.expr())
            return False
        raise BasicError('line %d: cannot run %r' % (self.numbers[self.li], (kind, v)))

    def st_rem(self):
        self.skip_line()

    def st_end(self):
        raise Stop

    def st_begin(self):
        pass

    def st_bend(self):
        pass

    def st_else(self):
        self.skip_line()              # the THEN part ran: the ELSE part doesn't

    def st_if(self):
        cond = self.expr()
        self.expect('kw', 'then')
        if cond:
            if self.peek()[0] == 'num':
                self.jump(self.take()[1])
            return
        if self.accept('kw', 'begin'):
            self.skip_block()
            return
        toks = self.lines[self.li]
        for j in range(self.i, len(toks)):
            if toks[j] == ('kw', 'else'):
                self.i = j + 1
                if self.peek()[0] == 'num':
                    self.jump(self.take()[1])
                return
        self.skip_line()

    def st_goto(self):
        self.jump(self.take()[1])

    def st_gosub(self):
        target = self.take()[1]
        self.gosub_stack.append((self.li, self.i, len(self.for_stack)))
        self.jump(target)

    def st_return(self):
        if not self.gosub_stack:
            return True
        self.li, self.i, depth = self.gosub_stack.pop()
        del self.for_stack[depth:]

    def st_for(self):
        kind, name = self.take()
        self.expect('op', '=')
        self.setvar(name, self.expr())
        self.expect('kw', 'to')
        limit = self.expr()
        step = self.expr() if self.accept('kw', 'step') else 1
        self.for_stack = [f for f in self.for_stack if f[0] != name]
        self.for_stack.append((name, limit, step, self.li, self.i))

    def st_next(self):
        name = self.take()[1] if self.peek()[0] == 'id' else None
        while self.for_stack and name and self.for_stack[-1][0] != name:
            self.for_stack.pop()
        if not self.for_stack:
            raise BasicError('?NEXT WITHOUT FOR')
        var, limit, step, li, i = self.for_stack[-1]
        value = self.getvar(var) + step
        self.setvar(var, value)
        if (step >= 0 and value > limit) or (step < 0 and value < limit):
            self.for_stack.pop()
        else:
            self.li, self.i = li, i

    def st_print(self):
        parts = []
        newline = True
        while self.peek()[0] != 'eol' and self.peek() not in (('op', ':'), ('kw', 'else')):
            if self.accept('op', ';'):
                newline = False
                continue
            if self.accept('op', ','):
                parts.append('\t')
                newline = False
                continue
            v = self.expr()
            parts.append(v if isinstance(v, str) else basic_str(v) + ' ')
            newline = True
        self.out.append(''.join(parts) + ('\r' if newline else ''))

    def st_sys(self):
        addr = self.expr()
        args = []
        while self.accept('op', ','):
            args.append(self.expr())
        self.sys(addr, args)

    def st_rreg(self):
        n = 0
        while True:
            self.setvar(self.take()[1], self.regs[n])
            n += 1
            if not self.accept('op', ','):
                return

    def st_get(self):
        self.setvar(self.take()[1], self.get())

    def st_cursor(self):
        x = self.expr()
        self.expect('op', ',')
        self.cursor(x, self.expr())

    def st_rcursor(self):
        x, y = self.rcursor()
        self.setvar(self.take()[1], x)
        self.expect('op', ',')
        self.setvar(self.take()[1], y)

    def st_movspr(self):
        self.expr()
        while self.accept('op', ','):
            self.expr()

    def st_sleep(self):
        self.expr()
