;=============================================================================
; TCP transmit: a send ring with a sliding window
;=============================================================================
; The application's bytes go into a 2 KB ring at TX_RING_BASE.  Segments of
; up to TCP_PAYLOAD_MAX bytes are cut from it and sent while the bytes in
; flight stay within TCP_TX_WINDOW and the peer's window, so several segments
; go out per round trip.  An ACK frees the bytes it covers.
;
; A short segment waits while data is in flight (Nagle's rule), so a message
; queued a byte at a time leaves as one segment once the last one is ACKed.
;
; On a timeout everything unacknowledged is sent again from SND.UNA
; (go-back-N).  TCP_TX_MAX_RETRIES timeouts in a row with no progress drop the
; connection with EV_TX_TIMEOUT; an ACK that frees anything starts the count
; again.  The stack doesn't send into a zero window, and doesn't probe one:
; it waits for the peer's window update.
;
;   TXQ_UNA            TXQ_NXT              TXQ_HEAD
;      |-- in flight ----|-- queued, unsent --|-- free --|
;   SND.UNA = TX_UNACK_SEQ, SND.NXT = LOCAL_ISN
;=============================================================================
.cerror (TX_RING_BASE & (TX_RING_SIZE - 1)) != 0, "the send ring must be aligned to its size"
.cerror (TX_RING_SIZE & $ff) != 0 || (TCP_TX_WINDOW & $ff) != 0, "the send ring and window must be whole pages"

TCP_TX_RESET:
    lda #$00
    sta TXQ_HEAD
    sta TXQ_HEAD+1
    sta TXQ_UNA
    sta TXQ_UNA+1
    sta TXQ_NXT
    sta TXQ_NXT+1
    sta TXQ_COUNT
    sta TXQ_COUNT+1
    sta TXQ_INFLIGHT
    sta TXQ_INFLIGHT+1
    sta TX_UNACK_PENDING
    sta TX_UNACK_RETRY_TICKS
    sta TX_UNACK_RETRY_LEFT
    sta TCP_TX_LAST_RASTER_LO
    sta TCP_TX_LAST_RASTER_HI
    sta TCP_PEER_MAC_VALID
    sta TCP_CLOSE_PENDING
    sta TX_PEER_WINDOW+1
    lda #TCP_PAYLOAD_MAX              ; one segment until the peer's window is known
    sta TX_PEER_WINDOW
    rts

; The window of the segment just received becomes the peer's window (the
; handshake's SYN-ACK or final ACK, then every acceptable ACK).
TCP_TX_TAKE_PEER_WINDOW:
    lda SEG_WND
    sta TX_PEER_WINDOW
    lda SEG_WND+1
    sta TX_PEER_WINDOW+1
    rts

; TXQ_TMP := free space in the ring
TCP_TX_FREE:
    sec
    lda #<TX_RING_SIZE
    sbc TXQ_COUNT
    sta TXQ_TMP
    lda #>TX_RING_SIZE
    sbc TXQ_COUNT+1
    sta TXQ_TMP+1
    rts

; A -> ring[TXQ_HEAD], TXQ_HEAD moves on (wrapping).  No checks.  X, Y kept.
TCP_TX_RING_PUT:
    pha
    lda TXQ_HEAD
    sta _put+1
    lda TXQ_HEAD+1
    ora #>TX_RING_BASE
    sta _put+2
    pla
_put:
    sta TX_RING_BASE
    inc TXQ_HEAD
    bne _done
    lda TXQ_HEAD+1
    inc a
    and #TX_RING_MASK_HI
    sta TXQ_HEAD+1
_done:
    rts

; Queue TCP_DATA_PAYLOAD (TCP_DATA_PAYLOAD_SIZE bytes, at most
; TCP_PAYLOAD_MAX).  C=1: too long, or no room for all of it.
TCP_TX_ENQUEUE_CURRENT:
    lda TCP_DATA_PAYLOAD_SIZE+1
    bne _fail
    lda TCP_DATA_PAYLOAD_SIZE
    beq _success
    cmp #TCP_PAYLOAD_MAX+1
    bcs _fail
    sta TXQ_ENQ_LEN

    jsr TCP_TX_FREE
    lda TXQ_TMP+1
    bne _room
    lda TXQ_TMP
    cmp TXQ_ENQ_LEN
    bcc _fail

_room:
    ldy #$00
_enqueue_loop:
    lda TCP_DATA_PAYLOAD,y
    jsr TCP_TX_RING_PUT
    iny
    cpy TXQ_ENQ_LEN
    bne _enqueue_loop

    clc
    lda TXQ_COUNT
    adc TXQ_ENQ_LEN
    sta TXQ_COUNT
    bcc _success
    inc TXQ_COUNT+1

_success:
    clc
    rts

_fail:
    sec
    rts

; Queue one byte (A) for the ML byte API.  It goes out at the next
; ETH_STATUS_POLL, with whatever else is queued by then.
; C=0 queued, C=1 not connected or the ring is full.
TCP_TX_PUT_BYTE:
    tax
    lda TCP_STATE
    cmp #TCP_STATE_ESTABLISHED
    bne _refused
    lda TXQ_COUNT+1
    cmp #>TX_RING_SIZE
    bcs _refused
    txa
    jsr TCP_TX_RING_PUT
    inc TXQ_COUNT
    bne _queued
    inc TXQ_COUNT+1
_queued:
    clc
    rts

_refused:
    sec
    rts

;=============================================================================
; An ACK arrived (ESTABLISHED): free what it covers, and take the window.
; Only segments at RCV.NXT count, as before.
;=============================================================================
TCP_TX_ACK_CHECK:
    lda ETH_RX_TCP_FLAGS
    and #TCP_FLAG_ACK
    beq _ret
    jsr TCP_SEQ_CMP_SEG_SEQ_REMOTE
    bne _ret

    lda TX_UNACK_PENDING
    beq _window

    ; SND.UNA < SEG.ACK <= SND.NXT frees bytes; an ACK of nothing new only
    ; brings the window; an ACK of data never sent is ignored.
    jsr TCP_SEQ_CMP_SEG_ACK_TX_UNACK_SEQ
    beq _window
    bmi _window
    jsr TCP_SEQ_CMP_SEG_ACK_LOCAL_ISN
    beq _acked
    bpl _ret

_acked:
    ; freed = SEG.ACK - SND.UNA: at most the bytes in flight, so 16 bits
    sec
    lda SEG_ACK+3
    sbc TX_UNACK_SEQ+3
    sta TXQ_TMP
    lda SEG_ACK+2
    sbc TX_UNACK_SEQ+2
    sta TXQ_TMP+1

    ldx #$03
_new_una:
    lda SEG_ACK,x
    sta TX_UNACK_SEQ,x
    dex
    bpl _new_una

    clc
    lda TXQ_UNA
    adc TXQ_TMP
    sta TXQ_UNA
    lda TXQ_UNA+1
    adc TXQ_TMP+1
    and #TX_RING_MASK_HI
    sta TXQ_UNA+1

    sec
    lda TXQ_COUNT
    sbc TXQ_TMP
    sta TXQ_COUNT
    lda TXQ_COUNT+1
    sbc TXQ_TMP+1
    sta TXQ_COUNT+1

    sec
    lda TXQ_INFLIGHT
    sbc TXQ_TMP
    sta TXQ_INFLIGHT
    lda TXQ_INFLIGHT+1
    sbc TXQ_TMP+1
    sta TXQ_INFLIGHT+1
    ora TXQ_INFLIGHT
    bne _progress

    ; everything sent is acknowledged: no timer
    lda #$00
    sta TX_UNACK_PENDING
    sta TX_UNACK_RETRY_TICKS
    sta TX_UNACK_RETRY_LEFT
    jmp _window

_progress:
    ; some acknowledged, more in flight: the timer and retries start again
    lda #TCP_TX_MAX_RETRIES
    sta TX_UNACK_RETRY_LEFT
    lda #TCP_TX_RETRY_TICKS
    sta TX_UNACK_RETRY_TICKS
    jsr TCP_TX_TIMER_STAMP

_window:
    jmp TCP_TX_TAKE_PEER_WINDOW

_ret:
    rts

;=============================================================================
; Every ETH_STATUS_POLL (and ETH_TCP_SEND): the retransmit timer, then send
; what the window allows.
;=============================================================================
TCP_TX_TICK:
    lda TCP_STATE
    cmp #TCP_STATE_ESTABLISHED
    beq _established
    jmp TCP_TX_RESET

_established:
    lda TX_UNACK_PENDING
    beq _send

    jsr TCP_TX_FRAME_WRAP_TICK
    bcc _send

    lda TX_UNACK_RETRY_TICKS
    beq _retry_expired
    dec TX_UNACK_RETRY_TICKS
_send:
    jmp TCP_TX_TRY_SEND_QUEUED

_retry_expired:
    lda TX_UNACK_RETRY_LEFT
    beq _timeout

    ; go back to SND.UNA and send it all again
    jsr TCP_TX_REWIND
    jsr TCP_TX_TRY_SEND_QUEUED
    lda TXQ_INFLIGHT
    ora TXQ_INFLIGHT+1
    beq _tx_busy

    dec TX_UNACK_RETRY_LEFT
    lda #TCP_TX_RETRY_TICKS
    sta TX_UNACK_RETRY_TICKS
    jsr TCP_TX_TIMER_STAMP
    rts

_tx_busy:
    ; nothing went out (transmitter busy): try again soon, retry not used
    lda #TCP_TX_BUSY_RETRY_TICKS
    sta TX_UNACK_RETRY_TICKS
    jsr TCP_TX_TIMER_STAMP
    rts

_timeout:
    jsr TCP_HARD_RESET
    lda TCP_EVENT_FLAG
    and #$FE
    ora #EV_TX_TIMEOUT
    sta TCP_EVENT_FLAG
    rts

; Back to SND.UNA: nothing in flight, the next send starts at the oldest
; unacknowledged byte.  TX_UNACK_PENDING stays set, so the retry count goes on.
TCP_TX_REWIND:
    lda TXQ_UNA
    sta TXQ_NXT
    lda TXQ_UNA+1
    sta TXQ_NXT+1
    lda #$00
    sta TXQ_INFLIGHT
    sta TXQ_INFLIGHT+1
    ldx #$03
_rewind_seq:
    lda TX_UNACK_SEQ,x
    sta LOCAL_ISN,x
    dex
    bpl _rewind_seq
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
    bne _frame_elapsed

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

;=============================================================================
; Send segments while there is unsent data and the window has room.
; C=1: not connected, or the transmitter couldn't take a segment.
;=============================================================================
TCP_TX_TRY_SEND_QUEUED:
    lda TCP_STATE
    cmp #TCP_STATE_ESTABLISHED
    beq _next_segment
    sec
    rts

_next_segment:
    ; unsent = COUNT - INFLIGHT
    sec
    lda TXQ_COUNT
    sbc TXQ_INFLIGHT
    sta TXQ_TMP
    lda TXQ_COUNT+1
    sbc TXQ_INFLIGHT+1
    sta TXQ_TMP+1
    ora TXQ_TMP
    beq _nothing_to_send

    ; length = min(unsent, TCP_PAYLOAD_MAX)
    lda TXQ_TMP+1
    bne _full_segment
    lda TXQ_TMP
    cmp #TCP_PAYLOAD_MAX+1
    bcc _have_length
_full_segment:
    lda #TCP_PAYLOAD_MAX
_have_length:
    sta TXQ_SEND_LEN

    ; room = min(peer window, TCP_TX_WINDOW) - INFLIGHT
    lda TX_PEER_WINDOW
    sta TXQ_TMP
    lda TX_PEER_WINDOW+1
    sta TXQ_TMP+1
    cmp #>TCP_TX_WINDOW
    bcc _have_window
    lda #<TCP_TX_WINDOW
    sta TXQ_TMP
    lda #>TCP_TX_WINDOW
    sta TXQ_TMP+1
_have_window:
    sec
    lda TXQ_TMP
    sbc TXQ_INFLIGHT
    sta TXQ_TMP
    lda TXQ_TMP+1
    sbc TXQ_INFLIGHT+1
    sta TXQ_TMP+1
    bcc _nothing_to_send              ; the window shrank below what is in flight
    ora TXQ_TMP
    beq _nothing_to_send              ; full (or zero) window
    lda TXQ_TMP+1
    bne _length_fits
    lda TXQ_TMP
    cmp TXQ_SEND_LEN
    bcs _length_fits
    sta TXQ_SEND_LEN                  ; only what the window takes

_length_fits:
    ; Nagle: a short segment only when nothing is in flight
    lda TXQ_SEND_LEN
    cmp #TCP_PAYLOAD_MAX
    beq _send_it
    lda TXQ_INFLIGHT
    ora TXQ_INFLIGHT+1
    bne _nothing_to_send

_send_it:
    jsr TCP_TX_SEND_SEGMENT
    bcc _next_segment
    rts

_nothing_to_send:
    clc
    rts

; Send TXQ_SEND_LEN bytes from ring[TXQ_NXT] with SEQ = SND.NXT.
; C=1: not sent (no MAC yet, or the transmitter is busy).
TCP_TX_SEND_SEGMENT:
    lda TXQ_NXT
    sta TXQ_SCAN
    lda TXQ_NXT+1
    sta TXQ_SCAN+1
    ldy #$00
_copy_from_ring:
    lda TXQ_SCAN
    sta _get+1
    lda TXQ_SCAN+1
    ora #>TX_RING_BASE
    sta _get+2
_get:
    lda TX_RING_BASE
    sta TCP_DATA_PAYLOAD,y
    inc TXQ_SCAN
    bne _scan_ok
    lda TXQ_SCAN+1
    inc a
    and #TX_RING_MASK_HI
    sta TXQ_SCAN+1
_scan_ok:
    iny
    cpy TXQ_SEND_LEN
    bne _copy_from_ring

    lda TXQ_SEND_LEN
    sta TCP_DATA_PAYLOAD_SIZE
    lda #$00
    sta TCP_DATA_PAYLOAD_SIZE+1

    lda #TCP_FLAG_PSH|TCP_FLAG_ACK
    jsr ETH_BUILD_TCPIP_PACKET
    bcs _send_fail
    jsr ETH_PACKET_SEND
    bcs _send_fail
    lda #$00
    sta ACK_REPLY_PENDING             ; this segment carries the latest ACK

    ; The first byte in flight starts the retransmit timer at SND.UNA.  A
    ; fresh start (not a resend after a timeout) also gets all its retries.
    lda TXQ_INFLIGHT
    ora TXQ_INFLIGHT+1
    bne _timer_running
    ldx #$03
_set_una:
    lda LOCAL_ISN,x
    sta TX_UNACK_SEQ,x
    dex
    bpl _set_una
    lda TX_UNACK_PENDING
    bne _keep_retries
    lda #TCP_TX_MAX_RETRIES
    sta TX_UNACK_RETRY_LEFT
    lda #$01
    sta TX_UNACK_PENDING
_keep_retries:
    lda #TCP_TX_RETRY_TICKS
    sta TX_UNACK_RETRY_TICKS
    jsr TCP_TX_TIMER_STAMP

_timer_running:
    lda TXQ_SCAN
    sta TXQ_NXT
    lda TXQ_SCAN+1
    sta TXQ_NXT+1
    clc
    lda TXQ_INFLIGHT
    adc TXQ_SEND_LEN
    sta TXQ_INFLIGHT
    bcc _inflight_ok
    inc TXQ_INFLIGHT+1
_inflight_ok:
    jsr CALC_LOCAL_ISN                ; SND.NXT += the payload (PSH)
    jsr CLEAR_TCP_PAYLOAD
    clc
    rts

_send_fail:
    jsr CLEAR_TCP_PAYLOAD
    sec
    rts
