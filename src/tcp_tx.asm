;=============================================================================
; TCP transmit queue and data retransmission
;=============================================================================
TCP_TX_RESET:
    lda #$00
    sta TXQ_HEAD
    sta TXQ_TAIL
    sta TXQ_COUNT
    sta TXQ_NEW_COUNT
    sta TXQ_ENQ_LEN
    sta TXQ_SEND_LEN
    sta TXQ_SCAN
    sta TX_UNACK_PENDING
    sta TX_UNACK_LEN
    sta TX_UNACK_RETRY_TICKS
    sta TX_UNACK_RETRY_LEFT
    sta TCP_TX_LAST_RASTER_LO
    sta TCP_TX_LAST_RASTER_HI
    sta TCP_PEER_MAC_VALID
    rts

TCP_TX_ENQUEUE_CURRENT:
    lda TCP_DATA_PAYLOAD_SIZE+1
    bne _fail

    lda TCP_DATA_PAYLOAD_SIZE
    beq _success
    cmp #TCP_PAYLOAD_MAX+1
    bcs _fail
    sta TXQ_ENQ_LEN

    lda TXQ_COUNT
    clc
    adc TXQ_ENQ_LEN
    bcs _fail
    sta TXQ_NEW_COUNT

    ldy #$00
_enqueue_loop:
    cpy TXQ_ENQ_LEN
    beq _enqueue_done
    ldx TXQ_HEAD
    lda TCP_DATA_PAYLOAD,y
    sta TX_APP_QUEUE,x
    inc TXQ_HEAD
    iny
    jmp _enqueue_loop

_enqueue_done:
    lda TXQ_NEW_COUNT
    sta TXQ_COUNT
    inc TCP_TX_ENQUEUE_OK_DBG

_success:
    clc
    rts

_fail:
    sec
    rts

TCP_TX_ACK_CHECK:
    lda TX_UNACK_PENDING
    beq _ret

    lda ETH_RX_TCP_FLAGS
    and #TCP_FLAG_ACK
    beq _ret
    inc TCP_TX_ACK_SEEN_DBG
    ldx #$00
_save_last_ack:
    lda SEG_ACK,x
    sta TCP_TX_LAST_ACK_DBG,x
    inx
    cpx #$04
    bne _save_last_ack

    ; RFC-style ACK bounds for stop-and-wait data:
    ; SND.UNA < SEG.ACK <= SND.NXT, and it must cover this segment.
    jsr TCP_SEQ_CMP_SEG_ACK_TX_UNACK_SEQ
    beq _ret
    bmi _ret

    jsr TCP_SEQ_CMP_SEG_ACK_LOCAL_ISN
    beq _ack_not_future
    bmi _ack_not_future
    rts

_ack_not_future:
    jsr TCP_SEQ_CMP_SEG_ACK_TX_EXPECT
    bmi _ret

_acked:
    inc TCP_TX_ACK_MATCH_DBG
    lda #$00
    sta TX_UNACK_PENDING
    sta TX_UNACK_RETRY_TICKS
    sta TX_UNACK_RETRY_LEFT

_ret:
    rts

TCP_TX_TICK:
    lda TCP_STATE
    cmp #TCP_STATE_ESTABLISHED
    beq _established
    jsr TCP_TX_RESET
    rts

_established:
    lda TX_UNACK_PENDING
    beq _try_send

    jsr TCP_TX_FRAME_WRAP_TICK
    bcc _timer_wait

    lda TX_UNACK_RETRY_TICKS
    beq _retry_expired
    dec TX_UNACK_RETRY_TICKS
_timer_wait:
    rts

_retry_expired:
    lda TX_UNACK_RETRY_LEFT
    beq _timeout

    jsr TCP_TX_RETRANSMIT_PENDING
    bcs _tx_busy

    dec TX_UNACK_RETRY_LEFT
    lda #TCP_TX_RETRY_TICKS
    sta TX_UNACK_RETRY_TICKS
    jsr TCP_TX_TIMER_STAMP
    rts

