;===================================================================================================
;
; MMM     MMM   EEEEEEEEE    GGGGGGGGGG        AAA              III     PPPPPPPPPP
; MMMM   MMMM   EEE          GGG             AAA AAA            III     PPP     PPP
; MMM MMM MMM   EEEEEE       GGG  GGGGG     AAA   AAA    --     III     PPP     PPP
; MMM  M  MMM   EEE          GGG    GGG     AAAAAAAAA    --     III     PPPPPPPPPP
; MMM  M  MMM   EEE          GGG    GGG     AAA   AAA           III     PPP
; MMM     MMM   EEEEEEEEEE   GGGGGGGGGG     AAA   AAA           III     PPP
;
; BASIC Ethernet Library for the Mega65 Personal Computer
; 64TASS Assembly (Compiles with v1.60.3243)
; Released under the PUBLIC DOMAIN - Hack as ye will.
; Originally developed by ChatGPT, with some occasional assistance from Scott Hutter - 8/30/2025
;
;===================================================================================================
; To load:
; BLOAD"eth.bin",P($42000),R
;
; Uses Bank 4 for code, bank 5 for incoming data ring buffer
; See jump table and BASIC demo for usage
;===================================================================================================

.include "macros.asm"
.include "mega65.asm"

.cpu "45gs02"


TCP_FLAG_SYN                = $02
TCP_FLAG_ACK                = $10
TCP_FLAG_PSH                = $08
TCP_FLAG_FIN                = $01
TCP_FLAG_RST                = $04

; Ethernet states
ETH_STATE_DOWN              = $00
ETH_STATE_ARP_WAITING       = $01

; TCP states
TCP_STATE_CLOSED            = $00
TCP_STATE_SYN_SENT          = $02
TCP_STATE_SYN_RECEIVED      = $03
TCP_STATE_ESTABLISHED       = $04
TCP_STATE_FIN_WAIT_1        = $05
TCP_STATE_FIN_WAIT_2        = $06
TCP_STATE_CLOSE_WAIT        = $07
TCP_STATE_LAST_ACK          = $09
TCP_STATE_TIME_WAIT         = $0a

; A bitfield returned by CONNECT_* entry points
CONN_CONNECTED              = %00000001     ; ESTABLISHED
CONN_FAILED                 = %00000010     ; handshake failed / RST / closed
CONN_IN_PROGRESS            = %00000100     ; we’re working on it
CONN_ARP_WAIT               = %00001000     ; ARP request outstanding
CONN_SYN_SENT               = %00010000     ; SYN has been sent

; Event bits returned by ETH_STATUS_POLL (sticky until read)
EV_RST                      = %00000001     ; hard reset seen (peer RST)          [existing]
EV_PEER_FIN                 = %00000010     ; peer initiated close (we saw FIN)
EV_LOCAL_CLOSE              = %00000100     ; our FIN exchange completed
EV_TIMEWAIT_DONE            = %00001000     ; TIME_WAIT expired → CLOSED
EV_CONNECT_FAIL             = %00010000     ; SYN handshake failed / timeout
EV_TX_TIMEOUT               = %00100000     ; data retransmit retries exhausted

TCP_PAYLOAD_MAX             = 235
TCP_PAYLOAD_PADDED_SIZE     = TCP_PAYLOAD_MAX + 1
DNS_HOST_BUFFER_SIZE        = 128
DNS_HOST_MAX                = DNS_HOST_BUFFER_SIZE - 1
BANK1_WORKSPACE_LOW_HI      = $20          ; bank-1 offset $2000 -> physical $12000
BANK1_COLOR_SHADOW_HI       = $f8          ; bank-1 offset $f800 -> physical $1f800
CONNECT_SYN_RETRY_TICKS     = 60
CONNECT_SYN_MAX_RETRIES     = 4
TCP_TX_RETRY_TICKS          = 45
TCP_TX_BUSY_RETRY_TICKS     = 5
TCP_TX_MAX_RETRIES          = 6
IP_PROTO_ICMP               = $01
IP_PROTO_TCP                = $06
IP_PROTO_UDP                = $11
ICMP_TYPE_ECHO_REPLY        = $00
ICMP_TYPE_ECHO_REQUEST      = $08

; This code is loaded to bank 4, starting at $2000 (BLOAD"eth.bin",P($42000),R)
; The reason is so that the standard MAP for BASIC remains in effect.
EXEC_BANK = $04     ; code is running from $42000

.include "api.asm"

;=============================================================================
; Knock routine to expose IO
;=============================================================================
MEGA65_IO_ENABLE:

    lda #$47
    sta MEGA65_IO_MODE
    lda #$53
    sta MEGA65_IO_MODE
    rts

;=============================================================================
; Initialization routine
;=============================================================================
ETH_INIT:
    php
    sei

    jsr MEGA65_IO_ENABLE

    ; Configure RX filter:
    ; - Multicast OFF  (bit5 = 0)
    ; - Broadcast ON   (bit4 = 1)  [needed for ARP etc.]
    ; - Promiscuous OFF (NOPROM=1, bit0 = 1)
    lda MEGA65_ETH_CTRL3
    and #%11011111        ; clear bit5 (MCST=0 → no multicast)
    ora #%00010001        ; set bit4 (BCST=1) and bit0 (NOPROM=1)
    sta MEGA65_ETH_CTRL3
    jmp _more

_ahead:
    ; set ETH TX phase to 1
    lda MEGA65_ETH_CTRL3
    and #%11110011          ; clear bits 3 and 2
    ora #%00000100          ; set bit 2
    sta MEGA65_ETH_CTRL3

    ; Set ETH RX Phase delay to 1
    lda MEGA65_ETH_CTRL3    ; read current value
    and #%00111111          ; clear bits 6 and 7
    ora #%01000000          ; set bit 6
    sta MEGA65_ETH_CTRL3    ; write it back
_more:
    ; read mac address from controller
    lda MEGA65_ETH_MAC+0
    sta ETH_TX_FRAME_SRC_MAC+0
    lda MEGA65_ETH_MAC+1
    sta ETH_TX_FRAME_SRC_MAC+1
    lda MEGA65_ETH_MAC+2
    sta ETH_TX_FRAME_SRC_MAC+2
    lda MEGA65_ETH_MAC+3
    sta ETH_TX_FRAME_SRC_MAC+3
    lda MEGA65_ETH_MAC+4
    sta ETH_TX_FRAME_SRC_MAC+4
    lda MEGA65_ETH_MAC+5
    sta ETH_TX_FRAME_SRC_MAC+5

    ; reset, then release from reset and reset TX FSM
    lda #$00
    sta MEGA65_ETH_CTRL1
    jsr ETH_WAIT_100MS

    lda #$03
    sta MEGA65_ETH_CTRL1
    jsr ETH_WAIT_100MS

    ; pulse TX FSM reset
    lda #$03
    sta MEGA65_ETH_CTRL2
    lda #$00
    sta MEGA65_ETH_CTRL2

    ; wait 4 seconds to allow PHY to come up again
    lda #40
    sta _loop_ctr

_loop_delay
    jsr ETH_WAIT_100MS
    dec _loop_ctr
    bne _loop_delay

_clear_buffer:
    jsr ETH_CLEAR_DRIVER_STATE
    plp
    rts

_loop_ctr:
    .byte $00

;=============================================================================
; Set local IP
;=============================================================================
ETH_SET_LOCAL_IP:
    sta LOCAL_IP+0
    stx LOCAL_IP+1
    sty LOCAL_IP+2
    tza
    sta LOCAL_IP+3
    rts

;=============================================================================
; Set remote IP
;=============================================================================
ETH_SET_REMOTE_IP:
    sta REMOTE_IP+0
    stx REMOTE_IP+1
    sty REMOTE_IP+2
    tza
    sta REMOTE_IP+3
    rts

;=============================================================================
; Set gateway IP
;=============================================================================
ETH_SET_GATEWAY_IP:
    sta GATEWAY_IP+0
    stx GATEWAY_IP+1
    sty GATEWAY_IP+2
    tza
    sta GATEWAY_IP+3
    rts

;=============================================================================
; Set subnet mask
;=============================================================================
ETH_SET_SUBNET_MASK:
    sta SUBNET_MASK+0
    stx SUBNET_MASK+1
    sty SUBNET_MASK+2
    tza
    sta SUBNET_MASK+3
    rts

;=============================================================================
; Set remote port
;=============================================================================
ETH_SET_REMOTE_PORT:
    sta REMOTE_PORT+0
    stx REMOTE_PORT+1
    rts

;=============================================================================
; Set primary DNS
;=============================================================================
ETH_SET_PRIMARY_DNS:
    sta PRIMARY_DNS+0
    stx PRIMARY_DNS+1
    sty PRIMARY_DNS+2
    tza
    sta PRIMARY_DNS+3
    rts

;=============================================================================
; Set character translation
;=============================================================================
ETH_SET_CHAR_XLATE:
    sta CHARACTER_MODE
    rts

;=============================================================================
; ETH_TCP_CONNECT_START
; Kick off a client connection without blocking.
; Returns A = status bits (see constants). Never busy-waits.
;=============================================================================
ETH_TCP_CONNECT_START:
    ; already established?
    lda TCP_STATE
    cmp #TCP_STATE_ESTABLISHED
    beq _already_up

    ; If a previous attempt is mid-flight, just report status
    lda CONNECT_ACTIVE
    bne _report_only

    ; Fresh attempt - generate new port
    lda LOCAL_PORT+1
    clc
    adc #$01
    sta LOCAL_PORT+1
    lda LOCAL_PORT+0
    adc #$00
    sta LOCAL_PORT+0

    ; Initialize connection state
    jsr CLEAR_TCP_PAYLOAD
    jsr TCP_TX_RESET
    jsr CLEAR_REMOTE_ISN

    inc LOCAL_ISN+3
    bne _ahead
    inc LOCAL_ISN+2
    bne _ahead
    inc LOCAL_ISN+1
    bne _ahead
    inc LOCAL_ISN+0

_ahead:
    lda #$00
    sta ETH_RX_TCP_FLAGS
    sta CONNECT_FAIL_LATCH
    sta CONNECT_SYN_SENT
    sta CONNECT_RETRY_TICKS
    sta CONNECT_LAST_RASTER_LO
    sta CONNECT_LAST_RASTER_HI
    sta TCP_EVENT_FLAG
    jsr CONNECT_CLEAR_DEBUG

    lda #$01
    sta CONNECT_ACTIVE
    lda #CONNECT_SYN_MAX_RETRIES
    sta CONNECT_RETRY_LEFT

    ; Try ARP cache first (remote or gateway)
    jsr CONNECT_SET_ARP_QUERY

_query_cache:
    jsr ARP_QUERY_CACHE
    beq _need_arp

    ; Have MAC → send SYN immediately
    jsr CONNECT_SEND_SYN
    bcs _send_fail                 ; (carry set = build error)
    lda #CONN_IN_PROGRESS|CONN_SYN_SENT
    rts

_need_arp:
    ; Start ARP and return quickly
    lda #ETH_STATE_ARP_WAITING
    sta ETH_STATE

    ; ARP_REQUEST expects ARP_REQUEST_IP; mirror ARP_QUERY_IP there
    ldx #$03
_cpy_arp:
    lda ARP_QUERY_IP,x
    sta ARP_REQUEST_IP,x
    dex
    bpl _cpy_arp

    jsr ARP_REQUEST

    lda #CONN_IN_PROGRESS|CONN_ARP_WAIT
    rts

_send_fail:
    lda #$00
    sta CONNECT_ACTIVE
    lda #CONN_FAILED
    rts

_already_up:
    lda #CONN_CONNECTED
    rts

_report_only:
    jmp ETH_CONNECT_POLL          ; reuse the polling logic to build A

CONNECT_SET_ARP_QUERY:
    jsr ETH_CHECK_SAME_NET
    bne _connect_use_remote

    ldx #$03
_connect_cpy_gw:
    lda GATEWAY_IP,x
    sta ARP_QUERY_IP,x
    dex
    bpl _connect_cpy_gw
    rts

_connect_use_remote:
    ldx #$03
_connect_cpy_rem:
    lda REMOTE_IP,x
    sta ARP_QUERY_IP,x
    dex
    bpl _connect_cpy_rem
    rts

CONNECT_SEND_SYN:
    lda #TCP_FLAG_SYN
    jsr ETH_BUILD_TCPIP_PACKET
    bcs _connect_syn_not_sent
    jsr ETH_PACKET_SEND
    bcs _connect_syn_not_sent
    inc CONNECT_SYN_TX_OK_DBG
    jsr TCP_SAVE_PEER_MAC

    lda #$01
    sta CONNECT_SYN_SENT
    lda #TCP_STATE_SYN_SENT
    sta TCP_STATE
    lda #CONNECT_SYN_RETRY_TICKS
    sta CONNECT_RETRY_TICKS
    jsr ARP_READ_RASTER
    lda ARP_CUR_RASTER_LO
    sta CONNECT_LAST_RASTER_LO
    lda ARP_CUR_RASTER_HI
    sta CONNECT_LAST_RASTER_HI
    clc
    rts

_connect_syn_not_sent:
    inc CONNECT_SYN_TX_FAIL_DBG
    sec
    rts

CONNECT_SYN_TICK:
    jsr CONNECT_FRAME_WRAP_TICK
    bcc _connect_syn_wait

    lda CONNECT_RETRY_TICKS
    beq _connect_syn_expired
    dec CONNECT_RETRY_TICKS
_connect_syn_wait:
    clc
    rts

_connect_syn_expired:
    lda CONNECT_RETRY_LEFT
    beq _connect_syn_timeout
    dec CONNECT_RETRY_LEFT
    lda #CONNECT_SYN_RETRY_TICKS
    sta CONNECT_RETRY_TICKS
    jsr CONNECT_SEND_SYN
    clc
    rts

_connect_syn_timeout:
    lda TCP_EVENT_FLAG
    ora #EV_CONNECT_FAIL
    sta TCP_EVENT_FLAG
    sec
    rts

;=============================================================================
; ETH_CONNECT_POLL
; Drive the connect attempt forward (ARP→SYN) and report status in A.
; Safe to call anytime (even when not connecting).
;=============================================================================
ETH_CONNECT_POLL:
    ; let mainline drain any deferred IRQ work
    jsr ETH_PROCESS_DEFERRED
    jsr ETH_RCV
    jsr ARP_RETRY_TICK
    jsr DNS_TICK

    lda CONNECT_ACTIVE
    beq _not_connecting

    ; failed earlier?
    lda CONNECT_FAIL_LATCH
    beq _chk_state
    jmp _fail

_chk_state:
    ; established?
    lda TCP_STATE
    cmp #TCP_STATE_ESTABLISHED
    bne _not_est
    jsr ETH_PROCESS_DEFERRED
    lda #$00
    sta CONNECT_ACTIVE
    sta CONNECT_SYN_SENT
    sta CONNECT_RETRY_TICKS
    sta CONNECT_RETRY_LEFT
    sta CONNECT_LAST_RASTER_LO
    sta CONNECT_LAST_RASTER_HI
    lda #CONN_CONNECTED
    rts

_not_est:
    ; If ARP finished and we haven’t sent SYN yet, send it now
    lda CONNECT_SYN_SENT
    beq _try_send_after_arp

    lda TCP_STATE
    cmp #TCP_STATE_SYN_SENT
    bne _inprog
    jsr CONNECT_SYN_TICK
    bcs _fail
    jmp _inprog

_try_send_after_arp:
    lda ETH_STATE
    cmp #ETH_STATE_ARP_WAITING
    beq _inprog                   ; still resolving MAC

    ; ARP done → verify cache then send SYN
    jsr CONNECT_SET_ARP_QUERY
    jsr ARP_QUERY_CACHE
    beq _inprog                   ; still not populated (rare)

    jsr CONNECT_SEND_SYN
    bcs _inprog     ; was: bcs _fail

_inprog:
    lda #CONN_IN_PROGRESS          ; start with IN_PROGRESS in A
    ldy CONNECT_SYN_SENT           ; if SYN has been sent, add that bit
    beq _no_syn
    ora #CONN_SYN_SENT
_no_syn:
    ldx ARP_STATE
    cpx #ARP_STATE_WAIT
    bne _ret
    ora #CONN_ARP_WAIT
_ret:
    rts

_fail:
    jsr CONNECT_SNAPSHOT_FAIL
    lda #$00
    sta CONNECT_ACTIVE
    sta CONNECT_SYN_SENT
    sta CONNECT_FAIL_LATCH
    sta CONNECT_RETRY_TICKS
    sta CONNECT_RETRY_LEFT
    sta CONNECT_LAST_RASTER_LO
    sta CONNECT_LAST_RASTER_HI
    lda #TCP_STATE_CLOSED
    sta TCP_STATE
    lda #CONN_FAILED
    rts

_not_connecting:
    ; Not in a connect attempt; reflect steady-state
    lda TCP_STATE
    cmp #TCP_STATE_ESTABLISHED
    beq _up
    lda #$00
    rts
_up:
    lda #CONN_CONNECTED
    rts

;=============================================================================
; ETH_CONNECT_CANCEL
; Abort an in-flight connect. Sends RST if a SYN was sent.
;=============================================================================
ETH_CONNECT_CANCEL:
    lda CONNECT_ACTIVE
    beq _done

    lda CONNECT_SYN_SENT
    beq _clear_only

    ; We sent SYN; send RST to abandon handshake
    lda #TCP_FLAG_RST
    jsr ETH_BUILD_TCPIP_PACKET
    bcc +
    jmp _clear_only               ; build failed → just clear
+   jsr ETH_PACKET_SEND

_clear_only:
    lda #$00
    sta CONNECT_ACTIVE
    sta CONNECT_SYN_SENT
    sta CONNECT_FAIL_LATCH
    sta CONNECT_RETRY_TICKS
    sta CONNECT_RETRY_LEFT
    sta CONNECT_LAST_RASTER_LO
    sta CONNECT_LAST_RASTER_HI
    lda #TCP_STATE_CLOSED
    sta TCP_STATE
_done:
    lda #$00
    rts

;=============================================================================
; In: TCP_LISTEN_PORT_HI/LO must be set by caller
;=============================================================================
ETH_TCP_LISTEN_START:

    sta TCP_LISTEN_PORT
    sta LOCAL_PORT
    stx TCP_LISTEN_PORT+1
    stx LOCAL_PORT+1

    ; only if no active connection in progress
    lda TCP_STATE
    cmp #TCP_STATE_CLOSED
    bne _busy_fail

    lda #0
    sta TCP_ACCEPT_FLAGS        ; clear accepted/fail
    lda #1
    sta TCP_LISTEN_ENABLED      ; go LISTEN
    jsr TCP_TX_RESET

    ; clean RX/TX rings (optional but safest for “fresh” accept)
    ;jsr RBUF_RESET_RX
    ;jsr RBUF_RESET_TX

    rts
_busy_fail:
    lda #2
    sta TCP_ACCEPT_FLAGS      ; fail bit set for poller (bit1)
    rts

