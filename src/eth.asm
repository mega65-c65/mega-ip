
.include "macros.asm"
.include "mega65.asm"


.cpu "45gs02"

TCP_FLAG_SYN = $02
TCP_FLAG_ACK = $10
TCP_FLAG_PSH = $08
TCP_FLAG_FIN = $01
TCP_FLAG_RST = $04

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

EXEC_BANK = $04     ; code is running from $42000
*=$2000

    ; Jump table for various functions
    jmp ETH_INIT
    jmp ETH_SET_GATEWAY_IP
    jmp ETH_SET_LOCAL_IP
    jmp ETH_SET_REMOTE_IP
    jmp ETH_SET_REMOTE_PORT
    jmp ETH_SET_SUBNET_MASK
    jmp ETH_TCP_CONNECT
    jmp ETH_TCP_SEND
    jmp ETH_TCP_SEND_STRING
    jmp RBUF_GET
    jmp ETH_TCP_DISCONNECT
    jmp ETH_STATUS_POLL

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

; Ring buffer layout in RAM
RBUF_HEAD:
    .byte $00
RBUF_TAIL:
    .byte $00

; recieved tcp data buffer
RBUF_BASE:
TCP_RX_DATA_BUFFER:
.fill 256, $00

; 2×MSL = 60 s → 600 ticks of 100 ms → 0x0258
TIME_WAIT_COUNTER_LO:
.byte $58

TIME_WAIT_COUNTER_HI:
.byte $02

; recieved tcp data buffer

; Constants for runtime addresses
IRQ_BASE = $1600
VEC_TABLE_ADDR = (ETH_VEC_TABLE - ETH_RCV_IRQ) + IRQ_BASE
CUST_IRQ_ADDR  = (ETH_CUST_IRQ - ETH_RCV_IRQ) + IRQ_BASE
IRQ_RETURN_ADDR = (ETH_IRQ_RETURN - ETH_RCV_IRQ) + IRQ_BASE

ETH_RCV_IRQ:
; This is the installer code that runs once via JSR $1600
.byte $38                                          ; SEC
.byte $a2, <VEC_TABLE_ADDR                        ; LDX #<vectable
.byte $a0, >VEC_TABLE_ADDR                        ; LDY #>vectable
.byte $20, $8d, $ff                               ; JSR $FF8D (VECTOR - read table)

; Copy original IIRQ vector to our JMP instruction
.byte $ad, <VEC_TABLE_ADDR, >VEC_TABLE_ADDR       ; LDA vectable (IIRQ low)
.byte $8d, <(IRQ_RETURN_ADDR+1), >(IRQ_RETURN_ADDR+1)  ; STA jmp+1
.byte $ad, <(VEC_TABLE_ADDR+1), >(VEC_TABLE_ADDR+1)    ; LDA vectable+1 (IIRQ high)
.byte $8d, <(IRQ_RETURN_ADDR+2), >(IRQ_RETURN_ADDR+2)  ; STA jmp+2

; Write our custom IRQ address to IIRQ vector
.byte $a9, <CUST_IRQ_ADDR                         ; LDA #<custom_irq
.byte $8d, <VEC_TABLE_ADDR, >VEC_TABLE_ADDR       ; STA vectable
.byte $a9, >CUST_IRQ_ADDR                         ; LDA #>custom_irq
.byte $8d, <(VEC_TABLE_ADDR+1), >(VEC_TABLE_ADDR+1)    ; STA vectable+1

; Install updated vector table
.byte $18                                          ; CLC
.byte $a2, <VEC_TABLE_ADDR                        ; LDX #<vectable
.byte $a0, >VEC_TABLE_ADDR                        ; LDY #>vectable
.byte $20, $8d, $ff                               ; JSR $FF8D (VECTOR - set table)
.byte $60                                          ; RTS

; The actual IRQ handler starts here (at offset $27 from $1600 = $1627)
ETH_CUST_IRQ:
; KERNAL has already saved A, X, Y, Z, B on stack
; We just need to save ZP locations we use

.byte $A5, $02                                    ; LDA $02
.byte $48                                          ; PHA
.byte $A5, $03                                    ; LDA $03
.byte $48                                          ; PHA
.byte $A5, $04                                    ; LDA $04
.byte $48                                          ; PHA
.byte $A5, $05                                    ; LDA $05
.byte $48                                          ; PHA

