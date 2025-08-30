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
ETH_STATE_ARP_READY         = $02
ETH_STATE_RX_FRAME          = $03
ETH_STATE_TX_FRAME          = $04

; TCP states
TCP_STATE_CLOSED            = $00
TCP_STATE_LISTEN            = $01
TCP_STATE_SYN_SENT          = $02
TCP_STATE_SYN_RECEIVED      = $03
TCP_STATE_ESTABLISHED       = $04
TCP_STATE_FIN_WAIT_1        = $05
TCP_STATE_FIN_WAIT_2        = $06
TCP_STATE_CLOSE_WAIT        = $07
TCP_STATE_CLOSING           = $08
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

; This code is loaded to bank 4, starting at $2000 (BLOAD"eth.bin",P($42000),R)
; The reason is so that the standard MAP for BASIC remains in effect.
EXEC_BANK = $04     ; code is running from $42000
*=$2000

    ; Jump table for various functions
    jmp ETH_INIT
    jmp ETH_SET_GATEWAY_IP
    jmp ETH_SET_LOCAL_IP
    jmp ETH_SET_REMOTE_IP
    jmp ETH_SET_REMOTE_PORT
    jmp ETH_SET_SUBNET_MASK
    jmp ETH_SET_CHAR_XLATE

    jmp ETH_TCP_SEND
    jmp ETH_TCP_SEND_STRING
    jmp RBUF_GET
    jmp ETH_TCP_DISCONNECT
    jmp ETH_STATUS_POLL

    jmp ETH_TCP_CONNECT_START
    jmp ETH_CONNECT_POLL
    jmp ETH_CONNECT_CANCEL

LOCAL_IP:
    .byte 192, 168, 1, 75

LOCAL_PORT:
    .byte $c0, $00              ; ephemeral port 49152

REMOTE_IP:
    .byte 192, 168, 1, 1

REMOTE_PORT:
    .byte $00, $17

GATEWAY_IP:
    .byte 192, 168, 1, 1

SUBNET_MASK:
    .byte $ff, $ff, $ff, $00

PRIMARY_DNS:
    .byte 8, 8, 8, 8

REMOTE_ISN:
    .byte $00, $00, $00, $00

LOCAL_ISN:
    .byte $00, $00, $00, $00

; temp values for seq number and ack number calcs
LOCAL_ISN_TMP:
    .byte $00

REMOTE_ISN_TMP:
    .byte $00, $00

; current state of ethernet
ETH_STATE:
    .byte $00
TCP_STATE:
    .byte $00

; recieved tcp pack flags
ETH_RX_TCP_FLAGS:
    .byte $00

ETH_PROMISCUOUS:
    .byte $00

ETH_TX_LEN_LSB:
    .byte $00
ETH_TX_LEN_MSB:
    .byte $00

; IPv4 checksum accumulators
ipv4_sum_lo: .byte 0
ipv4_sum_hi: .byte 0

; TCP checksum accumulators
tcp_sum_lo:  .byte 0
tcp_sum_hi:  .byte 0

; 2×MSL = 60 s → 600 ticks of 100 ms → 0x0258
TIME_WAIT_COUNTER_LO:
.byte $58

TIME_WAIT_COUNTER_HI:
.byte $02

; $00 = Commodore graphics (no translation)
; $01 = ASCII -> PETSCII (fix case flip)
CHARACTER_MODE: .byte $00

.include "random.asm"

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
    ; clear the receieve buffer
    lda #$00
    sta RBUF_HEAD_HI
    sta RBUF_HEAD_LO
    sta RBUF_TAIL_HI
    sta RBUF_TAIL_LO

    ; Initialize connection state
    sta TCP_EVENT_FLAG
    sta CONNECT_ACTIVE
    sta CONNECT_SYN_SENT
    sta CONNECT_FAIL_LATCH

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
; Set character translation
;=============================================================================
ETH_SET_CHAR_XLATE:
    sta CHARACTER_MODE
    rts