;=============================================================================
; A: bit0=accepted, bit1=failed (same style as your connect poll)
;=============================================================================
ETH_ACCEPT_POLL:
    lda TCP_ACCEPT_FLAGS
    rts

;=============================================================================
; Stop listening
;=============================================================================
ETH_TCP_LISTEN_STOP:
    lda #$00
    sta TCP_LISTEN_ENABLED
    rts

;=============================================================================
; Close a TCP connection
;=============================================================================
ETH_TCP_DISCONNECT:

    lda TCP_STATE
    cmp #TCP_STATE_ESTABLISHED
    bne _not_connected

    lda #TCP_FLAG_FIN|TCP_FLAG_ACK
    jsr ETH_BUILD_TCPIP_PACKET
    bcs _not_connected
    jsr ETH_PACKET_SEND
    bcs _not_connected

    jsr CALC_LOCAL_ISN

    lda #TCP_STATE_FIN_WAIT_1
    sta TCP_STATE

_not_connected:
    rts

;=============================================================================
; Queue payload for TCP send
;=============================================================================
ETH_TCP_SEND:

    lda TCP_STATE
    cmp #TCP_STATE_ESTABLISHED
    bne _not_connected

    jsr TCP_TX_ENQUEUE_CURRENT
    bcs _not_connected

    jsr CLEAR_TCP_PAYLOAD

    ; Give the stack a chance to send immediately when no segment is in flight.
    ; If TX is busy, the queued data remains pending for ETH_STATUS_POLL.
    jsr TCP_TX_TICK
    clc
    rts

_not_connected:
    jsr CLEAR_TCP_PAYLOAD
    sec
    rts

;=============================================================================
; Send BASIC A$ over TCP
;=============================================================================
; currently (!) 2 char variables start at $0F740
;  2 bytes for var name, $24 for string, then byte count, then <address and 
;  >address in bank 1
;
; single char variables start at $0FD60.  each three bytes is a letter of the
; alphabet ($FD60 for A$, $FD63 for B$, $FD66 for c$ etc).
; the three bytes are size, <addr, >addr (bank 1)
; 
; so IF TX$ exists, we will copy its data to the outgoing buffer and send it

ETH_TCP_SEND_STRING:

    php
    sei

    lda TCP_STATE
    cmp #TCP_STATE_ESTABLISHED
    beq _connected

_exit:
    plp
    rts

_connected:
    ; get size of A$ if defined
    FAR_PEEK $00, $FD60

    ; if zero length, exit
    beq _exit

    cmp #TCP_PAYLOAD_MAX+1
    bcc _tcp_len_ok
    lda #TCP_PAYLOAD_MAX
_tcp_len_ok:

    ; stash size otherwise
    sta _var_len
    lda #$00
    sta _var_len+1            ; DMA length MSB = 0

    ; get address
    FAR_PEEK $00, $FD61
    sta _var_addr

    FAR_PEEK $00, $FD62
    sta _var_addr+1

    ; now we will get the bytes and put them in the payload
    lda _var_len
    sta TCP_DATA_PAYLOAD_SIZE
    lda #$00
    sta TCP_DATA_PAYLOAD_SIZE+1

    ; use DMA to copy the bytes
    lda #$00
    sta $D707
    .byte $80                                   ; enhanced dma - src bits 20-27
    .byte $00   ; src hi
    .byte $81                                   ; enhanced dma - dest bits 20-27
    .byte $00   ; dest hi
    .byte $00                                   ; end of job options
    .byte $00                                   ; copy
_var_len:                                   
    .byte $00 ; <\length,
    .byte $00 ; >\length                    ; length lsb, msb
_var_addr:
    .byte $00, $00, $01                     ; src lsb, msb, bank 1 for string var data
_dest_addr:
    .byte <TCP_DATA_PAYLOAD, >TCP_DATA_PAYLOAD, EXEC_BANK             ; dest lsb, msb, bank
    .byte $00                                   ; command high byte
    .word $0000                                 ; modulo (ignored)

    jsr SEND_TRANSLATE_PAYLOAD
    
    plp
    jmp ETH_TCP_SEND


;=============================================================================
; Process deferred ARP reply from mainline
;=============================================================================
ETH_PROCESS_DEFERRED:

    php
    sei
    ; ---- ACK first, if any ----
    lda ACK_REPLY_PENDING
    beq _check_arp

    lda #$00
    sta ACK_REPLY_PENDING

    lda ACK_REPLY_LEN_L
    ora ACK_REPLY_LEN_H
    beq _ack_done
    ldx ACK_REPLY_LEN_L
_ack_copy_back:
    dex
    lda ACK_REPLY_PACKET,x
    sta ETH_TX_FRAME_DEST_MAC,x
    cpx #$00
    bne _ack_copy_back

    lda ACK_REPLY_LEN_L
    sta ETH_TX_LEN_LSB
    lda ACK_REPLY_LEN_H
    sta ETH_TX_LEN_MSB

    jsr ETH_PACKET_SEND
_ack_done:

_check_arp:
    lda ARP_REPLY_PENDING
    beq _epd_done

    lda #$00
    sta ARP_REPLY_PENDING

    ldx #$3c
_epd_copy:
    dex
    lda ARP_REPLY_PACKET,x
    sta ETH_TX_FRAME_DEST_MAC,x
    cpx #$00
    bne _epd_copy
    
    lda #$3c
    sta ETH_TX_LEN_LSB
    lda #$00
    sta ETH_TX_LEN_MSB

    jsr ETH_PACKET_SEND

_epd_done:
    plp
    rts

;=============================================================================
; TCP state handler
; - Handles RST
; - ESTABLISHED: trims overlap, ignores future segs, copies only new bytes,
;   ACKs exactly what was stored
;=============================================================================
TCP_STATE_HANDLER:

    lda ETH_RX_TCP_FLAGS
    and #TCP_FLAG_RST
    beq _not_RST

    ; remote sent RST → tear down immediately
    lda TCP_STATE
    cmp #TCP_STATE_SYN_SENT
    beq _rst_accepted
    cmp #TCP_STATE_CLOSED
    beq _rst_ignore
    jsr TCP_SEQ_CMP_SEG_SEQ_REMOTE
    bne _rst_ignore

_rst_accepted:
    jsr TCP_HARD_RESET
    lda CONNECT_ACTIVE
    beq +
    lda CONNECT_SYN_SENT
    beq +
    lda #$01
    sta CONNECT_FAIL_LATCH
    lda TCP_EVENT_FLAG
    ora #EV_CONNECT_FAIL
    sta TCP_EVENT_FLAG
 +  rts

_rst_ignore:
    rts

_not_RST:

    lda TCP_STATE

    ;---------------------------------------------------------------------------
    ; ESTABLISHED
    ;---------------------------------------------------------------------------
_check_ESTABLISHED:
    cmp #TCP_STATE_ESTABLISHED
    bne _check_CLOSED

    jsr TCP_TX_ACK_CHECK

    ; If the peer is closing too (FIN), go handle that first
    lda ETH_RX_TCP_FLAGS
    and #TCP_FLAG_FIN
    beq _no_fin_in_established
    jsr TCP_SEQ_CMP_SEG_SEQ_REMOTE
    beq _fin_seq_ok_established
    jsr TCP_DEFER_DUP_ACK
    rts

_fin_seq_ok_established:
    jmp _got_FIN_IN_ESTABLISHED

    ; If the peer is closing too (FIN+ACK), go handle that first
    ;lda ETH_RX_TCP_FLAGS
    ;and #(TCP_FLAG_FIN|TCP_FLAG_ACK)
    ;cmp #(TCP_FLAG_FIN|TCP_FLAG_ACK)
    ;beq _got_FIN_IN_ESTABLISHED

_no_fin_in_established:
    ; If our final handshake ACK was lost, the peer may retransmit SYN|ACK
    ; even though we have moved to ESTABLISHED. ip65 ACKs that again.
    lda ETH_RX_TCP_FLAGS
    and #(TCP_FLAG_SYN|TCP_FLAG_ACK)
    cmp #(TCP_FLAG_SYN|TCP_FLAG_ACK)
    bne _not_retx_synack
    lda TCP_RX_DATA_PAYLOAD_SIZE
    ora TCP_RX_DATA_PAYLOAD_SIZE+1
    bne _not_retx_synack
    lda #$00
    sta TCP_DATA_PAYLOAD_SIZE
    sta TCP_DATA_PAYLOAD_SIZE+1
    lda #TCP_FLAG_ACK
    jsr ETH_BUILD_TCPIP_PACKET
    bcs _est_done
    jsr DEFER_CURRENT_TX
    rts

_not_retx_synack:
    ; Any payload?
    lda TCP_RX_DATA_PAYLOAD_SIZE
    ora TCP_RX_DATA_PAYLOAD_SIZE+1
    beq _est_done
    
    ; ----------------- bounded critical section for copy -----------------
    php
    sei

    ; remaining := payload size (16-bit)
    lda TCP_RX_DATA_PAYLOAD_SIZE
    sta RX_COPY_REM_LO
    lda TCP_RX_DATA_PAYLOAD_SIZE+1
    sta RX_COPY_REM_HI

    ; ----------------- compare SEG.SEQ vs RCV.NXT (REMOTE_ISN) -----------------
    jsr TCP_SEQ_CMP_SEG_SEQ_REMOTE
    bmi _seg_in_past         ; SEG.SEQ <  RCV.NXT -> overlap on left
    beq _seg_in_order        ; SEG.SEQ == RCV.NXT -> in-order
    ; SEG.SEQ > RCV.NXT → out-of-order future → dup-ACK current RCV.NXT
_seg_in_future:
    lda #$00
    sta TCP_RX_DATA_PAYLOAD_SIZE
    sta TCP_RX_DATA_PAYLOAD_SIZE+1
    lda #$00
    sta REMOTE_ISN_BUMP
    jsr CALC_REMOTE_ISN            ; add 0 (keep RCV.NXT)
    lda #TCP_FLAG_ACK
    jsr ETH_BUILD_TCPIP_PACKET
    jsr DEFER_CURRENT_TX
    plp
    rts

_seg_in_past:
    ; SKIP := (RCV.NXT - SEG.SEQ) low 16 (clamp below)
    sec
    lda REMOTE_ISN+3
    sbc SEG_SEQ+3
    sta SKIP_LO
    lda REMOTE_ISN+2
    sbc SEG_SEQ+2
    sta SKIP_HI

    ; If SKIP >= seg_len → whole segment duplicate → dup-ACK and return
    lda SKIP_HI
    cmp RX_COPY_REM_HI
    bcc _have_tail
    bne _dup_entire
    lda SKIP_LO
    cmp RX_COPY_REM_LO
    bcc _have_tail
_dup_entire:
    lda #$00
    sta TCP_RX_DATA_PAYLOAD_SIZE
    sta TCP_RX_DATA_PAYLOAD_SIZE+1
    lda #$00
    sta REMOTE_ISN_BUMP
    jsr CALC_REMOTE_ISN
    lda #TCP_FLAG_ACK
    jsr ETH_BUILD_TCPIP_PACKET
    jsr DEFER_CURRENT_TX
    plp
    rts

_have_tail:
    ; remaining := seg_len - SKIP
    lda RX_COPY_REM_LO
    sec
    sbc SKIP_LO
    sta RX_COPY_REM_LO
    lda RX_COPY_REM_HI
    sbc SKIP_HI
    sta RX_COPY_REM_HI

    ; reader base := ETH_RX_FRAME_PAYLOAD + TCP_DATA_OFFSET + SKIP
    lda TCP_DATA_OFFSET
    clc
    adc SKIP_LO
    sta OFF_LO
    lda #$00
    adc SKIP_HI
    sta OFF_HI

    lda #<ETH_RX_FRAME_PAYLOAD
    clc
    adc OFF_LO
    sta _payload_read+1
    lda #>ETH_RX_FRAME_PAYLOAD
    adc OFF_HI
    sta _payload_read+2
    ldy #$00
    jmp _copy_setup_done

_seg_in_order:
    ; reader base := ETH_RX_FRAME_PAYLOAD + TCP_DATA_OFFSET
    lda #<ETH_RX_FRAME_PAYLOAD
    clc
    adc TCP_DATA_OFFSET
    sta _payload_read+1
    lda #>ETH_RX_FRAME_PAYLOAD
    adc #$00
    sta _payload_read+2
    ldy #$00

_copy_setup_done:
    ; Track how many bytes we actually store this pass
    lda #$00
    sta RX_CONSUMED_LO
    sta RX_CONSUMED_HI

    ; ------------------ copy loop ------------------
_lp_copy_data:
    lda RX_COPY_REM_LO
    ora RX_COPY_REM_HI
    beq _ack_what_we_took

    jsr RBUF_IS_FULL
    bcs _ack_what_we_took          ; ring full → ACK only consumed

_payload_read:
    .byte $B9, $00, $00            ; LDA abs,Y (operands patched above)
    phy
    jsr RBUF_PUT                   ; (RBUF_PUT returns C=1 if full; we prechecked)
    ply
    bcs _ack_what_we_took

_byte_consumed:
    ; consumed++
    inc RX_CONSUMED_LO
    bne _no_carry_cons
    inc RX_CONSUMED_HI

_no_carry_cons:
    ; advance source pointer
    iny
    bne _no_page
    inc _payload_read+2            ; crossed page

_no_page:
    ; remaining--
    sec
    lda RX_COPY_REM_LO
    sbc #1
    sta RX_COPY_REM_LO
    lda RX_COPY_REM_HI
    sbc #0
    sta RX_COPY_REM_HI

    ; any left?
    lda RX_COPY_REM_LO
    ora RX_COPY_REM_HI
    bne _lp_copy_data       ; Check if high byte went negative

    ; ------------------ ACK exactly what we took ------------------
_ack_what_we_took:
    ; Make CALC_REMOTE_ISN add “consumed” bytes only
    lda RX_CONSUMED_LO
    sta TCP_RX_DATA_PAYLOAD_SIZE
    lda RX_CONSUMED_HI
    sta TCP_RX_DATA_PAYLOAD_SIZE+1

    lda #$00
    sta REMOTE_ISN_BUMP
    jsr CALC_REMOTE_ISN            ; RCV.NXT += consumed

    ; Build a pure ACK (no data)
    lda #$00
    sta TCP_DATA_PAYLOAD_SIZE
    sta TCP_DATA_PAYLOAD_SIZE+1

    lda #TCP_FLAG_ACK
    jsr ETH_BUILD_TCPIP_PACKET
    
    ; Copy the built frame into a side buffer and flag it for mainline
    ; Clamp frame size to buffer limit
    lda ETH_TX_LEN_LSB
    ldx ETH_TX_LEN_MSB
    cpx #0                   ; High byte non-zero?
    bne _clamp_to_60         ; Yes, definitely > 60
    cmp #61                  ; Check low byte
    bcc _size_ok             ; < 61, we're good
    
_clamp_to_60:
    lda #60
    ldx #0
    
_size_ok:
    sta ACK_REPLY_LEN_L
    stx ACK_REPLY_LEN_H
    tax                      ; X = length for copy
    beq _ack_defer_done

_ack_defer_copy:
    dex
    lda ETH_TX_FRAME_DEST_MAC,x
    sta ACK_REPLY_PACKET,x
    cpx #$00
    bne _ack_defer_copy

    lda #$01
    sta ACK_REPLY_PENDING

_ack_defer_done:
    plp
    rts


_got_FIN_IN_ESTABLISHED:
    ; peer wants to close → ACK their FIN
    lda #$01
    sta REMOTE_ISN_BUMP
    jsr CALC_REMOTE_ISN              ; +1 for the FIN
    lda #$00
    sta REMOTE_ISN_BUMP

    lda #TCP_FLAG_ACK
    jsr ETH_BUILD_TCPIP_PACKET
    jsr DEFER_CURRENT_TX

    ; move into CLOSE_WAIT so application can call disconnect
    lda #TCP_STATE_CLOSE_WAIT
    sta TCP_STATE

    lda TCP_EVENT_FLAG
    ora #EV_PEER_FIN
    sta TCP_EVENT_FLAG
    rts

_est_done:
    rts

    ;---------------------------------------------------------------------------
    ; CLOSED
    ;---------------------------------------------------------------------------
_check_CLOSED:
    ; if closed, nothing to do. return
    cmp #TCP_STATE_CLOSED
    bne _check_SYN
    rts

    ;---------------------------------------------------------------------------
    ; SYN-SENT (await SYN+ACK)
    ;---------------------------------------------------------------------------
_check_SYN:
    cmp #TCP_STATE_SYN_SENT
    bne _check_FIN_WAIT_1

    lda ETH_RX_TCP_FLAGS
    and #(TCP_FLAG_SYN|TCP_FLAG_ACK)
    cmp #(TCP_FLAG_SYN|TCP_FLAG_ACK)
    bne _done

_got_SYNACK:
    inc CONNECT_SYNACK_RX_DBG

    ; SYN-ACK must acknowledge our SYN (LOCAL_ISN + 1).
    lda LOCAL_ISN+0
    sta CONNECT_EXPECT_ACK+0
    lda LOCAL_ISN+1
    sta CONNECT_EXPECT_ACK+1
    lda LOCAL_ISN+2
    sta CONNECT_EXPECT_ACK+2
    lda LOCAL_ISN+3
    sta CONNECT_EXPECT_ACK+3
    inc CONNECT_EXPECT_ACK+3
    bne _synack_ack_ready
    inc CONNECT_EXPECT_ACK+2
    bne _synack_ack_ready
    inc CONNECT_EXPECT_ACK+1
    bne _synack_ack_ready
    inc CONNECT_EXPECT_ACK+0

_synack_ack_ready:
    ldx #$00
_synack_ack_check:
    lda SEG_ACK,x
    cmp CONNECT_EXPECT_ACK,x
    bne _synack_bad_ack
    inx
    cpx #$04
    bne _synack_ack_check

    ; server's ISN is in SEG_SEQ (set by INCOMING_TCP_PACKET)
    lda SEG_SEQ+0
    sta REMOTE_ISN+0
    lda SEG_SEQ+1
    sta REMOTE_ISN+1
    lda SEG_SEQ+2
    sta REMOTE_ISN+2
    lda SEG_SEQ+3
    sta REMOTE_ISN+3

    ; consume the peer's SYN
    lda #$01
    sta REMOTE_ISN_BUMP
    jsr CALC_REMOTE_ISN
    lda #$00
    sta REMOTE_ISN_BUMP

    ; The SYN we sent consumes 1 sequence number
    inc LOCAL_ISN+3
    bne _got_SYNACK_ahead
    inc LOCAL_ISN+2
    bne _got_SYNACK_ahead
    inc LOCAL_ISN+1
    bne _got_SYNACK_ahead
    inc LOCAL_ISN+0

