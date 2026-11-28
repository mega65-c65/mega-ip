# mega-ip unit tests

These tests run the real assembled `eth.bin` on [m65sim](../tools/sim/README.md), a Python MEGA65 simulator, with a scripted host on the LAN. They don't need Xemu or hardware, and nothing needs to be installed beyond Python 3 and the repo's `64tass.exe`.

```
test.bat                     simulator self-tests, then these tests
python -m unittest discover -s tests          (just these)
```

`test.bat coverage` and `test.bat mutate ...` run the coverage report and mutation testing described below. The build (`build.bat`) doesn't run the tests.

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
| `test_peers.py` | Segments as real hosts send them: TCP options, timestamps, overlapping and duplicate retransmissions, keepalive probes, segment sizes around byte boundaries, a peer's zero window |
| `test_send_window.py` | The send queue and sliding window: several segments in flight, the peer's window and window updates, Nagle's rule, the ML send byte, go-back-N after a loss and the retry limit, the MSS option on SYN and SYN-ACK, full-size received segments |
| `test_comparisons.py` | Address and field checks compared byte by byte (MAC, peer MAC, IPs, DHCP client address, mask contiguity, DNS reply address), FIN and SYN-ACK retry intervals, the window-update threshold, over-long host names |
| `test_review_items.py` | Remaining review items confirmed or ruled out (ARP header validation, DNS port wrap, DHCP option position, `RBUF_PUT`) |
| `test_known_bugs.py` | Defects found in review (all fixed now), each with a control test; new known bugs go here |
| `test_malformed.py` | Bad frames that must be dropped silently, and seeded fuzzing of the receive path |
| `test_parser_fuzz.py` | Structure-aware fuzzing of the DNS and DHCP reply parsers: replies that pass the ID, port and checksum checks but have random structure, with an oracle (a lookup only resolves to an A record in the reply; DHCP only binds from a valid ACK) |
| `test_api.py` | The documented `$420xx` jump table in README, `api.asm` and the binary, and the fixed memory layout |
| `sim_rate.py` | Not a test: rough upload and download speed over a link with a round-trip delay (`python tests\sim_rate.py 100` for 100 ms). Set `MEGAIP_ROOT` to compare another checkout |
| `stack.py` | Harness: `Stack` (load, call, peek/poke, poll, `run_frames`, sent frames, BASIC `A$`, block and byte readers), `Peer` (answers ARP, drives a TCP connection either way), `Responder` (answers ARP and DNS while a blocking call runs) and DNS helpers |
| `net.py` | Builds and parses Ethernet, ARP, IPv4, TCP, UDP, DHCP and DNS frames with real checksums |

Test classes or docstrings that name a commit are regression tests for that fix.

## Known bugs

One known limitation is recorded this way now: DHCP options more than 255 bytes into the options field (`test_review_items.py`). A newly found bug can be recorded in `test_known_bugs.py` as a test marked `@unittest.expectedFailure`, so the run (and `test.bat`) stays green while the bug is known; the result line shows `expected failures=N`. When a fix lands, that test passes, unittest reports an unexpected success and the run fails: remove the marker in the same commit as the fix.

## Fuzzing

`test_malformed.py` feeds random and mutated frames to a connected stack, and `test_parser_fuzz.py` feeds structured DNS and DHCP replies that get past the ID and checksum checks into the parsers. After every frame it checks that the code doesn't crash, hang or unbalance the stack; every 50 frames it checks nothing was written outside the stack's own memory (zero page and stack, its bank 4 image, the bank 5 ring); at the end it checks the stack still connects and passes data.

The defaults (400 frames, 300 replies per parser) use fixed seeds, so the result is the same on every run and a build takes about a second for it. For a deeper run:

```
set MEGAIP_FUZZ=5000
set MEGAIP_FUZZ_SEED=42
python -m unittest discover -s tests -p test_malformed.py
```

A failure names the seed and case number and prints the frame, so it can be reproduced exactly.

## Coverage

```
python tests/coverage.py
```

runs the whole suite with instruction recording on and maps the executed addresses back to source lines through a 64tass listing. It prints coverage per source file and writes the full report to `target/coverage.txt`: routines no test enters, then for each partly covered routine the source lines that never ran (`--all` includes routines with only one or two missed lines). Use it to find what still needs a test.

## Mutation testing

```
python tests/mutate.py [--sample N] [--file dns.asm] [--jobs J] [--rerun SURVIVORS.txt]
```

flips one conditional branch at a time in `eth.bin` (only branches the suite runs) and runs the whole suite on each mutant, in parallel. A mutant the suite fails on is killed; a surviving one is a branch whose direction no test checks. Some survivors make no observable difference (for example, a loop that copies bytes which are already equal), so read each one before writing a test. It runs the suite once per mutant, so it isn't part of the build: the full set (about 800 branches) takes about 15 minutes on 12 cores. Save the output and use `--rerun` on it to retest only the survivors after adding tests. Last full run: 682 of 807 killed (85%); most of the rest make no observable difference or are checks repeated later in the receive path.

Every test also checks everything the stack sends: `Stack.sent()` fails on a bad IPv4, TCP, UDP or ICMP checksum, and on a frame shorter than 60 bytes or of odd length (a real MEGA65 never got odd-length frames through).

## Checking a test against older code

Set `MEGAIP_ROOT` to another checkout to assemble its `src/eth.asm` instead, for example to confirm a regression test fails without its fix:

```
git worktree add ../mega-ip-old master
set MEGAIP_ROOT=..\mega-ip-old
python -m unittest discover -s tests
```

## Limits

The ethernet, DMA and timing models follow the MEGA65 book and xemu. A passing test shows the code is correct against that model, not that the model matches the hardware, so hardware testing is still needed. Time advances by executed instructions, so a timing test checks counts such as raster lines or frames, not wall-clock time.