; Set up JSRFAR parameters
.byte $A9, EXEC_BANK                              ; LDA #EXEC_BANK
.byte $85, $02                                    ; STA $02
.byte $A9, >ETH_RCV                               ; LDA #>ETH_RCV
.byte $85, $03                                    ; STA $03
.byte $A9, <ETH_RCV                               ; LDA #<ETH_RCV
.byte $85, $04                                    ; STA $04
.byte $A9, $04                                    ; LDA #$04
.byte $85, $05                                    ; STA $05
.byte $20, $6E, $FF                               ; JSR $FF6E (JSRFAR)

; Restore ZP locations
.byte $68                                          ; PLA
.byte $85, $05                                    ; STA $05
.byte $68                                          ; PLA
.byte $85, $04                                    ; STA $04
.byte $68                                          ; PLA
.byte $85, $03                                    ; STA $03
.byte $68                                          ; PLA
.byte $85, $02                                    ; STA $02

ETH_IRQ_RETURN:
.byte $4C, $00, $00                               ; JMP $0000 (will be modified)

; Vector table (56 bytes)
ETH_VEC_TABLE:
.fill 56, $00

ETH_RCV_IRQ_END:

IRQ_LEN = ETH_RCV_IRQ_END - ETH_RCV_IRQ

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
    sta RBUF_HEAD
    sta RBUF_TAIL

    ; install IRQ handler if not already installed
    ;FAR_PEEK $00, $001600
    ;cmp #$38
    ;beq _clear_buffer

 ;   sta $D707
 ;   .byte $00                   ; end of job options
 ;   .byte $00                   ; copy
 ;   .byte IRQ_LEN, $00          ; length lsb, msb
 ;   .byte <ETH_RCV_IRQ, >ETH_RCV_IRQ, EXEC_BANK   ; src lsb, msb, bank
 ;   .byte $00, $16, $00         ; dest ($1600 in bank 0)
 ;   .byte $00                   ; command high byte
 ;   .word $0000                 ; modulo (ignored)

    ; Manual copy for debugging
    ldx #$00
_copy_loop:
    lda ETH_RCV_IRQ,x
    sta $01600,x
    inx
    cpx #IRQ_LEN
    bne _copy_loop

    jsr $1600                   ; start rcv irq
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
    stz LOCAL_IP+3
    rts

;=============================================================================
; Set remote IP
;=============================================================================
ETH_SET_REMOTE_IP:
    sta REMOTE_IP+0
    stx REMOTE_IP+1
    sty REMOTE_IP+2
    stz REMOTE_IP+3
    rts

;=============================================================================
; Set gateway IP
;=============================================================================
ETH_SET_GATEWAY_IP:
    sta GATEWAY_IP+0
    stx GATEWAY_IP+1
    sty GATEWAY_IP+2
    stz GATEWAY_IP+3
    rts

;=============================================================================
; Set subnet mask
;=============================================================================
ETH_SET_SUBNET_MASK:
    sta SUBNET_MASK+0
    stx SUBNET_MASK+1
    sty SUBNET_MASK+2
    stz SUBNET_MASK+3
    rts

;=============================================================================
; Set remote port
;=============================================================================
ETH_SET_REMOTE_PORT:
    sta REMOTE_PORT+0
    stx REMOTE_PORT+1
    rts

;=============================================================================
; Attempt to initiate a TCP connection
;=============================================================================
ETH_TCP_CONNECT:

    ; if idle, we can initiate a connection by sending a SYN
    lda TCP_STATE
    cmp #TCP_STATE_CLOSED
    beq _send_SYN

    ; not closed - hand off to handler routine
    jmp TCP_STATE_HANDLER

_send_SYN:

    ; generate a local ephemeral port number (start at $c000 and just add 1)
    lda LOCAL_PORT+1
    clc
    adc #$01
    sta LOCAL_PORT+1
    lda LOCAL_PORT+0
    adc #$00
    sta LOCAL_PORT+0

    jsr CLEAR_TCP_PAYLOAD

    lda #$00
    sta ETH_RX_TCP_FLAGS

    jsr CLEAR_LOCAL_ISN
    jsr CLEAR_REMOTE_ISN

    lda #TCP_FLAG_SYN
    jsr ETH_BUILD_TCPIP_PACKET
    bcs _connect_fail

    jsr ETH_PACKET_SEND

    lda #TCP_STATE_SYN_SENT
    sta TCP_STATE

    jsr CALC_LOCAL_ISN

    jmp TCP_STATE_HANDLER