CONNECT_ACTIVE:        .byte $00   ; 1 while a connect attempt is active
CONNECT_SYN_SENT:      .byte $00   ; 1 after we transmit SYN
CONNECT_FAIL_LATCH:    .byte $00   ; set by IRQ on RST/abort, polled/cleared in CONNECT_POLL

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

    lda #$01
    sta CONNECT_ACTIVE

    ; Try ARP cache first (remote or gateway)
    jsr ETH_CHECK_SAME_NET       ; C=1 same subnet, C=0 use gateway
  bcs _use_remote
_use_gateway:
    ; set ARP_QUERY_IP := GATEWAY_IP
    ldx #$03
_cpy_gw:
    lda GATEWAY_IP,x
    sta ARP_QUERY_IP,x
    dex
    bpl _cpy_gw
    jmp _query_cache
_use_remote:
    ; set ARP_QUERY_IP := REMOTE_IP
    ldx #$03
_cpy_rem:
    lda REMOTE_IP,x
    sta ARP_QUERY_IP,x
    dex
    bpl _cpy_rem

_query_cache:
    jsr ARP_QUERY_CACHE
    beq _need_arp

    ; Have MAC → send SYN immediately
    lda #TCP_FLAG_SYN
    jsr ETH_BUILD_TCPIP_PACKET
    bcs _send_fail                 ; (carry set = build error)
    
    jsr ETH_PACKET_SEND

    lda #$01
    sta CONNECT_SYN_SENT
    lda #TCP_STATE_SYN_SENT
    sta TCP_STATE
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

;=============================================================================
; ETH_CONNECT_POLL
; Drive the connect attempt forward (ARP→SYN) and report status in A.
; Safe to call anytime (even when not connecting).
;=============================================================================
ETH_CONNECT_POLL:
    ; let mainline drain any deferred IRQ work
    jsr ETH_PROCESS_DEFERRED

    ; check for an handle any incoming packets
    jsr ETH_RCV

    lda CONNECT_ACTIVE
    beq _not_connecting

    ; failed earlier?
    lda CONNECT_FAIL_LATCH
    beq _chk_state
    lda #$00
    sta CONNECT_ACTIVE
    sta CONNECT_SYN_SENT
    sta CONNECT_FAIL_LATCH
    lda #CONN_FAILED
    rts

_chk_state:
    ; established?
    lda TCP_STATE
    cmp #TCP_STATE_ESTABLISHED
    bne _not_est
    lda #$00
    sta CONNECT_ACTIVE
    sta CONNECT_SYN_SENT
    lda #CONN_CONNECTED
    rts

_not_est:
    ; If ARP finished and we haven’t sent SYN yet, send it now
    lda CONNECT_SYN_SENT
    bne _inprog

    lda ETH_STATE
    cmp #ETH_STATE_ARP_WAITING
    beq _inprog                   ; still resolving MAC

    ; ARP done → verify cache then send SYN
    jsr ARP_QUERY_CACHE
    beq _inprog                   ; still not populated (rare)

    lda #TCP_FLAG_SYN
    jsr ETH_BUILD_TCPIP_PACKET
    bcs _inprog     ; was: bcs _fail
    jsr ETH_PACKET_SEND
    lda #$01
    sta CONNECT_SYN_SENT
    lda #TCP_STATE_SYN_SENT
    sta TCP_STATE

_inprog:
    lda #CONN_IN_PROGRESS          ; start with IN_PROGRESS in A
    ldy CONNECT_SYN_SENT           ; if SYN has been sent, add that bit
    beq _no_syn
    ora #CONN_SYN_SENT
_no_syn:
    ldx ETH_STATE                  ; if still waiting on ARP, add that bit
    cpx #ETH_STATE_ARP_WAITING
    bne _ret
    ora #CONN_ARP_WAIT
_ret:
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
    lda #TCP_STATE_CLOSED
    sta TCP_STATE
_done:
    lda #$00
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
    jsr ETH_PACKET_SEND

    jsr CALC_LOCAL_ISN

    lda #TCP_STATE_FIN_WAIT_1
    sta TCP_STATE

_not_connected:
    rts

