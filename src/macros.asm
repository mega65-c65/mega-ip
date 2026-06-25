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