_got_SYNACK_ahead:
    ; build & send the final ACK
    lda #TCP_FLAG_ACK
    jsr ETH_BUILD_TCPIP_PACKET
    bcs _done
    jsr DEFER_CURRENT_TX

    ; handshake complete
    lda #TCP_STATE_ESTABLISHED
    sta TCP_STATE
    lda #$00
    sta TCP_EVENT_FLAG
    rts

_synack_bad_ack:
    inc CONNECT_SYNACK_BAD_ACK_DBG
    jmp _done

    ;---------------------------------------------------------------------------
    ; FIN-WAIT-1
    ;---------------------------------------------------------------------------
_check_FIN_WAIT_1:
    cmp #TCP_STATE_FIN_WAIT_1
    bne _check_FIN_WAIT_2

    lda ETH_RX_TCP_FLAGS
    and #TCP_FLAG_ACK
    cmp #TCP_FLAG_ACK
    bne _done
    jsr TCP_SEQ_CMP_SEG_SEQ_REMOTE
    beq _fin_wait_1_seq_ok
    jsr TCP_DEFER_DUP_ACK
    jmp _done

_fin_wait_1_seq_ok:
    jsr TCP_SEQ_CMP_SEG_ACK_LOCAL_ISN
    bne _done

_got_FIN_WAIT_1_ACK:
    lda #TCP_STATE_FIN_WAIT_2
    sta TCP_STATE
    jmp _done

    ;---------------------------------------------------------------------------
    ; FIN-WAIT-2
    ;---------------------------------------------------------------------------
_check_FIN_WAIT_2:
    ; await the FIN/ACK
    cmp #TCP_STATE_FIN_WAIT_2
    bne _check_TIME_WAIT

    ; await the FIN (ACK may or may not be set)
    lda ETH_RX_TCP_FLAGS
    and #TCP_FLAG_FIN
    beq _done
    jsr TCP_SEQ_CMP_SEG_SEQ_REMOTE
    beq _fin_wait_2_seq_ok
    jsr TCP_DEFER_DUP_ACK
    jmp _done

_fin_wait_2_seq_ok:

    ;lda ETH_RX_TCP_FLAGS
    ;and #(TCP_FLAG_FIN|TCP_FLAG_ACK)
    ;cmp #(TCP_FLAG_FIN|TCP_FLAG_ACK)
    ;bne _done

_got_FIN_ACK:
    ; consume the peer's FIN (+1 on remote sequence)
    lda #$01
    sta REMOTE_ISN_BUMP
    jsr CALC_REMOTE_ISN
    lda #$00
    sta REMOTE_ISN_BUMP

    ; send final ACK
    lda #TCP_FLAG_ACK
    jsr ETH_BUILD_TCPIP_PACKET
    bcs _done
    jsr DEFER_CURRENT_TX

    ; reset TIME_WAIT counter
    lda #$02
    sta TIME_WAIT_COUNTER_HI
    lda #$58
    sta TIME_WAIT_COUNTER_LO

    lda #TCP_STATE_TIME_WAIT
    sta TCP_STATE

    lda TCP_EVENT_FLAG
    ora #EV_LOCAL_CLOSE
    sta TCP_EVENT_FLAG
    jmp _done

    ;---------------------------------------------------------------------------
    ; TIME-WAIT
    ;---------------------------------------------------------------------------
_check_TIME_WAIT:
    cmp #TCP_STATE_TIME_WAIT
    bne _check_CLOSE_WAIT
    jsr TIME_WAIT_TICK
    rts

    ;---------------------------------------------------------------------------
    ; CLOSE-WAIT
    ;---------------------------------------------------------------------------
_check_CLOSE_WAIT:
    cmp #TCP_STATE_CLOSE_WAIT
    bne _check_LAST_ACK

    ; build & send FIN+ACK
    lda #TCP_FLAG_FIN|TCP_FLAG_ACK
    jsr ETH_BUILD_TCPIP_PACKET
    bcs _done
    jsr DEFER_CURRENT_TX
    jsr CALC_LOCAL_ISN
    ; move to LAST_ACK
    lda #TCP_STATE_LAST_ACK
    sta TCP_STATE
    rts

    ;---------------------------------------------------------------------------
    ; LAST-ACK
    ;---------------------------------------------------------------------------
_check_LAST_ACK:
    cmp #TCP_STATE_LAST_ACK
    bne _check_SYN_RCVD

    lda ETH_RX_TCP_FLAGS
    and #TCP_FLAG_ACK
    cmp #TCP_FLAG_ACK
    bne _done
    jsr TCP_SEQ_CMP_SEG_SEQ_REMOTE
    beq _last_ack_seq_ok
    jsr TCP_DEFER_DUP_ACK
    jmp _done

_last_ack_seq_ok:
    jsr TCP_SEQ_CMP_SEG_ACK_LOCAL_ISN
    bne _done

    ; peer ACK’d your FIN, now go TIME_WAIT
    lda #$02
    sta TIME_WAIT_COUNTER_HI
    lda #$58
    sta TIME_WAIT_COUNTER_LO

    lda #TCP_STATE_TIME_WAIT
    sta TCP_STATE

    ;---------------------------------------------------------------------------
    ; SYN-RECEIVED (server waiting for final ACK)
    ;---------------------------------------------------------------------------
_check_SYN_RCVD:
    cmp #TCP_STATE_SYN_RECEIVED
    bne _done

    ; Expect a pure ACK (no SYN/FIN/RST), payload len 0
    lda ETH_RX_TCP_FLAGS
    and #(TCP_FLAG_ACK | TCP_FLAG_SYN | TCP_FLAG_FIN | TCP_FLAG_RST)
    cmp #TCP_FLAG_ACK
    bne _done

    ; Optional sanity: require zero payload
    lda TCP_RX_DATA_PAYLOAD_SIZE
    ora TCP_RX_DATA_PAYLOAD_SIZE+1
    bne _done

    jsr TCP_SEQ_CMP_SEG_SEQ_REMOTE
    bne _done

    ldx #$00
_synrcvd_ack_check:
    lda SEG_ACK,x
    cmp LOCAL_ISN,x
    bne _done
    inx
    cpx #$04
    bne _synrcvd_ack_check

    ; Handshake complete
    lda #TCP_STATE_ESTABLISHED
    sta TCP_STATE

    ; Report accept once
    lda TCP_ACCEPT_FLAGS
    ora #$01
    sta TCP_ACCEPT_FLAGS

    ; Single-slot server: stop listening now
    lda #$00
    sta TCP_LISTEN_ENABLED

    rts

_done:
    rts

; ================================================================================
; Defers a duplicate ACK using the current receive-next value.
; ================================================================================
TCP_DEFER_DUP_ACK:
    lda #$00
    sta TCP_RX_DATA_PAYLOAD_SIZE
    sta TCP_RX_DATA_PAYLOAD_SIZE+1
    sta TCP_DATA_PAYLOAD_SIZE
    sta TCP_DATA_PAYLOAD_SIZE+1
    sta REMOTE_ISN_BUMP
    jsr CALC_REMOTE_ISN
    lda #TCP_FLAG_ACK
    jsr ETH_BUILD_TCPIP_PACKET
    bcs _tcp_defer_dup_ack_done
    jsr DEFER_CURRENT_TX

_tcp_defer_dup_ack_done:
    rts

; ================================================================================
; Defers transmit until out of IRQ
; ================================================================================
DEFER_CURRENT_TX:
    lda ETH_TX_LEN_LSB
    ldx ETH_TX_LEN_MSB
    cpx #$00
    bne _clamp
    cmp #61
    bcc _len_ok
_clamp:
    lda #60
    ldx #$00
_len_ok:
    sta ACK_REPLY_LEN_L
    stx ACK_REPLY_LEN_H

    ldx ACK_REPLY_LEN_L
    beq _done
_copy:
    dex
    lda ETH_TX_FRAME_DEST_MAC,x
    sta ACK_REPLY_PACKET,x
    cpx #0
    bne _copy
    lda #$01
    sta ACK_REPLY_PENDING
_done
    rts

;=============================================================================
; TIME_WAIT_TICK
; Called every 100 ms while in TIME_WAIT. Decrements the 16-bit counter,
; and when it hits zero, moves TCP_STATE to CLOSED.
;=============================================================================
TIME_WAIT_TICK:
    sec                         ; prepare carry for SBC
    lda TIME_WAIT_COUNTER_LO
    sbc #1                      ; decrement low byte
    sta TIME_WAIT_COUNTER_LO

    lda TIME_WAIT_COUNTER_HI
    sbc #0                      ; subtract borrow into high byte
    sta TIME_WAIT_COUNTER_HI

    ; if counter ≠ 0 yet, just return
    lda TIME_WAIT_COUNTER_LO
    ora TIME_WAIT_COUNTER_HI
    bne _done

    ; counter reached zero → close the socket
    lda #TCP_STATE_CLOSED
    sta TCP_STATE

    ; notify BASIC that TIME_WAIT ended
    lda TCP_EVENT_FLAG
    ora #EV_TIMEWAIT_DONE
    sta TCP_EVENT_FLAG

_done:
    rts

.include "rbuf.asm"

;=============================================================================
; Ethernet clear to send
;=============================================================================
ETH_WAIT_CLEAR_TO_SEND:
    ldx #$00
    ldy #$00
_cts_spin:
    lda MEGA65_ETH_CTRL1
    and #$80
    bne _cts_ready
    dey
    bne _cts_spin
    dex
    bne _cts_spin
    sec
    rts
_cts_ready:
    clc
    rts

;=============================================================================
; Routine to copy packet in TX buffer to Ethernet buffer and do transmit
;=============================================================================
ETH_PACKET_SEND:

    ; mega65 IO enable
    jsr MEGA65_IO_ENABLE

    ; Ethernet frames must be at least 60 bytes before the FCS. The IP length
    ; remains unchanged; these bytes are link-layer padding.
    lda ETH_TX_LEN_MSB
    bne _tx_len_ready
    lda ETH_TX_LEN_LSB
    cmp #$3c
    bcs _tx_len_ready
    tax
    lda #$00
_pad_min_frame:
    sta ETH_TX_FRAME_HEADER,x
    inx
    cpx #$3c
    bne _pad_min_frame
    lda #$3c
    sta ETH_TX_LEN_LSB

_tx_len_ready:
    lda ETH_TX_LEN_LSB
    sta MEGA65_ETH_TXSIZE_LSB
    sta _len_lsb
    lda ETH_TX_LEN_MSB
    sta MEGA65_ETH_TXSIZE_MSB
    sta _len_msb

    lda #<ETH_TX_FRAME_HEADER
    sta _ETH_BUF_SRC
    lda #>ETH_TX_FRAME_HEADER
    sta _ETH_BUF_SRC+1

php
sei
    ; inline DMA to copy our buffer to TX buffer
    sta $D707
    .byte $80          ; enhanced DMA: SRC bits 20–27
    .byte $00    ; = $04   ← ensure source is bank $04 (your code/data bank)

    .byte $81                   ; enhanced dma - dest bits 20-27
    .byte $ff                   ; ----------------------^
    .byte $00                   ; end of job options
    .byte $00                   ; copy
_len_lsb:
    .byte $00                   ; length lsb
_len_msb:
    .byte $00                   ; length msb
_ETH_BUF_SRC:
    .byte $00, $00, EXEC_BANK   ; src lsb, msb, bank
    .byte $00, $e8, $0d         ; dest eth TX/RX buffer ($ffde800)
    .byte $00                   ; command high byte
    .word $0000                 ; modulo (ignored)
plp

    ; make sure ethernet is not under reset
    lda #$03
    sta MEGA65_ETH_CTRL1

    ; be sure we can send
    jsr ETH_WAIT_CLEAR_TO_SEND
    bcs _tx_fail
    ; transmit now
    lda #$01
    sta MEGA65_ETH_COMMAND
    clc
    rts
_tx_fail:
    sec
    rts

;=============================================================================
; Wait a sec..
;=============================================================================
ETH_WAIT_100MS:

    ldx #>1600                  ; high byte
    ldy #<1600                  ; low byte

_wait_outer
    lda MEGA65_VICII_RSTR_CMP  ; read initial raster line
    sta tmp_raster             ; store it

-   lda MEGA65_VICII_RSTR_CMP
    cmp tmp_raster
    beq -                       ; loop until raster changes

    dey
    bne _wait_outer
    dex
    bne _wait_outer

    rts

;=============================================================================
; Routine compares LOCAL_IP and REMOTE_IP via SUBNET_MASK to
; determine if they are on the same network
;=============================================================================
ETH_CHECK_SAME_NET:

    ldx #$03
_compare_net:
    lda REMOTE_IP, x
    and SUBNET_MASK, x
    sta _tmp_oct

    lda LOCAL_IP, x
    and SUBNET_MASK, x
    cmp _tmp_oct
    bne _not_same_net

    dex
    bpl _compare_net

    lda #$01            ; same network (use Remote IP)
    rts

_not_same_net:
    lda #$00            ; not same network (use Gateway IP)
    rts

_tmp_oct: .byte $00


;=============================================================================
; Builds a TCP packet
; Parameters:
;   A=TCP flags (SYN/FIN/etc)
;=============================================================================
ETH_BUILD_TCPIP_PACKET:

    pha                             ; push the TCP_FLAG to stack

    lda TCP_STATE                   ; dont do a ARP if we already are connected
    cmp #TCP_STATE_ESTABLISHED
    beq _use_tcp_peer_mac

    ; we need to check if we are on the same net to send the packet to.
    ; if we are, then we just need to check the arp cache for the mac address
    ; of the machine on the same net.  Otherwise, we use the mac address of
    ; the gateway.

    ; if a non-blocking connect is in progress, don't ARP or spin here.
    ;lda CONNECT_ACTIVE
    ;beq _do_arp_request             ; not connecting => old behavior ok (your tooling)

    jsr ETH_CHECK_SAME_NET
    beq _use_gateway

_use_remote:
    lda REMOTE_IP+0
    sta ARP_QUERY_IP+0
    lda REMOTE_IP+1
    sta ARP_QUERY_IP+1
    lda REMOTE_IP+2
    sta ARP_QUERY_IP+2
    lda REMOTE_IP+3
    sta ARP_QUERY_IP+3
    jsr ARP_QUERY_CACHE
    bne _IP_found_in_cache 
    jmp _no_mac_yet
    
_use_gateway:
    lda GATEWAY_IP+0
    sta ARP_QUERY_IP+0
    lda GATEWAY_IP+1
    sta ARP_QUERY_IP+1
    lda GATEWAY_IP+2
    sta ARP_QUERY_IP+2
    lda GATEWAY_IP+3
    sta ARP_QUERY_IP+3
    jsr ARP_QUERY_CACHE
    bne _IP_found_in_cache

    ; ---- no MAC yet: start ARP (if needed) and return NOT READY ----
_no_mac_yet:
    ; If we aren't already waiting, mark waiting and kick ARP
    lda ETH_STATE
    cmp #ETH_STATE_ARP_WAITING
    beq _already_waiting

    lda #ETH_STATE_ARP_WAITING
    sta ETH_STATE

    ldx #3
-   lda ARP_QUERY_IP,x
    sta ARP_REQUEST_IP,x
    dex
    bpl -

    jsr ARP_REQUEST

_already_waiting:
    pla                 ; restore A if the caller pushed it earlier
    sec                 ; C=1 → not ready; caller must retry later
    rts


_use_tcp_peer_mac:
    jsr TCP_RESTORE_PEER_MAC
    jmp _IP_found_in_cache

_IP_found_in_cache:
    
    lda #$08                        ; Ipv4 ethertype
    sta ETH_TX_TYPE
    lda #$00
    sta ETH_TX_TYPE+1

    lda #$06                        ; IPV4 header with TCP protocol ($06)
    jsr BUILD_IPV4_HEADER

    pla                             ; get FLAGS from incoming param
    jsr BUILD_TCP_HEADER

    ; calc total frame size
    lda #<(14+20+20)                ; 14=Eth, 20=IP, 20=TCP (no payload)
    sta ETH_TX_LEN_LSB
    lda #>(14+20+20)
    sta ETH_TX_LEN_MSB

    lda TCP_DATA_PAYLOAD_SIZE       ; now add any TCP payload size
    clc
    adc ETH_TX_LEN_LSB
    sta ETH_TX_LEN_LSB
    lda ETH_TX_LEN_MSB
    adc #$00
    sta ETH_TX_LEN_MSB
    
    clc
    rts

.include "checksum.asm"
.include "ipv4.asm"

;=============================================================================
; Sets up a full IPv4 packet
; Parameters:
;   A= tcp flags (TCP_SYN, TCP_FIN, etc)
;=============================================================================
BUILD_TCP_HEADER:

    sta TCP_HDR_FLGS_OFFS+1                     ; TCP FLAGS

    ; first 4 bits determine tcp header size. each bit means 4 bytes
    ; 1010 = 5  ...  5x4 = 20 tcp header size (min)
    ; 1111 = 15 ... 15x4 = 60 tcp header size (max)
    ; final 4 bits are reserved, leave zero
    lda #%01010000                                  
    sta TCP_HDR_FLGS_OFFS

    ; Save the actual TCP header size for checksum calculation
    lda #20                          ; Default 20 bytes (no options)
    sta TCP_HEADER_SIZE              ; Add this variable

    ; copy ephimeral and remote ports
    lda LOCAL_PORT+0                
    sta TCP_HDR_SRC_PORT+0
    lda LOCAL_PORT+1
    sta TCP_HDR_SRC_PORT+1

    lda REMOTE_PORT+0
    sta TCP_HDR_DST_PORT+0
    lda REMOTE_PORT+1
    sta TCP_HDR_DST_PORT+1

    ; ---- compute free = (TAIL - HEAD - 1) mod 1024 ----
    jsr READ_HEAD_ATOMIC
    jsr READ_TAIL_ATOMIC

    ; free := (TAIL - HEAD - 1) mod 1024
    sec
    lda TMP_TAIL_LO
    sbc TMP_HEAD_LO
    sta FREE_LO
    lda TMP_TAIL_HI
    sbc TMP_HEAD_HI
    and #$07                          ; 11-bit pages 0..7
    sta FREE_HI

    ; subtract 1 (mod 1024)
    sec
    lda FREE_LO
    sbc #1
    sta FREE_LO
    lda FREE_HI
    sbc #0
    and #$07
    sta FREE_HI

    ; Write TCP window (16-bit, network order high:low in your struct)
    lda FREE_HI
    sta TCP_HDR_WINDOW
    lda FREE_LO
    sta TCP_HDR_WINDOW+1

    ; Remember what we advertised (16-bit)
    sta ADV_WINDOW_LAST_LO
    lda FREE_HI
    sta ADV_WINDOW_LAST_HI

    ; copy LOCAL_ISN into TCP Header Sequence Number
    lda LOCAL_ISN+0
    sta TCP_HDR_SEQ_NUM+0
    lda LOCAL_ISN+1
    sta TCP_HDR_SEQ_NUM+1
    lda LOCAL_ISN+2
    sta TCP_HDR_SEQ_NUM+2
    lda LOCAL_ISN+3
    sta TCP_HDR_SEQ_NUM+3

    ; copy the REMOTE_ISN into the TCP header’s Ack field
    lda REMOTE_ISN+0
    sta TCP_HDR_ACK_NUM+0
    lda REMOTE_ISN+1
    sta TCP_HDR_ACK_NUM+1
    lda REMOTE_ISN+2
    sta TCP_HDR_ACK_NUM+2
    lda REMOTE_ISN+3
    sta TCP_HDR_ACK_NUM+3


    ; If payload length is odd, write a 0 pad byte so checksum sees 0, not junk
    ldy TCP_DATA_PAYLOAD_SIZE
    tya
    and #$01
    beq _no_pad
    lda #$00
    sta TCP_DATA_PAYLOAD,y
    iny