;=============================================================================
; Send byte over TCP
;=============================================================================
ETH_TCP_SEND:

    lda TCP_STATE
    cmp #TCP_STATE_ESTABLISHED
    bne _not_connected

    lda #TCP_FLAG_PSH
    ora #TCP_FLAG_ACK
    jsr ETH_BUILD_TCPIP_PACKET
    jsr ETH_PACKET_SEND

    jsr CALC_LOCAL_ISN
    jsr CLEAR_TCP_PAYLOAD
    rts

_not_connected:
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
    ;lda #$00
    ;sta TCP_DATA_PAYLOAD_SIZE+1

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
    
    plp
    jmp ETH_TCP_SEND



; Process deferred ARP reply from mainline
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

    ldx #$2a
_epd_copy:
    dex
    lda ARP_REPLY_PACKET,x
    sta ETH_TX_FRAME_DEST_MAC,x
    cpx #$00
    bne _epd_copy
    
    lda #$2a
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

_not_RST:

    lda TCP_STATE

;---------------------------------------------------------------------------
; ESTABLISHED
;---------------------------------------------------------------------------
_check_ESTABLISHED:
    cmp #TCP_STATE_ESTABLISHED
    bne _check_CLOSED

    ; If the peer is closing too (FIN), go handle that first
    lda ETH_RX_TCP_FLAGS
    and #TCP_FLAG_FIN
    beq _no_fin_in_established
    jmp _got_FIN_IN_ESTABLISHED

    ; If the peer is closing too (FIN+ACK), go handle that first
    ;lda ETH_RX_TCP_FLAGS
    ;and #(TCP_FLAG_FIN|TCP_FLAG_ACK)
    ;cmp #(TCP_FLAG_FIN|TCP_FLAG_ACK)
    ;beq _got_FIN_IN_ESTABLISHED

_no_fin_in_established:
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
    lda SEG_SEQ+0
    cmp REMOTE_ISN+0
    bne _cmp_done
    lda SEG_SEQ+1
    cmp REMOTE_ISN+1
    bne _cmp_done
    lda SEG_SEQ+2
    cmp REMOTE_ISN+2
    bne _cmp_done
    lda SEG_SEQ+3
    cmp REMOTE_ISN+3
_cmp_done:
    bcc _seg_in_past         ; SEG.SEQ <  RCV.NXT → overlap on left
    beq _seg_in_order        ; SEG.SEQ == RCV.NXT → in-order
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
    jsr DEFER_CURRENT_TX

    ; handshake complete
    lda #TCP_STATE_ESTABLISHED
    sta TCP_STATE
    rts

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
    jsr DEFER_CURRENT_TX
    ; move to LAST_ACK
    lda #TCP_STATE_LAST_ACK
    sta TCP_STATE
    rts

;---------------------------------------------------------------------------
; LAST-ACK
;---------------------------------------------------------------------------
_check_LAST_ACK:
    cmp #TCP_STATE_LAST_ACK
    bne _done

    lda ETH_RX_TCP_FLAGS
    and #TCP_FLAG_ACK
    cmp #TCP_FLAG_ACK
    bne _done

    ; peer ACK’d your FIN, now go TIME_WAIT
    lda #$02
    sta TIME_WAIT_COUNTER_HI
    lda #$58
    sta TIME_WAIT_COUNTER_LO

    lda #TCP_STATE_TIME_WAIT
    sta TCP_STATE

_done:
    rts

RX_COPY_REM_LO:     .byte 0
RX_COPY_REM_HI:     .byte 0
RX_CONSUMED_LO:     .byte 0
RX_CONSUMED_HI:     .byte 0
SKIP_LO:          .byte 0
SKIP_HI:          .byte 0
OFF_LO:           .byte 0
OFF_HI:           .byte 0

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

