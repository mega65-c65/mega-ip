;=============================================================================
; Sets up a full IPv4 packet
; Parameters:
;   A= protocol ($06=TCP, $11=UDP, etc)
;=============================================================================
BUILD_IPV4_HEADER:

    sta IPV4_HDR_PROTO

    lda LOCAL_IP+0
    sta IPV4_HDR_SRC_IP+0
    lda LOCAL_IP+1
    sta IPV4_HDR_SRC_IP+1
    lda LOCAL_IP+2
    sta IPV4_HDR_SRC_IP+2
    lda LOCAL_IP+3
    sta IPV4_HDR_SRC_IP+3

    lda REMOTE_IP+0
    sta IPV4_HDR_DST_IP+0
    lda REMOTE_IP+1
    sta IPV4_HDR_DST_IP+1
    lda REMOTE_IP+2
    sta IPV4_HDR_DST_IP+2
    lda REMOTE_IP+3
    sta IPV4_HDR_DST_IP+3

    lda #>(20+20)               ; IP header (20) + TCP header (20)
    sta IPV4_HDR_LEN
    lda #<(20+20)
    sta IPV4_HDR_LEN+1

    lda TCP_DATA_PAYLOAD_SIZE   ; add the tcp payload data size (big endian)
    clc
    adc IPV4_HDR_LEN+1
    sta IPV4_HDR_LEN+1
    lda IPV4_HDR_LEN
    adc #$00
    sta IPV4_HDR_LEN

    ; dont fragment
    ; set DF=1 (0x4000) and offset=0, in network order
    lda #$40
    sta IPV4_HDR_FLGS_OFFS
    lda #$00
    sta IPV4_HDR_FLGS_OFFS+1

    jsr CALC_IPV4_CHECKSUM

    ; copy to TX buffer
    ldx #$00
_lp_copy:
    lda IPV4_HEADER, x
    sta ETH_TX_FRAME_PAYLOAD, x
    cpx #19
    beq _lp_done
    inx
    jmp _lp_copy

_lp_done:
    rts

IPV4_HEADER:
IPV4_HDR_IHL:       .byte $45                   ; 0100 (Version 4) | 0101 (min 5, max 15)
IPV4_HDR_DSCP:      .byte $00                   ; Type of service (Low delay, High throuput, Relibility)
IPV4_HDR_LEN:       .byte $00, $00              ; Length of header + data (16 bits) 0-65535
IPV4_HDR_IDEN:      .byte $00, $00              ; unique packet id
IPV4_HDR_FLGS_OFFS: .byte $00, $00              ; 3 flags, 1 bit each =  reserved (zero), do not fragment, more fragments
IPV4_HDR_TTL:       .byte $40                   ; time to live hops to dest
IPV4_HDR_PROTO:     .byte $11                   ; name of protocol for which data to be passed (ICMP=$01, TCP=$06, UDP=$11)
IPV4_HDR_CHKSM:     .byte $00, $00              ; 16 bit header checksum
IPV4_HDR_SRC_IP:    .byte $00, $00, $00, $00    ; source IP address
IPV4_HDR_DST_IP:    .byte $00, $00, $00, $00    ; dest IP address

;=============================================================================
; Routine to calculate the ipv4 checksum
;=============================================================================
CALC_IPV4_CHECKSUM:
    lda #$00
    sta IPV4_HDR_CHKSM
    sta IPV4_HDR_CHKSM+1

    lda #<IPV4_HEADER
    sta CHECKSUM_PTR_LO
    lda #>IPV4_HEADER
    sta CHECKSUM_PTR_HI
    lda #20
    sta CHECKSUM_LEN_LO
    lda #$00
    sta CHECKSUM_LEN_HI
    jsr CHECKSUM_ONES_COMP

    lda CHECKSUM_RESULT_HI
    sta IPV4_HDR_CHKSM
    lda CHECKSUM_RESULT_LO
    sta IPV4_HDR_CHKSM+1
    rts

;=============================================================================
; Validate copied inbound IPv4 packet at ETH_RX_FRAME_PAYLOAD.
; Out: C=0 valid, C=1 invalid/drop.
;=============================================================================
IPV4_VALIDATE_RX:
    ; Ethernet payload must hold the minimum IPv4 header.
    lda ETH_RX_PAYLOAD_LEN_H
    bne _ipv4_rx_payload_ge20
    lda ETH_RX_PAYLOAD_LEN_L
    cmp #20
    bcc _ipv4_rx_bad

