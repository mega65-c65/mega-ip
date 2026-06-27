;=============================================================================
; Shared Internet checksum helpers
;=============================================================================
; CHECKSUM_ONES_COMP computes the one's-complement checksum over a byte range.
;
; In:
;   CHECKSUM_PTR_LO/HI = source address in the current mapped bank
;   CHECKSUM_LEN_LO/HI = number of bytes to include
;
; Out:
;   CHECKSUM_RESULT_HI/LO = complemented checksum in network byte order
;=============================================================================

CHECKSUM_ONES_COMP:
    lda #$00
    sta CHECKSUM_SUM_HI
    sta CHECKSUM_SUM_LO
    sta CHECKSUM_WORD_HI
    sta CHECKSUM_WORD_LO
    sta CHECKSUM_RESULT_HI
    sta CHECKSUM_RESULT_LO

    lda CHECKSUM_PTR_LO
    sta CHECKSUM_READ_BYTE+1
    lda CHECKSUM_PTR_HI
    sta CHECKSUM_READ_BYTE+2
    ldy #$00

_checksum_loop:
    lda CHECKSUM_LEN_LO
    ora CHECKSUM_LEN_HI
    beq _checksum_done

    jsr CHECKSUM_READ_BYTE
    sta CHECKSUM_WORD_HI
    jsr CHECKSUM_DEC_LEN

    lda CHECKSUM_LEN_LO
    ora CHECKSUM_LEN_HI
    beq _checksum_odd_word

    jsr CHECKSUM_READ_BYTE
    sta CHECKSUM_WORD_LO
    jsr CHECKSUM_DEC_LEN
    bra _checksum_add_word

_checksum_odd_word:
    lda #$00
    sta CHECKSUM_WORD_LO

_checksum_add_word:
    jsr CHECKSUM_ADD_WORD
    bra _checksum_loop

_checksum_done:
    lda CHECKSUM_SUM_HI
    eor #$ff
    sta CHECKSUM_RESULT_HI
    lda CHECKSUM_SUM_LO
    eor #$ff
    sta CHECKSUM_RESULT_LO
    rts

CHECKSUM_READ_BYTE:
    lda $ffff,y
    iny
    bne _checksum_read_done
    inc CHECKSUM_READ_BYTE+2
_checksum_read_done:
    rts

CHECKSUM_DEC_LEN:
    lda CHECKSUM_LEN_LO
    bne _checksum_dec_lo
    dec CHECKSUM_LEN_HI
_checksum_dec_lo:
    dec CHECKSUM_LEN_LO
    rts

CHECKSUM_ADD_WORD:
    clc
    lda CHECKSUM_SUM_LO
    adc CHECKSUM_WORD_LO
    sta CHECKSUM_SUM_LO
    lda CHECKSUM_SUM_HI
    adc CHECKSUM_WORD_HI
    sta CHECKSUM_SUM_HI
    bcc _checksum_add_done
    inc CHECKSUM_SUM_LO
    bne _checksum_add_done
    inc CHECKSUM_SUM_HI
    bne _checksum_add_done
    inc CHECKSUM_SUM_LO
_checksum_add_done:
    rts

CHECKSUM_PTR_LO:    .byte $00
CHECKSUM_PTR_HI:    .byte $00
CHECKSUM_LEN_LO:    .byte $00
CHECKSUM_LEN_HI:    .byte $00
CHECKSUM_RESULT_HI: .byte $00
CHECKSUM_RESULT_LO: .byte $00
CHECKSUM_SUM_HI:    .byte $00
CHECKSUM_SUM_LO:    .byte $00
CHECKSUM_WORD_HI:   .byte $00
CHECKSUM_WORD_LO:   .byte $00
