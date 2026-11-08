"""Self-tests for m65sim: CPU instructions, flat addressing, DMA, ethernet.

Each test assembles a small snippet with the real 64tass, so the encodings
under test are the ones the assembler actually produces.

    python -m unittest discover -s tools/sim/tests
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from m65sim import Machine, assemble_text, find_tass  # noqa: E402

TASS = find_tass(os.path.dirname(__file__))
ORG = 0x2000


def run(body, setup=None, **regs):
    """Assemble `body` at $2000 (ending in rts), run it, return the machine."""
    text = '    .cpu "45gs02"\n    * = $%04x\nstart:\n%s\n    rts\n' % (ORG, body)
    asm = assemble_text(text, TASS)
    m = Machine()
    m.load_flat(asm.start, asm.binary)
    m.labels = asm.labels
    if setup:
        setup(m)
    m.call(asm['start'], **regs)
    return m


class Arithmetic(unittest.TestCase):
    def test_adc_carry_and_overflow(self):
        m = run('''
            clc
            lda #$7f
            adc #$01
            php
            pla
            sta $10
            sec
            lda #$ff
            adc #$00
            sta $11
            php
            pla
            sta $12
        ''')
        self.assertEqual(m.read(0x10) & 0xC3, 0x80 | 0x40)   # N V, no C/Z
        self.assertEqual(m.read(0x11), 0x00)
        self.assertEqual(m.read(0x12) & 0x03, 0x03)           # Z and C

    def test_sbc_borrow(self):
        m = run('''
            sec
            lda #$10
            sbc #$20
            sta $10
            lda #0
            rol
            sta $11
        ''')
        self.assertEqual(m.read(0x10), 0xF0)
        self.assertEqual(m.read(0x11), 0)                     # borrow -> C=0

    def test_cmp_sets_carry(self):
        m = run('''
            lda #5
            cmp #5
            lda #0
            rol
            sta $10
            lda #4
            cmp #5
            lda #0
            rol
            sta $11
        ''')
        self.assertEqual((m.read(0x10), m.read(0x11)), (1, 0))


class Ce02Instructions(unittest.TestCase):
    def test_z_register_and_stack(self):
        m = run('''
            ldz #$5a
            phz
            ldz #0
            plz
            tza
            sta $10
            lda #$33
            taz
            stz $11
            inz
            stz $12
        ''')
        self.assertEqual([m.read(a) for a in (0x10, 0x11, 0x12)], [0x5A, 0x33, 0x34])

    def test_long_branches_both_directions(self):
        m = run('''
            lda #0
            sta $10
            ldx #1
            bne far_ahead
            lda #$ee
            sta $10
        back:
            inc $10
            rts
            .fill 300, $00
        far_ahead:
            inc $10
            cpx #1
            beq back
        ''')
        self.assertEqual(m.read(0x10), 2)

    def test_word_ops_and_phw(self):
        m = run('''
            lda #$ff
            sta $20
            lda #$12
            sta $21
            inw $20
            phw #$beef
            pla
            sta $30
            pla
            sta $31
        ''')
        self.assertEqual(m.read(0x20) | (m.read(0x21) << 8), 0x1300)
        self.assertEqual((m.read(0x30), m.read(0x31)), (0xEF, 0xBE))

    def test_neg_asr_tsb_bbs(self):
        m = run('''
            lda #3
            neg
            sta $10
            lda #$84
            asr
            sta $11
            lda #$f0
            sta $12
            lda #$0f
            tsb $12
            lda #$00
            sta $13
            smb 3,$13
            bbs 3,$13,+
            lda #$ee
            sta $14
        +   rmb 3,$13
        ''')
        self.assertEqual([m.read(a) for a in (0x10, 0x11, 0x12, 0x13, 0x14)],
                         [0xFD, 0xC2, 0xFF, 0x00, 0x00])

    def test_bsr_and_jsr_indirect(self):
        m = run('''
            bsr sub
            jsr (vec)
            bra done
        sub:
            inc $10
            rts
        sub2:
            inc $11
            rts
        vec:
            .word sub2
        done:
        ''')
        self.assertEqual((m.read(0x10), m.read(0x11)), (1, 1))

    def test_zp_z_indexed_16bit(self):
        m = run('''
            lda #<$3000
            sta $40
            lda #>$3000
            sta $41
            ldz #5
            lda #$77
            sta ($40),z
        ''')
        self.assertEqual(m.read(0x3005), 0x77)


class FlatAddressing(unittest.TestCase):
    def test_flat_store_and_load_bank5(self):
        m = run('''
            lda #$00
            sta $45
            lda #$10
            sta $46
            lda #$05
            sta $47
            lda #$00
            sta $48
            ldz #3
            lda #$a5
            sta [$45],z
            ldz #4
            lda [$45],z
            sta $10
        ''', setup=lambda m: m.write_flat(0x51004, 0x3C))
        self.assertEqual(m.read_flat(0x51003), 0xA5)
        self.assertEqual(m.read(0x10), 0x3C)


class DmaJobs(unittest.TestCase):
    def test_inline_copy_and_continue(self):
        m = run('''
            sta $d707
            .byte $80, $00, $81, $00, $00     ; options, end
            .byte $00                         ; copy
            .word 4                           ; count
            .byte <src, >src, $00             ; source bank 0
            .byte $00, $40, $05               ; target $54000
            .byte $00                         ; sub-command
            .word $0000                       ; modulo
            lda #$99
            sta $10
            bra done
        src:
            .byte 1, 2, 3, 4
        done:
        ''')
        self.assertEqual(m.dump_flat(0x54000, 4), bytes([1, 2, 3, 4]))
        self.assertEqual(m.read(0x10), 0x99)       # execution resumed after the list
        self.assertEqual(m.dma.jobs, 1)

    def test_fill_with_target_megabyte(self):
        m = run('''
            sta $d707
            .byte $81, $ff, $00               ; target MB $ff
            .byte $03                         ; fill
            .word 3
            .byte $5a, $00, $00               ; fill value
            .byte $00, $e8, $0d               ; $ffde800 = ethernet TX buffer
            .byte $00
            .word $0000
        ''')
        self.assertEqual(bytes(m.eth.tx_buffer[:3]), b'\x5a\x5a\x5a')

    def test_megabyte_options_reset_per_job(self):
        m = run('''
            sta $d707
            .byte $81, $ff, $00
            .byte $03
            .word 1
            .byte $11, $00, $00
            .byte $00, $e8, $0d
            .byte $00
            .word 0
            sta $d707
            .byte $00                          ; no MB option this time
            .byte $03
            .word 1
            .byte $22, $00, $00
            .byte $00, $e8, $0d                ; -> $0de800 in bank $0d
            .byte $00
            .word 0
        ''')
        self.assertEqual(m.eth.tx_buffer[0], 0x11)
        self.assertEqual(m.read_flat(0x0DE800), 0x22)


class EthernetModel(unittest.TestCase):
    def test_rotate_on_rising_edge_and_rxq(self):
        m = Machine()
        e = m.eth
        frame = bytes([0xFF] * 6 + [1, 2, 3, 4, 5, 6, 0x08, 0x06]) + bytes(46)
        e.receive(frame)
        self.assertEqual(m.io_read(0xD6E1) & 0x20, 0x20)
        m.io_write(0xD6E1, 0x01)
        self.assertEqual(e.rotations, 0)
        m.io_write(0xD6E1, 0x03)
        self.assertEqual(e.rotations, 1)
        self.assertEqual(m.io_read(0xD6E1) & 0x20, 0)
        length = m.read_flat(0xFFDE800) | ((m.read_flat(0xFFDE801) & 0x0F) << 8)
        self.assertEqual(length, len(frame) + 4)
        self.assertEqual(m.read_flat(0xFFDE801) & 0x20, 0x20)   # broadcast flag
        self.assertEqual(m.dump_flat(0xFFDE802, 6), b'\xff' * 6)

    def test_ring_drops_when_full(self):
        e = Machine().eth
        for _ in range(3):
            self.assertTrue(e.receive(bytes(60)))
        self.assertFalse(e.receive(bytes(60)))
        self.assertEqual(e.dropped, 1)

    def test_transmit_captures_frame(self):
        m = Machine()
        for i in range(60):
            m.write_flat(0xFFDE800 + i, i)
        m.io_write(0xD6E2, 60)
        m.io_write(0xD6E3, 0)
        m.io_write(0xD6E4, 1)
        self.assertEqual(m.eth.take_sent(), [bytes(range(60))])


if __name__ == '__main__':
    unittest.main()