_ipv4_rx_payload_ge20:
    ; IPv4 version.
    lda ETH_RX_FRAME_PAYLOAD+0
    and #$f0
    cmp #$40
    bne _ipv4_rx_bad

    ; IHL is 32-bit words. Minimum IPv4 header is 5 words = 20 bytes.
    lda ETH_RX_FRAME_PAYLOAD+0
    and #$0f
    cmp #5
    bcc _ipv4_rx_bad
    asl
    asl
    sta IPV4_RX_IHL_BYTES

    ; IP total length must be at least IHL.
    lda ETH_RX_FRAME_PAYLOAD+2
    sta IPV4_RX_TOTAL_HI
    lda ETH_RX_FRAME_PAYLOAD+3
    sta IPV4_RX_TOTAL_LO
    lda IPV4_RX_TOTAL_HI
    bne _ipv4_rx_total_ge_ihl
    lda IPV4_RX_TOTAL_LO
    cmp IPV4_RX_IHL_BYTES
    bcc _ipv4_rx_bad

_ipv4_rx_total_ge_ihl:
    ; IP total length must fit in the copied Ethernet payload.
    lda ETH_RX_PAYLOAD_LEN_H
    cmp IPV4_RX_TOTAL_HI
    bcc _ipv4_rx_bad
    bne _ipv4_rx_total_in_frame
    lda ETH_RX_PAYLOAD_LEN_L
    cmp IPV4_RX_TOTAL_LO
    bcc _ipv4_rx_bad

_ipv4_rx_total_in_frame:
    ; No fragment reassembly yet: allow only unfragmented packets. DF is OK.
    lda ETH_RX_FRAME_PAYLOAD+6
    and #$bf
    ora ETH_RX_FRAME_PAYLOAD+7
    bne _ipv4_rx_bad

    jsr IPV4_RX_CHECKSUM_OK
    bcs _ipv4_rx_bad

    clc
    rts

_ipv4_rx_bad:
    sec
    rts

;=============================================================================
; Validate inbound IPv4 header checksum over the received IHL.
; Out: C=0 checksum OK, C=1 invalid.
;=============================================================================
IPV4_RX_CHECKSUM_OK:
    lda #$00
    sta IPV4_RX_SUM_LO
    sta IPV4_RX_SUM_HI
    sta IPV4_RX_WORD_HI
    sta IPV4_RX_WORD_LO

    lda IPV4_RX_IHL_BYTES
    lsr
    sta IPV4_RX_WORDS_LEFT
    ldy #$00

_ipv4_rx_sum_loop:
    lda IPV4_RX_WORDS_LEFT
    beq _ipv4_rx_sum_done

    lda ETH_RX_FRAME_PAYLOAD,y
    sta IPV4_RX_WORD_HI
    iny
    lda ETH_RX_FRAME_PAYLOAD,y
    sta IPV4_RX_WORD_LO
    iny

    clc
    lda IPV4_RX_SUM_LO
    adc IPV4_RX_WORD_LO
    sta IPV4_RX_SUM_LO
    lda IPV4_RX_SUM_HI
    adc IPV4_RX_WORD_HI
    sta IPV4_RX_SUM_HI
    bcc _ipv4_rx_no_carry
    inc IPV4_RX_SUM_LO
    bne _ipv4_rx_no_carry
    inc IPV4_RX_SUM_HI
    bne _ipv4_rx_no_carry
    inc IPV4_RX_SUM_LO

_ipv4_rx_no_carry:
    dec IPV4_RX_WORDS_LEFT
    jmp _ipv4_rx_sum_loop

_ipv4_rx_sum_done:
    lda IPV4_RX_SUM_HI
    cmp #$ff
    bne _ipv4_rx_sum_bad
    lda IPV4_RX_SUM_LO
    cmp #$ff
    bne _ipv4_rx_sum_bad
    clc
    rts

_ipv4_rx_sum_bad:
    sec
    rts

IPV4_RX_IHL_BYTES:  .byte $00
IPV4_RX_TOTAL_HI:   .byte $00
IPV4_RX_TOTAL_LO:   .byte $00
IPV4_RX_WORDS_LEFT: .byte $00
IPV4_RX_WORD_HI:    .byte $00
IPV4_RX_WORD_LO:    .byte $00
IPV4_RX_SUM_HI:     .byte $00
IPV4_RX_SUM_LO:     .byte $00
