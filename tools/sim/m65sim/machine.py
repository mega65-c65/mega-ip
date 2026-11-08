"""A MEGA65 machine for running code in isolation: memory, CPU memory map,
I/O dispatch, DMA, ethernet and video timing.

Memory is a sparse 28-bit flat space.  The CPU's 64K view is translated
through `cpu_map`, a list of (first, last, flat_base) ranges; addresses not
covered map to bank 0.  $D000-$DFFF is I/O while `io_visible` is true.

Time is counted in executed instructions.  The raster line advances every
`instructions_per_line` instructions; a frame is `lines_per_frame` lines.
`advance_frames()` jumps time forward, for timer tests.
"""

from .cpu import Cpu
from .dma import Dma
from .ethernet import Ethernet

ETH_BUFFER = 0xFFDE800
IO_FLAT = 0xFFD3000          # $D000-$DFFF in the flat address space


class StopRun(Exception):
    pass


class Registers:
    """CPU registers as they were when a call returned (a snapshot, so a
    later call can't change values a test is still checking)."""
    __slots__ = ('a', 'x', 'y', 'z', 'b', 'p', 'sp', 'pc')

    def __init__(self, cpu):
        for name in self.__slots__:
            setattr(self, name, getattr(cpu, name))

    @property
    def carry(self):
        return self.p & 1

    def __repr__(self):
        return 'Registers(a=$%02x x=$%02x y=$%02x z=$%02x p=$%02x sp=$%02x)' % (
            self.a, self.x, self.y, self.z, self.p, self.sp)