_connect_fail:
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
;    jmp TCP_STATE_HANDLER

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
    lda TCP_STATE
    cmp #TCP_STATE_ESTABLISHED
    bne _exit

    ; get size of A$ if defined
    FAR_PEEK $00, $FD60

    ; if zero length, exit
    beq _exit

    ; stash size otherwise
    sta _var_len

    ; get address
    FAR_PEEK $00, $FD61
    sta _var_addr

    FAR_PEEK $00, $FD62
    sta _var_addr+1

    ; now we will get the bytes and put them in the payload
    lda _var_len
    sta TCP_DATA_PAYLOAD_SIZE

php
sei
    ; use DMA to copy the bytes
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

_exit:
    rts

; Process deferred ARP reply from mainline
ETH_PROCESS_DEFERRED:
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
    lda ARP_REPLY_PACKET
    sta ETH_TX_FRAME_DEST_MAC
    
    lda #$2a
    sta ETH_TX_LEN_LSB
    lda #$00
    sta ETH_TX_LEN_MSB

    jsr ETH_PACKET_SEND
_epd_done:
    rts

;=============================================================================
; TCP state handler
;=============================================================================
TCP_STATE_HANDLER:

    ;jsr ETH_PROCESS_DEFERRED
    lda ETH_RX_TCP_FLAGS
    and #TCP_FLAG_RST
    beq _not_RST

    ; remote sent RST → tear down immediately
    ;lda #TCP_STATE_CLOSED
    ;sta TCP_STATE
jsr TCP_HARD_RESET
    rts

_not_RST:

    lda TCP_STATE

_check_ESTABLISHED:
    cmp #TCP_STATE_ESTABLISHED
    bne _check_CLOSED

    ;--- if the peer is closing too (FIN+ACK), go handle that first ---
    lda ETH_RX_TCP_FLAGS
    and #(TCP_FLAG_FIN|TCP_FLAG_ACK)
    cmp #(TCP_FLAG_FIN|TCP_FLAG_ACK)
    beq _got_FIN_IN_ESTABLISHED

    ; ——— did we get an ACK for our last PSH? ———
    ;lda ETH_RX_TCP_FLAGS
    ;and #TCP_FLAG_ACK
    ;cmp #TCP_FLAG_ACK
    ;beq _got_data_ack

    ;--- at this point, we have a server packet with possible incoming data to process
    lda TCP_RX_DATA_PAYLOAD_SIZE        ; previously calculated from INCOMING_TCP_PACKET
    beq _est_done                       ; no data to handle

    ;--- copy data to a small recieve buffer that BASIC will need to read from
    ldy #$00
_lp_copy_data: 
    jsr RBUF_IS_FULL                    ; if buffer is full, no choice...just ack the data
    bcs _ack_data                       ; we will do a proper window resizing soon
    lda ETH_RX_FRAME_PAYLOAD+20+20, y
    jsr RBUF_PUT 
    iny
    cpy TCP_RX_DATA_PAYLOAD_SIZE
    bne _lp_copy_data

    ; then ACK the data:
_ack_data:

    lda #$00
    sta TCP_DATA_PAYLOAD_SIZE
    sta TCP_DATA_PAYLOAD_SIZE+1   ; ensure 0-length outbound segment

    lda #$00
    sta REMOTE_ISN_BUMP
    jsr CALC_REMOTE_ISN                 ; ADVANCE REMOTE_ISN by +1+payload
    lda #TCP_FLAG_ACK
    jsr ETH_BUILD_TCPIP_PACKET
    jsr ETH_PACKET_SEND
    
    rts

_got_data_ack:
    rts

_got_FIN_IN_ESTABLISHED:
    ; peer wants to close → ACK their FIN
    lda #$01
    sta REMOTE_ISN_BUMP
    jsr CALC_REMOTE_ISN              ; +1 for the FIN
    lda #TCP_FLAG_ACK
    jsr ETH_BUILD_TCPIP_PACKET
    jsr ETH_PACKET_SEND

    ; move into CLOSE_WAIT so application can call disconnect
    lda #TCP_STATE_CLOSE_WAIT
    sta TCP_STATE
    rts

