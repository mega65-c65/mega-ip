;=============================================================================
; Receive ring buffer
;=============================================================================

;=============================================================================
; A = byte to write
; Carry set if buffer full, clear if success
;=============================================================================
; In:  A = byte to store
; Out: C=0 success, C=1 full (A preserved on success)
RBUF_PUT:
    php
    sei

    pha                         ; save data byte on stack
    jsr RBUF_SAVE_PTR_ZP

    ; snapshot current head into HLO/HHI
    lda RBUF_HEAD_LO
    sta HLO
    lda RBUF_HEAD_HI
    sta HHI

    ; next = head + 1 within the configured ring size
    clc
    lda HLO
    adc #1
    sta NEXT_LO
    lda HHI
    adc #0
    and #RING_BUFFER_PAGE_MASK
    sta NEXT_HI

    ; full? (next == tail)
    jsr READ_TAIL_ATOMIC
    lda NEXT_LO
    cmp TMP_TAIL_LO
    bne _not_full
    lda NEXT_HI
    cmp TMP_TAIL_HI
    bne _not_full
_full:
    jsr RBUF_RESTORE_PTR_ZP
    pla                         ; drop saved byte
    plp
    sec                         ; full
    rts

_not_full:
    ; RX ring payload lives in physical bank 5.  Build a 28-bit
    ; pointer to RING_BUFFER_BASE + (HHI << 8), then index by HLO.
    lda #<RING_BUFFER_BASE
    sta RBUF_PTR_LO
    lda #>RING_BUFFER_BASE
    clc
    adc HHI
    sta RBUF_PTR_HI
    lda #RING_BUFFER_BANK
    sta RBUF_PTR_BANK
    lda #RING_BUFFER_BANK_HI
    sta RBUF_PTR_TOP

    ldz HLO
    pla                          ; A = data byte
    sta [RBUF_PTR_LO],z

_pub:
    ; publish head = next
    lda NEXT_LO
    sta RBUF_HEAD_LO
    lda NEXT_HI
    sta RBUF_HEAD_HI

    jsr RBUF_RESTORE_PTR_ZP
    plp
    clc                         ; success
    rts



;=============================================================================
; Returns byte in A
; Carry set if buffer empty, clear if success
;=============================================================================
RBUF_GET:
    php
    sei
    tza
    pha
    jsr RBUF_SAVE_PTR_ZP

    ; empty? (head == tail)
    jsr READ_HEAD_ATOMIC
    lda RBUF_TAIL_LO
    cmp TMP_HEAD_LO
    bne _not_empty
    lda RBUF_TAIL_HI
    cmp TMP_HEAD_HI
    beq _empty

_not_empty:
    ; Read from physical bank-5 RING_BUFFER_BASE + (TAIL_HI << 8) + TAIL_LO.
    lda #<RING_BUFFER_BASE
    sta RBUF_PTR_LO
    lda #>RING_BUFFER_BASE
    clc
    adc RBUF_TAIL_HI             ; select ring page
    sta RBUF_PTR_HI
    lda #RING_BUFFER_BANK
    sta RBUF_PTR_BANK
    lda #RING_BUFFER_BANK_HI
    sta RBUF_PTR_TOP

    ldz RBUF_TAIL_LO
    lda [RBUF_PTR_LO],z
    pha

    ; tail = tail + 1 within the configured ring size
    inc RBUF_TAIL_LO
    bne _ok
    inc RBUF_TAIL_HI
    lda RBUF_TAIL_HI
    and #RING_BUFFER_PAGE_MASK
    sta RBUF_TAIL_HI
_ok:
    lda CHARACTER_MODE
    beq _ok_done
    pla
    jsr CHAR_TRANSLATE
    jmp _return_ok

_ok_done:
    pla

_return_ok:
    sta RBUF_GET_SAVE_A
    jsr RBUF_RESTORE_PTR_ZP
    pla
    taz
    lda RBUF_GET_SAVE_A
    plp
    clc
    rts

_empty:
    lda #$00
    sta RBUF_GET_SAVE_A
    jsr RBUF_RESTORE_PTR_ZP
    pla
    taz
    lda RBUF_GET_SAVE_A
    plp
    sec
    rts

RBUF_GET_SAVE_A:
    .byte $00

RBUF_SAVE_PTR_ZP:
    lda RBUF_PTR_LO
    sta RBUF_SAVE_PTR_LO
    lda RBUF_PTR_HI
    sta RBUF_SAVE_PTR_HI
    lda RBUF_PTR_BANK
    sta RBUF_SAVE_PTR_BANK
    lda RBUF_PTR_TOP
    sta RBUF_SAVE_PTR_TOP
    rts

RBUF_RESTORE_PTR_ZP:
    lda RBUF_SAVE_PTR_LO
    sta RBUF_PTR_LO
    lda RBUF_SAVE_PTR_HI
    sta RBUF_PTR_HI
    lda RBUF_SAVE_PTR_BANK
    sta RBUF_PTR_BANK
    lda RBUF_SAVE_PTR_TOP
    sta RBUF_PTR_TOP
    rts

RBUF_SAVE_PTR_LO:   .byte $00
RBUF_SAVE_PTR_HI:   .byte $00
RBUF_SAVE_PTR_BANK: .byte $00
RBUF_SAVE_PTR_TOP:  .byte $00


;=============================================================================
; Carry set if full
;=============================================================================
RBUF_IS_FULL:
    ; compute next = head+1
    lda RBUF_HEAD_LO
    sta HLO
    lda RBUF_HEAD_HI
    sta HHI
    clc
    lda HLO
    adc #1
    sta NEXT_LO
    lda HHI
    adc #0
    and #RING_BUFFER_PAGE_MASK
    sta NEXT_HI
    jsr READ_TAIL_ATOMIC
    lda NEXT_LO
    cmp TMP_TAIL_LO
    bne _no
    lda NEXT_HI
    cmp TMP_TAIL_HI
    beq _yes
_no:
    clc
    rts
_yes:
    sec
    rts
