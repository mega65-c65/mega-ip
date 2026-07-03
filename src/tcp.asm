;=============================================================================
; Routine to handle incoming TCP packet
;=============================================================================
; Internal handler: let it flow with the runtime image.
INCOMING_TCP_PACKET:

    ; Only handle IPv4 TCP; drop others (e.g., mDNS/UDP)
    lda ETH_RX_FRAME_PAYLOAD+0
    and #$F0
    cmp #$40
    bne _drop

    ; TCP protocol?
    lda ETH_RX_FRAME_PAYLOAD+9
    cmp #$06
    bne _drop

    ; ---- ip_len_bytes = IHL * 4 (keep in X, do NOT store in TCP_DATA_OFFSET) ----
    lda ETH_RX_FRAME_PAYLOAD+0
    and #$0F
    asl
    asl
    cmp #20
    bcc _drop
    cmp #61
    bcs _drop
    tax                               ; X = ip header length in bytes

    ; ------ IP address checks ------
    ; dst IP must be LOCAL_IP
    ldy #0
_chk_dip:
    lda ETH_RX_FRAME_PAYLOAD+16,y    ; IPv4 dst at +16..+19 (fixed in IPv4)
    cmp LOCAL_IP,y
    bne _drop
    iny
    cpy #4
    bne _chk_dip

    ; ---- TCP flags at ip_len + 13 ----
    lda ETH_RX_FRAME_PAYLOAD+13,x
    sta ETH_RX_TCP_FLAGS

    ; If LISTENING, begin the handshake
    ; X already holds IHL offset here in your code.

_passive_try:
    ; Only if we are CLOSED and explicitly listening
    lda TCP_STATE
    cmp #TCP_STATE_CLOSED
    bne _passive_done
    lda TCP_LISTEN_ENABLED
    beq _passive_done               ; not listening

    ; match TCP dst port to listen port
    lda ETH_RX_FRAME_PAYLOAD+2,x    ; dst port hi
    cmp TCP_LISTEN_PORT
    bne _passive_done
    lda ETH_RX_FRAME_PAYLOAD+3,x    ; dst port lo
    cmp TCP_LISTEN_PORT+1
    bne _passive_done

    ; Must be a bare SYN.  A passive open must not accept SYN+ACK.
    lda ETH_RX_TCP_FLAGS
    and #(TCP_FLAG_SYN | TCP_FLAG_ACK | TCP_FLAG_RST | TCP_FLAG_FIN)
    cmp #TCP_FLAG_SYN
    bne _passive_done               ; not a pure SYN - let normal path drop it

    ; Source MAC must be an individual address, not multicast/broadcast.
    lda ETH_RX_FRAME_SRC_MAC
    and #$01
    bne _drop

    ; ----- Capture peer tuple -----
    ; Peer IP = IPv4 src at +12..+15 from IP header base (not +x)
    ldy #12
    lda ETH_RX_FRAME_PAYLOAD+0,y
    sta REMOTE_IP+0
    lda ETH_RX_FRAME_PAYLOAD+1,y
    sta REMOTE_IP+1
    lda ETH_RX_FRAME_PAYLOAD+2,y
    sta REMOTE_IP+2
    lda ETH_RX_FRAME_PAYLOAD+3,y
    sta REMOTE_IP+3

    ; Peer TCP src port
    lda ETH_RX_FRAME_PAYLOAD+0,x
    sta REMOTE_PORT
    lda ETH_RX_FRAME_PAYLOAD+1,x
    sta REMOTE_PORT+1

    ; Local port for the connection becomes the listen port
    lda TCP_LISTEN_PORT
    sta LOCAL_PORT
    lda TCP_LISTEN_PORT+1
    sta LOCAL_PORT+1

    ; ----- IRS := SEG.SEQ ; RCV.NXT := IRS+1 -----
    ; (SEG.SEQ was already latched into SEG_SEQ0..3 earlier in your code.)
    ;lda #$01
    ;sta REMOTE_ISN_BUMP             ; bump by 1 for SYN
    ;jsr CALC_REMOTE_ISN             ; REMOTE_ISN := SEG_SEQ + payload_len + bump
                                    ; (for bare SYN, payload_len=0 -> IRS+1)

    ; ----- REMOTE_ISN := SEG.SEQ + 1 (consume their SYN) -----
    lda ETH_RX_FRAME_PAYLOAD+4,x
    sta REMOTE_ISN+0
    lda ETH_RX_FRAME_PAYLOAD+5,x
    sta REMOTE_ISN+1
    lda ETH_RX_FRAME_PAYLOAD+6,x
    sta REMOTE_ISN+2
    lda ETH_RX_FRAME_PAYLOAD+7,x
    sta REMOTE_ISN+3
    inc REMOTE_ISN+3
    bne +
    inc REMOTE_ISN+2
    bne +
    inc REMOTE_ISN+1
    bne +
    inc REMOTE_ISN+0