;=============================================================================
; A = byte to write
; Carry set if buffer full, clear if success
;=============================================================================
; In:  A = byte to store
; Out: C=0 success, C=1 full (A preserved on success)
RBUF_PUT:
    php
    sei

    pha                         ; save data byte on stack

    ; snapshot current head into HLO/HHI
    lda RBUF_HEAD_LO
    sta HLO
    lda RBUF_HEAD_HI
    sta HHI

    ; next = head + 1 (10-bit)
    clc
    lda HLO
    adc #1
    sta NEXT_LO
    lda HHI
    adc #0
    and #$03
    sta NEXT_HI

    ; full? (next == tail)
    jsr READ_TAIL_ATOMIC
    lda NEXT_LO
    cmp TMP_TAIL_LO
    bne _not_full
    lda NEXT_HI
    cmp TMP_TAIL_HI
    bne _not_full
_full:
    pla                         ; drop saved byte
    plp
    sec                         ; full
    rts

_not_full:
    ; write data at page(HHI) : offset(HLO)
    ldy HLO
    pla                         ; A = data byte
    ldx HHI
    cpx #0
    bne _p1
    ;FAR_POKE_Y $00, $55000
    STAY_FAR $00, $55000
    ;sta RBUF_PAGE0,y            ; page 0
    jmp _pub
_p1 cpx #1
    bne _p2
    ;FAR_POKE_Y $00, $56000
    STAY_FAR $00, $56000
    ;sta RBUF_PAGE1,y            ; page 1
    jmp _pub
_p2 cpx #2
    bne _p3
    ;FAR_POKE_Y $00, $57000
    STAY_FAR $00, $57000
    ;sta RBUF_PAGE2,y            ; page 2
    jmp _pub
_p3
    ;FAR_POKE_Y $00, $58000
    STAY_FAR $00, $58000
    ;sta RBUF_PAGE3,y            ; page 3

_pub:
    ; publish head = next
    lda NEXT_LO
    sta RBUF_HEAD_LO
    lda NEXT_HI
    sta RBUF_HEAD_HI

    plp
    clc                         ; success
    rts



;=============================================================================
; Returns byte in A
; Carry set if buffer empty, clear if success
;=============================================================================
RBUF_GET:
    php
    sei

    ; empty? (head == tail)
    jsr READ_HEAD_ATOMIC
    lda RBUF_TAIL_LO
    cmp TMP_HEAD_LO
    bne _not_empty
    lda RBUF_TAIL_HI
    cmp TMP_HEAD_HI
    beq _empty

_not_empty:
    ; read from page(TAIL_HI) : offset(TAIL_LO)
    ldy RBUF_TAIL_LO
    ldx RBUF_TAIL_HI
    cpx #0
    bne _g1
    ;FAR_PEEK_Y $00, $55000
    LDAY_FAR $00, $055000
    ;lda RBUF_PAGE0,y            ; page 0
    jmp _adv
_g1 cpx #1
    bne _g2
    ;FAR_PEEK_Y $00, $56000
    LDAY_FAR $00, $056000
    ;lda RBUF_PAGE1,y            ; page 1
    jmp _adv
_g2 cpx #2
    bne _g3
    ;FAR_PEEK_Y $00, $57000
    LDAY_FAR $00, $057000
    ;lda RBUF_PAGE2,y            ; page 2
    jmp _adv
_g3
    ;FAR_PEEK_Y $00, $58000
    LDAY_FAR $00, $058000
    ;lda RBUF_PAGE3,y            ; page 3

_adv:
    pha
    ; tail = tail + 1 (10-bit)
    inc RBUF_TAIL_LO
    bne _ok
    inc RBUF_TAIL_HI
    lda RBUF_TAIL_HI
    and #$03
    sta RBUF_TAIL_HI
_ok:
    lda CHARACTER_MODE
    beq _ok_done
    pla
    jsr CHAR_TRANSLATE
    plp
    clc
    rts

_ok_done:
    pla
    plp
    clc                         ; success
    rts

_empty:
    lda #$00
    plp
    sec
    rts


;=============================================================================
; Carry set if full
;=============================================================================
RBUF_IS_FULL:
    ; compute next = head+1
    lda RBUF_HEAD_LO
    sta HLO
    lda RBUF_HEAD_HI
    sta HHI
    clc
    lda HLO
    adc #1
    sta NEXT_LO
    lda HHI
    adc #0
    and #$03
    sta NEXT_HI
    jsr READ_TAIL_ATOMIC
    lda NEXT_LO
    cmp TMP_TAIL_LO
    bne _no
    lda NEXT_HI
    cmp TMP_TAIL_HI
    beq _yes
