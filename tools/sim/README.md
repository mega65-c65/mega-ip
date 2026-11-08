# m65sim

A small MEGA65 simulator in plain Python for unit-testing 45GS02 code in isolation. It doesn't depend on mega-ip, so it can be reused or moved to its own repo.

## What it models

| Part | Coverage |
|---|---|
| CPU (`cpu.py`) | Full 65CE02 instruction set: Z and B registers, 16-bit branches, `BSR`, `PHW`, `INW`/`DEW`, `ASW`/`ROW`, `NEG`/`ASR`, `TSB`/`TRB`, `RMB`/`SMB`, `BBR`/`BBS`, `(d,s),y`. The 45GS02 flat addressing prefix (`NOP` before `(zp),z` gives `[zp],z` with a 28-bit address). 8-bit stack in page 1. |
| Memory (`machine.py`) | Sparse 28-bit flat memory. The CPU's 64K view goes through `cpu_map`, a list of `(first, last, flat_base)` ranges; everything else is bank 0. `$D000-$DFFF` is I/O. |
| DMA (`dma.py`) | Inline enhanced jobs started by writing `$D707`: options `$80`/`$81`/`$90`/`$0B`, F018B 12-byte entries, chaining, copy and fill, I/O flag. |
| Ethernet (`ethernet.py`) | 45E100 registers `$D6E0-$D6EE` and the frame buffer at `$FFDE800`: RXQ, rotate on the rising edge of `$D6E1` bit 1, 4-buffer receive ring, receive flags, TX size and send, TX-busy switch for tests. |
| Video timing | `$D012`/`$D011` raster and the `$D7FA` frame counter, driven by executed instructions. `advance_frames(n)` jumps time forward. |
| Other I/O | `$D7EF`/`$D7FE` random numbers (deterministic). Unknown registers read 0, and writes are logged in `io_writes`. |
| Assembler (`tass.py`) | Runs 64tass and returns the binary, load address and labels. `find_tass()` checks `$M65SIM_TASS`, then `PATH`, then parent folders. |

## Not modelled

These raise an error if executed: decimal mode, interrupts (`BRK`/`RTI`), `MAP`, the 16-bit stack (`CLE`), and the 45GS02 32-bit Q instructions. Also not modelled: DMA modulo, F018A lists, the KERNAL and the screen.

## Limits

The hardware models follow the MEGA65 book and xemu's sources. Tests show code is correct against that model; only real hardware shows that the model matches the machine.

## Example

```python
from m65sim import Machine, assemble, find_tass

asm = assemble('src/main.asm', find_tass())
m = Machine(cpu_map=[(0x2000, 0x7FFF, 0x42000)])   # CPU $2000-$7FFF -> flat $42000
m.load_flat(0x40000 + asm.start, asm.binary)      # code assembled at $2000
m.call(asm['MY_ROUTINE'], a=1)
print(m.cpu.a, m.eth.take_sent())
```

## Self-tests

```
python -m unittest discover -s tools/sim/tests
```

`test_opcodes.py` assembles every opcode with 64tass and checks it against the CPU's opcode table. `test_cpu.py` runs snippets for arithmetic, 65CE02 instructions, flat addressing, DMA and the ethernet model.