_est_done:
    rts

_check_CLOSED:
    ; if closed, nothing to do. return
    cmp #TCP_STATE_CLOSED
    bne _check_SYN
    rts

_check_SYN:
    ; if SYN, await the SYN/ACK
    cmp #TCP_STATE_SYN_SENT
    bne _check_FIN_WAIT_1

    lda ETH_RX_TCP_FLAGS
    and #(TCP_FLAG_SYN|TCP_FLAG_ACK)
    cmp #(TCP_FLAG_SYN|TCP_FLAG_ACK)
    bne _wait_and_loop

_got_SYNACK:
    ; bump REMOTE_ISN + 1 (no data)
    lda #$01
    sta REMOTE_ISN_BUMP
    jsr CALC_REMOTE_ISN
    ; build & send the final ACK
    lda #TCP_FLAG_ACK
    jsr ETH_BUILD_TCPIP_PACKET
    jsr ETH_PACKET_SEND

    ; handshake complete
    lda #TCP_STATE_ESTABLISHED
    sta TCP_STATE
    rts

_check_FIN_WAIT_1:
    cmp #TCP_STATE_FIN_WAIT_1
    bne _check_FIN_WAIT_2

    lda ETH_RX_TCP_FLAGS
    and #TCP_FLAG_ACK
    cmp #TCP_FLAG_ACK
    bne _wait_and_loop

_got_FIN_WAIT_1_ACK:
    lda #TCP_STATE_FIN_WAIT_2
    sta TCP_STATE
    jmp _wait_and_loop

_check_FIN_WAIT_2:
    ; await the FIN/ACK
    cmp #TCP_STATE_FIN_WAIT_2
    bne _check_TIME_WAIT

    lda ETH_RX_TCP_FLAGS
    and #(TCP_FLAG_FIN|TCP_FLAG_ACK)
    cmp #(TCP_FLAG_FIN|TCP_FLAG_ACK)
    bne _wait_and_loop

_got_FIN_ACK:
    ; consume the peer's FIN (+1 on remote sequence)
    lda #$01
    sta REMOTE_ISN_BUMP
    jsr CALC_REMOTE_ISN

    ; send final ACK
    lda #TCP_FLAG_ACK
    jsr ETH_BUILD_TCPIP_PACKET
    jsr ETH_PACKET_SEND

    ; reset TIME_WAIT counter
    lda #$02
    sta TIME_WAIT_COUNTER_HI
    lda #$58
    sta TIME_WAIT_COUNTER_LO

    lda #TCP_STATE_TIME_WAIT
    sta TCP_STATE
    jmp _wait_and_loop

_check_TIME_WAIT:
    cmp #TCP_STATE_TIME_WAIT
    bne _check_CLOSE_WAIT
    jsr TIME_WAIT_TICK
    rts

_check_CLOSE_WAIT:
    cmp #TCP_STATE_CLOSE_WAIT
    bne _check_LAST_ACK

    ; build & send FIN+ACK
    lda #TCP_FLAG_FIN|TCP_FLAG_ACK
    jsr ETH_BUILD_TCPIP_PACKET
    jsr ETH_PACKET_SEND
    ; move to LAST_ACK
    lda #TCP_STATE_LAST_ACK
    sta TCP_STATE
    rts

_check_LAST_ACK:
    cmp #TCP_STATE_LAST_ACK
    bne _other

    lda ETH_RX_TCP_FLAGS
    and #TCP_FLAG_ACK
    cmp #TCP_FLAG_ACK
    bne _wait_and_loop

    ; peer ACK’d your FIN, now go TIME_WAIT
    lda #$02
    sta TIME_WAIT_COUNTER_HI
    lda #$58
    sta TIME_WAIT_COUNTER_LO

    lda #TCP_STATE_TIME_WAIT
    sta TCP_STATE
    rts

_other:
    ; not sure what would get us here
    rts

_wait_and_loop:
;    jsr ETH_WAIT_100MS
;    jmp TCP_STATE_HANDLER
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

_done:
    rts

