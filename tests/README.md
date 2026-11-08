# mega-ip unit tests

These tests run the real assembled `eth.bin` on [m65sim](../tools/sim/README.md), a Python MEGA65 simulator, with a scripted host on the LAN. They don't need Xemu or hardware, and nothing needs to be installed beyond Python 3 and the repo's `64tass.exe`.

```
python -m unittest discover -s tests
```

Each run assembles `src/eth.asm` into a temp folder. Tests call routines by label and check registers, state bytes and the frames the stack transmits.

| File | Covers |
|---|---|
| `test_tcp.py` | ARP replies, connect, sending and receiving data, closing in every state, listen, ARP cache aging, the TX path and deferred slot, `ETH_WAIT_100MS` |
| `test_dhcp.py` | DISCOVER, OFFER, REQUEST and ACK, late offers from a second server, ACKs from the wrong server |
| `test_known_bugs.py` | Defects found in review that aren't fixed yet, each with a control test |
| `test_malformed.py` | Bad frames that must be dropped silently, and seeded fuzzing of the receive path |
| `test_api.py` | The documented `$420xx` jump table in README, `api.asm` and the binary, and the fixed memory layout |
| `stack.py` | Harness: `Stack` (load, call, peek/poke, poll, sent frames, BASIC `A$`) and `Peer` (answers ARP, drives a TCP connection either way) |
| `net.py` | Builds and parses Ethernet, ARP, IPv4, TCP, UDP, DHCP and DNS frames with real checksums |

Test classes or docstrings that name a commit are regression tests for that fix.

## Known bugs

Tests in `test_known_bugs.py` are marked `@unittest.expectedFailure`, so the run (and `build.bat`) stays green while the bug is known; the result line shows `expected failures=N`. When a fix lands, that test passes, unittest reports an unexpected success and the run fails: remove the marker in the same commit as the fix.

## Fuzzing

`test_malformed.py` feeds random and mutated frames to a connected stack. After every frame it checks that the code doesn't crash, hang or unbalance the stack; every 50 frames it checks nothing was written outside the stack's own memory (zero page and stack, its bank 4 image, the bank 5 ring); at the end it checks the stack still connects and passes data.

The default is 400 frames from a fixed seed, so the result is the same on every run and a build takes about a second for it. For a deeper run:

```
set MEGAIP_FUZZ=5000
set MEGAIP_FUZZ_SEED=42
python -m unittest discover -s tests -p test_malformed.py
```

A failure names the seed and case number and prints the frame, so it can be reproduced exactly.

## Checking a test against older code

Set `MEGAIP_ROOT` to another checkout to assemble its `src/eth.asm` instead, for example to confirm a regression test fails without its fix:

```
git worktree add ../mega-ip-old master
set MEGAIP_ROOT=..\mega-ip-old
python -m unittest discover -s tests
```

## Limits

The ethernet, DMA and timing models follow the MEGA65 book and xemu. A passing test shows the code is correct against that model, not that the model matches the hardware, so hardware testing is still needed. Time advances by executed instructions, so a timing test checks counts such as raster lines or frames, not wall-clock time.
