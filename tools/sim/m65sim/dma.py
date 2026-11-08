"""MEGA65 enhanced DMA controller (F018B job lists), inline form only.

A write to $D707 starts an inline job: the list is read from the CPU's
current PC (just after the triggering store) and the CPU resumes after the
last list byte.  Behaviour follows xemu's dma65.c:

- enhanced options end at $00; options with bit 7 set take one argument;
  $80/$81 set the source/target megabyte and reset to 0 for each new job
  (they stay set across chained entries);
- each entry is 12 bytes: command, count (2), source (3), target (3),
  sub-command, modulo (2);
- an address is (MB << 20) + (bits 4-6 of the bank byte << 20) + low 20 bits;
  bit 7 of the bank byte selects I/O for $D000-$DFFF;
- copy (op 0) and fill (op 3) are supported; count 0 means 65536.
"""


class DmaError(Exception):
    pass


class Dma:
    def __init__(self, machine):
        self.m = machine
        self.jobs = 0           # jobs run, for tests

    def run_inline(self, cpu):
        pc = cpu.pc

        def rd():
            nonlocal pc
            v = self.m.read(pc)
            pc = (pc + 1) & 0xFFFF
            return v

        src_mb = dst_mb = 0
        count_hi = 0
        while True:
            # enhanced options
            while True:
                opt = rd()
                if opt == 0:
                    break
                arg = rd() if opt & 0x80 else None
                if opt == 0x80:
                    src_mb = arg
                elif opt == 0x81:
                    dst_mb = arg
                elif opt == 0x90:
                    count_hi = arg
                elif opt == 0x0A:
                    raise DmaError('F018A job lists are not modelled')
                elif opt == 0x0B:
                    pass
                else:
                    raise DmaError('DMA option $%02x is not modelled' % opt)
            job = [rd() for _ in range(12)]
            self._run_job(job, src_mb, dst_mb, count_hi)
            self.jobs += 1
            if not job[0] & 0x04:       # not chained
                break
        cpu.pc = pc

    def _address(self, lo, mid, bank, mb):
        base = ((mb << 20) + ((bank & 0x70) << 16)) & 0xFF00000
        off = ((bank & 0x0F) << 16) | (mid << 8) | lo
        io = bool(bank & 0x80) and 0xD000 <= (off & 0xFFFF) <= 0xDFFF and off < 0x10000
        return base + off, io

    def _run_job(self, job, src_mb, dst_mb, count_hi):
        cmd = job[0]
        op = cmd & 3
        count = job[1] | (job[2] << 8) | (count_hi << 16)
        if count == 0:
            count = 0x10000
        src, src_io = self._address(job[3], job[4], job[5], src_mb)
        dst, dst_io = self._address(job[6], job[7], job[8], dst_mb)
        sub = job[9]
        src_step = 0 if sub & 0x02 else (-1 if cmd & 0x10 else 1)
        dst_step = 0 if sub & 0x08 else (-1 if cmd & 0x20 else 1)
        if sub & 0x05:
            raise DmaError('DMA modulo is not modelled')
        if op == 0:
            for _ in range(count):
                v = self.m.io_read(src & 0xFFFF) if src_io else self.m.read_flat(src)
                if dst_io:
                    self.m.io_write(dst & 0xFFFF, v)
                else:
                    self.m.write_flat(dst, v)
                src += src_step
                dst += dst_step
        elif op == 3:
            fill = job[3]
            for _ in range(count):
                if dst_io:
                    self.m.io_write(dst & 0xFFFF, fill)
                else:
                    self.m.write_flat(dst, fill)
                dst += dst_step
        else:
            raise DmaError('DMA operation %d is not modelled' % op)