;=============================================================================
; A = byte to write
; Carry set if buffer full, clear if success
;=============================================================================
RBUF_PUT:
    pha

    lda RBUF_HEAD
    clc
    adc #1                ; head + 1
    cmp RBUF_TAIL
    beq _full             ; if next head == tail, buffer full
    sta _next_head

    ldx RBUF_HEAD
    pla
    sta RBUF_BASE,x       ; store byte to buffer

    lda _next_head
    sta RBUF_HEAD

    clc                   ; success
    rts

_full:
    pla
    sec
    rts

_next_head:
    .byte $00

;=============================================================================
; Returns byte in A
; Carry set if buffer empty, clear if success
;=============================================================================
RBUF_GET:
    lda RBUF_HEAD
    cmp RBUF_TAIL
    beq _empty              ; nothing to read

    ldx RBUF_TAIL
    lda RBUF_BASE,x         ; get byte
    inc RBUF_TAIL           ; advance tail

    clc                     ; success
    rts

_empty:
    lda #$00
    sec
    rts

;=============================================================================
; Carry set if empty
;=============================================================================
RBUF_IS_EMPTY:
    lda RBUF_HEAD
    cmp RBUF_TAIL
    beq _yes
    clc
    rts
_yes:
    sec
    rts

;=============================================================================
; Carry set if full
;=============================================================================
RBUF_IS_FULL:
    lda RBUF_HEAD
    clc
    adc #1
    cmp RBUF_TAIL
    beq _yes
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

;-   lda MEGA65_ETH_CTRL1
;    and #$80
;    beq -
;    rts

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
    ;.byte $00, $00, $05         ; debug destination
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
    jmp _handle_arp_cache_result
    
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

    ; restore the processor register, which will disable interrupts again
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
IPV4_HDR_TTL:       .byte $80                   ; time to live hops to dest
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

    lda LOCAL_PORT+0                            ; copy ephimeral and remote ports
    sta TCP_HDR_SRC_PORT+0
    lda LOCAL_PORT+1
    sta TCP_HDR_SRC_PORT+1

    lda REMOTE_PORT+0
    sta TCP_HDR_DST_PORT+0
    lda REMOTE_PORT+1
    sta TCP_HDR_DST_PORT+1

 ;   lda #$00                                    ; set window size to 255 bytes (could be higher)
 ;   sta TCP_HDR_WINDOW
 ;   lda #$ff
 ;   sta TCP_HDR_WINDOW+1

; =====
; --- compute advertised window from ring free space (0..255) ---
; free = (TAIL - HEAD - 1) mod 256
    lda RBUF_TAIL
    sec
    sbc RBUF_HEAD
    sbc #1
    sta TCP_HDR_WINDOW+1   ; low byte
    lda #$00
    sta TCP_HDR_WINDOW     ; high byte (we cap at 255)

; =====
    
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

; we will max our data payload at 235 bytes which is small, but
; fits well with BASIC string sizes (tcp header = 20 + 235 = 255)
TCP_DATA_PAYLOAD_SIZE:
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
    lda #20
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
    ; —— now sum the 10 words of the TCP header ——
    ldx #$0a                ; x = 10 (count of words)
    ldy #$00                ; y = 0 (each byte)

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

; --- ADD THIS: end-around carry if that addition overflowed ---
    bcc _no_final_carry     ; if no carry from the high-byte add, skip
    inc _num1lo             ; add the end-around carry back in
    bne _no_final_carry
    inc _num1hi
;---
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
    cpy #233
    beq _done
    iny
    jmp _lp_copy

