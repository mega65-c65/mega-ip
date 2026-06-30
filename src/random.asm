;=============================================================================
; Randomness helpers
;=============================================================================

TCP_ISN_RNG_WAIT = $20

; Seed LOCAL_ISN for a new TCP connection.
; The hardware RNG is the primary source.  The fallback mix keeps the stack
; moving if the RNG ever stays not-ready for the bounded wait.
TCP_SEED_LOCAL_ISN:
    jsr MEGA65_IO_ENABLE
    jsr TCP_ISN_FALLBACK_MIX

    ldx #$00
_rng_loop:
    jsr TCP_HWRNG_READ_BYTE
    bcs _rng_skip
    eor LOCAL_ISN,x
    sta LOCAL_ISN,x

_rng_skip:
    inx
    cpx #$04
    bne _rng_loop

    lda LOCAL_ISN+0
    ora LOCAL_ISN+1
    ora LOCAL_ISN+2
    ora LOCAL_ISN+3
    bne _done
    inc LOCAL_ISN+3

_done:
    rts

TCP_HWRNG_READ_BYTE:
    ldy #TCP_ISN_RNG_WAIT

_wait_ready:
    lda MEGA65_HWRNG_STATUS
    and #MEGA65_HWRNG_NOT_READY
    beq _ready
    dey
    bne _wait_ready
    lda #$00
    sec
    rts

_ready:
    lda MEGA65_HWRNG_RANDOM
    clc
    rts

TCP_ISN_FALLBACK_MIX:
    lda LOCAL_ISN+3
    clc
    adc #$01
    sta LOCAL_ISN+3
    lda LOCAL_ISN+2
    adc #$00
    sta LOCAL_ISN+2
    lda LOCAL_ISN+1
    adc #$00
    sta LOCAL_ISN+1
    lda LOCAL_ISN+0
    adc #$00
    sta LOCAL_ISN+0

    lda LOCAL_ISN+0
    eor LOCAL_IP+0
    eor REMOTE_IP+0
    eor MEGA65_ETH_MAC+0
    eor MEGA65_FRAMECOUNT
    sta LOCAL_ISN+0

    lda LOCAL_ISN+1
    eor LOCAL_IP+1
    eor REMOTE_IP+1
    eor MEGA65_ETH_MAC+1
    eor MEGA65_VICII_RSTR_CMP
    sta LOCAL_ISN+1

    lda LOCAL_ISN+2
    eor LOCAL_IP+2
    eor REMOTE_IP+2
    eor LOCAL_PORT+0
    eor REMOTE_PORT+0
    eor MEGA65_ETH_MAC+2
    sta LOCAL_ISN+2

    lda LOCAL_ISN+3
    eor LOCAL_IP+3
    eor REMOTE_IP+3
    eor LOCAL_PORT+1
    eor REMOTE_PORT+1
    eor MEGA65_ETH_MAC+3
    sta LOCAL_ISN+3
    rts