_no_pad:
    ; TCP_DATA_PAYLOAD_WORD_COUNT = (size + 1) >> 1
    tya
    lsr
    sta TCP_DATA_PAYLOAD_WORD_COUNT

    jsr CALC_TCP_CHECKSUM
    
    ; copy header to buffer
    ldx #$00
_lp_copy:
    lda TCP_HDR, x
    sta ETH_TX_FRAME_PAYLOAD+20, x
    inx 
    cpx #20
    bne _lp_copy

    ; copy data to buffer
    ldx #$00
_lp_data_copy:
    cpx TCP_DATA_PAYLOAD_SIZE
    beq _lp_done
    lda TCP_DATA_PAYLOAD, x
    sta ETH_TX_FRAME_PAYLOAD+20+20, x
    inx
    jmp _lp_data_copy

_lp_done:
    rts

WINUPDATE_THRESHOLD = $01    ; send update when we open by ≥1 bytes

WINUPDATE_GROW_LO = $00
WINUPDATE_GROW_HI = $01

; we will max our data payload at 235 bytes which is small, but
; fits well with BASIC string sizes (tcp header = 20 + 235 = 255)
TCP_DATA_PAYLOAD_SIZE:
.byte $00
.byte $00

TCP_HEADER_SIZE:
.byte $00

TCP_DATA_PAYLOAD_WORD_COUNT:
.byte $00

TCP_PSEUDO_HDR:
.byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

TCP_HDR:
TCP_HDR_SRC_PORT:   .byte $00, $00
TCP_HDR_DST_PORT:   .byte $00, $00
TCP_HDR_SEQ_NUM:    .byte $00, $00, $00, $00
TCP_HDR_ACK_NUM:    .byte $00, $00, $00, $00
TCP_HDR_FLGS_OFFS:  .byte $00, $00
TCP_HDR_WINDOW:     .byte $00, $00
TCP_HDR_CHKSM:      .byte $00, $00
TCP_HDR_URGNT:      .byte $00, $00

; max size of 235 bytes. One extra pad byte lets checksum handle odd lengths.
TCP_DATA_PAYLOAD:
.byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
.byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
.byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
.byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
.byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
.byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
.byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
.byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
.byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
.byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
.byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
.byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
.byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
.byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
.byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

TCP_DATA_PAYLOAD_PAD:
.byte $00

;=============================================================================
; Routine to calculate the tcp checksum
;=============================================================================
CALC_TCP_CHECKSUM:

    ; clear results
    lda #$00
    sta _reslo
    sta _reshi
    sta _resex

    ; 1) Zero out the checksum field
    lda #$00
    sta TCP_HDR_CHKSM
    lda #$00
    sta TCP_HDR_CHKSM+1

    ; copy data to the ip pseudo header
    lda IPV4_HDR_SRC_IP+0
    sta TCP_PSEUDO_HDR+0
    lda IPV4_HDR_SRC_IP+1
    sta TCP_PSEUDO_HDR+1
    lda IPV4_HDR_SRC_IP+2
    sta TCP_PSEUDO_HDR+2
    lda IPV4_HDR_SRC_IP+3
    sta TCP_PSEUDO_HDR+3
    lda IPV4_HDR_DST_IP+0
    sta TCP_PSEUDO_HDR+4
    lda IPV4_HDR_DST_IP+1
    sta TCP_PSEUDO_HDR+5
    lda IPV4_HDR_DST_IP+2
    sta TCP_PSEUDO_HDR+6
    lda IPV4_HDR_DST_IP+3
    sta TCP_PSEUDO_HDR+7
    lda #$00
    sta TCP_PSEUDO_HDR+8
    lda IPV4_HDR_PROTO
    sta TCP_PSEUDO_HDR+9

    ; tcp header size
    lda #$00
    sta TCP_PSEUDO_HDR+10
    lda TCP_HEADER_SIZE
    sta TCP_PSEUDO_HDR+11
    
    ; add size of data payload
    lda TCP_DATA_PAYLOAD_SIZE
    clc
    adc TCP_PSEUDO_HDR+11
    sta TCP_PSEUDO_HDR+11
    lda #$00
    adc TCP_PSEUDO_HDR+10
    sta TCP_PSEUDO_HDR+10

    ; calculate tcp data word count (word count = byte count / 2)
    lda TCP_DATA_PAYLOAD_SIZE
    clc
    adc #1                          ; A = byte_count + 1
    lsr                             ; A = (byte_count + 1) >> 1
    sta TCP_DATA_PAYLOAD_WORD_COUNT ; store the word count in one byte

    ; set starting summation value
    ldy #$00                        ; Y = offset into pseudo header (0,2,4,...)
    lda TCP_PSEUDO_HDR,y            ; init summation result
    sta _reshi
    iny
    lda TCP_PSEUDO_HDR,y
    sta _reslo

    ; Sum each word in the pseudo header
    ldx #$05                ; x=5 (countdown of words)
_loop_pseudo_header
    lda _reslo              ; store add result back into num1
    sta _num1lo
    lda _reshi
    sta _num1hi

    iny
    lda TCP_PSEUDO_HDR,Y    ; get hi byte of next value
    sta _num2hi
    iny
    lda TCP_PSEUDO_HDR,Y    ; get lo byte of next value
    sta _num2lo
    jsr _addwords           ; add them to prev result

    dex                     ; x--
    bne _loop_pseudo_header ; if x <> 0 then loop again

_sum_tcp_hdr:
    ; Calculate word count from TCP_HEADER_SIZE
    lda TCP_HEADER_SIZE
    lsr                              ; Divide by 2 to get word count
    tax                              ; x = word count
    ldy #$00

_loop_tcp_header:
    lda _reslo              ; store add result back into num1
    sta _num1lo
    lda _reshi
    sta _num1hi

    lda TCP_HDR,y           ; hi
    sta _num2hi
    iny
    lda TCP_HDR,y           ; lo
    sta _num2lo
    iny
    jsr _addwords           ; add to prev result

    dex                     ; x--
    bne _loop_tcp_header    ; if x<>0 then loop again

_sum_tcp_data:

    lda TCP_DATA_PAYLOAD_WORD_COUNT
    beq _add_overflow        ; no data to sum, go finish up

    tax                     ; x = word count
    ldy #$00                ; y = 0 (each byte)

_loop_tcp_data:
    lda _reslo              ; store add result back into num1
    sta _num1lo
    lda _reshi
    sta _num1hi

    lda TCP_DATA_PAYLOAD,y  ; hi
    sta _num2hi
    iny
    lda TCP_DATA_PAYLOAD,y  ; lo
    sta _num2lo
    iny
    jsr _addwords           ; add to prev result

    dex                     ; x--
    bne _loop_tcp_data      ; if x <> 0 loop again

_add_overflow:
    lda _reslo               ; add overflow byte 24 back into the result
    sta _num1lo
    lda _reshi
    sta _num1hi
    lda _resex
    clc
    adc _num1lo
    sta _num1lo
    lda _num1hi
    adc #$00
    sta _num1hi

    ; end-around carry if that addition overflowed
    bcc _no_final_carry     ; if no carry from the high-byte add, skip
    inc _num1lo             ; add the end-around carry back in
    bne _no_final_carry
    inc _num1hi

_no_final_carry:
    lda _num1lo              ; move result to 2nd value
    sta _num2lo
    lda _num1hi
    sta _num2hi
    lda #$ff                ; subtract value from $ffff
    sta _num1lo
    sta _num1hi
    jsr _subwords           ; final in _reslo/_reshi

    lda _reshi
    sta TCP_HDR_CHKSM
    lda _reslo
    sta TCP_HDR_CHKSM+1

    rts

_addwords	
    clc				; clear carry
	lda _num1lo
	adc _num2lo
	sta _reslo			; store sum of LSBs
	lda _num1hi
	adc _num2hi			; add the MSBs using carry from
	sta _reshi			; the previous calculation
    lda _resex
    adc #$00
    sta _resex
    rts

_subwords:
    lda #$00
    sta _reslo
    sta _reshi
    sta _resex

    sec				    ; set carry for borrow purpose
	lda _num1lo
	sbc _num2lo			; perform subtraction on the LSBs
	sta _reslo
	lda _num1hi			; do the same for the MSBs, with carry
	sbc _num2hi			; set according to the previous result
	sta _reshi
	rts

_num1lo: .byte $00
_num1hi: .byte $00
_num2lo: .byte $00
_num2hi: .byte $00
_reslo: .byte $00
_reshi: .byte $00
_resex: .byte $00

;=============================================================================
;
;=============================================================================
CLEAR_LOCAL_ISN:
    lda #$00
    sta LOCAL_ISN+0
    sta LOCAL_ISN+1
    sta LOCAL_ISN+2
    sta LOCAL_ISN+3
    sta LOCAL_ISN_TMP
    rts

;=============================================================================
;
;=============================================================================
CLEAR_REMOTE_ISN:
    lda #$00
    sta REMOTE_ISN+0
    sta REMOTE_ISN+1
    sta REMOTE_ISN+2
    sta REMOTE_ISN+3
    sta REMOTE_ISN_TMP
    sta REMOTE_ISN_TMP+1
    rts

;=============================================================================
;
;=============================================================================
CLEAR_TCP_PAYLOAD:
    lda #$00
    ldy #$00
_lp_copy:
    sta TCP_DATA_PAYLOAD,Y
    cpy #234
    beq _done
    iny
    jmp _lp_copy

_done:
    sta TCP_DATA_PAYLOAD_SIZE
    sta TCP_DATA_PAYLOAD_SIZE+1
    rts

; =============================================================================
; Calculates the sequence number depending on state
; =============================================================================
CALC_LOCAL_ISN:
    ; decide if we should bump LOCAL_ISN:
    ;  • Always bump if we’re finalizing the handshake (state = SYN_SENT)
    ;  • Or if this packet carries PSH (data) or FIN
    lda TCP_STATE
    cmp #TCP_STATE_SYN_SENT
    beq _add_one                        ; handshake‐ACK must consume the SYN

    cmp #TCP_STATE_ESTABLISHED          ; dont change seq # if not established
    bne _done

    lda TCP_HDR_FLGS_OFFS+1
    and #TCP_FLAG_FIN
    bne _add_one                        ; if FIN present, add 1

    lda TCP_HDR_FLGS_OFFS+1
    and #TCP_FLAG_PSH
    bne _add_payload_size               ; if PSH or FIN present, do bump

    lda TCP_HDR_FLGS_OFFS+1
    cmp #TCP_FLAG_ACK
    beq _done                        ; if it’s _exactly_ ACK, skip bump

_add_payload_size:
    ; get payload size to add
    lda TCP_DATA_PAYLOAD_SIZE
    sta LOCAL_ISN_TMP
    jmp _update_seq

_add_one:
    lda #$01
    sta LOCAL_ISN_TMP

_update_seq:

    ; 2) add that sum into the low byte of LOCAL_ISN
    lda LOCAL_ISN+3
    clc
    adc LOCAL_ISN_TMP
    sta LOCAL_ISN+3

    ; 3) ripple any carry into the upper bytes
    lda LOCAL_ISN+2
    adc #$00
    sta LOCAL_ISN+2
    lda LOCAL_ISN+1
    adc #$00
    sta LOCAL_ISN+1
    lda LOCAL_ISN+0
    adc #$00
    sta LOCAL_ISN+0

_done:
    rts

;=============================================================================
; CALC_REMOTE_ISN
;   Advances 32-bit REMOTE_ISN by (A + received_payload_length).
;   Uses TCP_RX_DATA_PAYLOAD_SIZE computed above.
;   Only called when a frame is recieved
;=============================================================================
CALC_REMOTE_ISN:

    ; 1) Compute 16-bit (received_size + 1) into REMOTE_ISN_TMP
    lda TCP_RX_DATA_PAYLOAD_SIZE
    clc
    adc REMOTE_ISN_BUMP
    sta REMOTE_ISN_TMP            ; low byte
    lda TCP_RX_DATA_PAYLOAD_SIZE+1
    adc #$00
    sta REMOTE_ISN_TMP+1         ; high byte

    ; 2) add that sum into the low byte of REMOTE_ISN
    lda REMOTE_ISN+3
    clc
    adc REMOTE_ISN_TMP
    sta REMOTE_ISN+3
    ; next byte:
    lda REMOTE_ISN+2
    adc REMOTE_ISN_TMP+1
    sta REMOTE_ISN+2
    ; ripple into remaining:
    lda REMOTE_ISN+1
    adc #$00
    sta REMOTE_ISN+1
    lda REMOTE_ISN+0
    adc #$00
    sta REMOTE_ISN+0
    rts

REMOTE_ISN_BUMP:
    .byte $00

;=============================================================================
; CALC_RX_TCP_BYTE_COUNT
;   Computes the TCP payload length of the received frame and
;   stores the 16-bit result into TCP_RX_DATA_PAYLOAD_SIZE (little-endian).
;   Expects: ETH_RX_FRAME_PAYLOAD points at first IP header byte.
;=============================================================================
CALC_RX_TCP_BYTE_COUNT:

    ; ----- IP header length (bytes) from Version/IHL -----
    lda ETH_RX_FRAME_PAYLOAD+0     ; Version(4) | IHL(4)
    and #$0f                       ; IHL (words)
    asl                            ; *2
    asl                            ; *4 -> bytes (20..60)
    sta _TMP_IP_HDR_LEN

    ; clamp [20..60]
    lda _TMP_IP_HDR_LEN
    cmp #20
    bcs _ip_ge20
    lda #20
_ip_ge20
    cmp #60
    bcc _ip_ok
    lda #60
_ip_ok
    sta _TMP_IP_HDR_LEN

    ; ----- TCP header length (bytes) from DataOffset nibble -----
    ; Read byte at (IP base + IHL*4 + 12)
    lda #<ETH_RX_FRAME_PAYLOAD+12
    clc
    adc _TMP_IP_HDR_LEN
    sta _rd_off_nib+1
    lda #>ETH_RX_FRAME_PAYLOAD+12
    adc #$00
    sta _rd_off_nib+2

_rd_off_nib:
    .byte $AD, $00, $00            ; LDA $0000 (patched above to IP+IHL*4+12)
    and #$F0                       ; DataOffset (high nibble, words)
    lsr
    lsr
    lsr
    lsr                            ; -> words (5..15)
    asl
    asl                            ; *4 -> bytes (20..60)
    sta _TMP_TCP_HDR_LEN

    ; clamp [20..60]
    lda _TMP_TCP_HDR_LEN
    cmp #20
    bcs _tcp_ge20
    lda #20
_tcp_ge20
    cmp #60
    bcc _tcp_ok
    lda #60
_tcp_ok
    sta _TMP_TCP_HDR_LEN

    ; ----- Total header bytes for later payload start -----
    lda _TMP_IP_HDR_LEN
    clc
    adc _TMP_TCP_HDR_LEN
    sta TCP_DATA_OFFSET            ; (non-ZP byte you define in .bss/.data)

    ; ----- IP Total Length (network order at +2/+3) -----
    ; Build: tmp = IP_TOTAL_LEN - IP_HDR_LEN
    lda ETH_RX_FRAME_PAYLOAD+3     ; total len LSB
    sec
    sbc _TMP_IP_HDR_LEN
    sta _tmp_len_lo
    lda ETH_RX_FRAME_PAYLOAD+2     ; total len MSB
    sbc #$00
    sta _tmp_len_hi

    ; Then subtract TCP_HDR_LEN:  payload = tmp - TCP_HDR_LEN
    lda _tmp_len_lo
    sec
    sbc _TMP_TCP_HDR_LEN
    sta TCP_RX_DATA_PAYLOAD_SIZE       ; LSB
    lda _tmp_len_hi
    sbc #$00
    sta TCP_RX_DATA_PAYLOAD_SIZE+1     ; MSB
    bcs _done                           ; carry=1 → no borrow → non-negative

    ; underflow → clamp to zero (defensive)
    lda #$00
    sta TCP_RX_DATA_PAYLOAD_SIZE
    sta TCP_RX_DATA_PAYLOAD_SIZE+1

_done
    rts

; ---- local scratch in normal RAM (not ZP) ----
_tmp_len_lo:       .byte 0
_tmp_len_hi:       .byte 0


_TMP_LO:
    .byte $00
_TMP_HI:
    .byte $00

_TMP_IP_HDR_LEN:
    .byte $00

_TMP_TCP_HDR_LEN:
    .byte $00

; total bytes from start of IP header to start of TCP payload
TCP_DATA_OFFSET: 
    .byte $00   

;=============================================================================
; Tear everything down on RST (or fatal error)
;=============================================================================
TCP_HARD_RESET:
    ; state
    lda #$00
    sta ETH_RX_TCP_FLAGS

    lda #$00
    sta TIME_WAIT_COUNTER_LO
    sta TIME_WAIT_COUNTER_HI

    lda #$00
    sta LOCAL_ISN_TMP
    jsr CLEAR_REMOTE_ISN

    ; flush RX ring (optional, but avoids BASIC reading stale bytes)
    lda RBUF_HEAD_HI
    sta RBUF_TAIL_HI
    lda RBUF_HEAD_LO
    sta RBUF_TAIL_LO
    jsr TCP_TX_RESET

    ; mark closed
    lda #$00
    sta ETH_STATE            ; if you use it for TX/RX gate
    lda #TCP_STATE_CLOSED
    sta TCP_STATE

    lda #$00
    sta REMOTE_ISN_BUMP

    lda #$00
    sta TCP_DATA_PAYLOAD_SIZE
    sta TCP_DATA_PAYLOAD_SIZE+1

    ; notify BASIC: set a sticky event flag it can poll
    ; bit0 = RST seen
    lda TCP_EVENT_FLAG
    ora #$01
    sta TCP_EVENT_FLAG
    rts

TCP_EVENT_FLAG
    .byte $00

;=============================================================================
; ETH_STATUS_POLL
; - Flush deferred TX (ACK/ARP) so IRQ never has to send
; - If we previously advertised a 0 window and we’ve freed space,
;   send a pure ACK to wake the peer (ETH_MAYBE_WINUPDATE)
; - Advance TIME_WAIT
; - If any events are latched, return them (and clear)
; - Otherwise return 0=connected/ok, 1=disconnected
;=============================================================================
ETH_STATUS_POLL:
    ; 1) Do non-IRQ work first
    jsr ETH_PROCESS_DEFERRED
    
    ; check for an handle any incoming packets
    jsr ETH_RCV
    lda TCP_STATE
    cmp #TCP_STATE_ESTABLISHED
    bne _skip_tcp_tx_tick
    jsr TCP_TX_TICK