_done:
    sta TCP_DATA_PAYLOAD_SIZE
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

    ;—— 1) Pull IP Total-Length into TMP_HI:TMP_LO ——  
    lda ETH_RX_FRAME_PAYLOAD+3    ; low byte of Total-Length  
    sta _TMP_LO  
    lda ETH_RX_FRAME_PAYLOAD+2    ; high byte of Total-Length  
    sta _TMP_HI  

    ;—— 2) Subtract the IP header length ——  
    ; IHL is low nibble of byte 0, in 32-bit words → ×4 = bytes  
    lda ETH_RX_FRAME_PAYLOAD      ; Version/IHL  
    and #$0F                      ; isolate IHL  
    asl                           ; ×2  
    asl                           ; ×4  
    sta _TMP_IP_HDR_LEN            ; now holds IP-header bytes (usually 20)  

    sec                           ; prepare for subtraction  
    lda _TMP_LO  
    sbc _TMP_IP_HDR_LEN            ; low–byte subtract  
    sta _TMP_LO  
    lda _TMP_HI 
    sbc #$00                      ; high–byte subtract  
    sta _TMP_HI  

    ;—— 3) Subtract the TCP header length ——  
    ; Data-Offset is high nibble of byte (20+12) in payload; value = words  
    lda ETH_RX_FRAME_PAYLOAD+32   ; that's payload-offset 20 + 12  
    and #$F0                      ; isolate high nibble (DataOffset<<4)  
    lsr                           ; >>1  
    lsr                           ; >>2  
    lsr                           ; >>3  
    lsr                           ; >>4  ; now A = DataOffset in 32-bit words  
    asl                           ; *2  
    asl                           ; *4  ; A = TCP-header bytes (usually 20)  
    sta _TMP_TCP_HDR_LEN  

    sec  
    lda _TMP_LO  
    sbc _TMP_TCP_HDR_LEN           ; subtract low byte  
    sta _TMP_LO  
    lda _TMP_HI
    sbc #$00  
    sta _TMP_HI 
    
    lda _TMP_LO
    sta TCP_RX_DATA_PAYLOAD_SIZE
    lda _TMP_HI
    sta TCP_RX_DATA_PAYLOAD_SIZE+1

    ; now TCP_RX_DATA_PAYLOAD_SIZE = number of data bytes in the TCP segment (little endian)
    rts

_TMP_LO:
    .byte $00
_TMP_HI:
    .byte $00

_TMP_IP_HDR_LEN:
    .byte $00

_TMP_TCP_HDR_LEN:
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
    lda RBUF_HEAD
    sta RBUF_TAIL

    ; mark closed
    lda #$00
    sta ETH_STATE            ; if you use it for TX/RX gate
    lda #TCP_STATE_CLOSED
    sta TCP_STATE

    lda #$00
    sta REMOTE_ISN_BUMP

    lda #$00
    sta TCP_DATA_PAYLOAD_SIZE

    ; notify BASIC: set a sticky event flag it can poll
    ; bit0 = RST seen
    lda TCP_EVENT_FLAG
    ora #$01
    sta TCP_EVENT_FLAG
    rts

TCP_EVENT_FLAG
    .byte $00


; returns current event bits in A and clears them (BASIC can poll this for hard reset)
ETH_STATUS_POLL:
    jsr ETH_PROCESS_DEFERRED

   ; Allow TIME_WAIT to progress while BASIC polls
   lda TCP_STATE
   cmp #TCP_STATE_TIME_WAIT
   bne _no_tw
   jsr TIME_WAIT_TICK

_no_tw:
    lda TCP_EVENT_FLAG
    pha
    lda #$00
    sta TCP_EVENT_FLAG
    pla
    rts

;==========


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
    bne _accept_packet
    ;jsr ETH_PROCESS_DEFERRED 
    rts

_accept_packet:
    ; Acknowledge the ethernet frame, freeing the buffer up for next RX
    lda #$01
    sta MEGA65_ETH_CTRL2
    lda #$03
    sta MEGA65_ETH_CTRL2

;==============
; --- Early filter using NIC’s 2 status bytes (before any DMA) ---
; Buffer layout per MEGA65 doc (per received frame):
;   +0 : length LSB
;   +1 : [bits 0..3: length MSB nibble]
;        bit4 = 1 → multicast
;        bit5 = 1 → broadcast
;        bit6 = 1 → unicast-to-me (matches MACADDR)
;        bit7 = 1 → CRC error (bad frame)

    ; Peek meta byte 0 (length LSB) — optional, but handy to have
    FAR_PEEK $ff, $0de800
    sta _rx_len_lsb

    ; Peek meta byte 1 (flags + length MSB nibble)
    FAR_PEEK $ff, $0de801
    sta _rx_meta1

    ; ---- Drop CRC-bad frames fast (bit7) ----
 ;   lda _rx_meta1
 ;   and #%10000000
 ;   beq _chk_multicast
    ; ack & bail
    ;lda #$01
    ;sta MEGA65_ETH_CTRL2
    ;lda #$03
    ;sta MEGA65_ETH_CTRL2
 ;   rts