class Machine:
    def __init__(self, cpu_map=None, instructions_per_line=2, lines_per_frame=312):
        self.pages = {}
        self._cpu_map = list(cpu_map or [])
        self._io_visible = True
        self._cpu_pages = None
        self.io_regs = {}
        self.cpu = Cpu(self)
        self.dma = Dma(self)
        self.eth = Ethernet()
        self.instructions_per_line = instructions_per_line
        self.lines_per_frame = lines_per_frame
        self.time_offset = 0
        self.rng_state = 0x1234
        self._dma_pending = False
        self.io_writes = []          # (addr, value) for registers no model owns
        self.coverage = None         # a coverage.Coverage to record executed PCs

    # ---- flat memory -----------------------------------------------------
    def _page(self, addr, create):
        key = addr >> 12
        p = self.pages.get(key)
        if p is None and create:
            p = self.pages[key] = bytearray(4096)
        return p

    def read_flat(self, addr):
        addr &= 0x0FFFFFFF
        if ETH_BUFFER <= addr < ETH_BUFFER + 0x800:
            return self.eth.buffer_read(addr - ETH_BUFFER)
        if IO_FLAT <= addr < IO_FLAT + 0x1000:
            return self.io_read(0xD000 + addr - IO_FLAT)
        p = self._page(addr, False)
        return p[addr & 0xFFF] if p else 0

    def write_flat(self, addr, v):
        addr &= 0x0FFFFFFF
        if ETH_BUFFER <= addr < ETH_BUFFER + 0x800:
            self.eth.buffer_write(addr - ETH_BUFFER, v & 0xFF)
            return
        if IO_FLAT <= addr < IO_FLAT + 0x1000:
            self.io_write(0xD000 + addr - IO_FLAT, v & 0xFF)
            return
        self._page(addr, True)[addr & 0xFFF] = v & 0xFF

    def load_flat(self, addr, data):
        for i, b in enumerate(data):
            self.write_flat(addr + i, b)

    def dump_flat(self, addr, n):
        return bytes(self.read_flat(addr + i) for i in range(n))

    # ---- CPU view --------------------------------------------------------
    # Each 256-byte CPU page that maps to plain RAM gets a memoryview into
    # the flat page, so ordinary reads and writes skip the address
    # translation.  Pages that hit I/O or the ethernet buffer stay None and
    # take the slow path.  Changing cpu_map or io_visible rebuilds the table.

    @property
    def cpu_map(self):
        return self._cpu_map

    @cpu_map.setter
    def cpu_map(self, value):
        self._cpu_map = list(value)
        self._cpu_pages = None

    @property
    def io_visible(self):
        return self._io_visible

    @io_visible.setter
    def io_visible(self, value):
        self._io_visible = bool(value)
        self._cpu_pages = None

    def _build_cpu_pages(self):
        table = []
        for hi in range(256):
            addr = hi << 8
            flat = self.translate(addr) & 0x0FFFFFFF
            special = ((self._io_visible and 0xD0 <= hi <= 0xDF)
                       or (flat & 0xFFF) > 0xF00
                       or (ETH_BUFFER - 0x100 < flat < ETH_BUFFER + 0x800)
                       or (IO_FLAT - 0x100 < flat < IO_FLAT + 0x1000))
            if special:
                table.append(None)
            else:
                page = self._page(flat, True)
                off = flat & 0xFFF
                table.append(memoryview(page)[off:off + 256])
        self._cpu_pages = table
        return table

    def translate(self, addr):
        for first, last, base in self._cpu_map:
            if first <= addr <= last:
                return base + (addr - first)
        return addr

    def read(self, addr):
        pages = self._cpu_pages or self._build_cpu_pages()
        mv = pages[(addr >> 8) & 0xFF]
        if mv is not None:
            return mv[addr & 0xFF]
        addr &= 0xFFFF
        if self._io_visible and 0xD000 <= addr <= 0xDFFF:
            return self.io_read(addr)
        return self.read_flat(self.translate(addr))

    def write(self, addr, v):
        pages = self._cpu_pages or self._build_cpu_pages()
        mv = pages[(addr >> 8) & 0xFF]
        if mv is not None:
            mv[addr & 0xFF] = v & 0xFF
            return
        addr &= 0xFFFF
        if self._io_visible and 0xD000 <= addr <= 0xDFFF:
            self.io_write(addr, v & 0xFF)
            return
        self.write_flat(self.translate(addr), v)

    # memoryviews can't be pickled or deep-copied: drop the page table from
    # snapshots and rebuild it on first use.
    def __getstate__(self):
        state = self.__dict__.copy()
        state['_cpu_pages'] = None
        return state

    def __setstate__(self, state):
        self.__dict__.update(state)

    # ---- video timing ----------------------------------------------------
    @property
    def time(self):
        return self.cpu.instructions + self.time_offset

    @property
    def raster_line(self):
        return (self.time // self.instructions_per_line) % self.lines_per_frame

    @property
    def frame(self):
        return self.time // (self.instructions_per_line * self.lines_per_frame)

    def advance_frames(self, n):
        self.time_offset += n * self.instructions_per_line * self.lines_per_frame

    # ---- I/O ------------------------------------------------------------
    def io_read(self, addr):
        if 0xD6E0 <= addr <= 0xD6EF:
            return self.eth.reg_read(addr - 0xD6E0)
        if addr == 0xD012:
            return self.raster_line & 0xFF
        if addr == 0xD011:
            return ((self.raster_line >> 1) & 0x80) | (self.io_regs.get(addr, 0x1B) & 0x7F)
        if addr == 0xD7FA:
            return self.frame & 0xFF
        if addr == 0xD7EF:
            self.rng_state = (self.rng_state * 1103515245 + 12345) & 0x7FFFFFFF
            return (self.rng_state >> 16) & 0xFF
        if addr == 0xD7FE:
            return 0x00                 # RNG ready
        return self.io_regs.get(addr, 0)

    def io_write(self, addr, v):
        if 0xD6E0 <= addr <= 0xD6EF:
            self.eth.reg_write(addr - 0xD6E0, v)
            return
        if addr == 0xD707:
            self._dma_pending = True
            return
        self.io_regs[addr] = v
        self.io_writes.append((addr, v))

    # ---- execution ------------------------------------------------------
    def needs_after_instruction(self):
        """Lets Cpu.run() skip after_instruction() when nothing is pending."""
        return self._dma_pending

    def after_instruction(self, cpu):
        if self._dma_pending:
            self._dma_pending = False
            self.dma.run_inline(cpu)

    def call(self, addr, a=0, x=0, y=0, z=0, max_instructions=5_000_000,
             return_addr=0xFFF0):
        """JSR to `addr` with the given registers and run until it returns.

        A return address on the stack points at `return_addr`, which must not
        be executed by the code under test.  Returns a Registers snapshot.
        """
        c = self.cpu
        c.a, c.x, c.y, c.z = a & 0xFF, x & 0xFF, y & 0xFF, z & 0xFF
        sp_before = c.sp
        ret = (return_addr - 1) & 0xFFFF
        c.push(ret >> 8)
        c.push(ret & 0xFF)
        c.pc = addr & 0xFFFF
        if not c.run(return_addr, max_instructions):
            raise StopRun('$%04x did not return within %d instructions (pc=$%04x)'
                          % (addr, max_instructions, c.pc))
        if c.sp != sp_before:
            raise StopRun('stack unbalanced after $%04x: sp $%02x -> $%02x'
                          % (addr, sp_before, c.sp))
        return Registers(c)