_skip_tcp_tx_tick:
    jsr ARP_RETRY_TICK
    jsr DNS_TICK
    jsr ETH_MAYBE_WINUPDATE

    ; 2) Let TIME_WAIT progress while BASIC polls
    lda TCP_STATE
    cmp #TCP_STATE_TIME_WAIT
    bne _check_events
    jsr TIME_WAIT_TICK

_check_events:
    lda TCP_EVENT_FLAG
    beq _check_state          ; no events → fall through
    pha
    lda #$00
    sta TCP_EVENT_FLAG        ; clear sticky bits after read
    pla
    rts

_check_state:
    ; 0 = connected/normal
    ; 1 = disconnected/closed
    lda TCP_STATE
    cmp #TCP_STATE_ESTABLISHED
    beq _connected
    cmp #TCP_STATE_CLOSED
    beq _disconnected

    ; transitional states → treat as "ok" (0) for the poller
    lda #$00
    rts

_connected:
    lda #$00
    rts

_disconnected:
    lda #$01
    rts

;=============================================================================
; Computes free = (TAIL - HEAD - 1) mod 1024 (10-bit),
; and if last advertised window was 0 and free >= threshold,
; sends a pure ACK to wake the sender.  No zero-page used.
;=============================================================================
ETH_MAYBE_WINUPDATE:

    lda TCP_STATE
    cmp #TCP_STATE_ESTABLISHED
    bne _ret                    ; only while connected

    lda REMOTE_IP
    ora REMOTE_IP+1
    ora REMOTE_IP+2
    ora REMOTE_IP+3
    beq _ret                    ; don’t send if peer IP unknown

    lda REMOTE_PORT
    ora REMOTE_PORT+1
    beq _ret                    ; don’t send if peer port unknown

    ; ---- cur_free = (TAIL - HEAD - 1) mod 1024 ----
    jsr READ_HEAD_ATOMIC              ; fills TMP_HEAD_LO/TMP_HEAD_HI
    jsr READ_TAIL_ATOMIC              ; fills TMP_TAIL_LO/TMP_TAIL_HI

    lda TMP_TAIL_LO
    sec
    sbc TMP_HEAD_LO
    sta _cur_free_lo
    lda TMP_TAIL_HI
    sbc TMP_HEAD_HI
    and #$07
    sta _cur_free_hi

    ; cur_free -= 1
    sec
    lda _cur_free_lo
    sbc #1
    sta _cur_free_lo
    lda _cur_free_hi
    sbc #0
    and #$07
    sta _cur_free_hi

    ; if free == 0, there is nothing useful to advertise
    lda _cur_free_lo
    ora _cur_free_hi
    beq _ret

    ; Always update after a zero-window advertisement.
    lda ADV_WINDOW_LAST_LO
    ora ADV_WINDOW_LAST_HI
    beq _send_update

    ; Otherwise only update if current free > last advertised window.
    lda _cur_free_hi
    cmp ADV_WINDOW_LAST_HI
    bcc _ret
    bne _cur_gt_last
    lda _cur_free_lo
    cmp ADV_WINDOW_LAST_LO
    bcc _ret
    beq _ret

_cur_gt_last:
    ; delta = cur_free - last_advertised; require >= threshold.
    sec
    lda _cur_free_lo
    sbc ADV_WINDOW_LAST_LO
    sta _win_delta_lo
    lda _cur_free_hi
    sbc ADV_WINDOW_LAST_HI
    sta _win_delta_hi

    lda _win_delta_hi
    cmp #WINUPDATE_GROW_HI
    bcc _ret
    bne _send_update
    lda _win_delta_lo
    cmp #WINUPDATE_GROW_LO
    bcc _ret
    jmp _send_update

    ; ---- Only act if we last advertised 0 ----
    lda ADV_WINDOW_LAST_LO
    ora ADV_WINDOW_LAST_HI
    bne _ret                           ; last adv wasn’t zero → nothing to do

    ; if free == 0 → nothing to send
    lda _cur_free_lo
    ora _cur_free_hi
    beq _ret

    ; require at least a small opening (hysteresis)
    lda _cur_free_lo                   ; low byte compare is fine with threshold=1
    cmp #WINUPDATE_THRESHOLD
    bcc _ret

_send_update:
    ; ---- Build & send pure ACK (no data) to advertise the new window ----
    lda #$00
    sta TCP_DATA_PAYLOAD_SIZE
    sta TCP_DATA_PAYLOAD_SIZE+1
    lda #TCP_FLAG_ACK
    jsr ETH_BUILD_TCPIP_PACKET
    bcs _ret
    jsr ETH_PACKET_SEND
    bcs _ret

    ; This cumulative ACK supersedes any older deferred TCP ACK.
    lda #$00
    sta ACK_REPLY_PENDING

    ; Record what we *actually* advertised (also set in BUILD_TCP_HEADER on future TX)
    lda _cur_free_lo
    sta ADV_WINDOW_LAST_LO
    lda _cur_free_hi
    sta ADV_WINDOW_LAST_HI

_ret:
    rts

; locals (not zero-page)
_cur_free_lo: .byte 0
_cur_free_hi: .byte 0
_win_delta_lo: .byte 0
_win_delta_hi: .byte 0


.include "arp.asm"
.include "dns.asm"
.include "dhcp.asm"

;=============================================================================
; Initiate a DNS lookup request
;=============================================================================
ETH_DNS_LOOKUP:

    ; A$ should contain the host name to lookup
    jsr COPY_ASTR_TO_DNS_HOST

DNS_LOOKUP_HOSTSTR:

    ; Kick a new lookup
    lda #<host_str
    ldx #>host_str
    jsr DNS_RESOLVE_START
    bcs DNS_LOOKUP_FAIL       ; carry set means input label too long etc.

    ; Poll until done/fail (drive your normal net pollers in the loop)
DNS_LOOKUP_WAIT:
    jsr DNS_POLL              ; A = 0 idle, 1 wait, 2 done, 3 fail
    cmp #DNS_STATE_DONE
    beq DNS_LOOKUP_RESOLVED
    cmp #DNS_STATE_FAIL
    beq DNS_LOOKUP_FAIL

    ; your regular network polling (must include DNS_TICK and RX processing)
    jsr ETH_STATUS_POLL       ; or your driver tick, which calls DNS_TICK
    ;jsr ETH_RCV              ; must end up calling DNS_UDP_IN for UDP frames
    jmp DNS_LOOKUP_WAIT

DNS_LOOKUP_RESOLVED:
    ; IPv4 result is here:
    ;   DNS_RESULT_IP[0..3]
    lda DNS_RESULT_IP+0
    sta REMOTE_IP+0
    lda DNS_RESULT_IP+1
    sta REMOTE_IP+1
    lda DNS_RESULT_IP+2
    sta REMOTE_IP+2
    lda DNS_RESULT_IP+3
    sta REMOTE_IP+3
    ; ... use it (open TCP/UDP to that IP, etc.)
    ; Optional: you can start another resolve immediately with DNS_RESOLVE_START
    lda #$01
    rts

DNS_LOOKUP_FAIL:
    lda #$00
    sta REMOTE_IP+0
    sta REMOTE_IP+1
    sta REMOTE_IP+2
    sta REMOTE_IP+3
    ; handle failure (timeout, truncated, invalid, etc.)
    lda #$00
    rts

;=============================================================================
; Check state of the DNS lookup
;=============================================================================
ETH_GET_DNS_STATE:
    lda DNS_STATE
    rts

;=============================================================================
; Copy A$ to the DNS HOST buffer (host_str) for lookup
;=============================================================================
COPY_ASTR_TO_DNS_HOST:

    ; get size of A$ if defined
    FAR_PEEK $00, $FD60

    ; if zero length, exit
    beq _exit

    cmp #DNS_HOST_BUFFER_SIZE
    bcc _dns_len_ok
    lda #DNS_HOST_MAX
_dns_len_ok:

    ; stash size otherwise
    sta _var_len
    lda #$00
    sta _var_len+1            ; DMA length MSB = 0

    ; get address
    FAR_PEEK $00, $FD61
    sta _var_addr

    FAR_PEEK $00, $FD62
    sta _var_addr+1

    ; now we will get the bytes and put them in the payload
    ; IF DNS LOOKUP BREAKS, PUT THIS BACK IN.  IT DOESNT SEEM TO MAKE SENSE HERE
;    lda _var_len
;    sta TCP_DATA_PAYLOAD_SIZE
;    lda #$00
;    sta TCP_DATA_PAYLOAD_SIZE+1

    ; use DMA to copy the bytes
    lda #$00
    sta $D707
    .byte $80                                   ; enhanced dma - src bits 20-27
    .byte $00   ; src hi
    .byte $81                                   ; enhanced dma - dest bits 20-27
    .byte $00   ; dest hi
    .byte $00                                   ; end of job options
    .byte $00                                   ; copy
_var_len:                                   
    .byte $00 ; <\length,
    .byte $00 ; >\length                    ; length lsb, msb
_var_addr:
    .byte $00, $00, $01                     ; src lsb, msb, bank 1 for string var data
_dest_addr:
    .byte <host_str, >host_str, EXEC_BANK             ; dest lsb, msb, bank
    .byte $00                                   ; command high byte
    .word $0000                                 ; modulo (ignored)
    
    ;lda _var_len
    ;clc
    ;adc #$01
    ;tay

    ; add zero to end of the string
    lda #$00
    ldy _var_len
    sta host_str, y

_exit:
    rts

;=============================================================================
; ETH_GET_DNS_RESULT_IP
; Returns the DNS result in a/x/y/z (useful for RREG A,X,Y,Z from BASIC)
;=============================================================================
ETH_GET_DNS_RESULT_IP:
    lda DNS_RESULT_IP
    ldx DNS_RESULT_IP+1
    ldy DNS_RESULT_IP+2
    ldz DNS_RESULT_IP+3
    rts

;=============================================================================
; Network recieve polling routine
;=============================================================================
ETH_RCV:
    jsr MEGA65_IO_ENABLE

    ; update ARP cache
    jsr ARP_CACHE_PURGE

    ; check if frame has been recieved
    lda MEGA65_ETH_CTRL2
    and #%00100000                  ; check RX bit for waiting frame
    bne _latch_frame
    rts

_latch_frame:

    ; --- Early filter using NIC’s 2 status bytes (before any DMA) ---
    ; Buffer layout per MEGA65 doc (per received frame):
    ;   +0 : length LSB
    ;   +1 : [bits 0..3: length MSB nibble]
    ;        bit4 = 1 → multicast
    ;        bit5 = 1 → broadcast
    ;        bit6 = 1 → unicast-to-me (matches MACADDR)
    ;        bit7 = 1 → CRC error (bad frame)

    LDA_FAR $ff, $0de800
    sta _len_lsb
    LDA_FAR $ff, $0de801
    sta RX_META1

    ; build 16 bit length from meta
    lda RX_META1
    and #$0F
    sta _len_msb

    ; drop zero length
    lda _len_msb
    ora _len_lsb
    bne _len_nonzero

    lda #$01
    sta MEGA65_ETH_CTRL2
    lda #$03
    sta MEGA65_ETH_CTRL2
    rts

_len_nonzero:

_chk_bad_crc:
    ; ---- Drop CRC-bad frames fast (bit7) ----
    lda RX_META1
    and #%10000000
    beq _chk_multicast

    lda #$01
    sta MEGA65_ETH_CTRL2
    lda #$03
    sta MEGA65_ETH_CTRL2
    rts

_chk_multicast:

    ; While DHCP is running, or LISTENer is active, dont filter multicast
    lda DHCP_IN_PROGRESS
    bne _chk_dest_ok

    lda TCP_LISTEN_ENABLED
    bne _chk_dest_ok
    
    ; ---- Drop multicast (bit4) ----
    lda RX_META1
    and #%00010000
    beq _chk_dest_ok

    lda #$01
    sta MEGA65_ETH_CTRL2
    lda #$03
    sta MEGA65_ETH_CTRL2
    rts

_chk_dest_ok:
    ; Do not trust the NIC's broadcast/unicast meta bits for final delivery.
    ; Copy the frame and verify the actual destination MAC below instead.
    jmp _accept_packet

_accept_packet:
inc DHCP_RX_ACCEPTS
    inc CONNECT_RAW_RX_DBG
    lda DNS_STATE
    cmp #DNS_STATE_WAIT
    bne +
    inc DNS_RAW_RX_COUNT
+
    ; --- subtract FCS (4 bytes), drop on underflow ---
    sec
    lda _len_lsb
    sbc #$04
    sta _len_lsb
    lda _len_msb
    sbc #$00
    sta _len_msb
    bcs _after_fcs                ; C=1 => no borrow
    ; underflow (len < 4) → drop
    lda #$01
    sta MEGA65_ETH_CTRL2
    lda #$03
    sta MEGA65_ETH_CTRL2
    rts

_after_fcs:
    ; --- drop runts: must be >= 14 (Ethernet header) ---
    lda _len_msb
    bne _ge14_ok
    lda _len_lsb
    cmp #$0E
    bcs _ge14_ok
    ; < 14 → drop
    lda #$01
    sta MEGA65_ETH_CTRL2
    lda #$03
    sta MEGA65_ETH_CTRL2
    rts

_ge14_ok:
    ; --- drop frames larger than our 14-byte header + 1600-byte payload buffer ---
    lda _len_msb
    cmp #$06
    bcc _do_copy                 ; < 0x0600 → safe
    bne _drop_oversize
    lda _len_lsb
    cmp #$4E                      ; == 0x06 → check low byte
    bcc _do_copy                 ; <= 0x064D → safe
_drop_oversize:
    lda #$01
    sta MEGA65_ETH_CTRL2
    lda #$03
    sta MEGA65_ETH_CTRL2
    rts

_do_copy:
    lda _len_lsb
    sta ETH_RX_FRAME_LEN_L
    sec
    sbc #14
    sta ETH_RX_PAYLOAD_LEN_L
    lda _len_msb
    sta ETH_RX_FRAME_LEN_H
    sbc #0
    sta ETH_RX_PAYLOAD_LEN_H

    php
    sei
    ; inline DMA to copy ethernet buffer to RX buffer
    sta $D707
    .byte $80                   ; enhanced dma - src bits 20-27
    .byte $ff                   ; ----------------------^
    .byte $00                   ; end of job options
    .byte $00                   ; copy
_len_lsb:
    .byte $00                   ; length lsb
_len_msb:
    .byte $00                   ; length msb
    .byte $02, $e8, $0d         ; src eth TX/RX buffer ($ffde802) (2nd byte, skipping length bytes)
    .byte <ETH_RX_FRAME_HEADER, >ETH_RX_FRAME_HEADER, EXEC_BANK   ; dest lsb, msb, bank
    .byte $00                   ; command high byte
    .word $0000                 ; modulo (ignored)

    plp

    lda #$01
    sta MEGA65_ETH_CTRL2
    lda #$03
    sta MEGA65_ETH_CTRL2

    ; verify dest mac or broadcast from the copied Ethernet header
    jsr ETH_IS_PACKET_FOR_US
    sta CONNECT_LAST_RX_DC_DBG
    inc CONNECT_COPY_RX_DBG
    lda ETH_RX_TYPE
    sta CONNECT_LAST_RX_TYPE_HI_DBG
    lda ETH_RX_TYPE+1
    sta CONNECT_LAST_RX_TYPE_LO_DBG
    lda ETH_RX_FRAME_PAYLOAD+9
    sta CONNECT_LAST_RX_PROTO_DBG
    lda CONNECT_LAST_RX_DC_DBG
    bne _chk_eth_type
    lda DNS_STATE
    cmp #DNS_STATE_WAIT
    bne _unknown_packet
    inc DNS_NOT_FOR_US_COUNT
    jmp _unknown_packet

_chk_eth_type:
    ; --- classify by EtherType first ---
    lda ETH_RX_TYPE
    cmp #$08
    bne _unknown_packet

    lda ETH_RX_TYPE+1
    cmp #$06                            ; is packet $0806 (ARP)?
    beq _is_arp
    cmp #$00                            ; is packet $0800 (IPv4)?
    beq _is_ipv4
    jmp _unknown_packet

_is_arp:
    ; OPER must be 0x0001 (request) or 0x0002 (reply)
    lda ETH_RX_FRAME_PAYLOAD+6          ; OPER MSB
    bne _unknown_packet                 ; reject non-zero MSB
    lda ETH_RX_FRAME_PAYLOAD+7          ; now A = OPER_hi|OPER_lo
    cmp #$01                            ; = 1 (request)?
    beq _call_arp_reply
    cmp #$02                            ; = 2 (reply)?
    beq _call_arp_update_cache
    rts                                 ; neither request nor reply → ignore

_call_arp_reply:
    jmp ARP_REPLY

_call_arp_update_cache:
    jmp ARP_UPDATE_CACHE

_is_ipv4:
    jsr IPV4_VALIDATE_RX
    bcs _unknown_packet

    lda DNS_STATE
    cmp #DNS_STATE_WAIT
    bne +
    inc DNS_IPV4_RX_COUNT
+
    ; IPv4 protocol dispatch
    lda ETH_RX_FRAME_HEADER+23         ; Protocol (14 + 9)
    cmp #IP_PROTO_ICMP                 ; ICMP?
    beq _call_incoming_icmp
    cmp #IP_PROTO_TCP                  ; TCP?
    beq _call_incoming_tcp
    cmp #IP_PROTO_UDP                  ; UDP?
    beq _udp_demux
    rts

_call_incoming_icmp:
    jmp ICMP_ECHO_REPLY

    ; --- UDP demux (DHCP first, then DNS) ---
_udp_demux:
    lda DNS_STATE
    cmp #DNS_STATE_WAIT
    bne +
    inc DNS_UDP_RX_COUNT
+
    ; Compute IHL in bytes: IHL field is low nibble of first IP byte, units of 4 bytes
    lda ETH_RX_FRAME_HEADER+14         ; Version/IHL at start of IP header
    and #$0F
    asl                                ; *4
    asl
    sta DHCP_IP_IHL_BYTES
    tay                                ; Y = IHL in bytes (typically 20)

    ; Check UDP destination port (at UDP header offset +2)
    lda ETH_RX_FRAME_PAYLOAD+2,y       ; dst port high
    cmp #>(UDP_PORT_DHCP_CLIENT)       ; 68
    bne _udp_maybe_dns
    lda ETH_RX_FRAME_PAYLOAD+3,y       ; dst port low
    cmp #<(UDP_PORT_DHCP_CLIENT)
    bne _udp_maybe_dns

    ; DHCP → handle and return
inc DHCP_UDP68_HITS    
    jsr DHCP_ON_UDP
    rts