_chk_multicast:
    ; ---- Drop multicast (bit4) ----
    lda _rx_meta1
    and #%00010000
    beq _chk_dest_ok
    ; ack & bail
    lda #$01
    sta MEGA65_ETH_CTRL2
    lda #$03
    sta MEGA65_ETH_CTRL2
    ;jsr ETH_PROCESS_DEFERRED 
    rts

_chk_dest_ok:
    jmp _accept_for_us
    ; ---- Keep only broadcast (bit5) OR unicast-to-me (bit6) ----
;    lda _rx_meta1
;    and #%01100000            ; isolate bits 6|5
;    bne _accept_for_us        ; if either set → keep
    ; otherwise: not for us → drop
    ;lda #$01
    ;sta MEGA65_ETH_CTRL2
    ;lda #$03
    ;sta MEGA65_ETH_CTRL2
;    rts

_rx_len_lsb: .byte $00
_rx_meta1:   .byte $00

_accept_for_us:
;=============
    ; get the length of bytes in incoming RX buffer
    ; using full 32 bit access method

    ;lda #$00        ; byte 0 LSB of length
    ;sta $45
    ;lda #$e8
    ;sta $46
    ;lda #$0d 
    ;sta $47
    ;lda #$ff
    ;sta $48

    ;ldz #$00
    ;lda [$45],z

    FAR_PEEK $ff, $0de800
    sta _len_lsb                ; store lsb in our inline dma command

    ; MSB nibble from meta byte 1
    FAR_PEEK $ff, $0de801
    and #$0f
    sta _len_msb

    ;lda #$01                    ; byte 1 MSB of length (first 4 bits)
    ;sta $45
    ;lda [$45],z                 ; peek it again
    ;and #$0f                    ; strip upper 4 bits
    ;sta _len_msb                ; store msb in our inline dma command

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




; Drop IPv6 outright
;    lda ETH_RX_TYPE
;    cmp #$86
;    bne _rx_not_ipv6
;    lda ETH_RX_TYPE+1
;    cmp #$DD
;    bne _rx_not_ipv6
;    rts

;_rx_not_ipv6:
; Drop IPv6 multicast MAC 33:33:xx:xx:xx:xx (in case hardware filter changes)
;    lda ETH_RX_FRAME_DEST_MAC+0
;    cmp #$33
;    bne _rx_continue
;    lda ETH_RX_FRAME_DEST_MAC+1
;    cmp #$33
;    bne _rx_continue

;_forever:
;    inc $d021
;    jmp _forever
;
 ;   rts


_rx_continue:

; --- classify by EtherType first ---
    lda ETH_RX_TYPE
    cmp #$08
    bne _unknown_packet

    lda ETH_RX_TYPE+1
    cmp #$06
    beq _is_arp              ; handle ARP without MAC gating

    ; confirm if this packet is for us
    jsr ETH_IS_PACKET_FOR_US
    beq _unknown_packet
    jmp _tcp_packet_check

    ;lda ETH_RX_TYPE
    ;cmp #$08                            ; is packet $08xx?
    ;bne _unknown_packet                 ; no - ignore this packet

;_arp_packet_check:
;    lda ETH_RX_TYPE+1
;    cmp #$06                            ; is packet $0806 (ARP)?
;    bne _tcp_packet_check

_is_arp:
    lda ETH_RX_FRAME_PAYLOAD+6          ; high byte of OPER
    ora ETH_RX_FRAME_PAYLOAD+7          ; now A = OPER_hi|OPER_lo
    cmp #$01                            ; = 1 (request)?
    beq _call_arp_reply
    cmp #$02                            ; = 2 (reply)?
    beq _call_arp_update_cache
    ;jsr ETH_PROCESS_DEFERRED 
    rts                                 ; neither request nor reply → ignore

_tcp_packet_check:
    lda ETH_RX_TYPE+1
    cmp #$00                            ; is packet $0800 (TCP)?
    bne _unknown_packet

_tcp_socket_check:
    ; correct: verify dst == our local ephemeral
    lda ETH_RX_FRAME_PAYLOAD+20+2   ; TCP dst port hi
    cmp LOCAL_PORT+0
    bne _unknown_packet
    lda ETH_RX_FRAME_PAYLOAD+20+3   ; TCP dst port lo
    cmp LOCAL_PORT+1
    bne _unknown_packet
    jmp INCOMING_TCP_PACKET