_tx_busy:
    lda #TCP_TX_BUSY_RETRY_TICKS
    sta TX_UNACK_RETRY_TICKS
    jsr TCP_TX_TIMER_STAMP
    rts

_timeout:
    inc TCP_TX_TIMEOUT_DBG
    lda TX_UNACK_LEN
    sta TCP_TX_TIMEOUT_LEN_DBG
    lda TX_UNACK_RETRY_LEFT
    sta TCP_TX_TIMEOUT_RETRY_DBG
    ldx #$00
_timeout_snapshot:
    lda TX_UNACK_EXPECT_ACK,x
    sta TCP_TX_TIMEOUT_EXPECT_DBG,x
    lda TCP_TX_LAST_ACK_DBG,x
    sta TCP_TX_TIMEOUT_ACK_DBG,x
    inx
    cpx #$04
    bne _timeout_snapshot

    jsr TCP_HARD_RESET
    lda TCP_EVENT_FLAG
    and #$FE
    ora #EV_TX_TIMEOUT
    sta TCP_EVENT_FLAG
    rts

_try_send:
    jsr TCP_TX_TRY_SEND_QUEUED
    rts

TCP_TX_TIMER_STAMP:
    jsr ARP_READ_RASTER
    lda ARP_CUR_RASTER_LO
    sta TCP_TX_LAST_RASTER_LO
    lda ARP_CUR_RASTER_HI
    sta TCP_TX_LAST_RASTER_HI
    rts

TCP_TX_FRAME_WRAP_TICK:
    jsr ARP_READ_RASTER

    lda ARP_CUR_RASTER_HI
    cmp TCP_TX_LAST_RASTER_HI
    bcc _frame_elapsed
    bne _no_frame

    lda ARP_CUR_RASTER_LO
    cmp TCP_TX_LAST_RASTER_LO
    bcc _frame_elapsed

_no_frame:
    lda ARP_CUR_RASTER_LO
    sta TCP_TX_LAST_RASTER_LO
    lda ARP_CUR_RASTER_HI
    sta TCP_TX_LAST_RASTER_HI
    clc
    rts

_frame_elapsed:
    lda ARP_CUR_RASTER_LO
    sta TCP_TX_LAST_RASTER_LO
    lda ARP_CUR_RASTER_HI
    sta TCP_TX_LAST_RASTER_HI
    sec
    rts

TCP_TX_TRY_SEND_QUEUED:
    lda TCP_STATE
    cmp #TCP_STATE_ESTABLISHED
    bne _send_fail

    lda TX_UNACK_PENDING
    bne _nothing_to_send

    lda TXQ_COUNT
    beq _nothing_to_send
    cmp #TCP_PAYLOAD_MAX+1
    bcc _use_queue_count
    lda #TCP_PAYLOAD_MAX

_use_queue_count:
    sta TXQ_SEND_LEN

    lda TXQ_TAIL
    sta TXQ_SCAN
    ldy #$00
_copy_from_queue:
    cpy TXQ_SEND_LEN
    beq _payload_ready
    ldx TXQ_SCAN
    lda TX_APP_QUEUE,x
    sta TCP_DATA_PAYLOAD,y
    inc TXQ_SCAN
    iny
    jmp _copy_from_queue

_payload_ready:
    lda TXQ_SEND_LEN
    sta TCP_DATA_PAYLOAD_SIZE
    lda #$00
    sta TCP_DATA_PAYLOAD_SIZE+1

    lda #TCP_FLAG_PSH|TCP_FLAG_ACK
    jsr ETH_BUILD_TCPIP_PACKET
    bcs _send_fail_clear
    jsr ETH_PACKET_SEND
    bcs _send_fail_clear
    lda #$00
    sta ACK_REPLY_PENDING
    inc TCP_TX_SEND_OK_DBG
    lda CONNECT_RAW_RX_DBG
    sta TCP_TX_BASE_RAW_DBG
    lda CONNECT_TCP_DISPATCH_DBG
    sta TCP_TX_BASE_DISPATCH_DBG
    lda CONNECT_TCP_RX_DBG
    sta TCP_TX_BASE_HANDLER_DBG

    ldx #$00