_no: 
    clc
    rts
_yes:
    sec
    rts

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

; temp storage
tmp_raster: .byte 0

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

    lda #$01
    rts

_not_same_net:
    lda #$00
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
    beq _IP_found_in_cache

    ; we need to check if we are on the same net to send the packet to.
    ; if we are, then we just need to check the arp cache for the mac address
    ; of the machine on the same net.  Otherwise, we use the mac address of
    ; the gateway.

    ; if a non-blocking connect is in progress, don't ARP or spin here.
    lda CONNECT_ACTIVE
    beq _do_arp_request             ; not connecting => old behavior ok (your tooling)

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
    beq _no_mac_yet
    jmp _IP_found_in_cache
    
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
    beq _no_mac_yet
    jmp _IP_found_in_cache

_no_mac_yet:
    pla                     ; restore flags byte
    sec                     ; C=1 => caller keeps polling
    rts

_handle_arp_cache_result:
    bne _IP_found_in_cache          ; if found in cache, skip ahead
                                    ; otherwise we need to do an ARP_REQUEST

_do_arp_request:                    ; use the IP we looked up in cache and do an ARP_REQUEST
    lda ARP_QUERY_IP+0
    sta ARP_REQUEST_IP+0
    lda ARP_QUERY_IP+1
    sta ARP_REQUEST_IP+1
    lda ARP_QUERY_IP+2
    sta ARP_REQUEST_IP+2
    lda ARP_QUERY_IP+3
    sta ARP_REQUEST_IP+3
    
    lda #$00
    sta ETH_STATE
    jsr ARP_REQUEST

    ; at this point, interrupts are disabled, but we need to re-enable them so an
    ; ARP request can be sent and the response dealt with.  There should be better
    ; ways to handle this though.  It also assumes there will be an ARP response
    ; for now, thats ok but real world, a failure will lock the machine.
    cli

_arp_reply_loop:                    ; wait for ARP reply
    lda ETH_STATE
    cmp #ETH_STATE_ARP_WAITING
    beq _arp_reply_loop

    ; disable interrupts
    sei

    jsr ARP_QUERY_CACHE             ; cache should be populated now, so query again
    jmp _handle_arp_cache_result    ; jump back up to confirm and query again if needed

    ; we now have the IP address in the cache and can continue building the packet
    ; ETH_TX_FRAME_DEST_MAC will be auto populated if cache hit
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

CALC_IPV4_CHECKSUM:

    ; clear results
    lda #$00
    sta _reslo
    sta _reshi
    sta _resex

    ; 1) Zero out the checksum field
    lda #$00
    sta IPV4_HDR_CHKSM
    lda #$00
    sta IPV4_HDR_CHKSM+1

    ; 3) Sum each of the ten 16-bit words (20 bytes total)
    ldx #$00                ; counter as we sum bytes
    ldy #$00                ; Y = offset into IPV4_HEADER (0,2,4,...,18)

_sum_word:
    lda IPV4_HEADER,Y
    sta _num1hi
    iny
    lda IPV4_HEADER,y
    sta _num1lo
    iny
    lda IPV4_HEADER,Y
    sta _num2hi
    iny
    lda IPV4_HEADER,Y
    sta _num2lo
    jsr _addwords

