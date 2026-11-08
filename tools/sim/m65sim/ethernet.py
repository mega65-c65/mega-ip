"""MEGA65 45E100 ethernet controller model.

Registers at $D6E0-$D6EF and the frame buffer at $FFDE800-$FFDEFFF, following
the MEGA65 book (appendix "45E100", pp. U-4/U-5) and xemu's ethernet65.c:

- $D6E0 read bit 7 = TX idle; writes hold the reset bits.
- $D6E1 read bit 5 = RXQ, at least one received frame is waiting.
  A rising edge of bit 1 (write $01 then $03) rotates the receive ring: the
  next waiting frame becomes visible and the previous buffer is freed.
- $D6E2/$D6E3 = TX size (12 bits); writing $01 to $D6E4 transmits.
- $D6E5 = control 3 (filter bits); $D6E9-$D6EE = MAC address.
- Reading the frame buffer returns the buffer the CPU currently sees:
  +0 length low, +1 length bits 8-11 plus flags (bit 4 multicast, bit 5
  broadcast, bit 6 unicast to our MAC, bit 7 CRC error), frame from +2.
  As on hardware the length includes the 4-byte CRC that follows the frame.
  Writing the buffer fills the TX buffer.

The ring has 4 buffers: the one the CPU sees plus up to 3 waiting frames.
Frames that arrive while all are full are dropped and counted.
"""

from collections import deque


class Ethernet:
    RX_BUFFERS = 4
    BUFFER_SIZE = 0x800

    def __init__(self):
        self.mac = [0x02, 0x47, 0x53, 0x65, 0x65, 0x65]
        self.ctrl1 = 0
        self.ctrl2 = 0
        self.ctrl3 = 0
        self.tx_size = 0
        self.tx_busy = False            # tests may set this to make TX "busy"
        self.rx_waiting = deque()
        self.rx_visible = bytearray(self.BUFFER_SIZE)
        self.tx_buffer = bytearray(self.BUFFER_SIZE)
        self.sent = []                  # transmitted frames (bytes), oldest first
        self.dropped = 0
        self.rotations = 0
        self.empty_rotations = 0

    # ---- test-side API -------------------------------------------------
    def receive(self, frame, crc_error=False):
        """Queue a frame (without CRC) as if it arrived from the wire."""
        frame = bytes(frame)
        if len(self.rx_waiting) >= self.RX_BUFFERS - 1:
            self.dropped += 1
            return False
        dest = frame[:6]
        flags = 0
        if dest == b'\xff' * 6:
            flags |= 0x20
        elif dest[0] & 1:
            flags |= 0x10
        if list(dest) == self.mac:
            flags |= 0x40
        if crc_error:
            flags |= 0x80
        length = len(frame) + 4
        buf = bytearray(self.BUFFER_SIZE)
        buf[0] = length & 0xFF
        buf[1] = ((length >> 8) & 0x0F) | flags
        buf[2:2 + len(frame)] = frame
        buf[2 + len(frame):6 + len(frame)] = b'\xde\xad\xbe\xef'   # stand-in CRC
        self.rx_waiting.append(buf)
        return True

    def take_sent(self):
        """Return and clear the frames transmitted so far."""
        out, self.sent = self.sent, []
        return out

    # ---- bus side --------------------------------------------------------
    def reg_read(self, off):
        if off == 0:
            return (0 if self.tx_busy else 0x80) | (self.ctrl1 & 0x3F)
        if off == 1:
            return (0x20 if self.rx_waiting else 0) | (self.ctrl2 & 0xC0)
        if off == 2:
            return self.tx_size & 0xFF
        if off == 3:
            return (self.tx_size >> 8) & 0x0F
        if off == 5:
            return self.ctrl3
        if 9 <= off <= 14:
            return self.mac[off - 9]
        return 0

    def reg_write(self, off, v):
        if off == 0:
            self.ctrl1 = v
        elif off == 1:
            if not (self.ctrl2 & 0x02) and (v & 0x02):
                self._rotate()
            self.ctrl2 = v
        elif off == 2:
            self.tx_size = (self.tx_size & 0xF00) | v
        elif off == 3:
            self.tx_size = (self.tx_size & 0xFF) | ((v & 0x0F) << 8)
        elif off == 4:
            if v == 0x01:
                self.sent.append(bytes(self.tx_buffer[:self.tx_size]))
        elif off == 5:
            self.ctrl3 = v
        elif 9 <= off <= 14:
            self.mac[off - 9] = v

    def _rotate(self):
        self.rotations += 1
        if self.rx_waiting:
            self.rx_visible = self.rx_waiting.popleft()
        else:
            self.empty_rotations += 1

    def buffer_read(self, off):
        return self.rx_visible[off]

    def buffer_write(self, off, v):
        self.tx_buffer[off] = v