+
    lda #$00
    sta TCP_DATA_PAYLOAD_SIZE
    sta TCP_DATA_PAYLOAD_SIZE+1

    jsr TCP_SAVE_RX_PEER_MAC
    jsr TCP_SEED_LOCAL_ISN
    ldx #$00
_save_synack_iss:
    lda LOCAL_ISN,x
    sta TCP_SYNACK_ISS,x
    inx
    cpx #$04
    bne _save_synack_iss

    jsr TCP_PASSIVE_SEND_SYNACK
    bcs _drop

    ; ----- The SYN we sent consumes 1 sequence number. -----
    inc LOCAL_ISN+3
    bne +
    inc LOCAL_ISN+2
    bne +
    inc LOCAL_ISN+1
    bne +
    inc LOCAL_ISN+0
+
    lda #CONNECT_SYN_MAX_RETRIES
    sta CONNECT_RETRY_LEFT
    lda #CONNECT_SYN_RETRY_TICKS
    sta CONNECT_RETRY_TICKS
    jsr CONNECT_STAMP_TIMER

    ; Enter SYN-RCVD so final ACK will complete the handshake
    lda #TCP_STATE_SYN_RECEIVED
    sta TCP_STATE
    rts                              ; fully handled this segment

_passive_done:
    ; ===== end passive-open demux =====

    ; No active socket accepted this TCP segment.  If we are otherwise closed,
    ; answer with RST instead of silently dropping it.
    lda TCP_STATE
    cmp #TCP_STATE_CLOSED
    bne _active_tuple_check
    jsr TCP_SEND_RESET_FOR_RX
    rts

_active_tuple_check:
    ; src IP must be REMOTE_IP (once we are trying to talk to a peer)
    ; (do this unconditionally; if you prefer, you can skip while CLOSED)
    ldy #0
_chk_sip:
    lda ETH_RX_FRAME_PAYLOAD+12,y    ; IPv4 src at +12..+15
    cmp REMOTE_IP,y
    bne _reset_drop
    iny
    cpy #4
    bne _chk_sip

    ; verify this is our socket (dst port at ip_len+2) ----
    lda ETH_RX_FRAME_PAYLOAD+2,x      ; dst port hi
    cmp LOCAL_PORT+0
    bne _reset_drop
    lda ETH_RX_FRAME_PAYLOAD+3,x      ; dst port lo
    cmp LOCAL_PORT+1
    bne _reset_drop

    ; verify peer source port too
    lda ETH_RX_FRAME_PAYLOAD+0,x      ; src port hi
    cmp REMOTE_PORT+0
    bne _reset_drop
    lda ETH_RX_FRAME_PAYLOAD+1,x      ; src port lo
    cmp REMOTE_PORT+1
    bne _reset_drop

    ; ---- TCP flags at ip_len + 13 ----
    lda ETH_RX_FRAME_PAYLOAD+13,x
    sta ETH_RX_TCP_FLAGS

    ; SEG.SEQ -> SEG_SEQ[0..3] (big endian)
    lda ETH_RX_FRAME_PAYLOAD+4,x
    sta SEG_SEQ+0
    lda ETH_RX_FRAME_PAYLOAD+5,x
    sta SEG_SEQ+1
    lda ETH_RX_FRAME_PAYLOAD+6,x
    sta SEG_SEQ+2
    lda ETH_RX_FRAME_PAYLOAD+7,x
    sta SEG_SEQ+3

    ; SEG.ACK -> SEG_ACK[0..3] (big endian)
    lda ETH_RX_FRAME_PAYLOAD+8,x
    sta SEG_ACK+0
    lda ETH_RX_FRAME_PAYLOAD+9,x
    sta SEG_ACK+1
    lda ETH_RX_FRAME_PAYLOAD+10,x
    sta SEG_ACK+2
    lda ETH_RX_FRAME_PAYLOAD+11,x
    sta SEG_ACK+3

    ; ---- compute payload size and TCP_DATA_OFFSET (payload start) ----
    jsr CALC_RX_TCP_BYTE_COUNT

    ; hand off to the state machine (still in IRQ context)
    jmp TCP_STATE_HANDLER

_drop:
    rts

_reset_drop:
    jsr TCP_SEND_RESET_FOR_RX
    rts

TCP_SYNACK_TICK:
    lda TCP_STATE
    cmp #TCP_STATE_SYN_RECEIVED
    beq _synack_tick_active
    rts

