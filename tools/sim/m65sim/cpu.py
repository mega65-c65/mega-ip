"""45GS02 CPU core (65CE02 instruction set plus flat [zp],z addressing).

Enough of the MEGA65 CPU to run mega-ip in isolation:
- the full 65CE02 opcode map (Z and B registers, 16-bit branches, BSR, PHW,
  INW/DEW, ASW/ROW, NEG/ASR, TSB/TRB, RMB/SMB, BBR/BBS, (d,SP),Y);
- the 45GS02 flat addressing prefix: NOP ($EA) before a (zp),Z instruction
  uses a 32-bit pointer and a 28-bit address.

Not modelled (they raise CpuError): decimal mode, interrupts/BRK/RTI, MAP,
and the 45GS02 32-bit Q instructions (NEG NEG prefix).  mega-ip uses none of
them.  The stack is the 8-bit 6502 stack in page 1.
"""


class CpuError(Exception):
    pass


N, V, E, B_FLAG, D, I, Z_FLAG, C = 0x80, 0x40, 0x20, 0x10, 0x08, 0x04, 0x02, 0x01

# opcode -> (mnemonic, addressing mode)
_OPS = """
00 brk imp  01 ora izx  02 cle imp  03 see imp  04 tsb zp   05 ora zp   06 asl zp   07 rmb0 zp
08 php imp  09 ora imm  0a asl acc  0b tsy imp  0c tsb abs  0d ora abs  0e asl abs  0f bbr0 zpr
10 bpl rel  11 ora izy  12 ora izz  13 bpl rlw  14 trb zp   15 ora zpx  16 asl zpx  17 rmb1 zp
18 clc imp  19 ora aby  1a inc acc  1b inz imp  1c trb abs  1d ora abx  1e asl abx  1f bbr1 zpr
20 jsr abs  21 and izx  22 jsr ind  23 jsr iax  24 bit zp   25 and zp   26 rol zp   27 rmb2 zp
28 plp imp  29 and imm  2a rol acc  2b tys imp  2c bit abs  2d and abs  2e rol abs  2f bbr2 zpr
30 bmi rel  31 and izy  32 and izz  33 bmi rlw  34 bit zpx  35 and zpx  36 rol zpx  37 rmb3 zp
38 sec imp  39 and aby  3a dec acc  3b dez imp  3c bit abx  3d and abx  3e rol abx  3f bbr3 zpr
40 rti imp  41 eor izx  42 neg acc  43 asr acc  44 asr zp   45 eor zp   46 lsr zp   47 rmb4 zp
48 pha imp  49 eor imm  4a lsr acc  4b taz imp  4c jmp abs  4d eor abs  4e lsr abs  4f bbr4 zpr
50 bvc rel  51 eor izy  52 eor izz  53 bvc rlw  54 asr zpx  55 eor zpx  56 lsr zpx  57 rmb5 zp
58 cli imp  59 eor aby  5a phy imp  5b tab imp  5c map imp  5d eor abx  5e lsr abx  5f bbr5 zpr
60 rts imp  61 adc izx  62 rtn imm  63 bsr rlw  64 stz zp   65 adc zp   66 ror zp   67 rmb6 zp
68 pla imp  69 adc imm  6a ror acc  6b tza imp  6c jmp ind  6d adc abs  6e ror abs  6f bbr6 zpr
70 bvs rel  71 adc izy  72 adc izz  73 bvs rlw  74 stz zpx  75 adc zpx  76 ror zpx  77 rmb7 zp
78 sei imp  79 adc aby  7a ply imp  7b tba imp  7c jmp iax  7d adc abx  7e ror abx  7f bbr7 zpr
80 bra rel  81 sta izx  82 sta isy  83 bra rlw  84 sty zp   85 sta zp   86 stx zp   87 smb0 zp
88 dey imp  89 bit imm  8a txa imp  8b sty abx  8c sty abs  8d sta abs  8e stx abs  8f bbs0 zpr
90 bcc rel  91 sta izy  92 sta izz  93 bcc rlw  94 sty zpx  95 sta zpx  96 stx zpy  97 smb1 zp
98 tya imp  99 sta aby  9a txs imp  9b stx aby  9c stz abs  9d sta abx  9e stz abx  9f bbs1 zpr
a0 ldy imm  a1 lda izx  a2 ldx imm  a3 ldz imm  a4 ldy zp   a5 lda zp   a6 ldx zp   a7 smb2 zp
a8 tay imp  a9 lda imm  aa tax imp  ab ldz abs  ac ldy abs  ad lda abs  ae ldx abs  af bbs2 zpr
b0 bcs rel  b1 lda izy  b2 lda izz  b3 bcs rlw  b4 ldy zpx  b5 lda zpx  b6 ldx zpy  b7 smb3 zp
b8 clv imp  b9 lda aby  ba tsx imp  bb ldz abx  bc ldy abx  bd lda abx  be ldx aby  bf bbs3 zpr
c0 cpy imm  c1 cmp izx  c2 cpz imm  c3 dew zp   c4 cpy zp   c5 cmp zp   c6 dec zp   c7 smb4 zp
c8 iny imp  c9 cmp imm  ca dex imp  cb asw abs  cc cpy abs  cd cmp abs  ce dec abs  cf bbs4 zpr
d0 bne rel  d1 cmp izy  d2 cmp izz  d3 bne rlw  d4 cpz zp   d5 cmp zpx  d6 dec zpx  d7 smb5 zp
d8 cld imp  d9 cmp aby  da phx imp  db phz imp  dc cpz abs  dd cmp abx  de dec abx  df bbs5 zpr
e0 cpx imm  e1 sbc izx  e2 lda isy  e3 inw zp   e4 cpx zp   e5 sbc zp   e6 inc zp   e7 smb6 zp
e8 inx imp  e9 sbc imm  ea nop imp  eb row abs  ec cpx abs  ed sbc abs  ee inc abs  ef bbs6 zpr
f0 beq rel  f1 sbc izy  f2 sbc izz  f3 beq rlw  f4 phw iw   f5 sbc zpx  f6 inc zpx  f7 smb7 zp
f8 sed imp  f9 sbc aby  fa plx imp  fb plz imp  fc phw abs  fd sbc abx  fe inc abx  ff bbs7 zpr
"""

