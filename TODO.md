# mega-ip TODO

## High Priority

1. Add a real inbound IPv4 validation layer.
   - Validate version/IHL.
   - Validate IPv4 total length against the actual captured frame length.
   - Verify IPv4 header checksum.
   - Drop fragments unless/until reassembly is implemented.
   - Use this to protect ICMP, DNS, DHCP, and TCP from malformed packet lengths.

2. Verify inbound TCP checksums.
   - Drop bad TCP segments before they affect state.
   - Do not ACK, reset, or copy payload from a segment with a bad checksum.

3. Fix TCP sequence and ACK comparisons.
   - Use modular 32-bit sequence comparisons.
   - Enforce ACK bounds, including `SEG.ACK <= SND.NXT`.
   - Add RFC 793 segment acceptability checks against `RCV.NXT` and the receive window.

4. Make RST handling RFC-safe.
   - Do not accept blind RSTs.
   - Validate RST sequence numbers before tearing down a connection.
   - Emit RST for closed or unmatched TCP segments where appropriate.

5. Add intentional ISN generation.
   - Restore randomness intentionally, not as unused dead code.
   - Mix a hardware/random source with timer/raster state and connection tuple data.
   - Use it for both active open and passive open.

6. Store the actual RX frame length globally.
   - Make the copied frame length available to IPv4, ICMP, DNS, DHCP, and TCP.
   - Use it for all bounds checks.

7. Implement DHCP lease lifecycle.
   - Use option 51 lease time.
   - Add T1/T2 renewal and rebind behavior.
   - Preserve the currently stable DHCP path while adding this.

8. Update ARP cache from ARP requests.
   - Merge sender SHA/SPA from ARP requests into the cache before replying.
   - This follows RFC 826 behavior.

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

## Proposed ASM Refactor

Split the current stack into smaller files once behavior is stable enough to move safely:

- `src/api.asm`
  Public jump table, BASIC/ML ABI, getters, and setters.

- `src/eth.asm`
  MEGA65 Ethernet controller access, DMA RX/TX, frame send/receive, and MAC filtering.

- `src/ipv4.asm`
  IPv4 parse/validate/build, checksum, total-length checks, and fragment policy.

- `src/tcp.asm`
  TCP state machine and segment receive handling.

- `src/tcp_tx.asm`
  Send queue, ACK retirement, retransmit logic, and peer window handling.

- `src/tcp_seq.asm`
  32-bit modular sequence helpers and segment acceptability tests.

- `src/icmp.asm`
  Echo replies and future ICMP error handling.

- `src/rbuf.asm`
  RX ring buffer.

- `src/checksum.asm`
  Shared checksum helpers for IP, TCP, UDP, and ICMP.

- Keep existing focused modules:
  `src/arp.asm`, `src/dns.asm`, `src/dhcp.asm`, `src/macros.asm`, and `src/mega65.asm`.

Suggested order:

1. Extract files without behavior changes.
2. Add inbound IPv4 validation.
3. Add inbound TCP checksum verification.
4. Add modular TCP sequence helpers.
5. Harden RST and TCP segment acceptability.
6. Revisit DHCP lease renewal and DNS bounds checks.
