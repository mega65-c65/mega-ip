;=============================================================================
; ICMP echo reply
;=============================================================================
; Keep this compact block in the free gap before the TCP handler. It handles
; ordinary IPv4 echo requests only: no IP options and no fragments.
* = $682c
ICMP_ECHO_REPLY:
    ; IPv4, IHL=5 only.
    lda ETH_RX_FRAME_PAYLOAD+0
    cmp #$45
    bne _icmp_drop

    ; Drop fragments. Allow DF, reject MF and any non-zero fragment offset.
    lda ETH_RX_FRAME_PAYLOAD+6
    and #$3f
    ora ETH_RX_FRAME_PAYLOAD+7
    bne _icmp_drop

    ; Destination IP must be our local address.
    ldx #$00
_icmp_check_dst_ip:
    lda ETH_RX_FRAME_PAYLOAD+16,x
    cmp LOCAL_IP,x
    bne _icmp_drop
    inx
    cpx #$04
    bne _icmp_check_dst_ip

    ; Require a minimum IPv4 length of 20-byte IP + 8-byte ICMP header.
    lda ETH_RX_FRAME_PAYLOAD+2
    bne _icmp_len_ok
    lda ETH_RX_FRAME_PAYLOAD+3
    cmp #28
    bcc _icmp_drop
_icmp_len_ok:

    ; ICMP echo request, code 0.
    lda ETH_RX_FRAME_PAYLOAD+20
    cmp #ICMP_TYPE_ECHO_REQUEST
    bne _icmp_drop
    lda ETH_RX_FRAME_PAYLOAD+21
    bne _icmp_drop

    ; TX frame length = IPv4 total length + Ethernet header.
    lda ETH_RX_FRAME_PAYLOAD+3
    clc
    adc #14
    sta ETH_TX_LEN_LSB
    sta _icmp_dma_len
    lda ETH_RX_FRAME_PAYLOAD+2
    adc #$00
    sta ETH_TX_LEN_MSB
    sta _icmp_dma_len+1

    ; Copy the received frame to TX, then edit it into a reply.
    php
    sei
    lda #$00
    sta $D707
    .byte $80
    .byte $00
    .byte $81
    .byte $00
    .byte $00
    .byte $00
_icmp_dma_len:
    .byte $00, $00
    .byte <ETH_RX_FRAME_HEADER, >ETH_RX_FRAME_HEADER, EXEC_BANK
    .byte <ETH_TX_FRAME_HEADER, >ETH_TX_FRAME_HEADER, EXEC_BANK
    .byte $00
    .word $0000
    plp

    ldx #$00
_icmp_mac_loop:
    lda ETH_RX_FRAME_SRC_MAC,x
    sta ETH_TX_FRAME_DEST_MAC,x
    lda MEGA65_ETH_MAC,x
    sta ETH_TX_FRAME_SRC_MAC,x
    inx
    cpx #$06
    bne _icmp_mac_loop

    ; Ethernet type is IPv4.
    lda #$08
    sta ETH_TX_TYPE
    lda #$00
    sta ETH_TX_TYPE+1

    ; Swap IPv4 endpoints and make a fresh reply header/checksum.
    ldx #$00
_icmp_ip_loop:
    lda LOCAL_IP,x
    sta ETH_TX_FRAME_PAYLOAD+12,x
    lda ETH_RX_FRAME_PAYLOAD+12,x
    sta ETH_TX_FRAME_PAYLOAD+16,x
    inx
    cpx #$04
    bne _icmp_ip_loop

    lda #$40
    sta ETH_TX_FRAME_PAYLOAD+8
    lda #$00
    sta ETH_TX_FRAME_PAYLOAD+10
    sta ETH_TX_FRAME_PAYLOAD+11

    ; Echo reply keeps identifier, sequence, and payload.
    lda #ICMP_TYPE_ECHO_REPLY
    sta ETH_TX_FRAME_PAYLOAD+20
    lda #$00
    sta ETH_TX_FRAME_PAYLOAD+22
    sta ETH_TX_FRAME_PAYLOAD+23

    ldx #$00
_icmp_copy_ip_hdr:
    lda ETH_TX_FRAME_PAYLOAD,x
    sta IPV4_HEADER,x
    inx
    cpx #20
    bne _icmp_copy_ip_hdr
    jsr CALC_IPV4_CHECKSUM
    ldx #$00
_icmp_copy_ip_back:
    lda IPV4_HEADER,x
    sta ETH_TX_FRAME_PAYLOAD,x
    inx
    cpx #20
    bne _icmp_copy_ip_back

    jsr ICMP_CALC_CHECKSUM
    lda ICMP_SUM_HI
    sta ETH_TX_FRAME_PAYLOAD+22
    lda ICMP_SUM_LO
    sta ETH_TX_FRAME_PAYLOAD+23

    jmp ETH_PACKET_SEND

_icmp_drop:
    rts

ICMP_CALC_CHECKSUM:
    lda #$00
    sta ICMP_SUM_LO
    sta ICMP_SUM_HI
    sta ICMP_WORD_LO
    sta ICMP_WORD_HI

    lda ETH_RX_FRAME_PAYLOAD+3
    sec
    sbc #20
    sta ICMP_LEN_LO
    lda ETH_RX_FRAME_PAYLOAD+2
    sbc #$00
    sta ICMP_LEN_HI

    lda #<ETH_TX_FRAME_PAYLOAD+20
    sta _icmp_read_hi+1
    sta _icmp_read_lo+1
    lda #>ETH_TX_FRAME_PAYLOAD+20
    sta _icmp_read_hi+2
    sta _icmp_read_lo+2
    ldy #$00

_icmp_sum_loop:
    lda ICMP_LEN_LO
    ora ICMP_LEN_HI
    beq _icmp_sum_done

_icmp_read_hi:
    lda $ffff,y
    sta ICMP_WORD_HI
    iny
    bne _icmp_dec_after_hi
    inc _icmp_read_hi+2
    inc _icmp_read_lo+2
_icmp_dec_after_hi:
    dec ICMP_LEN_LO
    lda ICMP_LEN_LO
    cmp #$ff
    bne _icmp_have_lo_check
    dec ICMP_LEN_HI

_icmp_have_lo_check:
    lda ICMP_LEN_LO
    ora ICMP_LEN_HI
    beq _icmp_odd_word

_icmp_read_lo:
    lda $ffff,y
    sta ICMP_WORD_LO
    iny
    bne _icmp_dec_after_lo
    inc _icmp_read_hi+2
    inc _icmp_read_lo+2
_icmp_dec_after_lo:
    dec ICMP_LEN_LO
    lda ICMP_LEN_LO
    cmp #$ff
    bne _icmp_add_word
    dec ICMP_LEN_HI
    bra _icmp_add_word

_icmp_odd_word:
    lda #$00
    sta ICMP_WORD_LO

_icmp_add_word:
    clc
    lda ICMP_SUM_LO
    adc ICMP_WORD_LO
    sta ICMP_SUM_LO
    lda ICMP_SUM_HI
    adc ICMP_WORD_HI
    sta ICMP_SUM_HI
    bcc _icmp_sum_loop
    inc ICMP_SUM_LO
    bne _icmp_sum_loop
    inc ICMP_SUM_HI
    bra _icmp_sum_loop

_icmp_sum_done:
    lda ICMP_SUM_HI
    eor #$ff
    sta ICMP_SUM_HI
    lda ICMP_SUM_LO
    eor #$ff
    sta ICMP_SUM_LO
    rts