_udp_maybe_dns:
    ; Not DHCP(68) — let your DNS handler decide (it already drops non-DNS)
    jmp DNS_UDP_IN

_call_incoming_tcp:
    jsr TCP_RX_CHECKSUM_OK
    bcs _unknown_packet

    inc CONNECT_TCP_DISPATCH_DBG
    lda ETH_RX_FRAME_PAYLOAD
    and #$0F
    asl
    asl
    tax
    lda ETH_RX_FRAME_PAYLOAD+0,x
    sta CONNECT_LAST_TCP_SRC_PORT_HI_DBG
    lda ETH_RX_FRAME_PAYLOAD+1,x
    sta CONNECT_LAST_TCP_SRC_PORT_LO_DBG
    lda ETH_RX_FRAME_PAYLOAD+2,x
    sta CONNECT_LAST_TCP_DST_PORT_HI_DBG
    lda ETH_RX_FRAME_PAYLOAD+3,x
    sta CONNECT_LAST_TCP_DST_PORT_LO_DBG
    lda ETH_RX_FRAME_PAYLOAD+13,x
    sta CONNECT_LAST_TCP_FLAGS_DBG
    ldx #$03
_tcp_dbg_ip:
    lda ETH_RX_FRAME_PAYLOAD+12,x
    sta CONNECT_LAST_TCP_SRC_IP_DBG,x
    dex
    bpl _tcp_dbg_ip
    jmp INCOMING_TCP_PACKET

_unknown_packet:
    rts

;=============================================================================
; Routine to check if packed in RX buffer is for this machine / IP
;=============================================================================
ETH_IS_PACKET_FOR_US:

    ; check if packet intended for us

    ldx #$06                            ; count = 6
_lp_mac_compare:
    dex
    lda ETH_TX_FRAME_SRC_MAC,x          ; local MAC byte
    cmp ETH_RX_FRAME_DEST_MAC,x
    bne _check_broadcast
    cpx #$00
    bne _lp_mac_compare
    lda #$01                            ; A=1 (Yes, dest mac is us)
    rts

_check_broadcast:
    ldx #$06
    lda #$ff
_lp_bcast:
    dex
    cmp ETH_RX_FRAME_DEST_MAC,x
    bne _not_ours
    cpx #$00
    bne _lp_bcast
    lda #$02                            ; A=2 (Yes, broadcast packet)    
    rts                        

_not_ours:
    lda #$00                            ; A=0 (no, packet not for us)
    rts

TCP_SAVE_PEER_MAC:
    ldx #$00
_save_mac:
    lda ETH_TX_FRAME_DEST_MAC,x
    sta TCP_PEER_MAC,x
    inx
    cpx #$06
    bne _save_mac
    lda #$01
    sta TCP_PEER_MAC_VALID
    rts

TCP_RESTORE_PEER_MAC:
    lda TCP_PEER_MAC_VALID
    beq _restore_done
    ldx #$00
_restore_mac:
    lda TCP_PEER_MAC,x
    sta ETH_TX_FRAME_DEST_MAC,x
    inx
    cpx #$06
    bne _restore_mac
_restore_done:
    rts

.include "icmp.asm"

.include "tcp.asm"

.include "tcp_tx.asm"

;=============================================================================
; Routine to convert A from ASCII to PETSCII
;=============================================================================
CHAR_TRANSLATE:
    jmp CHAR_TRANSLATE_IMPL

;=============================================================================
; Convert outgoing BASIC/PETSCII payload to ASCII when CHARACTER_MODE=1.
;=============================================================================
SEND_TRANSLATE_PAYLOAD:
    lda CHARACTER_MODE
    beq _send_xlate_done

    ldy #$00
_send_xlate_loop:
    cpy TCP_DATA_PAYLOAD_SIZE
    beq _send_xlate_done
    lda TCP_DATA_PAYLOAD,y
    jsr PETSCII_TO_ASCII
    sta TCP_DATA_PAYLOAD,y
    iny
    jmp _send_xlate_loop

_send_xlate_done:
    rts

PETSCII_TO_ASCII:
    cmp #$c1
    bcc _petscii_maybe_lower
    cmp #$db
    bcs _petscii_maybe_lower
    and #$7f
    rts

_petscii_maybe_lower:
    cmp #$41
    bcc _petscii_ascii_done
    cmp #$5b
    bcs _petscii_ascii_done
    ora #$20

_petscii_ascii_done:
    rts

.include "tcp_seq.asm"

;=============================================================================
; Temporary Storage
;=============================================================================
; BASIC samples peek a few values in this block for display/debugging.
; Keep the block fixed unless those samples are updated at the same time.
* = $4bf5
LOCAL_IP:               .byte 192, 168, 1, 75
LOCAL_PORT:             .byte $c0, $00              ; ephemeral port 49152
REMOTE_IP:              .byte 192, 168, 1, 1
REMOTE_PORT:            .byte $00, $17
GATEWAY_IP:             .byte 192, 168, 1, 1
SUBNET_MASK:            .byte $ff, $ff, $ff, $00
PRIMARY_DNS:            .byte 8, 8, 8, 8

ETH_STATE:              .byte $00                   ; current state of ethernet
TCP_STATE:              .byte $00

REMOTE_ISN:             .byte $00, $00, $00, $00
LOCAL_ISN:              .byte $00, $00, $00, $00
LOCAL_ISN_TMP:          .byte $00                   ; temp values for seq number and ack number calcs
REMOTE_ISN_TMP:         .byte $00, $00

CONNECT_ACTIVE:         .byte $00                   ; 1 while a connect attempt is active
CONNECT_SYN_SENT:       .byte $00                   ; 1 after we transmit SYN
CONNECT_FAIL_LATCH:     .byte $00                   ; set by IRQ on RST/abort, polled/cleared in CONNECT_POLL
CONNECT_RETRY_TICKS:    .byte $00
CONNECT_RETRY_LEFT:     .byte $00
CONNECT_LAST_RASTER_LO: .byte $00
CONNECT_LAST_RASTER_HI: .byte $00
CONNECT_EXPECT_ACK:     .byte $00, $00, $00, $00

TCP_LISTEN_PORT:        .byte $00, $00              ; ---- Passive-accept (single slot) ----
TCP_LISTEN_STATE:       .byte $00                   ; 0=idle, 1=LISTEN, 2=SYN_RCVD
TCP_ACCEPT_FLAGS:       .byte $00                   ; bit0=accepted, bit1=fail
TCP_LISTEN_ENABLED:     .byte $00                   ; 0=off, 1=on

RX_COPY_REM_LO:         .byte 0
RX_COPY_REM_HI:         .byte 0
RX_CONSUMED_LO:         .byte 0
RX_CONSUMED_HI:         .byte 0
SKIP_LO:                .byte 0
SKIP_HI:                .byte 0
OFF_LO:                 .byte 0
OFF_HI:                 .byte 0

ETH_RX_TCP_FLAGS:       .byte $00                   ; recieved tcp pack flags
ETH_TX_LEN_LSB:         .byte $00
ETH_TX_LEN_MSB:         .byte $00
ETH_RX_FRAME_LEN_L:     .byte $00                   ; copied Ethernet frame length, excluding FCS
ETH_RX_FRAME_LEN_H:     .byte $00
ETH_RX_PAYLOAD_LEN_L:   .byte $00                   ; copied Ethernet payload length, excluding header/FCS
ETH_RX_PAYLOAD_LEN_H:   .byte $00
TIME_WAIT_COUNTER_LO:   .byte $58                   ; 2×MSL = 60 s → 600 ticks of 100 ms → 0x0258
TIME_WAIT_COUNTER_HI:   .byte $02
CHARACTER_MODE:         .byte $00                   ; $00 = C= gfx (no translation), $01 = ASCII->PETSCII

ACK_REPLY_PENDING:      .byte 0
ACK_REPLY_LEN_L:        .byte 0
ACK_REPLY_LEN_H:        .byte 0
ACK_REPLY_PACKET:       .fill 60, $00               ; 60 bytes is enough (14+20+20), 60 gives slack

RBUF_HEAD_LO:           .byte 0
RBUF_HEAD_HI:           .byte 0                     ; 0..7
RBUF_TAIL_LO:           .byte 0
RBUF_TAIL_HI:           .byte 0                     ; 0..7

TMP_TAIL_LO:            .byte 0
TMP_TAIL_HI:            .byte 0
TMP_HEAD_LO:            .byte 0
TMP_HEAD_HI:            .byte 0
NEXT_LO:                .byte 0
NEXT_HI:                .byte 0
HLO:                    .byte 0
HHI:                    .byte 0
FREE_LO:                .byte 0
FREE_HI:                .byte 0

ADV_WINDOW_LAST_LO:     .byte 0
ADV_WINDOW_LAST_HI:     .byte 0

SEG_SEQ:                .byte 0,0,0,0
SEG_ACK:                .byte 0,0,0,0
RX_META1:               .byte $00
tmp_raster:             .byte 0
ICMP_LEN_LO:            .byte 0
ICMP_LEN_HI:            .byte 0
ICMP_SUM_LO:            .byte 0
ICMP_SUM_HI:            .byte 0
ICMP_WORD_LO:           .byte 0
ICMP_WORD_HI:           .byte 0

host_str:               .fill DNS_HOST_BUFFER_SIZE, $00

;=============================================================================
; TRANSMITTING FRAME BUFFER
;
; Ethernet frame structures
;
; Dest MAC  - Desitnation mac address   6 bytes
; Source MAX - MAC address of sender    6 bytes
; EtherType - protocol in payload       2 bytes  (eg 0x800 = IPv4, 0x0806 = ARP, 0x86dd = IPv6, 0x8100 = VLAN tagged frame)
; Payload - actual data                 46-1500
; FCS (CRC32) - frame check sequence    4 bytes (calculated and appended by NIC hardware, not software)
; 
; Min frame size = 64 bytes
; max payload = 1500 bytes
; max total frame = 1518 bytes without VLAN, 1522 with VLAN tag
;=============================================================================
ETH_TX_FRAME_HEADER:
ETH_TX_FRAME_DEST_MAC:
    .byte $ff, $ff, $ff, $ff, $ff, $ff
ETH_TX_FRAME_SRC_MAC:
    .byte $00, $00, $00, $00, $00, $00
ETH_TX_TYPE:
    .byte $08, $06
ETH_TX_FRAME_PAYLOAD:
    .fill 1600, $00

;=============================================================================
; RECIEVED FRAME BUFFER
;=============================================================================
ETH_RX_FRAME_HEADER:
ETH_RX_FRAME_DEST_MAC:
    .byte $00, $00, $00, $00, $00, $00
ETH_RX_FRAME_SRC_MAC:
    .byte $00, $00, $00, $00, $00, $00
ETH_RX_TYPE:
    .byte $00, $00
ETH_RX_FRAME_PAYLOAD:
    .fill 1600, $00
RX_CANARY:            
    .byte $C3, $3C  ; should never change!!
TCP_RX_DATA_PAYLOAD_SIZE:
    .byte $00, $00

;=============================================================================
; INCOMING DATA RING BUFFER
;=============================================================================

RING_BUFFER:
    .fill 2048, $00

;=============================================================================
; OUTGOING TCP DATA QUEUE
;=============================================================================

TXQ_HEAD:               .byte 0
TXQ_TAIL:               .byte 0
TXQ_COUNT:              .byte 0
TXQ_NEW_COUNT:          .byte 0
TXQ_ENQ_LEN:            .byte 0
TXQ_SEND_LEN:           .byte 0
TXQ_SCAN:               .byte 0

TX_UNACK_PENDING:       .byte 0
TX_UNACK_LEN:           .byte 0
TX_UNACK_RETRY_TICKS:   .byte 0
TX_UNACK_RETRY_LEFT:    .byte 0
TCP_TX_LAST_RASTER_LO:  .byte 0
TCP_TX_LAST_RASTER_HI:  .byte 0
TX_UNACK_SEQ:           .byte 0,0,0,0
TX_UNACK_EXPECT_ACK:    .byte 0,0,0,0
TX_SAVE_LOCAL_ISN:      .byte 0,0,0,0
TCP_PEER_MAC_VALID:     .byte 0
TCP_PEER_MAC:           .byte 0,0,0,0,0,0

TCP_TX_ENQUEUE_OK_DBG:  .byte 0
TCP_TX_SEND_OK_DBG:     .byte 0
TCP_TX_ACK_SEEN_DBG:    .byte 0
TCP_TX_ACK_MATCH_DBG:   .byte 0
TCP_TX_TIMEOUT_DBG:     .byte 0
TCP_TX_TIMEOUT_LEN_DBG: .byte 0
TCP_TX_TIMEOUT_RETRY_DBG: .byte 0
TCP_TX_SEND_FAIL_DBG:   .byte 0
TCP_TX_RETX_OK_DBG:     .byte 0
TCP_TX_RETX_FAIL_DBG:   .byte 0
TCP_TX_BASE_RAW_DBG:    .byte 0
TCP_TX_BASE_DISPATCH_DBG: .byte 0
TCP_TX_BASE_HANDLER_DBG: .byte 0
TCP_TX_LAST_ACK_DBG:    .byte 0,0,0,0
TCP_TX_TIMEOUT_EXPECT_DBG: .byte 0,0,0,0
TCP_TX_TIMEOUT_ACK_DBG: .byte 0,0,0,0

TX_APP_QUEUE:
    .fill 256, $00

TX_UNACK_PAYLOAD:
    .fill TCP_PAYLOAD_MAX, $00

;=============================================================================
; Set local (ephemeral) port
;=============================================================================
ETH_SET_LOCAL_PORT:
    sta LOCAL_PORT+0
    stx LOCAL_PORT+1
    rts

;=============================================================================
; Get local IP
;=============================================================================
ETH_GET_LOCAL_IP:
    lda LOCAL_IP+0
    ldx LOCAL_IP+1
    ldy LOCAL_IP+2
    ldz LOCAL_IP+3
    rts

;=============================================================================
; Get gateway IP
;=============================================================================
ETH_GET_GATEWAY_IP:
    lda GATEWAY_IP+0
    ldx GATEWAY_IP+1
    ldy GATEWAY_IP+2
    ldz GATEWAY_IP+3
    rts

;=============================================================================
; Get subnet mask
;=============================================================================
ETH_GET_SUBNET_MASK:
    lda SUBNET_MASK+0
    ldx SUBNET_MASK+1
    ldy SUBNET_MASK+2
    ldz SUBNET_MASK+3
    rts

;=============================================================================
; Get primary DNS
;=============================================================================
ETH_GET_PRIMARY_DNS:
    lda PRIMARY_DNS+0
    ldx PRIMARY_DNS+1
    ldy PRIMARY_DNS+2
    ldz PRIMARY_DNS+3
    rts

;=============================================================================
; Get remote IP
;=============================================================================
ETH_GET_REMOTE_IP:
    lda REMOTE_IP+0
    ldx REMOTE_IP+1
    ldy REMOTE_IP+2
    ldz REMOTE_IP+3
    rts

;=============================================================================
; Force TCP state closed for demos/listeners that want to immediately reuse
; the stack after a close.
;=============================================================================
ETH_TCP_FORCE_CLOSE:
    jsr TCP_HARD_RESET
    lda #$00
    sta TCP_EVENT_FLAG
    sta TCP_LISTEN_ENABLED
    sta TCP_ACCEPT_FLAGS
    sta CONNECT_ACTIVE
    sta CONNECT_SYN_SENT
    sta CONNECT_FAIL_LATCH
    sta CONNECT_RETRY_TICKS
    sta CONNECT_RETRY_LEFT
    sta ARP_STATE
    sta ARP_RETRY_TICKS
    sta ARP_RETRY_LEFT
    sta DNS_STATE
    sta DNS_RETRY_LEFT
    sta DNS_RETRY_TICKS
    sta DNS_FRAME_TICKS
    sta ACK_REPLY_PENDING
    sta ACK_REPLY_LEN_L
    sta ACK_REPLY_LEN_H
    rts

;=============================================================================
; ABI info. A/X = version 1.0, Y = BASIC features, Z = ML extensions.
;=============================================================================
ETH_GET_ABI_INFO:
    lda #$01
    ldx #$00
    ldy #%00000001       ; config getters / force-close are present
    ldz #%00000001       ; ML buffer/byte extension table is present
    rts

;=============================================================================
; Start a DNS lookup from BASIC A$ without blocking.
; Out: A = 1 if started, 0 if A$ was empty or invalid.
;=============================================================================
ETH_DNS_START_ASTR:
    jsr COPY_ASTR_TO_DNS_HOST
    lda host_str
    beq _dns_start_astr_fail

    lda #<host_str
    ldx #>host_str
    jsr DNS_RESOLVE_START
    bcs _dns_start_astr_fail

    lda #$01
    rts

_dns_start_astr_fail:
    lda #$00
    rts

;=============================================================================
; TCP transmit idle status.
; Out: A = 1 when the TX queue is empty and no data awaits ACK.
;=============================================================================
ETH_TCP_TX_IDLE:
    lda TXQ_COUNT
    ora TX_UNACK_PENDING
    beq _tcp_tx_idle_yes
    lda #$00
    rts

_tcp_tx_idle_yes:
    lda #$01
    rts

;=============================================================================
; Routine to convert A from ASCII to PETSCII
;=============================================================================
CHAR_TRANSLATE_IMPL:
    pha
    lda CHARACTER_MODE
    beq _char_no_translate

    pla
    cmp #$41
    bcc _char_check_lower
    cmp #$5B
    bcs _char_check_lower
    ora #$80                    ; ASCII A-Z ($41-$5A) -> PETSCII upper ($C1-$DA)
    rts

_char_check_lower:
    cmp #$61
    bcc _char_printable
    cmp #$7B
    bcs _char_printable
    and #$DF                    ; ASCII a-z ($61-$7A) -> PETSCII lower ($41-$5A)
    rts

_char_printable:
    rts

_char_no_translate:
    pla
    rts

;=============================================================================
;
;=============================================================================
READ_TAIL_ATOMIC:
_again:
    lda RBUF_TAIL_HI
    sta TMP_TAIL_HI
    lda RBUF_TAIL_LO
    sta TMP_TAIL_LO
    lda RBUF_TAIL_HI
    cmp TMP_TAIL_HI
    bne _again
    rts

;=============================================================================
;
;=============================================================================
READ_HEAD_ATOMIC:
_again:
    lda RBUF_HEAD_HI
    sta TMP_HEAD_HI
    lda RBUF_HEAD_LO
    sta TMP_HEAD_LO
    lda RBUF_HEAD_HI
    cmp TMP_HEAD_HI
    bne _again
    rts

;=============================================================================
; Driver reset helpers
;=============================================================================