_synack_tick_active:
    jsr CONNECT_FRAME_WRAP_TICK
    bcc _synack_tick_done

    lda CONNECT_RETRY_TICKS
    beq _synack_retry_expired
    dec CONNECT_RETRY_TICKS

_synack_tick_done:
    rts

_synack_retry_expired:
    lda CONNECT_RETRY_LEFT
    beq _synack_timeout

    jsr TCP_PASSIVE_RETRANSMIT_SYNACK
    bcs _synack_retry_busy

    dec CONNECT_RETRY_LEFT
    lda #CONNECT_SYN_RETRY_TICKS
    sta CONNECT_RETRY_TICKS
    jsr CONNECT_STAMP_TIMER
    rts

_synack_retry_busy:
    lda #TCP_TX_BUSY_RETRY_TICKS
    sta CONNECT_RETRY_TICKS
    jsr CONNECT_STAMP_TIMER
    rts

_synack_timeout:
    lda #TCP_STATE_CLOSED
    sta TCP_STATE
    lda #$00
    sta CONNECT_RETRY_TICKS
    sta CONNECT_RETRY_LEFT
    rts

TCP_PASSIVE_RETRANSMIT_SYNACK:
    ldx #$00
_synack_save_live_isn:
    lda LOCAL_ISN,x
    sta TX_SAVE_LOCAL_ISN,x
    lda TCP_SYNACK_ISS,x
    sta LOCAL_ISN,x
    inx
    cpx #$04
    bne _synack_save_live_isn

    jsr TCP_PASSIVE_SEND_SYNACK
    php

    ldx #$00
_synack_restore_live_isn:
    lda TX_SAVE_LOCAL_ISN,x
    sta LOCAL_ISN,x
    inx
    cpx #$04
    bne _synack_restore_live_isn

    plp
    rts

TCP_PASSIVE_SEND_SYNACK:
    lda #$08
    sta ETH_TX_TYPE
    lda #$00
    sta ETH_TX_TYPE+1
    sta TCP_DATA_PAYLOAD_SIZE
    sta TCP_DATA_PAYLOAD_SIZE+1

    lda #20
    sta TCP_HEADER_SIZE

    lda #$06
    jsr BUILD_IPV4_HEADER

    lda #(TCP_FLAG_SYN|TCP_FLAG_ACK)
    jsr BUILD_TCP_HEADER

    jsr TCP_RESTORE_PEER_MAC

    lda #60
    sta ETH_TX_LEN_LSB
    lda #$00
    sta ETH_TX_LEN_MSB

    jsr ETH_PACKET_SEND
    rts

;=============================================================================
; Validate inbound TCP checksum over pseudo-header + TCP segment.
; Out: C=0 valid, C=1 invalid/drop.
;=============================================================================
TCP_RX_CHECKSUM_OK:
    lda #$00
    sta TCP_RX_SUM_LO
    sta TCP_RX_SUM_HI
    sta TCP_RX_WORD_HI
    sta TCP_RX_WORD_LO

    ; TCP length = IPv4 total length - IPv4 header length.
    lda IPV4_RX_TOTAL_LO
    sec
    sbc IPV4_RX_IHL_BYTES
    sta TCP_RX_LEN_LO
    lda IPV4_RX_TOTAL_HI
    sbc #$00
    sta TCP_RX_LEN_HI
    bcs _tcp_rx_len_nonnegative
    jmp _tcp_rx_bad

_tcp_rx_len_nonnegative:
    lda TCP_RX_LEN_HI
    bne _tcp_rx_len_ge_min
    lda TCP_RX_LEN_LO
    cmp #20
    bcc _tcp_rx_bad

_tcp_rx_len_ge_min:
    ; TCP segment pointer = IP payload base + IHL.
    lda #<ETH_RX_FRAME_PAYLOAD
    clc
    adc IPV4_RX_IHL_BYTES
    sta TCP_RX_PTR_LO
    lda #>ETH_RX_FRAME_PAYLOAD
    adc #$00
    sta TCP_RX_PTR_HI

    ; TCP data offset must be at least 20 bytes and fit within TCP length.
    lda TCP_RX_PTR_LO
    clc
    adc #12
    sta _tcp_rx_offset_read+1
    lda TCP_RX_PTR_HI
    adc #$00
    sta _tcp_rx_offset_read+2
_tcp_rx_offset_read:
    lda $ffff
    and #$f0
    lsr
    lsr
    lsr
    lsr
    asl
    asl
    sta TCP_RX_HDR_LEN
    cmp #20
    bcc _tcp_rx_bad

    lda TCP_RX_LEN_HI
    bne _tcp_rx_hdr_fits
    lda TCP_RX_LEN_LO
    cmp TCP_RX_HDR_LEN
    bcc _tcp_rx_bad