_unknown_packet:
    ;jsr ETH_PROCESS_DEFERRED 
    rts

_call_arp_reply:
    jmp ARP_REPLY

_call_arp_update_cache:
    jmp ARP_UPDATE_CACHE

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
    beq _tcp_check
    rts
_tcp_check:
    lda ETH_RX_FRAME_PAYLOAD+9
    cmp #$06
    beq _tcp_ok
    rts
_tcp_ok:
    ;inc $d020
    ;lda $d020
    ;cmp #$0f
    ;bne _extract_flags
    ;lda #$00
    ;sta $d020

_extract_flags:
    lda ETH_RX_FRAME_PAYLOAD+20+13      ; TCP FLAGS
    sta ETH_RX_TCP_FLAGS

;lda ETH_RX_FRAME_PAYLOAD+20+4   ; SEQ[31:24]
;sta REMOTE_ISN+0
;lda ETH_RX_FRAME_PAYLOAD+20+5   ; SEQ[23:16]
;sta REMOTE_ISN+1
;lda ETH_RX_FRAME_PAYLOAD+20+6   ; SEQ[15:8]
;sta REMOTE_ISN+2
;lda ETH_RX_FRAME_PAYLOAD+20+7   ; SEQ[7:0]
;sta REMOTE_ISN+3

_retain_remote_isn:
    ; stash seq number in REMOTE_ISN
    lda ETH_RX_FRAME_PAYLOAD+20+4       ; SEQ number
    sta REMOTE_ISN+0
    lda ETH_RX_FRAME_PAYLOAD+20+5
    sta REMOTE_ISN+1
    lda ETH_RX_FRAME_PAYLOAD+20+6
    sta REMOTE_ISN+2
    lda ETH_RX_FRAME_PAYLOAD+20+7
    sta REMOTE_ISN+3

    jsr CALC_RX_TCP_BYTE_COUNT      ; fills TCP_RX_DATA_PAYLOAD_SIZE
    
    jmp TCP_STATE_HANDLER



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

ETH_TX_FRAME_HEADER:
ETH_TX_FRAME_DEST_MAC:
    .byte $ff, $ff, $ff, $ff, $ff, $ff
ETH_TX_FRAME_SRC_MAC:
    .byte $00, $00, $00, $00, $00, $00
ETH_TX_TYPE:
    .byte $08, $06
ETH_TX_FRAME_PAYLOAD:
    .fill 1500, $00
;ETH_TX_FRAME_PAYLOAD_SIZE
;    .byte $00, $00

ETH_RX_FRAME_HEADER:
ETH_RX_FRAME_DEST_MAC:
    .byte $00, $00, $00, $00, $00, $00
ETH_RX_FRAME_SRC_MAC:
    .byte $00, $00, $00, $00, $00, $00
ETH_RX_TYPE:
    .byte $00, $00
ETH_RX_FRAME_PAYLOAD:
    .fill 1500, $00
ETH_RX_FRAME_PAYLOAD_SIZE:
    .byte $00, $00
TCP_RX_DATA_PAYLOAD_SIZE:
    .byte $00, $00

; Non-blocking packet send (IRQ-safe)
ETH_PACKET_SEND_NO_WAIT:
    jsr MEGA65_IO_ENABLE
    lda ETH_TX_LEN_LSB
    sta MEGA65_ETH_TXSIZE_LSB
    lda ETH_TX_LEN_MSB
    sta MEGA65_ETH_TXSIZE_MSB
    lda #<ETH_TX_FRAME_HEADER
    sta _ETH_BUF_SRC2
    lda #>ETH_TX_FRAME_HEADER
    sta _ETH_BUF_SRC2+1

php
sei

    sta $D707
    .byte $81
    .byte $ff
    .byte $00
    .byte $00
    .byte $00,$00
_ETH_BUF_SRC2:
    .byte $00,$00,EXEC_BANK
    .byte $00,$e8,$0d
    .byte $00
    .word $0000

plp
    lda #$03
    sta MEGA65_ETH_CTRL1
    lda MEGA65_ETH_CTRL1
    and #$80
    beq _nw_fail
    lda #$01
    sta MEGA65_ETH_COMMAND
    clc
    rts
_nw_fail:
    sec
    rts