_save_seq:
    lda LOCAL_ISN,x
    sta TX_UNACK_SEQ,x
    sta TX_UNACK_EXPECT_ACK,x
    inx
    cpx #$04
    bne _save_seq

    lda TX_UNACK_EXPECT_ACK+3
    clc
    adc TXQ_SEND_LEN
    sta TX_UNACK_EXPECT_ACK+3
    lda TX_UNACK_EXPECT_ACK+2
    adc #$00
    sta TX_UNACK_EXPECT_ACK+2
    lda TX_UNACK_EXPECT_ACK+1
    adc #$00
    sta TX_UNACK_EXPECT_ACK+1
    lda TX_UNACK_EXPECT_ACK+0
    adc #$00
    sta TX_UNACK_EXPECT_ACK+0

    ldy #$00
_save_payload:
    cpy TXQ_SEND_LEN
    beq _payload_saved
    lda TCP_DATA_PAYLOAD,y
    sta TX_UNACK_PAYLOAD,y
    iny
    jmp _save_payload

_payload_saved:
    lda TXQ_SCAN
    sta TXQ_TAIL
    lda TXQ_COUNT
    sec
    sbc TXQ_SEND_LEN
    sta TXQ_COUNT

    lda TXQ_SEND_LEN
    sta TX_UNACK_LEN
    lda #$01
    sta TX_UNACK_PENDING
    lda #TCP_TX_RETRY_TICKS
    sta TX_UNACK_RETRY_TICKS
    lda #TCP_TX_MAX_RETRIES
    sta TX_UNACK_RETRY_LEFT
    jsr TCP_TX_TIMER_STAMP

    jsr CALC_LOCAL_ISN
    jsr CLEAR_TCP_PAYLOAD
    clc
    rts

_nothing_to_send:
    clc
    rts

_send_fail_clear:
    jsr CLEAR_TCP_PAYLOAD

_send_fail:
    inc TCP_TX_SEND_FAIL_DBG
    sec
    rts

TCP_TX_RETRANSMIT_PENDING:
    lda TX_UNACK_PENDING
    beq _no_pending

    lda TX_UNACK_LEN
    beq _clear_pending

    ldx #$00
_save_current_isn:
    lda LOCAL_ISN,x
    sta TX_SAVE_LOCAL_ISN,x
    lda TX_UNACK_SEQ,x
    sta LOCAL_ISN,x
    inx
    cpx #$04
    bne _save_current_isn

    ldy #$00
_copy_unack_payload:
    cpy TX_UNACK_LEN
    beq _unack_payload_ready
    lda TX_UNACK_PAYLOAD,y
    sta TCP_DATA_PAYLOAD,y
    iny
    jmp _copy_unack_payload

_unack_payload_ready:
    lda TX_UNACK_LEN
    sta TCP_DATA_PAYLOAD_SIZE
    lda #$00
    sta TCP_DATA_PAYLOAD_SIZE+1

    lda #TCP_FLAG_PSH|TCP_FLAG_ACK
    jsr ETH_BUILD_TCPIP_PACKET
    php

    ldx #$00
_restore_isn_after_build:
    lda TX_SAVE_LOCAL_ISN,x
    sta LOCAL_ISN,x
    inx
    cpx #$04
    bne _restore_isn_after_build

    plp
    bcs _retransmit_fail

    jsr ETH_PACKET_SEND
    bcs _retransmit_fail
    lda #$00
    sta ACK_REPLY_PENDING
    inc TCP_TX_RETX_OK_DBG

    jsr CLEAR_TCP_PAYLOAD
    clc
    rts

_retransmit_fail:
    inc TCP_TX_RETX_FAIL_DBG
    jsr CLEAR_TCP_PAYLOAD
    sec
    rts

_clear_pending:
    lda #$00
    sta TX_UNACK_PENDING

_no_pending:
    clc
    rts
