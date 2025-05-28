; *=$1600

XORSHIFT32STATE:
    .byte $01, $00, $00, $00

RAND32_RANGE:
    .byte $00, $00, $00, $00

RAND32_VALUE:
    .byte $00, $00, $00, $00


RAND32_SEED:

    lda $D41B
    sta XORSHIFT32STATE+0
    lda $D41B
    sta XORSHIFT32STATE+1
    lda $D41B
    sta XORSHIFT32STATE+2
    lda $D41B
    sta XORSHIFT32STATE+3

    jsr RAND32
    rts

RAND32:

    jsr XORSHIFT32

    clc
    lda RAND32_RANGE+0
    adc RAND32_RANGE+1
    adc RAND32_RANGE+2
    adc RAND32_RANGE+3
    bne _ahead

    jsr XORSHIFT32

    lda XORSHIFT32STATE+0
    sta RAND32_VALUE+0
    lda XORSHIFT32STATE+1
    sta RAND32_VALUE+1
    lda XORSHIFT32STATE+2
    sta RAND32_VALUE+2
    lda XORSHIFT32STATE+3
    sta RAND32_VALUE+3

    rts

_ahead:
    ; 32 bit multiply
    lda XORSHIFT32STATE+0
    sta $D770               ; MULTINA
    lda XORSHIFT32STATE+1
    sta $D771               ; MULTINA
    lda XORSHIFT32STATE+2
    sta $D772               ; MULTINA
    lda XORSHIFT32STATE+3
    sta $D773               ; MULTINA

    ; x range
    lda RAND32_RANGE+0
    sta $D774               ; MULTINB
    lda RAND32_RANGE+1
    sta $D775               ; MULTINB
    lda RAND32_RANGE+2
    sta $D776               ; MULTINB
    lda RAND32_RANGE+3
    sta $D777               ; MULTINB

    lda $d77c 
    sta RAND32_VALUE+0
    lda $d77d
    sta RAND32_VALUE+1
    lda $d77e
    sta RAND32_VALUE+2
    lda $d77f
    sta RAND32_VALUE+3

    rts


XORSHIFT32:

; -- Copy _x to temp1 --
        ldx #$03
_copy_x:
        lda XORSHIFT32STATE,x
        sta _temp1,x
        dex
        bpl _copy_x

; -- x ^= x << 13 (shift left by 13 bits = 1 byte + 5 bits) --
; Shift temp1 left 8 bits into temp3
        lda _temp1+1
        sta _temp3+0
        lda _temp1+2
        sta _temp3+1
        lda _temp1+3
        sta _temp3+2
        lda #$00
        sta _temp3+3

; Now shift temp3 left 5 bits
        ldx #$00
        lda _temp3+0
        asl a
        rol _temp3+1
        rol _temp3+2
        rol _temp3+3
        asl a
        rol _temp3+1
        rol _temp3+2
        rol _temp3+3
        asl a
        rol _temp3+1
        rol _temp3+2
        rol _temp3+3
        asl a
        rol _temp3+1
        rol _temp3+2
        rol _temp3+3
        asl a
        rol _temp3+1
        rol _temp3+2
        rol _temp3+3
        sta _temp3

; XOR temp1 ^= temp3
        ldx #$03
_xor13:
        lda _temp1,x
        eor _temp3,x
        sta _temp1,x
        dex
        bpl _xor13

; -- x ^= x >> 17 (2 bytes + 1 bit) --
        lda _temp1+2
        sta _temp2+0
        lda _temp1+3
        sta _temp2+1
        lda #$00
        sta _temp2+2
        sta _temp2+3

; Shift temp2 right 1 bit (LSR + ROR chain)
        lsr _temp2+3
        ror _temp2+2
        ror _temp2+1
        ror _temp2

; XOR temp1 ^= temp2
        ldx #$03
_xor17:
        lda _temp1,x
        eor _temp2,x
        sta _temp1,x
        dex
        bpl _xor17

; -- x ^= x << 5 --
; Copy temp1 back to temp3
        ldx #$03
_copy2:
        lda _temp1,x
        sta _temp3,x
        dex
        bpl _copy2

; Shift temp3 left 5 bits
        ldx #$00
        lda _temp3+0
        asl a
        rol _temp3+1
        rol _temp3+2
        rol _temp3+3
        asl a
        rol _temp3+1
        rol _temp3+2
        rol _temp3+3
        asl a
        rol _temp3+1
        rol _temp3+2
        rol _temp3+3
        asl a
        rol _temp3+1
        rol _temp3+2
        rol _temp3+3
        asl a
        rol _temp3+1
        rol _temp3+2
        rol _temp3+3
        sta _temp3+0

; Final XOR: temp1 ^= temp3 → store to _x
        ldx #$03
_final_xor:
        lda _temp1,x
        eor _temp3,x
        sta XORSHIFT32STATE,x
        dex
        bpl _final_xor

        rts

_temp1:
    .byte $00, $00, $00, $00
_temp2:
    .byte $00, $00, $00, $00
_temp3:
    .byte $00, $00, $00, $00





