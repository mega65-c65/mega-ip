# ML Samples

`ml-term.asm` is a small 45GS02 assembly terminal that calls the MegaIP
library through its public jump table.

Build everything from the repository root:

```bat
build.bat
```

Run it from BASIC 65:

```basic
LOAD "ML-TERM.PRG"
RUN
```

The BASIC launcher in `ml-term.prg` jumps into the machine-language terminal,
which loads `ETH.BIN` from disk into bank 4 at `$42000` before calling MegaIP.
The ML sample sends typed bytes directly through MegaIP's send-byte entry point,
and hostname lookup passes the ML input buffer directly to MegaIP. It does not
use BASIC `A$` for terminal I/O.

The DNS helper used by `ml-term` reads that input buffer from the loaded
program's bank-0 memory by calling the banked `$4700f` helper with `Y=0`.
MegaIP also exposes a bank-1 workspace helper at `$47018`; callers using that
helper should keep buffers in physical `$12000-$1f7ff` because physical
`$10000-$11fff` is reserved for C65 DOS variables and `$1f800-$1ffff` overlaps
color RAM.

For argument-bearing MegaIP calls, `ml-term` stages `A/X/Y/Z` from bank 0 into the bank-4
argument block at `$471c0` and calls the `$4701b` dispatcher. Direct KERNAL
`JSRFAR` calls are still fine for no-argument entries, but they do not preserve
entry registers reliably enough for calls like DNS buffer lookup or TCP send
byte.

At startup, the sample asks whether to use DHCP or manual network setup, then
asks whether to connect by remote IP address or hostname, and prompts for the
remote TCP port. Manual network setup prompts for local IP, default gateway,
subnet mask, and primary DNS. If DHCP fails, the sample falls back to the same
manual prompts.