_tcp_rx_hdr_fits:
    ; Pseudo-header: source IP.
    lda ETH_RX_FRAME_PAYLOAD+12
    sta TCP_RX_WORD_HI
    lda ETH_RX_FRAME_PAYLOAD+13
    sta TCP_RX_WORD_LO
    jsr TCP_RX_ADD_WORD
    lda ETH_RX_FRAME_PAYLOAD+14
    sta TCP_RX_WORD_HI
    lda ETH_RX_FRAME_PAYLOAD+15
    sta TCP_RX_WORD_LO
    jsr TCP_RX_ADD_WORD

    ; Pseudo-header: destination IP.
    lda ETH_RX_FRAME_PAYLOAD+16
    sta TCP_RX_WORD_HI
    lda ETH_RX_FRAME_PAYLOAD+17
    sta TCP_RX_WORD_LO
    jsr TCP_RX_ADD_WORD
    lda ETH_RX_FRAME_PAYLOAD+18
    sta TCP_RX_WORD_HI
    lda ETH_RX_FRAME_PAYLOAD+19
    sta TCP_RX_WORD_LO
    jsr TCP_RX_ADD_WORD

    ; Pseudo-header: zero + protocol.
    lda #$00
    sta TCP_RX_WORD_HI
    lda #IP_PROTO_TCP
    sta TCP_RX_WORD_LO
    jsr TCP_RX_ADD_WORD

    ; Pseudo-header: TCP length.
    lda TCP_RX_LEN_HI
    sta TCP_RX_WORD_HI
    lda TCP_RX_LEN_LO
    sta TCP_RX_WORD_LO
    jsr TCP_RX_ADD_WORD

    ; Sum TCP segment, padding odd byte with zero.
_tcp_rx_sum_loop:
    lda TCP_RX_LEN_HI
    ora TCP_RX_LEN_LO
    beq _tcp_rx_sum_done

    jsr TCP_RX_READ_BYTE
    sta TCP_RX_WORD_HI
    jsr TCP_RX_DEC_LEN

    lda TCP_RX_LEN_HI
    ora TCP_RX_LEN_LO
    beq _tcp_rx_odd_byte

    jsr TCP_RX_READ_BYTE
    sta TCP_RX_WORD_LO
    jsr TCP_RX_DEC_LEN
    bra _tcp_rx_add_segment_word

_tcp_rx_odd_byte:
    lda #$00
    sta TCP_RX_WORD_LO

_tcp_rx_add_segment_word:
    jsr TCP_RX_ADD_WORD
    bra _tcp_rx_sum_loop

_tcp_rx_sum_done:
    lda TCP_RX_SUM_HI
    cmp #$ff
    bne _tcp_rx_bad
    lda TCP_RX_SUM_LO
    cmp #$ff
    bne _tcp_rx_bad
    clc
    rts

_tcp_rx_bad:
    sec
    rts

TCP_RX_READ_BYTE:
    lda TCP_RX_PTR_LO
    sta _tcp_rx_read_abs+1
    lda TCP_RX_PTR_HI
    sta _tcp_rx_read_abs+2
_tcp_rx_read_abs:
    lda $ffff
    inc TCP_RX_PTR_LO
    bne _tcp_rx_read_done
    inc TCP_RX_PTR_HI
_tcp_rx_read_done:
    rts

TCP_RX_DEC_LEN:
    lda TCP_RX_LEN_LO
    bne _tcp_rx_dec_low
    dec TCP_RX_LEN_HI
_tcp_rx_dec_low:
    dec TCP_RX_LEN_LO
    rts

TCP_RX_ADD_WORD:
    clc
    lda TCP_RX_SUM_LO
    adc TCP_RX_WORD_LO
    sta TCP_RX_SUM_LO
    lda TCP_RX_SUM_HI
    adc TCP_RX_WORD_HI
    sta TCP_RX_SUM_HI
    bcc _tcp_rx_add_done
    inc TCP_RX_SUM_LO
    bne _tcp_rx_add_done
    inc TCP_RX_SUM_HI
    bne _tcp_rx_add_done
    inc TCP_RX_SUM_LO
_tcp_rx_add_done:
    rts

TCP_RX_LEN_LO:  .byte $00
TCP_RX_LEN_HI:  .byte $00
TCP_RX_PTR_LO:  .byte $00
TCP_RX_PTR_HI:  .byte $00
TCP_RX_HDR_LEN: .byte $00
TCP_RX_WORD_HI: .byte $00
TCP_RX_WORD_LO: .byte $00
TCP_RX_SUM_HI:  .byte $00
TCP_RX_SUM_LO:  .byte $00
