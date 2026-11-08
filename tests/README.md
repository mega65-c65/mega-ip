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
| `stack.py` | Harness: `Stack` (load, call, peek/poke, poll, sent frames) and `Peer` (answers ARP, drives a TCP connection) |
| `net.py` | Builds and parses Ethernet, ARP, IPv4, TCP, UDP and DHCP frames with real checksums |

Test classes or docstrings that name a commit are regression tests for that fix.

## Checking a test against older code

Set `MEGAIP_ROOT` to another checkout to assemble its `src/eth.asm` instead, for example to confirm a regression test fails without its fix:

```
git worktree add ../mega-ip-old master
set MEGAIP_ROOT=..\mega-ip-old
python -m unittest discover -s tests
```

## Limits

The ethernet, DMA and timing models follow the MEGA65 book and xemu. A passing test shows the code is correct against that model, not that the model matches the hardware, so hardware testing is still needed. Time advances by executed instructions, so a timing test checks counts such as raster lines or frames, not wall-clock time.