_loop
    lda _reslo
    sta _num1lo
    lda _reshi
    sta _num1hi

    iny
    lda IPV4_HEADER,Y
    sta _num2hi
    iny
    lda IPV4_HEADER,Y
    sta _num2lo
    jsr _addwords

    inx
    cpx #$08
    beq _add_overflow
    jmp _loop

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

    lda _num1lo              ; move result to 2nd value
    sta _num2lo
    lda _num1hi
    sta _num2hi
    lda #$ff                ; subtract value from $ffff
    sta _num1lo
    sta _num1hi
    jsr _subwords           ; final in reslo/reshi

    lda _reshi              ; move to header
    sta IPV4_HDR_CHKSM
    lda _reslo
    sta IPV4_HDR_CHKSM+1
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
    and #$03                          ; keep to 10-bit pages 0..3
    sta FREE_HI

    ; subtract 1 (mod 1024)
    sec
    lda FREE_LO
    sbc #1
    sta FREE_LO
    lda FREE_HI
    sbc #0
    and #$03
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


    ;lda #$ff                                    ; generate a 32 bit random sequence number between 0 - $ffffff
    ;sta RAND32_RANGE+0
    ;sta RAND32_RANGE+1
    ;sta RAND32_RANGE+2
    ;sta RAND32_RANGE+3

    ;jsr RAND32_SEED
    
    ;lda RAND32_VALUE+0                          ; copy sequence number
    ;sta TCP_HDR_SEQ_NUM+0
    ;lda RAND32_VALUE+1
    ;sta TCP_HDR_SEQ_NUM+1
    ;lda RAND32_VALUE+2
    ;sta TCP_HDR_SEQ_NUM+2
    ;lda RAND32_VALUE+3
    ;sta TCP_HDR_SEQ_NUM+3

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
    
    ;lda #0
    ;sta ETH_TX_FRAME_PAYLOAD_SIZE+1
    ;lda #20
    ;sta ETH_TX_FRAME_PAYLOAD_SIZE

    rts

WINUPDATE_THRESHOLD = $01    ; send update when we open by ≥1 bytes

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

; max size of 235 bytes.  fits with basic strings and helps with checksum calculation
; since tcp header = 20 bytes (with no options) + 235 bytes = 255 bytes
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

CLEAR_LOCAL_ISN:
    lda #$00
    sta LOCAL_ISN+0
    sta LOCAL_ISN+1
    sta LOCAL_ISN+2
    sta LOCAL_ISN+3
    sta LOCAL_ISN_TMP
    rts

CLEAR_REMOTE_ISN:
    lda #$00
    sta REMOTE_ISN+0
    sta REMOTE_ISN+1
    sta REMOTE_ISN+2
    sta REMOTE_ISN+3
    sta REMOTE_ISN_TMP
    sta REMOTE_ISN_TMP+1
    rts

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

;=========
; Tear everything down on RST (or fatal error)
TCP_HARD_RESET:
    ; state
    lda #$00
    sta ETH_RX_TCP_FLAGS

    lda #$00
    sta TIME_WAIT_COUNTER_LO
    sta TIME_WAIT_COUNTER_HI

    jsr CLEAR_LOCAL_ISN
    jsr CLEAR_REMOTE_ISN

    ; flush RX ring (optional, but avoids BASIC reading stale bytes)
    lda RBUF_HEAD_HI
    sta RBUF_TAIL_HI
    lda RBUF_HEAD_LO
    sta RBUF_TAIL_LO

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


; returns current event bits in A and clears them (BASIC can poll this for hard reset)
STATUS_LAST_EVENTS: .byte 0

; ETH_STATUS_POLL
; - Flush deferred TX (ACK/ARP) so IRQ never has to send
; - If we previously advertised a 0 window and we’ve freed space,
;   send a pure ACK to wake the peer (ETH_MAYBE_WINUPDATE)
; - Advance TIME_WAIT
; - If any events are latched, return them (and clear)
; - Otherwise return 0=connected/ok, 1=disconnected

ETH_STATUS_POLL:
    ; 1) Do non-IRQ work first
    jsr ETH_PROCESS_DEFERRED
    jsr ETH_MAYBE_WINUPDATE

    ; check for an handle any incoming packets
    jsr ETH_RCV

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

; Computes free = (TAIL - HEAD - 1) mod 1024 (10-bit),
; and if last advertised window was 0 and free >= threshold,
; sends a pure ACK to wake the sender.  No zero-page used.

