# mega-ip TODO

## High Priority

1. Add RFC 793 TCP segment acceptability checks.
   - Validate incoming segment sequence numbers against `RCV.NXT` and the receive window.
   - Keep duplicate/past segment ACK behavior.
   - Decide how much out-of-order support is worth implementing for this stack.

2. Make RST handling RFC-safe.
   - Do not accept blind RSTs.
   - Validate RST sequence numbers before tearing down a connection.
   - Emit RST for closed or unmatched TCP segments where appropriate.

3. Add intentional ISN generation.
   - Restore randomness intentionally, not as unused dead code.
   - Mix a hardware/random source with timer/raster state and connection tuple data.
   - Use it for both active open and passive open.

4. Implement DHCP lease lifecycle.
   - Use option 51 lease time.
   - Add T1/T2 renewal and rebind behavior.
   - Preserve the currently stable DHCP path while adding this.

5. Update ARP cache from ARP requests.
   - Merge sender SHA/SPA from ARP requests into the cache before replying.
   - This follows RFC 826 behavior.

## Completed

1. Added accepted RX frame length storage.
   - Stores copied Ethernet frame length excluding FCS.
   - Stores copied Ethernet payload length for protocol bounds checks.
   - Drops over-buffer Ethernet frames instead of parsing truncated data.

2. Added a real inbound IPv4 validation layer.
   - Validates version/IHL.
   - Validates IPv4 total length against the copied Ethernet payload length.
   - Verifies IPv4 header checksum.
   - Drops fragments unless/until reassembly is implemented.
   - Gates ICMP, DNS, DHCP, and TCP dispatch behind this validation.

3. Added inbound TCP checksum verification.
   - Verifies pseudo-header, TCP header, options, and payload checksum.
   - Bounds TCP header length against the validated IPv4 total length.
   - Drops bad TCP segments before they affect TCP state or buffers.

4. Added modular TCP sequence comparison helpers.
   - Added `src/tcp_seq.asm` in the fixed gap before the BASIC-visible data block.
   - Uses signed 32-bit sequence deltas for `SEG.SEQ` vs `RCV.NXT`.
   - Uses bounded ACK retirement: `SND.UNA < SEG.ACK <= SND.NXT`.
   - Retires pending data only when the ACK covers the pending segment.

5. Centralized IPv4 header checksum generation.
   - Added `src/checksum.asm` with a shared one's-complement checksum helper.
   - `ipv4.asm` and DHCP IPv4-header checksum generation now use the shared helper.
   - Removed DHCP's duplicate local IPv4 checksum adder/folder scratch code.

## Medium Priority

1. Respect the peer TCP window.
   - Read `SEG.WND`.
   - Do not send beyond the advertised window.
   - Add zero-window probe behavior.

2. Improve retransmit timing.
   - Replace the fixed retry timer with adaptive RTO/backoff.
   - Model R1/R2-style retry behavior instead of hard reset after a fixed count.

3. Tighten TCP close states.
   - FIN-WAIT-1 should advance only when an ACK covers our FIN.
   - TIME-WAIT should re-ACK retransmitted FINs.
   - Document or revisit the shortened TIME-WAIT duration.

4. Harden DHCP validation.
   - Match `chaddr` against our MAC.
   - Accept ACK only in the expected state.
   - Use higher-entropy XIDs.

5. Harden DNS parsing.
   - Bound every read against DNS packet length.
   - Match A-record owner names where practical.
   - Keep truncated responses as fail-only unless TCP DNS is added later.

6. Handle inbound ICMP errors.
   - Surface destination unreachable and time exceeded to TCP/connect state.
   - Use ICMP errors to fail connects faster when possible.

7. Create a C-friendly integration layer.
   - Define stable C-callable wrappers around the public jump table.
   - Document calling convention, register clobbers, memory/bank assumptions, and buffer ownership.
   - Provide headers or bindings for common MEGA65 C toolchains.
   - Include examples for init, DHCP/manual config, DNS lookup, connect, send, receive, poll, and disconnect.

## Low Priority

1. Add TCP MSS option.
   - Send MSS on SYN and SYN-ACK.
   - Low urgency because payloads are already capped small.

2. Generate IP identification values if DF behavior changes.
   - Current fixed IP ID is acceptable while DF is always set.

3. Deduplicate checksum code.
   - DHCP has a separate IPv4 checksum path.
   - Shared checksum helpers would reduce maintenance risk.

4. Improve ARP niceties.
   - Send gratuitous ARP after DHCP bind.
   - Replace slot-0 overwrite with a better cache replacement policy.

## ASM Refactor

Initial behavior-preserving extraction has started. Keep future moves mechanical:
same include order, same labels, same fixed `* =` placements, and a clean build after
each group.

- `src/api.asm` - extracted
  Public jump table, BASIC/ML ABI, getters, and setters.

- `src/eth.asm`
  MEGA65 Ethernet controller access, DMA RX/TX, frame send/receive, and MAC filtering.

- `src/ipv4.asm` - extracted
  IPv4 parse/validate/build, checksum, total-length checks, and fragment policy.

- `src/tcp.asm` - partially extracted
  TCP state machine and segment receive handling.

- `src/tcp_tx.asm` - extracted
  Send queue, ACK retirement, retransmit logic, and peer window handling.

- `src/tcp_seq.asm` - extracted
   32-bit modular sequence helpers and segment acceptability tests.

- `src/icmp.asm` - extracted
  Echo replies and future ICMP error handling.

- `src/rbuf.asm` - extracted
  RX ring buffer.

- `src/checksum.asm` - extracted
  Shared one's-complement checksum helper. IPv4 and DHCP header checksums use it.

- Keep existing focused modules:
  `src/arp.asm`, `src/dns.asm`, `src/dhcp.asm`, `src/macros.asm`, and `src/mega65.asm`.

Suggested order:

1. Harden RST and TCP segment acceptability.
2. Revisit TCP close-state ACK validation.
3. Revisit DHCP lease renewal and DNS bounds checks.