OPCODES = {}
for _line in _OPS.strip().splitlines():
    _f = _line.split()
    for _i in range(0, len(_f), 3):
        OPCODES[int(_f[_i], 16)] = (_f[_i + 1], _f[_i + 2])
assert len(OPCODES) == 256

# operand bytes after the opcode, per mode
_LEN = {'imp': 0, 'acc': 0, 'imm': 1, 'iw': 2, 'zp': 1, 'zpx': 1, 'zpy': 1,
        'abs': 2, 'abx': 2, 'aby': 2, 'ind': 2, 'iax': 2, 'izx': 1, 'izy': 1,
        'izz': 1, 'isy': 1, 'rel': 1, 'rlw': 2, 'zpr': 2}

_IZZ = [OPCODES[i][1] == 'izz' for i in range(256)]

_BRANCH = {'bpl': (N, False), 'bmi': (N, True), 'bvc': (V, False), 'bvs': (V, True),
           'bcc': (C, False), 'bcs': (C, True), 'bne': (Z_FLAG, False),
           'beq': (Z_FLAG, True)}


class Cpu:
    """bus must provide read(addr16), write(addr16, v), read_flat(addr28),
    write_flat(addr28, v) and after_instruction(cpu)."""

    def __init__(self, bus):
        self.bus = bus
        self.a = self.x = self.y = self.z = 0
        self.b = 0                      # base page
        self.sp = 0xFF
        self.p = E | I                  # 8-bit stack (E=1)
        self.pc = 0
        self.instructions = 0
        self._addr_modes = self._build_addr_modes()
        self._table = self._build_table()

    # ---- helpers -----------------------------------------------------
    def _fetch(self):
        v = self.bus.read(self.pc)
        self.pc = (self.pc + 1) & 0xFFFF
        return v

    def _nz(self, v):
        v &= 0xFF
        self.p = (self.p & ~(N | Z_FLAG)) | (v & N) | (0 if v else Z_FLAG)
        return v

    def _flag(self, f, on):
        self.p = (self.p | f) if on else (self.p & ~f)

    def push(self, v):
        self.bus.write(0x100 | self.sp, v & 0xFF)
        self.sp = (self.sp - 1) & 0xFF

    def pull(self):
        self.sp = (self.sp + 1) & 0xFF
        return self.bus.read(0x100 | self.sp)

    def _zp(self, off):
        return (self.b << 8) | (off & 0xFF)

    def _ptr16(self, zp):
        return self.bus.read(self._zp(zp)) | (self.bus.read(self._zp(zp + 1)) << 8)

    # ---- addressing ---------------------------------------------------
    # Each mode has a small function returning ('mem', addr16),
    # ('flat', addr28), ('acc',) or ('imm', value); the dict is looked up per
    # instruction instead of walking an if-chain.

    def _am_acc(self, o, f): return ('acc',)
    def _am_imm(self, o, f): return ('imm', o[0])
    def _am_zp(self, o, f): return ('mem', (self.b << 8) | o[0])
    def _am_zpx(self, o, f): return ('mem', (self.b << 8) | ((o[0] + self.x) & 0xFF))
    def _am_zpy(self, o, f): return ('mem', (self.b << 8) | ((o[0] + self.y) & 0xFF))
    def _am_abs(self, o, f): return ('mem', o[0] | (o[1] << 8))
    def _am_abx(self, o, f): return ('mem', ((o[0] | (o[1] << 8)) + self.x) & 0xFFFF)
    def _am_aby(self, o, f): return ('mem', ((o[0] | (o[1] << 8)) + self.y) & 0xFFFF)
    def _am_izx(self, o, f): return ('mem', self._ptr16(o[0] + self.x))
    def _am_izy(self, o, f): return ('mem', (self._ptr16(o[0]) + self.y) & 0xFFFF)

    def _am_izz(self, o, f):
        if f:
            ptr = 0
            for i in range(4):
                ptr |= self.bus.read(self._zp(o[0] + i)) << (8 * i)
            return ('flat', ((ptr & 0x0FFFFFFF) + self.z) & 0x0FFFFFFF)
        return ('mem', (self._ptr16(o[0]) + self.z) & 0xFFFF)

    def _am_isy(self, o, f):
        base = 0x100 | ((self.sp + o[0]) & 0xFF)
        ptr = self.bus.read(base) | (self.bus.read(0x100 | ((base + 1) & 0xFF)) << 8)
        return ('mem', (ptr + self.y) & 0xFFFF)

    def _operand_addr(self, mode, ops, flat):
        """Return ('mem', addr16) / ('flat', addr28) / ('acc',) / ('imm', v)."""
        fn = self._addr_modes.get(mode)
        if fn is None:
            raise CpuError('no operand address for mode %s' % mode)
        return fn(ops, flat)

    def _val(self, mode, ops, flat):
        """The operand's value (fast path for loads and ALU ops)."""
        if mode == 'imm':
            return ops[0]
        loc = self._addr_modes[mode](ops, flat)
        kind = loc[0]
        if kind == 'mem':
            return self.bus.read(loc[1])
        if kind == 'flat':
            return self.bus.read_flat(loc[1])
        return self.a                                   # acc

    def _store(self, mode, ops, flat, v):
        loc = self._addr_modes[mode](ops, flat)
        if loc[0] == 'mem':
            self.bus.write(loc[1], v & 0xFF)
        else:
            self._write(loc, v)

    def _read(self, loc):
        kind = loc[0]
        if kind == 'acc':
            return self.a
        if kind == 'imm':
            return loc[1]
        if kind == 'flat':
            return self.bus.read_flat(loc[1])
        return self.bus.read(loc[1])

    def _write(self, loc, v):
        v &= 0xFF
        kind = loc[0]
        if kind == 'acc':
            self.a = v
        elif kind == 'flat':
            self.bus.write_flat(loc[1], v)
        elif kind == 'mem':
            self.bus.write(loc[1], v)
        else:
            raise CpuError('cannot write to %r' % (loc,))

    # ---- arithmetic -----------------------------------------------------
    def _adc(self, v):
        if self.p & D:
            raise CpuError('decimal mode is not modelled')
        r = self.a + v + (self.p & C)
        self._flag(C, r > 0xFF)
        self._flag(V, (~(self.a ^ v) & (self.a ^ r) & 0x80) != 0)
        self.a = self._nz(r)

    def _cmp(self, reg, v):
        r = reg - v
        self._flag(C, r >= 0)
        self._nz(r)

    # ---- execution ----------------------------------------------------
    def _build_addr_modes(self):
        return {m: getattr(self, '_am_' + m) for m in
                ('acc', 'imm', 'zp', 'zpx', 'zpy', 'abs', 'abx', 'aby', 'izx', 'izy',
                 'izz', 'isy')}

    def _build_table(self):
        """Per-opcode (handler, mode, operand length), resolved once."""
        table = []
        for op in range(256):
            mn, mode = OPCODES[op]
            if mn == 'bra':
                h = self._make_branch(None, True)
            elif mn in _BRANCH:
                h = self._make_branch(*_BRANCH[mn])
            elif mn[:3] in ('bbr', 'bbs'):
                h = self._make_bbx(int(mn[3]), mn[:3] == 'bbs')
            elif mn[:3] in ('rmb', 'smb'):
                h = self._make_bit(int(mn[3]), mn[0] == 's')
            else:
                h = getattr(self, '_op_' + mn, None)
                if h is None:
                    raise CpuError('no handler for %s' % mn)
            table.append((h, mode, _LEN[mode]))
        return table

    def _make_branch(self, flag, want):
        def branch(mode, ops, flat, start):
            if flag is None or bool(self.p & flag) == want:
                if mode == 'rel':
                    off = ops[0] - 256 if ops[0] & 0x80 else ops[0]
                    self.pc = (self.pc + off) & 0xFFFF
                else:   # 16-bit: relative to opcode address + 2
                    off = ops[0] | (ops[1] << 8)
                    off = off - 0x10000 if off & 0x8000 else off
                    self.pc = (start + 2 + off) & 0xFFFF
        return branch

    def _make_bbx(self, bit, if_set):
        def bbx(mode, ops, flat, start):
            v = self.bus.read(self._zp(ops[0]))
            if bool(v & (1 << bit)) == if_set:
                off = ops[1] - 256 if ops[1] & 0x80 else ops[1]
                self.pc = (self.pc + off) & 0xFFFF
        return bbx

    def _make_bit(self, bit, set_it):
        def rmb_smb(mode, ops, flat, start):
            addr = self._zp(ops[0])
            v = self.bus.read(addr)
            self.bus.write(addr, (v | (1 << bit)) if set_it else (v & ~(1 << bit)))
        return rmb_smb

    def step(self):
        table = self._table
        read = self.bus.read
        start = self.pc
        op = read(start)
        pc = (start + 1) & 0xFFFF
        flat = False
        if op == 0xEA:
            nxt = read(pc)
            if _IZZ[nxt]:                       # NOP prefix -> flat [zp],z
                flat = True
                op = nxt
                pc = (pc + 1) & 0xFFFF
        elif op == 0x42 and read(pc) == 0x42:
            raise CpuError('45GS02 Q instructions are not modelled (pc=$%04x)' % start)
        h, mode, n = table[op]
        if n == 0:
            ops = ()
        elif n == 1:
            ops = (read(pc),)
            pc = (pc + 1) & 0xFFFF
        else:
            ops = (read(pc), read((pc + 1) & 0xFFFF))
            pc = (pc + 2) & 0xFFFF
        self.pc = pc
        h(mode, ops, flat, start)
        self.instructions += 1
        self.bus.after_instruction(self)

    def run(self, stop_pc, max_instructions):
        """Execute until PC == stop_pc or `max_instructions` have run.
        Returns True if stop_pc was reached.  Same semantics as calling
        step() in a loop, with the per-instruction overhead hoisted out."""
        table = self._table
        bus = self.bus
        read = bus.read
        after = bus.after_instruction
        izz = _IZZ
        hook = getattr(bus, 'needs_after_instruction', None)
        left = max_instructions
        while self.pc != stop_pc:
            if left <= 0:
                return False
            left -= 1
            start = self.pc
            op = read(start)
            pc = (start + 1) & 0xFFFF
            flat = False
            if op == 0xEA:
                nxt = read(pc)
                if izz[nxt]:
                    flat = True
                    op = nxt
                    pc = (pc + 1) & 0xFFFF
            elif op == 0x42 and read(pc) == 0x42:
                raise CpuError('45GS02 Q instructions are not modelled (pc=$%04x)' % start)
            h, mode, n = table[op]
            if n == 0:
                ops = ()
            elif n == 1:
                ops = (read(pc),)
                pc = (pc + 1) & 0xFFFF
            else:
                ops = (read(pc), read((pc + 1) & 0xFFFF))
                pc = (pc + 2) & 0xFFFF
            self.pc = pc
            h(mode, ops, flat, start)
            self.instructions += 1
            if hook is None or hook():
                after(self)
        return True

    # The handler table holds bound methods and closures over this Cpu;
    # rebuild it after a copy so it doesn't point at the original.
    def __getstate__(self):
        state = self.__dict__.copy()
        state.pop('_table', None)
        state.pop('_addr_modes', None)
        return state

    def __setstate__(self, state):
        self.__dict__.update(state)
        self._addr_modes = self._build_addr_modes()
        self._table = self._build_table()

    # loads / stores
    def _op_lda(self, m, o, f, s): self.a = self._nz(self._val(m, o, f))
    def _op_ldx(self, m, o, f, s): self.x = self._nz(self._val(m, o, f))
    def _op_ldy(self, m, o, f, s): self.y = self._nz(self._val(m, o, f))
    def _op_ldz(self, m, o, f, s): self.z = self._nz(self._val(m, o, f))
    def _op_sta(self, m, o, f, s): self._store(m, o, f, self.a)
    def _op_stx(self, m, o, f, s): self._store(m, o, f, self.x)
    def _op_sty(self, m, o, f, s): self._store(m, o, f, self.y)
    def _op_stz(self, m, o, f, s): self._store(m, o, f, self.z)

    # logic / arithmetic
    def _op_ora(self, m, o, f, s): self.a = self._nz(self.a | self._val(m, o, f))
    def _op_and(self, m, o, f, s): self.a = self._nz(self.a & self._val(m, o, f))
    def _op_eor(self, m, o, f, s): self.a = self._nz(self.a ^ self._val(m, o, f))
    def _op_adc(self, m, o, f, s): self._adc(self._val(m, o, f))
    def _op_sbc(self, m, o, f, s): self._adc(self._val(m, o, f) ^ 0xFF)
    def _op_cmp(self, m, o, f, s): self._cmp(self.a, self._val(m, o, f))
    def _op_cpx(self, m, o, f, s): self._cmp(self.x, self._val(m, o, f))
    def _op_cpy(self, m, o, f, s): self._cmp(self.y, self._val(m, o, f))
    def _op_cpz(self, m, o, f, s): self._cmp(self.z, self._val(m, o, f))

    def _op_bit(self, m, o, f, s):
        v = self._read(self._operand_addr(m, o, f))
        self._flag(Z_FLAG, (self.a & v) == 0)
        if m != 'imm':
            self.p = (self.p & ~(N | V)) | (v & (N | V))

    def _rmw(self, m, o, f, fn):
        loc = self._operand_addr(m, o, f)
        self._write(loc, fn(self._read(loc)))

    def _op_asl(self, m, o, f, s):
        def fn(v):
            self._flag(C, v & 0x80)
            return self._nz(v << 1)
        self._rmw(m, o, f, fn)

    def _op_lsr(self, m, o, f, s):
        def fn(v):
            self._flag(C, v & 1)
            return self._nz(v >> 1)
        self._rmw(m, o, f, fn)

    def _op_rol(self, m, o, f, s):
        def fn(v):
            r = (v << 1) | (self.p & C)
            self._flag(C, v & 0x80)
            return self._nz(r)
        self._rmw(m, o, f, fn)

    def _op_ror(self, m, o, f, s):
        def fn(v):
            r = (v >> 1) | (0x80 if self.p & C else 0)
            self._flag(C, v & 1)
            return self._nz(r)
        self._rmw(m, o, f, fn)

    def _op_asr(self, m, o, f, s):
        def fn(v):
            self._flag(C, v & 1)
            return self._nz((v >> 1) | (v & 0x80))
        self._rmw(m, o, f, fn)

    def _op_inc(self, m, o, f, s): self._rmw(m, o, f, lambda v: self._nz(v + 1))
    def _op_dec(self, m, o, f, s): self._rmw(m, o, f, lambda v: self._nz(v - 1))
    def _op_neg(self, m, o, f, s): self.a = self._nz(-self.a)

    def _op_tsb(self, m, o, f, s):
        loc = self._operand_addr(m, o, f)
        v = self._read(loc)
        self._flag(Z_FLAG, (v & self.a) == 0)
        self._write(loc, v | self.a)

    def _op_trb(self, m, o, f, s):
        loc = self._operand_addr(m, o, f)
        v = self._read(loc)
        self._flag(Z_FLAG, (v & self.a) == 0)
        self._write(loc, v & ~self.a)

    # 16-bit memory ops
    def _op_inw(self, m, o, f, s):
        a = self._zp(o[0])
        w = (self.bus.read(a) | (self.bus.read(self._zp(o[0] + 1)) << 8)) + 1
        self.bus.write(a, w & 0xFF)
        self.bus.write(self._zp(o[0] + 1), (w >> 8) & 0xFF)
        self._flag(Z_FLAG, (w & 0xFFFF) == 0)
        self._flag(N, w & 0x8000)

    def _op_dew(self, m, o, f, s):
        a = self._zp(o[0])
        w = (self.bus.read(a) | (self.bus.read(self._zp(o[0] + 1)) << 8)) - 1
        self.bus.write(a, w & 0xFF)
        self.bus.write(self._zp(o[0] + 1), (w >> 8) & 0xFF)
        self._flag(Z_FLAG, (w & 0xFFFF) == 0)
        self._flag(N, w & 0x8000)

    def _word_rmw(self, o, fn):
        a = o[0] | (o[1] << 8)
        w = self.bus.read(a) | (self.bus.read((a + 1) & 0xFFFF) << 8)
        r = fn(w) & 0xFFFF
        self.bus.write(a, r & 0xFF)
        self.bus.write((a + 1) & 0xFFFF, r >> 8)
        self._flag(Z_FLAG, r == 0)
        self._flag(N, r & 0x8000)

    def _op_asw(self, m, o, f, s):
        def fn(w):
            self._flag(C, w & 0x8000)
            return w << 1
        self._word_rmw(o, fn)

    def _op_row(self, m, o, f, s):
        def fn(w):
            r = (w << 1) | (self.p & C)
            self._flag(C, w & 0x8000)
            return r
        self._word_rmw(o, fn)

    # register transfers and inc/dec
    def _op_tax(self, *a): self.x = self._nz(self.a)
    def _op_tay(self, *a): self.y = self._nz(self.a)
    def _op_taz(self, *a): self.z = self._nz(self.a)
    def _op_txa(self, *a): self.a = self._nz(self.x)
    def _op_tya(self, *a): self.a = self._nz(self.y)
    def _op_tza(self, *a): self.a = self._nz(self.z)
    def _op_tsx(self, *a): self.x = self._nz(self.sp)
    def _op_txs(self, *a): self.sp = self.x
    def _op_tsy(self, *a): self.y = self._nz(0x01)          # SPH (8-bit stack page)
    def _op_tys(self, *a):
        if self.y != 0x01:
            raise CpuError('moving the stack page is not modelled')
    def _op_tab(self, *a): self.b = self.a
    def _op_tba(self, *a): self.a = self._nz(self.b)
    def _op_inx(self, *a): self.x = self._nz(self.x + 1)
    def _op_iny(self, *a): self.y = self._nz(self.y + 1)
    def _op_inz(self, *a): self.z = self._nz(self.z + 1)
    def _op_dex(self, *a): self.x = self._nz(self.x - 1)
    def _op_dey(self, *a): self.y = self._nz(self.y - 1)
    def _op_dez(self, *a): self.z = self._nz(self.z - 1)

    # flags
    def _op_clc(self, *a): self.p &= ~C
    def _op_sec(self, *a): self.p |= C
    def _op_cli(self, *a): self.p &= ~I
    def _op_sei(self, *a): self.p |= I
    def _op_clv(self, *a): self.p &= ~V
    def _op_cld(self, *a): self.p &= ~D
    def _op_sed(self, *a): raise CpuError('decimal mode is not modelled')
    def _op_cle(self, *a): raise CpuError('16-bit stack (CLE) is not modelled')
    def _op_see(self, *a): self.p |= E
    def _op_nop(self, *a): pass

    # stack
    def _op_pha(self, *a): self.push(self.a)
    def _op_phx(self, *a): self.push(self.x)
    def _op_phy(self, *a): self.push(self.y)
    def _op_phz(self, *a): self.push(self.z)
    def _op_php(self, *a): self.push(self.p | B_FLAG)
    def _op_pla(self, *a): self.a = self._nz(self.pull())
    def _op_plx(self, *a): self.x = self._nz(self.pull())
    def _op_ply(self, *a): self.y = self._nz(self.pull())
    def _op_plz(self, *a): self.z = self._nz(self.pull())
    def _op_plp(self, *a): self.p = (self.pull() & ~B_FLAG) | E

    def _op_phw(self, m, o, f, s):
        if m == 'iw':
            w = o[0] | (o[1] << 8)
        else:
            a = o[0] | (o[1] << 8)
            w = self.bus.read(a) | (self.bus.read((a + 1) & 0xFFFF) << 8)
        self.push(w >> 8)
        self.push(w & 0xFF)

    # jumps and subroutines
    def _op_jmp(self, m, o, f, s):
        w = o[0] | (o[1] << 8)
        if m == 'abs':
            self.pc = w
        elif m == 'ind':
            self.pc = self.bus.read(w) | (self.bus.read((w + 1) & 0xFFFF) << 8)
        else:   # iax
            w = (w + self.x) & 0xFFFF
            self.pc = self.bus.read(w) | (self.bus.read((w + 1) & 0xFFFF) << 8)

    def _op_jsr(self, m, o, f, s):
        ret = (self.pc - 1) & 0xFFFF
        self.push(ret >> 8)
        self.push(ret & 0xFF)
        self._op_jmp(m, o, f, s)

    def _op_bsr(self, m, o, f, s):
        ret = (self.pc - 1) & 0xFFFF
        self.push(ret >> 8)
        self.push(ret & 0xFF)
        off = o[0] | (o[1] << 8)
        off = off - 0x10000 if off & 0x8000 else off
        self.pc = (s + 2 + off) & 0xFFFF

    def _op_rts(self, *a):
        lo = self.pull()
        hi = self.pull()
        self.pc = (((hi << 8) | lo) + 1) & 0xFFFF

    def _op_rtn(self, m, o, f, s):
        self._op_rts()
        self.sp = (self.sp + o[0]) & 0xFF

    def _op_brk(self, m, o, f, s): raise CpuError('BRK at $%04x' % s)
    def _op_rti(self, m, o, f, s): raise CpuError('RTI is not modelled ($%04x)' % s)
    def _op_map(self, m, o, f, s): raise CpuError('MAP is not modelled ($%04x)' % s)