ETH_MAYBE_WINUPDATE:
    ; ---- cur_free = (TAIL - HEAD - 1) mod 1024 ----
    jsr READ_HEAD_ATOMIC              ; fills TMP_HEAD_LO/TMP_HEAD_HI
    jsr READ_TAIL_ATOMIC              ; fills TMP_TAIL_LO/TMP_TAIL_HI

    lda TMP_TAIL_LO
    sec
    sbc TMP_HEAD_LO
    sta _cur_free_lo
    lda TMP_TAIL_HI
    sbc TMP_HEAD_HI
    and #$03
    sta _cur_free_hi

    ; cur_free -= 1
    sec
    lda _cur_free_lo
    sbc #1
    sta _cur_free_lo
    lda _cur_free_hi
    sbc #0
    and #$03
    sta _cur_free_hi

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

    ; ---- Build & send pure ACK (no data) to advertise the new window ----
    lda #$00
    sta TCP_DATA_PAYLOAD_SIZE
    sta TCP_DATA_PAYLOAD_SIZE+1
    lda #TCP_FLAG_ACK
    jsr ETH_BUILD_TCPIP_PACKET
    bcs _ret
 jsr ETH_PACKET_SEND
;;    jsr DEFER_CURRENT_TX

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


.include "arp.asm"
;.include "dhcp.asm"

;=============================================================================
; Main IRQ / Incoming data routine
;=============================================================================
*=$4000
ETH_RCV:
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
    ; ---- Keep only broadcast (bit5) OR unicast-to-me (bit6) ----
    lda RX_META1
    and #%01100000            ; isolate bits 6|5
    bne _accept_packet        ; if either set → keep

    lda #$01
    sta MEGA65_ETH_CTRL2
    lda #$03
    sta MEGA65_ETH_CTRL2
    rts

_accept_packet:
    ; length < 1600?
;    lda _len_msb
;    cmp #$06
;    bcc _do_copy              ; msb < 6  -> definitely < 1600
;    bne _length_too_big         ; msb > 6  -> definitely >= 1600

;    lda _len_lsb                ; msb == 6, compare low byte
;    cmp #$40
;    bcc _do_copy              ; lsb < 0x40 -> < 1600

;_length_too_big:
;    lda #$01
;    sta MEGA65_ETH_CTRL2
;    lda #$03
;    sta MEGA65_ETH_CTRL2
;    rts
; ===

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
    ; --- cap to 1614 (0x064E) = 14 hdr + 1600 payload ---
    lda _len_msb
    cmp #$06
    bcc _do_copy                 ; < 0x0600 → safe
    bne _do_cap                  ; > 0x06xx → cap unconditionally
    lda _len_lsb
    cmp #$4E                      ; == 0x06 → check low byte
    bcc _do_copy                 ; <= 0x064D → safe
_do_cap:
    lda #$4E
    sta _len_lsb
    lda #$06
    sta _len_msb
;===
_do_copy:
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

    ; verify dest mac or broadcast
    ;jsr ETH_IS_PACKET_FOR_US
    ;beq _unknown_packet

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
    lda ETH_RX_FRAME_PAYLOAD+6          ; high byte of OPER
    ora ETH_RX_FRAME_PAYLOAD+7          ; now A = OPER_hi|OPER_lo
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
    ; IPv4: keep only TCP (protocol = $06). Drop everything else (UDP, ICMP, etc.)
    lda ETH_RX_FRAME_HEADER+23         ; IPv4 Protocol byte (14 + 9)
    cmp #$06                           ; TCP?
    beq _call_incoming_tcp
    rts

_call_incoming_tcp
    jmp INCOMING_TCP_PACKET

_unknown_packet:
    rts

RX_META1:
    .byte $00

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

;=============================================================================
; Routine to handle incoming TCP packet
;=============================================================================
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

    ; src IP must be REMOTE_IP (once we are trying to talk to a peer)
    ; (do this unconditionally; if you prefer, you can skip while CLOSED)
    ldy #0
