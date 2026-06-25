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

    ; snapshot current head into HLO/HHI
    lda RBUF_HEAD_LO
    sta HLO
    lda RBUF_HEAD_HI
    sta HHI

    ; next = head + 1 (11-bit)
    clc
    lda HLO
    adc #1
    sta NEXT_LO
    lda HHI
    adc #0
    and #$07
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
    pla                         ; drop saved byte
    plp
    sec                         ; full
    rts

_not_full:
    ; 2k buffer in bank 5
    ; write data at page(HHI) : offset(HLO)
    ldy HLO
    lda #<RING_BUFFER
    sta _rbuf_sta+1
    lda #>RING_BUFFER
    clc
    adc HHI                      ; select page 0..7
    sta _rbuf_sta+2

    pla                          ; A = data byte
_rbuf_sta:
    .byte $99, $00, $00          ; STA abs,Y (patched above)

_pub:
    ; publish head = next
    lda NEXT_LO
    sta RBUF_HEAD_LO
    lda NEXT_HI
    sta RBUF_HEAD_HI

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

    ; empty? (head == tail)
    jsr READ_HEAD_ATOMIC
    lda RBUF_TAIL_LO
    cmp TMP_HEAD_LO
    bne _not_empty
    lda RBUF_TAIL_HI
    cmp TMP_HEAD_HI
    beq _empty

_not_empty:
    ; ---- read A from RING_BUFFER + (TAIL_HI<<8) + TAIL_LO ----
    ldy RBUF_TAIL_LO
    lda #<RING_BUFFER
    sta _rbuf_lda+1
    lda #>RING_BUFFER
    clc
    adc RBUF_TAIL_HI
    sta _rbuf_lda+2

_rbuf_lda:
    .byte $B9, $00, $00          ; LDA abs,Y (patched above)
    pha

    ; tail = tail + 1 (11-bit)
    inc RBUF_TAIL_LO
    bne _ok
    inc RBUF_TAIL_HI
    lda RBUF_TAIL_HI
    and #$07
    sta RBUF_TAIL_HI
_ok:
    lda CHARACTER_MODE
    beq _ok_done
    pla
    jsr CHAR_TRANSLATE
    plp
    clc
    rts

_ok_done:
    pla
    plp
    clc
    rts

_empty:
    lda #$00
    plp
    sec
    rts


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
    and #$07
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