ETH_CLEAR_DRIVER_STATE:
    lda #$00
    sta RBUF_HEAD_HI
    sta RBUF_HEAD_LO
    sta RBUF_TAIL_HI
    sta RBUF_TAIL_LO
    sta ARP_STATE
    sta ARP_RETRY_TICKS
    sta ARP_RETRY_LEFT
    sta ARP_LAST_RASTER_LO
    sta ARP_LAST_RASTER_HI
    sta DNS_STATE
    sta DNS_RETRY_LEFT
    sta DNS_RETRY_TICKS
    sta DNS_LAST_BACKOFF
    sta DNS_FRAME_TICKS
    sta DHCP_IN_PROGRESS
    sta DHCP_STATE
    sta DHCP_RETRY_TICKS
    sta DHCP_FRAME_TICKS
    sta TCP_EVENT_FLAG
    sta ETH_STATE
    sta TCP_STATE
    sta CONNECT_ACTIVE
    sta CONNECT_SYN_SENT
    sta CONNECT_FAIL_LATCH
    sta CONNECT_RETRY_TICKS
    sta CONNECT_RETRY_LEFT
    sta CONNECT_LAST_RASTER_LO
    sta CONNECT_LAST_RASTER_HI
    sta TCP_LISTEN_STATE
    sta TCP_ACCEPT_FLAGS
    sta TCP_LISTEN_ENABLED
    sta ACK_REPLY_PENDING
    sta ACK_REPLY_LEN_L
    sta ACK_REPLY_LEN_H
    sta ETH_RX_TCP_FLAGS
    sta TCP_DATA_PAYLOAD_PAD
    jsr TCP_TX_RESET
    jsr CLEAR_LOCAL_ISN
    jsr CLEAR_REMOTE_ISN
    jsr CLEAR_TCP_PAYLOAD
    rts

CONNECT_FRAME_WRAP_TICK:
    jsr ARP_READ_RASTER

    lda ARP_CUR_RASTER_HI
    cmp CONNECT_LAST_RASTER_HI
    bcc _connect_frame_elapsed
    bne _connect_no_frame

    lda ARP_CUR_RASTER_LO
    cmp CONNECT_LAST_RASTER_LO
    bcc _connect_frame_elapsed

_connect_no_frame:
    lda ARP_CUR_RASTER_LO
    sta CONNECT_LAST_RASTER_LO
    lda ARP_CUR_RASTER_HI
    sta CONNECT_LAST_RASTER_HI
    clc
    rts

_connect_frame_elapsed:
    lda ARP_CUR_RASTER_LO
    sta CONNECT_LAST_RASTER_LO
    lda ARP_CUR_RASTER_HI
    sta CONNECT_LAST_RASTER_HI
    sec
    rts

CONNECT_CLEAR_DEBUG:
    lda #$00
    sta CONNECT_FAIL_REASON_DBG
    sta CONNECT_SYNACK_RX_DBG
    sta CONNECT_SYNACK_BAD_ACK_DBG
    sta CONNECT_SYN_TX_OK_DBG
    sta CONNECT_SYN_TX_FAIL_DBG
    sta CONNECT_RAW_RX_DBG
    sta CONNECT_TCP_RX_DBG
    sta CONNECT_COPY_RX_DBG
    sta CONNECT_TCP_DISPATCH_DBG
    sta CONNECT_LAST_RX_DC_DBG
    sta CONNECT_LAST_RX_TYPE_HI_DBG
    sta CONNECT_LAST_RX_TYPE_LO_DBG
    sta CONNECT_LAST_RX_PROTO_DBG
    sta CONNECT_LAST_TCP_SRC_PORT_HI_DBG
    sta CONNECT_LAST_TCP_SRC_PORT_LO_DBG
    sta CONNECT_LAST_TCP_DST_PORT_HI_DBG
    sta CONNECT_LAST_TCP_DST_PORT_LO_DBG
    sta CONNECT_LAST_TCP_FLAGS_DBG
    sta CONNECT_LAST_TCP_SRC_IP_DBG+0
    sta CONNECT_LAST_TCP_SRC_IP_DBG+1
    sta CONNECT_LAST_TCP_SRC_IP_DBG+2
    sta CONNECT_LAST_TCP_SRC_IP_DBG+3
    sta TCP_TX_ENQUEUE_OK_DBG
    sta TCP_TX_SEND_OK_DBG
    sta TCP_TX_ACK_SEEN_DBG
    sta TCP_TX_ACK_MATCH_DBG
    sta TCP_TX_TIMEOUT_DBG
    sta TCP_TX_TIMEOUT_LEN_DBG
    sta TCP_TX_TIMEOUT_RETRY_DBG
    sta TCP_TX_SEND_FAIL_DBG
    sta TCP_TX_RETX_OK_DBG
    sta TCP_TX_RETX_FAIL_DBG
    sta TCP_TX_BASE_RAW_DBG
    sta TCP_TX_BASE_DISPATCH_DBG
    sta TCP_TX_BASE_HANDLER_DBG
    sta TCP_TX_LAST_ACK_DBG+0
    sta TCP_TX_LAST_ACK_DBG+1
    sta TCP_TX_LAST_ACK_DBG+2
    sta TCP_TX_LAST_ACK_DBG+3
    sta TCP_TX_TIMEOUT_EXPECT_DBG+0
    sta TCP_TX_TIMEOUT_EXPECT_DBG+1
    sta TCP_TX_TIMEOUT_EXPECT_DBG+2
    sta TCP_TX_TIMEOUT_EXPECT_DBG+3
    sta TCP_TX_TIMEOUT_ACK_DBG+0
    sta TCP_TX_TIMEOUT_ACK_DBG+1
    sta TCP_TX_TIMEOUT_ACK_DBG+2
    sta TCP_TX_TIMEOUT_ACK_DBG+3
    rts

CONNECT_SNAPSHOT_FAIL:
    lda CONNECT_FAIL_REASON_DBG
    bne _connect_reason_done

    lda CONNECT_FAIL_LATCH
    beq _connect_not_rst
    lda #$02
    sta CONNECT_FAIL_REASON_DBG
    rts

_connect_not_rst:
    lda CONNECT_SYNACK_BAD_ACK_DBG
    beq _connect_not_bad_ack
    lda #$04
    sta CONNECT_FAIL_REASON_DBG
    rts

_connect_not_bad_ack:
    lda CONNECT_SYNACK_RX_DBG
    beq _connect_not_seen_synack
    lda #$05
    sta CONNECT_FAIL_REASON_DBG
    rts

_connect_not_seen_synack:
    lda CONNECT_SYN_SENT
    beq _connect_generic_fail
    lda CONNECT_RETRY_LEFT
    bne _connect_generic_fail
    lda #$01
    sta CONNECT_FAIL_REASON_DBG
    rts

_connect_generic_fail:
    lda #$03
    sta CONNECT_FAIL_REASON_DBG

_connect_reason_done:
    rts

CONNECT_FAIL_REASON_DBG:     .byte $00
CONNECT_SYNACK_RX_DBG:       .byte $00
CONNECT_SYNACK_BAD_ACK_DBG:  .byte $00
CONNECT_SYN_TX_OK_DBG:       .byte $00
CONNECT_SYN_TX_FAIL_DBG:     .byte $00
CONNECT_RAW_RX_DBG:          .byte $00
CONNECT_TCP_RX_DBG:          .byte $00
CONNECT_COPY_RX_DBG:         .byte $00
CONNECT_TCP_DISPATCH_DBG:    .byte $00
CONNECT_LAST_RX_DC_DBG:      .byte $00
CONNECT_LAST_RX_TYPE_HI_DBG: .byte $00
CONNECT_LAST_RX_TYPE_LO_DBG: .byte $00
CONNECT_LAST_RX_PROTO_DBG:   .byte $00
CONNECT_LAST_TCP_SRC_PORT_HI_DBG: .byte $00
CONNECT_LAST_TCP_SRC_PORT_LO_DBG: .byte $00
CONNECT_LAST_TCP_DST_PORT_HI_DBG: .byte $00
CONNECT_LAST_TCP_DST_PORT_LO_DBG: .byte $00
CONNECT_LAST_TCP_FLAGS_DBG:       .byte $00
CONNECT_LAST_TCP_SRC_IP_DBG:      .byte $00, $00, $00, $00

ETH_INIT_ML_SAFE:
    php
    sei
    jsr MEGA65_IO_ENABLE

    lda MEGA65_ETH_CTRL3
    and #%11011111
    ora #%00010001
    sta MEGA65_ETH_CTRL3

    lda MEGA65_ETH_CTRL3
    and #%11110011
    ora #%00000100
    sta MEGA65_ETH_CTRL3

    lda MEGA65_ETH_CTRL3
    and #%00111111
    ora #%01000000
    sta MEGA65_ETH_CTRL3

    lda MEGA65_ETH_MAC+0
    sta ETH_TX_FRAME_SRC_MAC+0
    lda MEGA65_ETH_MAC+1
    sta ETH_TX_FRAME_SRC_MAC+1
    lda MEGA65_ETH_MAC+2
    sta ETH_TX_FRAME_SRC_MAC+2
    lda MEGA65_ETH_MAC+3
    sta ETH_TX_FRAME_SRC_MAC+3
    lda MEGA65_ETH_MAC+4
    sta ETH_TX_FRAME_SRC_MAC+4
    lda MEGA65_ETH_MAC+5
    sta ETH_TX_FRAME_SRC_MAC+5

    lda #$03
    sta MEGA65_ETH_CTRL1
    sta MEGA65_ETH_CTRL2
    lda #$00
    sta MEGA65_ETH_CTRL2

    jsr ETH_CLEAR_DRIVER_STATE
    plp
    rts

;=============================================================================
; DNS helper routines
;
; Placed after the large buffers to keep the original BASIC-facing data block
; fixed while still allowing DNS to handle compressed CNAME RDATA.
;=============================================================================

DNS2_COPY_CNAME_RDATA:
    lda DNS2_RD_LO
    sta DNS2_NAME_LO
    lda DNS2_RD_HI
    sta DNS2_NAME_HI
    lda #$00
    sta q_out
    sta q_guard

DNS2_COPY_NAME_LOOP:
    inc q_guard
    lda q_guard
    cmp #$40
    bcs DNS2_COPY_NAME_BAD

    jsr DNS2_READ_NAME_BYTE
    beq DNS2_COPY_NAME_ZERO
    tax
    and #$C0
    beq DNS2_COPY_NAME_LABEL
    cmp #$C0
    beq DNS2_COPY_NAME_POINTER
    jmp DNS2_COPY_NAME_BAD

DNS2_COPY_NAME_LABEL:
    txa
    and #$3F
    beq DNS2_COPY_NAME_BAD
    sta lbl_len

    ldx q_out
    cpx #128
    bcs DNS2_COPY_NAME_BAD
    lda lbl_len
    sta DNS_QNAME,x
    inx
    stx q_out

    lda lbl_len
    sta lbl_cnt
DNS2_COPY_LABEL_BYTE:
    jsr DNS2_READ_NAME_BYTE
    ldx q_out
    cpx #128
    bcs DNS2_COPY_NAME_BAD
    sta DNS_QNAME,x
    inx
    stx q_out
    dec lbl_cnt
    bne DNS2_COPY_LABEL_BYTE
    jmp DNS2_COPY_NAME_LOOP

DNS2_COPY_NAME_POINTER:
    txa
    and #$3F
    sta ptr_hi
    jsr DNS2_READ_NAME_BYTE
    sta ptr_lo

    lda DNS2_BASE_LO
    clc
    adc ptr_lo
    sta DNS2_NAME_LO
    lda DNS2_BASE_HI
    adc ptr_hi
    sta DNS2_NAME_HI
    jmp DNS2_COPY_NAME_LOOP

DNS2_COPY_NAME_ZERO:
    lda DNS2_BOUNDS_FAIL
    bne DNS2_COPY_NAME_BAD
    ldx q_out
    cpx #128
    bcs DNS2_COPY_NAME_BAD
    lda #$00
    sta DNS_QNAME,x
    inx
    stx DNS_QNAME_LEN
    clc
    rts

DNS2_COPY_NAME_BAD:
    sec
    rts

DNS2_READ_NAME_BYTE:
    lda DNS2_NAME_HI
    cmp DNS2_END_HI
    bcc DNS2_READ_NAME_OK
    bne DNS2_READ_NAME_BAD
    lda DNS2_NAME_LO
    cmp DNS2_END_LO
    bcc DNS2_READ_NAME_OK

DNS2_READ_NAME_BAD:
    lda #$01
    sta DNS2_BOUNDS_FAIL
    lda #$00
    sec
    rts

DNS2_READ_NAME_OK:
    lda DNS2_NAME_LO
    sta DNS2_NAME_READ_ABS+1
    lda DNS2_NAME_HI
    sta DNS2_NAME_READ_ABS+2
DNS2_NAME_READ_ABS:
    lda $ffff
    pha
    inc DNS2_NAME_LO
    bne DNS2_NAME_ADV_DONE
    inc DNS2_NAME_HI
DNS2_NAME_ADV_DONE:
    pla
    clc
    rts

DNS2_REQUERY_CNAME:
    lda DNS2_BOUNDS_FAIL
    beq DNS2_REQUERY_BOUNDS_OK
    jmp DNS2_FAIL

DNS2_REQUERY_BOUNDS_OK:
    lda #DNS_MAX_RETRIES
    sta DNS_RETRY_LEFT
    lda #DNS_TIMEOUT_TICKS_BASE
    sta DNS_RETRY_TICKS
    sta DNS_LAST_BACKOFF
    lda #DNS_TICK_FRAMES
    sta DNS_FRAME_TICKS
    jsr ARP_READ_RASTER
    lda ARP_CUR_RASTER_LO
    sta DNS_LAST_RASTER_LO
    lda ARP_CUR_RASTER_HI
    sta DNS_LAST_RASTER_HI

    inc DNS_CLIENT_PORT_HI
    lda DNS_CLIENT_PORT_LO
    clc
    adc #$3D
    sta DNS_CLIENT_PORT_LO
    bcc DNS2_REQUERY_PORT_OK
    inc DNS_CLIENT_PORT_HI
DNS2_REQUERY_PORT_OK:
    inc DNS_MSG_ID_LO
    bne DNS2_REQUERY_ID_OK
    inc DNS_MSG_ID_HI
DNS2_REQUERY_ID_OK:
    lda #DNS_STATE_WAIT
    sta DNS_STATE
    jsr DNS_SEND_QUERY
    bcc DNS2_REQUERY_DONE

    lda #$01
    sta DNS_RETRY_TICKS
    lda #40
    sta DNS_ARP_DEFERS
DNS2_REQUERY_DONE:
    rts

;=============================================================================
; Get up to Z received TCP bytes into a caller buffer.
; In: A/X = dest pointer, Y = dest bank, Z = max bytes.
; Out: A/X/Z = count copied.
;=============================================================================
ETH_RBUF_GET_BLOCK:
    sta RBUF_BLOCK_DEST_LO
    stx RBUF_BLOCK_DEST_HI
    sty RBUF_BLOCK_DEST_BANK
    tza
    sta RBUF_BLOCK_MAX
    lda #$00
    sta RBUF_BLOCK_COUNT

    lda $45
    sta RBUF_BLOCK_SAVE45
    lda $46
    sta RBUF_BLOCK_SAVE46
    lda $47
    sta RBUF_BLOCK_SAVE47
    lda $48
    sta RBUF_BLOCK_SAVE48

    lda RBUF_BLOCK_DEST_LO
    sta $45
    lda RBUF_BLOCK_DEST_HI
    sta $46
    lda RBUF_BLOCK_DEST_BANK
    sta $47
    lda #$00
    sta $48

_rbuf_block_loop:
    lda RBUF_BLOCK_COUNT
    cmp RBUF_BLOCK_MAX
    bcs _rbuf_block_done
    jsr RBUF_GET
    bcs _rbuf_block_done
    ldz RBUF_BLOCK_COUNT
    sta [$45],z
    inc RBUF_BLOCK_COUNT
    bra _rbuf_block_loop

_rbuf_block_done:
    lda RBUF_BLOCK_SAVE45
    sta $45
    lda RBUF_BLOCK_SAVE46
    sta $46
    lda RBUF_BLOCK_SAVE47
    sta $47
    lda RBUF_BLOCK_SAVE48
    sta $48

    lda RBUF_BLOCK_COUNT
    tax
    taz
    rts

RBUF_BLOCK_DEST_LO:   .byte $00
RBUF_BLOCK_DEST_HI:   .byte $00
RBUF_BLOCK_DEST_BANK: .byte $00
RBUF_BLOCK_MAX:       .byte $00
RBUF_BLOCK_COUNT:     .byte $00
RBUF_BLOCK_SAVE45:    .byte $00
RBUF_BLOCK_SAVE46:    .byte $00
RBUF_BLOCK_SAVE47:    .byte $00
RBUF_BLOCK_SAVE48:    .byte $00

;=============================================================================
; ML extension entry points
;
; These live outside the original BASIC-facing jump table so existing SYS
; addresses and hard-coded BASIC peeks stay compatible.
;=============================================================================

* = $7000

    jmp ETH_TCP_SEND_BYTE
    jmp ETH_DNS_LOOKUP_BUFFER
    jmp ETH_INIT_ML_SAFE
    jmp ETH_DHCP_DEBUG
    jmp ETH_DHCP_DEBUG_TX
    jmp ETH_DNS_START_BUFFER
    jmp ETH_DNS_DEBUG
    jmp ETH_DNS_DEBUG2
    jmp ETH_DNS_START_BUFFER_YLEN
    jmp ETH_ML_CALL_STAGED
    jmp ETH_RBUF_GET_BYTE
    jmp ETH_RBUF_GET_BLOCK
    jmp ETH_DNS_DEBUG3
    jmp ETH_CONNECT_DEBUG
    jmp ETH_CONNECT_DEBUG2
    jmp ETH_CONNECT_DEBUG3

;=============================================================================
; Send one byte over TCP
; In: A = byte to send
;=============================================================================
ETH_TCP_SEND_BYTE:
    sta TCP_DATA_PAYLOAD
    lda #$01
    sta TCP_DATA_PAYLOAD_SIZE
    lda #$00
    sta TCP_DATA_PAYLOAD_SIZE+1

    lda TCP_STATE
    cmp #TCP_STATE_ESTABLISHED
    bne _send_byte_fail

    jsr ETH_TCP_SEND
    bcs _send_byte_fail
    lda #$01
    clc
    rts

_send_byte_fail:
    jsr CLEAR_TCP_PAYLOAD
    lda #$00
    sec
    rts

;=============================================================================
; Initiate a DNS lookup request from a caller buffer.
; In: A/X = source pointer, Y = source bank, Z = byte length.
;=============================================================================
ETH_DNS_LOOKUP_BUFFER:
    jsr ETH_DNS_COPY_BUFFER
    bcs ETH_DNS_LOOKUP_BUFFER_FAIL
    jmp DNS_LOOKUP_HOSTSTR

ETH_DNS_LOOKUP_BUFFER_FAIL:
    jmp DNS_LOOKUP_FAIL