_chk_sip:
    lda ETH_RX_FRAME_PAYLOAD+12,y    ; IPv4 src at +12..+15
    cmp REMOTE_IP,y
    bne _drop
    iny
    cpy #4
    bne _chk_sip

    ; verify this is our socket (dst port at ip_len+2) ----
    lda ETH_RX_FRAME_PAYLOAD+2,x      ; dst port hi
    cmp LOCAL_PORT+0
    bne _drop
    lda ETH_RX_FRAME_PAYLOAD+3,x      ; dst port lo
    cmp LOCAL_PORT+1
    bne _drop

    ; ---- TCP flags at ip_len + 13 ----
    lda ETH_RX_FRAME_PAYLOAD+13,x
    sta ETH_RX_TCP_FLAGS

    ; SEG.SEQ → SEG_SEQ[0..3] (big endian)
    lda ETH_RX_FRAME_PAYLOAD+4,x
    sta SEG_SEQ+0
    lda ETH_RX_FRAME_PAYLOAD+5,x
    sta SEG_SEQ+1
    lda ETH_RX_FRAME_PAYLOAD+6,x
    sta SEG_SEQ+2
    lda ETH_RX_FRAME_PAYLOAD+7,x
    sta SEG_SEQ+3

    ; ---- compute payload size and TCP_DATA_OFFSET (payload start) ----
    jsr CALC_RX_TCP_BYTE_COUNT

    ; hand off to the state machine (still in IRQ context)
    jmp TCP_STATE_HANDLER

_drop:
    rts

CHAR_TRANSLATE:
    pha
    lda CHARACTER_MODE
    beq _no_translate

    pla             ; get ASCII char back

    ; --- A-Z (0x41–0x5A) need to become PETSCII lowercase (0xC1–0xDA) ---
    cmp #$41
    bcc _check_lower
    cmp #$5B
    bcs _check_lower
    ora #$80        ; force bit 7 → makes PETSCII lowercase
    rts

_check_lower:
    ; --- a-z (0x61–0x7A) need to become PETSCII uppercase (0x41–0x5A) ---
    cmp #$61
    bcc _printable
    cmp #$7B
    bcs _printable
    and #$DF        ; clear bit 5 → fold to uppercase
    rts

_printable:
    ; leave digits, symbols, etc. as-is
    rts

_no_translate:
    pla
    rts

; ==== Ring configuration (no zero-page) ====

RBUF_PAGE0      = RBUF_BASE + $000
RBUF_PAGE1      = RBUF_BASE + $100
RBUF_PAGE2      = RBUF_BASE + $200
RBUF_PAGE3      = RBUF_BASE + $300

; Producer (IRQ) publishes HEAD; consumer (mainline) publishes TAIL
RBUF_HEAD_LO:   .byte 0
RBUF_HEAD_HI:   .byte 0                  ; 0..3
RBUF_TAIL_LO:   .byte 0
RBUF_TAIL_HI:   .byte 0                  ; 0..3

; temps (not ZP)
TMP_TAIL_LO:    .byte 0
TMP_TAIL_HI:    .byte 0
TMP_HEAD_LO:    .byte 0
TMP_HEAD_HI:    .byte 0
NEXT_LO:        .byte 0
NEXT_HI:        .byte 0
HLO:            .byte 0
HHI:            .byte 0
FREE_LO:        .byte 0
FREE_HI:        .byte 0

ADV_WINDOW_LAST_LO: .byte 0
ADV_WINDOW_LAST_HI: .byte 0

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

;RBUF_BASE: .fill 1024, $00                  ; 1 KiB aligned (4 pages)
RBUF_BASE = $0000

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

SEG_SEQ: .byte 0,0,0,0

ETH_TX_FRAME_HEADER:
ETH_TX_FRAME_DEST_MAC:
    .byte $ff, $ff, $ff, $ff, $ff, $ff
ETH_TX_FRAME_SRC_MAC:
    .byte $00, $00, $00, $00, $00, $00
ETH_TX_TYPE:
    .byte $08, $06
ETH_TX_FRAME_PAYLOAD:
    .fill 1600, $00

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
ETH_RX_FRAME_PAYLOAD_SIZE:
    .byte $00, $00
TCP_RX_DATA_PAYLOAD_SIZE:
    .byte $00, $00

ACK_REPLY_PENDING: .byte 0
ACK_REPLY_LEN_L:   .byte 0
ACK_REPLY_LEN_H:   .byte 0
ACK_REPLY_PACKET:  .fill 60, $00       ; 60 bytes is enough (14+20+20), 60 gives slack
