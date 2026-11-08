# mega-ip unit tests

These tests run the real assembled `eth.bin` on [m65sim](../tools/sim/README.md), a Python MEGA65 simulator, with a scripted host on the LAN. They don't need Xemu or hardware, and nothing needs to be installed beyond Python 3 and the repo's `64tass.exe`.

```
python -m unittest discover -s tests
```

Each run assembles `src/eth.asm` into a temp folder. Tests call routines by label and check registers, state bytes and the frames the stack transmits. Time passes with `Stack.run_frames()`, which polls at least twice per frame as a MEGA65 program would; the stack's timers count a frame when the raster has gone back since the previous poll.

| File | Covers |
|---|---|
| `test_tcp.py` | ARP replies, connect, sending and receiving data, closing in every state, listen, ARP cache aging, the TX path and deferred slot, `ETH_WAIT_100MS` |
| `test_dhcp.py` | DISCOVER, OFFER, REQUEST and ACK, late offers from a second server, ACKs from the wrong server |
| `test_retransmit.py` | Data retransmission and timeout, SYN, SYN-ACK, FIN and ARP retries, TIME_WAIT length and expiry |
| `test_rst.py` | RST in every synchronized state, out-of-window RSTs, RST during the handshake, stray RSTs |
| `test_window.py` | Advertised window, full ring and zero window, window updates, data through the ring wrap, frames waiting in or dropped by the NIC |
| `test_icmp.py` | Echo replies (fields, checksums, large and odd payloads) and requests that must not be answered |
| `test_dns.py` | Query format, A records, CNAMEs (in one reply or followed), NXDOMAIN, truncation, malformed and mismatched replies, timeout |
| `test_api_calls.py` | The `$420xx` and `$476xx` entry points called by address: settings, A$ send and character translation, byte and block receive, connect poll and cancel, listen and accept, blocking and buffer DNS lookups, the staged dispatcher, reserved slots |
| `test_sessions.py` | Many connections on one stack: back-to-back client sessions with every kind of close, the web server's accept loop, state and unread data not leaking between connections |
| `test_routing.py` | Gateway routing and subnet masks, frame filtering, ARP, ping and DNS during a transfer, the send queue |
| `test_timers.py` | Timers when the program polls once per frame at a fixed raster line |
| `test_review_items.py` | Remaining review items confirmed or ruled out (ARP header validation, DNS port wrap, DHCP option position, `RBUF_PUT`) |
| `test_known_bugs.py` | Defects found in review (all fixed now), each with a control test; new known bugs go here |
| `test_malformed.py` | Bad frames that must be dropped silently, and seeded fuzzing of the receive path |
| `test_api.py` | The documented `$420xx` jump table in README, `api.asm` and the binary, and the fixed memory layout |
| `stack.py` | Harness: `Stack` (load, call, peek/poke, poll, `run_frames`, sent frames, BASIC `A$`, block and byte readers), `Peer` (answers ARP, drives a TCP connection either way), `Responder` (answers ARP and DNS while a blocking call runs) and DNS helpers |
| `net.py` | Builds and parses Ethernet, ARP, IPv4, TCP, UDP, DHCP and DNS frames with real checksums |

Test classes or docstrings that name a commit are regression tests for that fix.

## Known bugs

One known limitation is recorded this way now: DHCP options more than 255 bytes into the options field (`test_review_items.py`). A newly found bug can be recorded in `test_known_bugs.py` as a test marked `@unittest.expectedFailure`, so the run (and `build.bat`) stays green while the bug is known; the result line shows `expected failures=N`. When a fix lands, that test passes, unittest reports an unexpected success and the run fails: remove the marker in the same commit as the fix.

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