;=============================================================================
; Start a DNS lookup from a caller buffer without blocking.
; In: A/X = source pointer, Y = source bank, Z = byte length.
; Out: A = 1 if started, 0 if invalid input.
;=============================================================================
ETH_DNS_START_BUFFER:
    jsr ETH_DNS_COPY_BUFFER
    bcs ETH_DNS_START_BUFFER_FAIL

    lda #<host_str
    ldx #>host_str
    jsr DNS_RESOLVE_START
    bcs ETH_DNS_START_BUFFER_FAIL

    lda #$01
    rts

ETH_DNS_START_BUFFER_FAIL:
    lda #$00
    rts

;=============================================================================
; Start a DNS lookup from a BASIC/ML workspace buffer without blocking.
; In: A/X = source pointer, Y = byte length. This variant avoids passing length
; in Z for staged ML callers. The source bank is 1 because the standard MEGA65
; BASIC map keeps loaded PRG/data there for DMA.
; The source offset must stay in bank-1 workspace ($2000-$f7ff), avoiding
; C65 DOS variables at physical $10000-$11fff and color RAM at $1f800-$1ffff.
; Out: A = 1 if started, 0 if invalid input.
;=============================================================================
ETH_DNS_START_BUFFER_YLEN:
    jsr ETH_DNS_COPY_BUFFER_YLEN_BANK1
    bcs ETH_DNS_START_BUFFER_FAIL

    lda #<host_str
    ldx #>host_str
    jsr DNS_RESOLVE_START
    bcs ETH_DNS_START_BUFFER_FAIL

    lda #$01
    rts

ETH_DNS_COPY_BUFFER:
    sta DNS_COPY_SRC_ADDR+0
    stx DNS_COPY_SRC_ADDR+1
    sty DNS_COPY_SRC_ADDR+2
    lda #$30
    sta DNS_DEBUG_STAGE
    tza
    jmp ETH_DNS_COPY_BUFFER_LEN_A

ETH_DNS_COPY_BUFFER_YLEN_BANK1:
    sta DNS_COPY_SRC_ADDR+0
    stx DNS_COPY_SRC_ADDR+1
    lda #$01
    sta DNS_COPY_SRC_ADDR+2
    lda #$32
    sta DNS_DEBUG_STAGE
    cpx #BANK1_WORKSPACE_LOW_HI
    bcc ETH_DNS_COPY_BUFFER_BANK1_RANGE_FAIL
    cpx #BANK1_COLOR_SHADOW_HI
    bcs ETH_DNS_COPY_BUFFER_BANK1_RANGE_FAIL
    cpx #BANK1_COLOR_SHADOW_HI-1
    bne _bank1_range_ok
    tya
    clc
    adc DNS_COPY_SRC_ADDR+0
    bcc _bank1_range_ok
    beq _bank1_range_ok
    bra ETH_DNS_COPY_BUFFER_BANK1_RANGE_FAIL

_bank1_range_ok:
    tya

ETH_DNS_COPY_BUFFER_LEN_A:
    beq ETH_DNS_COPY_BUFFER_FAIL
    cmp #DNS_HOST_BUFFER_SIZE
    bcs ETH_DNS_COPY_BUFFER_FAIL
    sta DNS_COPY_BUF_LEN+0
    lda #$00
    sta DNS_COPY_BUF_LEN+1

    ; Copy caller bytes to host_str and zero-terminate for DNS_RESOLVE_START.
    lda #$00
    sta $D707
    .byte $80                                   ; enhanced DMA - src bits 20-27
    .byte $00
    .byte $81                                   ; enhanced DMA - dest bits 20-27
    .byte $00
    .byte $00                                   ; end of job options
    .byte $00                                   ; copy
DNS_COPY_BUF_LEN:
    .byte $00, $00                              ; length lsb, msb
DNS_COPY_SRC_ADDR:
    .byte $00, $00, $00                         ; source lsb, msb, bank
DNS_COPY_DEST_ADDR:
    .byte <host_str, >host_str, EXEC_BANK       ; dest lsb, msb, bank
    .byte $00                                   ; command high byte
    .word $0000                                 ; modulo (ignored)

    ldy DNS_COPY_BUF_LEN+0
    lda #$00
    sta host_str,y
    clc
    rts

ETH_DNS_COPY_BUFFER_BANK1_RANGE_FAIL:
    lda #$33
    sta DNS_DEBUG_STAGE
    lda DNS_COPY_SRC_ADDR+1
    sta DNS_ARP_WAIT_COUNT
    lda DNS_COPY_SRC_ADDR+0
    sta DNS_PARSE_FAILS
    sec
    rts

ETH_DNS_COPY_BUFFER_FAIL:
    lda #$31
    sta DNS_DEBUG_STAGE
    sec
    rts

;=============================================================================
; Return DHCP debug counters for ML callers.
; Out: A = accepted RX frames, X = UDP/68 hits, Y = parser stage, Z = msg type.
;=============================================================================
ETH_DHCP_DEBUG:
    lda DHCP_RX_ACCEPTS
    ldx DHCP_UDP68_HITS
    ldy DHCP_DEBUG_STAGE
    ldz dhcp_msg_type
    rts

;=============================================================================
; Return DHCP transmit counters for ML callers.
; Out: A/X = DISCOVER ok/fail, Y/Z = REQUEST ok/fail.
;=============================================================================
ETH_DHCP_DEBUG_TX:
    lda DHCP_DISCOVER_TX_OK
    ldx DHCP_DISCOVER_TX_FAIL
    ldy DHCP_REQUEST_TX_OK
    ldz DHCP_REQUEST_TX_FAIL
    rts

;=============================================================================
; Return DNS debug counters for ML callers.
; Out: A = state, X = stage, Y/Z = query TX ok/fail.
;=============================================================================
ETH_DNS_DEBUG:
    lda DNS_STATE
    ldx DNS_DEBUG_STAGE
    ldy DNS_QUERY_TX_OK
    ldz DNS_QUERY_TX_FAIL
    rts

;=============================================================================
; Return additional DNS debug counters for ML callers.
; Out: A = RX hits, X = ARP waits, Y = parse fails, Z = client port high.
;=============================================================================
ETH_DNS_DEBUG2:
    lda DNS_CLIENT_PORT_HI
    and #$1F
    ora #$C0
    taz
    lda DNS_RX_HITS
    ldx DNS_ARP_WAIT_COUNT
    ldy DNS_PARSE_FAILS
    rts

;=============================================================================
; Return DNS RX-path counters for ML callers.
; Out: A = raw accepted, X = IPv4, Y = UDP, Z = not-for-us drops.
;=============================================================================
ETH_DNS_DEBUG3:
    lda DNS_RAW_RX_COUNT
    ldx DNS_IPV4_RX_COUNT
    ldy DNS_UDP_RX_COUNT
    ldz DNS_NOT_FOR_US_COUNT
    rts

;=============================================================================
; Return connect debug state for BASIC/ML callers.
; Out: A = event bits, X = fail reason, Y = SYN-ACKs seen, Z = bad SYN-ACK ACKs.
;=============================================================================
ETH_CONNECT_DEBUG:
    lda TCP_EVENT_FLAG
    ldx CONNECT_FAIL_REASON_DBG
    ldy CONNECT_SYNACK_RX_DBG
    ldz CONNECT_SYNACK_BAD_ACK_DBG
    rts

;=============================================================================
; Return connect RX/TX counters.
; Out: A = SYN TX ok, X = SYN TX fail, Y = raw RX, Z = TCP RX.
;=============================================================================
ETH_CONNECT_DEBUG2:
    lda CONNECT_SYN_TX_OK_DBG
    ldx CONNECT_SYN_TX_FAIL_DBG
    ldy CONNECT_RAW_RX_DBG
    ldz CONNECT_TCP_RX_DBG
    rts

;=============================================================================
; Return last copied RX frame summary.
; Out: A = dest class, X/Y = EtherType hi/lo, Z = IPv4 protocol byte.
;=============================================================================
ETH_CONNECT_DEBUG3:
    lda CONNECT_LAST_RX_DC_DBG
    ldx CONNECT_LAST_RX_TYPE_HI_DBG
    ldy CONNECT_LAST_RX_TYPE_LO_DBG
    ldz CONNECT_LAST_RX_PROTO_DBG
    rts

;=============================================================================
; Get one received TCP byte for ML callers without relying on carry across
; KERNAL JSRFAR. Out: X=1 and A=byte when a byte was read, X=0 when empty.
;=============================================================================
ETH_RBUF_GET_BYTE:
    jsr RBUF_GET
    bcs _ml_rbuf_empty
    ldx #$01
    rts

_ml_rbuf_empty:
    lda #$00
    tax
    rts

;=============================================================================
; Dispatch a staged ML call.
;
; KERNAL JSRFAR is reliable for no-argument calls and return registers, but it
; does not preserve entry registers for the far target. ML callers can DMA this
; block into bank 4 and call this dispatcher instead.
;=============================================================================
ETH_ML_CALL_STAGED:
    lda ML_CALL_TARGET_LO
    sta _ml_call_jsr+1
    lda ML_CALL_TARGET_HI
    sta _ml_call_jsr+2

    lda ML_CALL_ARG_Z
    taz
    ldy ML_CALL_ARG_Y
    ldx ML_CALL_ARG_X
    lda ML_CALL_ARG_A
_ml_call_jsr:
    jsr $ffff

    php
    sta ML_CALL_RET_A
    stx ML_CALL_RET_X
    sty ML_CALL_RET_Y
    tza
    sta ML_CALL_RET_Z

    lda #$00
    tab

    lda ML_CALL_RET_Z
    taz
    ldy ML_CALL_RET_Y
    ldx ML_CALL_RET_X
    lda ML_CALL_RET_A
    plp
    rts

* = $71c0

ML_CALL_TARGET_LO:      .byte $00
ML_CALL_TARGET_HI:      .byte $00
ML_CALL_ARG_A:          .byte $00
ML_CALL_ARG_X:          .byte $00
ML_CALL_ARG_Y:          .byte $00
ML_CALL_ARG_Z:          .byte $00
ML_CALL_RET_A:          .byte $00
ML_CALL_RET_X:          .byte $00
ML_CALL_RET_Y:          .byte $00
ML_CALL_RET_Z:          .byte $00

;=============================================================================
; BASIC connect/SYN diagnostics.
;
; These are intentionally outside the original BASIC jump table and the $7000
; ML extension table so existing addresses stay fixed.
;=============================================================================
* = $7200

    jmp ETH_CONNECT_TX_DEBUG1      ; $47200
    jmp ETH_CONNECT_TX_DEBUG2      ; $47203
    jmp ETH_CONNECT_TX_DEBUG3      ; $47206
    jmp ETH_CONNECT_TX_DEBUG4      ; $47209
    jmp ETH_CONNECT_TX_DEBUG5      ; $4720c
    jmp ETH_CONNECT_TX_DEBUG6      ; $4720f
    jmp ETH_DEBUG_ZERO             ; $47212 reserved
    jmp ETH_DEBUG_ZERO             ; $47215 reserved
    jmp ETH_DEBUG_ZERO             ; $47218 reserved
    jmp ETH_CONNECT_RX_DEBUG1      ; $4721b
    jmp ETH_CONNECT_RX_DEBUG2      ; $4721e
    jmp ETH_CONNECT_RX_DEBUG3      ; $47221
    jmp ETH_CONNECT_RX_DEBUG4      ; $47224
    jmp ETH_TCP_TX_DEBUG1          ; $47227
    jmp ETH_TCP_TX_DEBUG2          ; $4722a
    jmp ETH_TCP_TX_DEBUG3          ; $4722d
    jmp ETH_TCP_TX_DEBUG4          ; $47230
    jmp ETH_TX_DUMP4               ; $47233
    jmp ETH_TCP_TX_DEBUG5          ; $47236
    jmp ETH_TCP_TX_DEBUG6          ; $47239

; Out: A/X = frame length lo/hi, Y/Z = EtherType hi/lo.
ETH_CONNECT_TX_DEBUG1:
    lda ETH_TX_LEN_LSB
    ldx ETH_TX_LEN_MSB
    ldy ETH_TX_TYPE
    ldz ETH_TX_TYPE+1
    rts

; Out: A/X = TCP dst port hi/lo, Y/Z = TCP src port hi/lo.
ETH_CONNECT_TX_DEBUG2:
    lda ETH_TX_FRAME_PAYLOAD+20+2
    ldx ETH_TX_FRAME_PAYLOAD+20+3
    ldy ETH_TX_FRAME_PAYLOAD+20+0
    ldz ETH_TX_FRAME_PAYLOAD+20+1
    rts

; Out: A/X/Y/Z = IPv4 destination address.
ETH_CONNECT_TX_DEBUG3:
    lda ETH_TX_FRAME_PAYLOAD+16
    ldx ETH_TX_FRAME_PAYLOAD+17
    ldy ETH_TX_FRAME_PAYLOAD+18
    ldz ETH_TX_FRAME_PAYLOAD+19
    rts

; Out: A = IP protocol, X = TCP flags, Y/Z = TCP checksum hi/lo.
ETH_CONNECT_TX_DEBUG4:
    lda ETH_TX_FRAME_PAYLOAD+9
    ldx ETH_TX_FRAME_PAYLOAD+20+13
    ldy ETH_TX_FRAME_PAYLOAD+20+16
    ldz ETH_TX_FRAME_PAYLOAD+20+17
    rts

; Out: A/X/Y/Z = destination MAC bytes 0..3.
ETH_CONNECT_TX_DEBUG5:
    lda ETH_TX_FRAME_DEST_MAC+0
    ldx ETH_TX_FRAME_DEST_MAC+1
    ldy ETH_TX_FRAME_DEST_MAC+2
    ldz ETH_TX_FRAME_DEST_MAC+3
    rts

; Out: A/X = destination MAC bytes 4..5, Y = same-net route, Z = ETH_STATE.
ETH_CONNECT_TX_DEBUG6:
    jsr ETH_CHECK_SAME_NET
    tay
    lda ETH_TX_FRAME_DEST_MAC+4
    ldx ETH_TX_FRAME_DEST_MAC+5
    ldz ETH_STATE
    rts

ETH_DEBUG_ZERO:
    lda #$00
    tax
    tay
    taz
    rts

; Out: A = copied RX frames, X = TCP dispatches, Y = TCP handler entries,
; Z = current TCP state.
ETH_CONNECT_RX_DEBUG1:
    lda CONNECT_COPY_RX_DBG
    ldx CONNECT_TCP_DISPATCH_DBG
    ldy CONNECT_TCP_RX_DBG
    ldz TCP_STATE
    rts

; Out: A/X = last RX TCP src port hi/lo, Y/Z = dst port hi/lo.
ETH_CONNECT_RX_DEBUG2:
    lda CONNECT_LAST_TCP_SRC_PORT_HI_DBG
    ldx CONNECT_LAST_TCP_SRC_PORT_LO_DBG
    ldy CONNECT_LAST_TCP_DST_PORT_HI_DBG
    ldz CONNECT_LAST_TCP_DST_PORT_LO_DBG
    rts

; Out: A/X/Y/Z = last RX IPv4 source address.
ETH_CONNECT_RX_DEBUG3:
    lda CONNECT_LAST_TCP_SRC_IP_DBG+0
    ldx CONNECT_LAST_TCP_SRC_IP_DBG+1
    ldy CONNECT_LAST_TCP_SRC_IP_DBG+2
    ldz CONNECT_LAST_TCP_SRC_IP_DBG+3
    rts

; Out: A = last RX TCP flags, X/Y/Z reserved.
ETH_CONNECT_RX_DEBUG4:
    lda CONNECT_LAST_TCP_FLAGS_DBG
    ldx #$00
    ldy #$00
    ldz #$00
    rts

; Out: A = timeout count, X = timeout length, Y = timeout retries left,
; Z = queued bytes still waiting when sampled.
ETH_TCP_TX_DEBUG1:
    lda TCP_TX_TIMEOUT_DBG
    ldx TCP_TX_TIMEOUT_LEN_DBG
    ldy TCP_TX_TIMEOUT_RETRY_DBG
    ldz TXQ_COUNT
    rts

; Out: A/X/Y/Z = expected ACK captured when TX timed out.
ETH_TCP_TX_DEBUG2:
    lda TCP_TX_TIMEOUT_EXPECT_DBG+0
    ldx TCP_TX_TIMEOUT_EXPECT_DBG+1
    ldy TCP_TX_TIMEOUT_EXPECT_DBG+2
    ldz TCP_TX_TIMEOUT_EXPECT_DBG+3
    rts

; Out: A/X/Y/Z = last ACK seen while TX was pending.
ETH_TCP_TX_DEBUG3:
    lda TCP_TX_TIMEOUT_ACK_DBG+0
    ldx TCP_TX_TIMEOUT_ACK_DBG+1
    ldy TCP_TX_TIMEOUT_ACK_DBG+2
    ldz TCP_TX_TIMEOUT_ACK_DBG+3
    rts

; Out: A = ACKs seen, X = ACKs matched, Y = TX sends ok, Z = reserved.
ETH_TCP_TX_DEBUG4:
    lda TCP_TX_ACK_SEEN_DBG
    ldx TCP_TX_ACK_MATCH_DBG
    ldy TCP_TX_SEND_OK_DBG
    ldz #$00
    rts

; Out: A/X/Y = RX raw/TCP-dispatch/TCP-handler deltas since data TX,
; Z = last RX TCP flags.
ETH_TCP_TX_DEBUG5:
    lda CONNECT_RAW_RX_DBG
    sec
    sbc TCP_TX_BASE_RAW_DBG
    sta TX_DUMP_A
    lda CONNECT_TCP_DISPATCH_DBG
    sec
    sbc TCP_TX_BASE_DISPATCH_DBG
    tax
    lda CONNECT_TCP_RX_DBG
    sec
    sbc TCP_TX_BASE_HANDLER_DBG
    tay
    ldz CONNECT_LAST_TCP_FLAGS_DBG
    lda TX_DUMP_A
    rts

; Out: A = retransmits ok, X = retransmits failed, Y = TX fail count,
; Z = TX pending flag.
ETH_TCP_TX_DEBUG6:
    lda TCP_TX_RETX_OK_DBG
    ldx TCP_TX_RETX_FAIL_DBG
    ldy TCP_TX_SEND_FAIL_DBG
    ldz TX_UNACK_PENDING
    rts

; Return four bytes from the last built TX frame.
; In: A = byte offset from ETH_TX_FRAME_HEADER.
; Out: A/X/Y/Z = bytes offset+0..offset+3.
ETH_TX_DUMP4:
    tax
    lda ETH_TX_FRAME_HEADER+0,x
    sta TX_DUMP_A
    lda ETH_TX_FRAME_HEADER+1,x
    sta TX_DUMP_X
    lda ETH_TX_FRAME_HEADER+2,x
    sta TX_DUMP_Y
    lda ETH_TX_FRAME_HEADER+3,x
    taz
    ldy TX_DUMP_Y
    ldx TX_DUMP_X
    lda TX_DUMP_A
    rts

TX_DUMP_A: .byte $00
TX_DUMP_X: .byte $00
TX_DUMP_Y: .byte $00
