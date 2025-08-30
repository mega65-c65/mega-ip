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

DMA_FILL    .macro   dest, count, value
    sta $D707
    .byte $00
    .byte $03                                   ; fill
    .byte <\count, >\count                      ; length lsb, msb
    .byte <\value, >\value
    .byte $00                                   ; src bank (ignored)
    .byte <\dest, >\dest, `\dest             ; dest lsb, msb, bank ($ffde800)
    .byte $00                                   ; command high byte
    .word $0000                                 ; modulo (ignored)
.endm

LDA_FAR .macro hi, address

    sta $D707
    .byte $80               ; src
    .byte \hi               ; src hi
    .byte $81               ; enhanced dma - dest bits 20-27
    .byte $00               ; dest hi
    .byte $00               ; end of job options
    .byte $00               ; copy
    .byte $01               ; length LSB = 1
    .byte $00               ; length MSB = 0
    .byte <\address, >\address, `\address    ; src = $FFDE800
    .byte <tmp, >tmp, EXEC_BANK
    .byte $00
    .word $0000

    lda tmp
    jmp over
tmp:
    .byte $00
over:

.endm


FAR_PEEK   .macro hi, address

    lda $45
    pha
    lda $46
    pha
    lda $47
    pha
    lda $48
    pha

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

    taz

    pla
    sta $48
    pla
    sta $47
    pla
    sta $46
    pla
    sta $45

    tza

.endm

STAY_FAR .macro hi, address

    sta tmp

    tya
    clc
    adc #<\address
    sta lobyte
    lda #>\address
    adc #$00
    sta hibyte

    sta $D707
    .byte $80               ; src
    .byte \hi               ; src hi
    .byte $81               ; enhanced dma - dest bits 20-27
    .byte $00               ; dest hi
    .byte $00               ; end of job options
    .byte $00               ; copy
    .byte $01               ; length LSB = 1
    .byte $00               ; length MSB = 0
    .byte <tmp, >tmp, EXEC_BANK
lobyte:
    .byte <\address
hibyte: 
    .byte >\address 
bank:
    .byte `\address         ; src = $FFDE800
    .byte $00
    .word $0000

    lda tmp
    jmp over
tmp:
    .byte $00
over:

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

LDAY_FAR .macro hi, address

    tya
    clc
    adc #<\address
    sta lobyte
    lda #>\address
    adc #$00
    sta hibyte

    sta $D707
    .byte $80               ; src
    .byte \hi               ; src hi
    .byte $81               ; enhanced dma - dest bits 20-27
    .byte $00               ; dest hi
    .byte $00               ; end of job options
    .byte $00               ; copy
    .byte $01              ; length LSB = 1
    .byte $00              ; length MSB = 0
lobyte:
    .byte <\address
hibyte: 
    .byte >\address 
bank:
    .byte `\address         ; src = $FFDE800
    .byte <tmp, >tmp, EXEC_BANK
    .byte $00
    .word $0000

    lda tmp
    jmp over
tmp:
    .byte $00
over:

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

