; #DMA_COPY $00,$042500, $ff, $0de800, 42
DMA_COPY    .macro   src_hi, src, dest_hi, dest, length
    sta $D707
    .byte $80                                   ; enhanced dma - src bits 20-27
    .byte (\src_hi)
    .byte $81                                   ; enhanced dma - dest bits 20-27
    .byte (\dest_hi)
    .byte $00                                   ; end of job options
    .byte $00                                   ; copy
    .byte <\length, >\length                    ; length lsb, msb
    .byte <\src, >\src, `\src                ; src lsb, msb, bank
    .byte <\dest, >\dest, `\dest             ; dest lsb, msb, bank ($ffde800)
    .byte $00                                   ; command high byte
    .word $0000                                 ; modulo (ignored)
.endm

FAR_PEEK   .macro hi, address

    lda #<\address
    sta $45
    lda #>\address
    sta $46
    lda #`\address
    sta $47
    lda #\hi
    sta $48

    ldz #$00
    lda [$45],z

.endm

FAR_POKE_Y   .macro hi, address

    pha
    phy
    lda #<\address
    sta $45
    lda #>\address
    sta $46
    lda #`\address
    sta $47
    lda #\hi
    sta $48
    plz
    pla
    sta [$45],z
    
.endm

FAR_PEEK_Y   .macro hi, address

    phy
    lda #<\address
    sta $45
    lda #>\address
    sta $46
    lda #`\address
    sta $47
    lda #\hi
    sta $48
    plz
    lda [$45],z

.endm