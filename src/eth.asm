
.include "macros.asm"
.include "mega65.asm"


.cpu "45gs02"

TCP_FLAG_SYN = $02
TCP_FLAG_ACK = $10
TCP_FLAG_PSH = $08
TCP_FLAG_FIN = $01
TCP_FLAG_RST = $04

ETH_STATE_IDLE              = $00
ETH_STATE_ARP_WAITING       = $01
ETH_STATE_TCP_SYN_SENT      = $02
ETH_STATE_TCP_SYNACK_RCVD   = $03
ETH_STATE_TCP_RST_RCVD      = $04
ETH_STATE_TCP_CONNECTED     = $05
ETH_STATE_TCP_FINACK_RCVD   = $06
ETH_STATE_ERR               = $FF

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
    jmp ETH_TCP_DISCONNECT

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

ETH_STATE:
    .byte $00                   ; $00=idle, $01=arp sent/waiting

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

ETH_RCV_IRQ:
.byte $38, $A2, $3D, $A0, $16, $20, $8D, $FF, $AD, $3D, $16, $8D, $3B, $16, $AD, $3E
.byte $16, $8D, $3C, $16, $A9, $27, $8D, $3D, $16, $A9, $16, $8D, $3E, $16, $18, $A2
.byte $3D, $A0, $16, $20, $8D, $FF, $60

.byte $A9, EXEC_BANK
.byte $85, $02
.byte $A9, >ETH_RCV
.byte $85, $03
.byte $A9, <ETH_RCV
.byte $85, $04
.byte $A9, $04          ; ensure interrupts disabled upon JSRFAR call
.byte $85, $05, $20

.byte $6E, $FF, $4C, $EC, $F9, $27, $16, $26
.byte $CE, $B6, $F9, $6D, $F3, $3F, $F4, $E1, $F3, $11, $F4, $9E, $F4, $2C, $F3, $58
.byte $F3, $75, $F8, $1C, $F3, $9A, $F4, $26, $CE, $E0, $F4, $70, $F7, $5D, $CC, $69
.byte $CC, $75, $CC, $84, $CC, $93, $CC, $A2, $CC, $B1, $CC, $C0, $CC, $EB, $E6, $2C
.byte $E7, $22, $E9, $AF, $E1 

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

    lda ETH_PROMISCUOUS
    beq +

    lda MEGA65_ETH_CTRL3    ; promiscous mode on
    and #%11111110          ; clear bit 0
    sta MEGA65_ETH_CTRL3
    jmp _ahead

+   lda MEGA65_ETH_CTRL3
    ora #$01 
    sta MEGA65_ETH_CTRL3

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

    ; install IRQ handler
    sta $D707
    .byte $00                   ; end of job options
    .byte $00                   ; copy
    .byte $75, $00              ; length lsb, msb ($75 = 117 bytes)
    .byte <ETH_RCV_IRQ, >ETH_RCV_IRQ, EXEC_BANK   ; src lsb, msb, bank
    .byte $00, $16, $00         ; dest ($1600 in bank 0)
    .byte $00                   ; command high byte
    .word $0000                 ; modulo (ignored)

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
    lda ETH_STATE
    cmp #ETH_STATE_IDLE
    beq _send_SYN

    ; if SYN/ACK recieved, send an ACK
    cmp #ETH_STATE_TCP_SYNACK_RCVD
    beq _send_ACK

    ; if RESET (disconnect) recieved, cancel connection
    cmp #ETH_STATE_TCP_RST_RCVD
    beq _cancel_connection

    ; if FIN/ACK recieved, send ACK and close
    cmp #ETH_STATE_TCP_FINACK_RCVD
    beq _send_final_ACK

    ; wait a bit, then check again
    jsr ETH_WAIT_100MS
    jmp ETH_TCP_CONNECT

_send_SYN:
    lda #TCP_FLAG_SYN
    jsr ETH_BUILD_TCPIP_PACKET
    jsr ETH_PACKET_SEND

    lda #ETH_STATE_TCP_SYN_SENT
    sta ETH_STATE
    jmp ETH_TCP_CONNECT

_send_ACK:
    lda #TCP_FLAG_ACK
    jsr ETH_BUILD_TCPIP_PACKET
    jsr ETH_PACKET_SEND

    lda #ETH_STATE_TCP_CONNECTED
    sta ETH_STATE
    rts

_cancel_connection:
    lda #ETH_STATE_IDLE
    sta ETH_STATE
    rts

_send_final_ACK:
    lda #TCP_FLAG_ACK
    jsr ETH_BUILD_TCPIP_PACKET
    jsr ETH_PACKET_SEND

    lda #ETH_STATE_IDLE
    sta ETH_STATE
    rts

;=============================================================================
; Close a TCP connection
;=============================================================================
ETH_TCP_DISCONNECT:

    lda ETH_STATE
    cmp #ETH_STATE_TCP_CONNECTED
    bne _not_connected

    lda #TCP_FLAG_FIN                   ; send FIN/ACK
    ora #TCP_FLAG_ACK
    jsr ETH_BUILD_TCPIP_PACKET
    jsr ETH_PACKET_SEND

    ; todo:  the server should send back an ACK and then its own FIN


_not_connected:
    rts


;=============================================================================
; Ethernet clear to send
;=============================================================================
ETH_WAIT_CLEAR_TO_SEND:

    ;lda MEGA65_ETH_CTRL1        ; test if bit 7 is set
    ;ora #$80
    ;sta MEGA65_ETH_CTRL1
    
-   lda MEGA65_ETH_CTRL1
    and #$80
    beq -
    rts

;=============================================================================
; Routine to copy packet in TX buffer to Ethernet buffer and do transmit
;=============================================================================
ETH_PACKET_SEND:

    ; mega65 IO enable
    jsr MEGA65_IO_ENABLE

    lda ETH_TX_LEN_LSB
    sta MEGA65_ETH_TXSIZE_LSB
    lda ETH_TX_LEN_MSB
    sta MEGA65_ETH_TXSIZE_MSB

    lda #<ETH_TX_FRAME_HEADER
    sta _ETH_BUF_SRC
    lda #>ETH_TX_FRAME_HEADER
    sta _ETH_BUF_SRC+1

    ; inline DMA to copy our buffer to TX buffer
    sta $D707
    .byte $81                   ; enhanced dma - dest bits 20-27
    .byte $ff                   ; ----------------------^
    .byte $00                   ; end of job options
    .byte $00                   ; copy
    .byte $00, $00              ; length lsb, msb
_ETH_BUF_SRC:
    .byte $00, $00, EXEC_BANK   ; src lsb, msb, bank
    ;.byte $00, $00, $05         ; debug destination
    .byte $00, $e8, $0d         ; dest eth TX/RX buffer ($ffde800)
    .byte $00                   ; command high byte
    .word $0000                 ; modulo (ignored)


    ; make sure ethernet is not under reset
    lda #$03
    sta MEGA65_ETH_CTRL1

    ; be sure we can send
    jsr ETH_WAIT_CLEAR_TO_SEND

    ; transmit now
    lda #$01
    sta MEGA65_ETH_COMMAND
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
    cmp LOCAL_IP, x
    bne _not_same_net
    dex
    bne _compare_net

    lda #$01
    rts

_not_same_net:
    lda #$00
    rts


;=============================================================================
; Builds a TCP packet
; Parameters:
;   A=TCP flags (SYN/FIN/etc)
;=============================================================================
ETH_BUILD_TCPIP_PACKET:

    pha                             ; push the TCP_FLAG to stack

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
    
    jsr ARP_REQUEST

    cli                             ; i dont like this, but it seems necessary
_arp_reply_loop:                    ; wait for ARP reply
    lda ETH_STATE
    cmp #ETH_STATE_ARP_WAITING
    beq _arp_reply_loop

    jsr ARP_QUERY_CACHE             ; cache should be populated now, so query again
    jmp _handle_arp_cache_result

_IP_found_in_cache:
    ; ETH_TX_FRAME_DEST_MAC will be auto populated if cache hit

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

    lda #>(20+20)       ; IP header (20) + TCP header (20)
    sta IPV4_HDR_LEN
    lda #<(20+20)
    sta IPV4_HDR_LEN+1

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
    lda #0
    sta ETH_TX_FRAME_PAYLOAD_SIZE+1
    lda #20
    sta ETH_TX_FRAME_PAYLOAD_SIZE

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

    lda #$04                                    ; set window
    sta TCP_HDR_WINDOW
    lda #$00
    sta TCP_HDR_WINDOW+1

    lda LOCAL_ISN+3                             ; add 1 to local SEQ num
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

    lda LOCAL_ISN+0                             ; write SEQ number
    sta TCP_HDR_SEQ_NUM+0
    lda LOCAL_ISN+1
    sta TCP_HDR_SEQ_NUM+1
    lda LOCAL_ISN+2
    sta TCP_HDR_SEQ_NUM+2
    lda LOCAL_ISN+3
    sta TCP_HDR_SEQ_NUM+3

    lda REMOTE_ISN+3                             ; add 1 to remote ISN
    clc
    adc #$01
    sta REMOTE_ISN+3
    lda REMOTE_ISN+2
    adc #$00
    sta REMOTE_ISN+2
    lda REMOTE_ISN+1
    adc #$00
    sta REMOTE_ISN+1
    lda REMOTE_ISN+0
    adc #$00
    sta REMOTE_ISN+0

    lda REMOTE_ISN+0                            ; update acknowledment number
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
    
    ; copy to buffer
    ldx #$00
_lp_copy:
    lda TCP_HDR, x
    sta ETH_TX_FRAME_PAYLOAD+20, x
    cpx #19
    beq _lp_done
    inx
    jmp _lp_copy

_lp_done:
    
    lda #0
    sta ETH_TX_FRAME_PAYLOAD_SIZE+1
    lda #20
    sta ETH_TX_FRAME_PAYLOAD_SIZE

    rts

TCP_DATA_SIZE:
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
    lda #$00
    sta TCP_PSEUDO_HDR+10
    lda #20
    sta TCP_PSEUDO_HDR+11

    ; 3) Sum each word in the pseudo header + data
    ldx #$00                ; counter as we sum bytes
    ldy #$00                ; Y = offset into pseudo header (0,2,4,...)

_sum_word:
    lda TCP_PSEUDO_HDR,y
    sta _num1hi
    iny
    lda TCP_PSEUDO_HDR,y
    sta _num1lo
    iny
    lda TCP_PSEUDO_HDR,Y
    sta _num2hi
    iny
    lda TCP_PSEUDO_HDR,Y
    sta _num2lo
    jsr _addwords

_loop
    lda _reslo
    sta _num1lo
    lda _reshi
    sta _num1hi

    iny
    lda TCP_PSEUDO_HDR,Y
    sta _num2hi
    iny
    lda TCP_PSEUDO_HDR,Y
    sta _num2lo
    jsr _addwords

    inx
    cpx #14
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

.include "arp.asm"
.include "dhcp.asm"

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
    rts

_accept_packet:
    ; Acknowledge the ethernet frame, freeing the buffer up for next RX
    lda #$01
    sta MEGA65_ETH_CTRL2
    lda #$03
    sta MEGA65_ETH_CTRL2

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

    #FAR_PEEK $ff, $0de800
    sta _len_lsb                ; store lsb in our inline dma command

    lda #$01                    ; byte 1 MSB of length (first 4 bits)
    sta $45
    lda [$45],z                 ; peek it again
    and #$0f                    ; strip upper 4 bits
    sta _len_msb                ; store msb in our inline dma command

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

    ; confirm if this packet is for us
    jsr ETH_IS_PACKET_FOR_US
    beq _unknown_packet

    lda ETH_RX_TYPE
    cmp #$08                            ; is packet $08xx?
    bne _unknown_packet                 ; no - ignore this packet

_arp_packet_check:
    lda ETH_RX_TYPE+1
    cmp #$06                            ; is packet $0806 (ARP)?
    bne _tcp_packet_check

_is_arp:
    lda ETH_RX_FRAME_PAYLOAD+6          ; high byte of OPER
    ora ETH_RX_FRAME_PAYLOAD+7          ; now A = OPER_hi|OPER_lo
    cmp #$01                            ; = 1 (request)?
    beq _call_arp_reply
    cmp #$02                            ; = 2 (reply)?
    beq _call_arp_update_cache
    rts                                 ; neither request nor reply → ignore

_tcp_packet_check:
    lda ETH_RX_TYPE+1
    cmp #$00                            ; is packet $0800 (TCP)?
    bne _unknown_packet
    jmp INCOMING_TCP_PACKET

_unknown_packet:
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

    inc $d020
    lda $d020
    cmp #$0f
    bne _ahead
    lda #$00
    sta $d020

_ahead:

    lda ETH_RX_FRAME_PAYLOAD+20+13      ; TCP FLAGS
    cmp #$12                            ; SYN/ACK
    beq _tcp_syn_ack

    cmp #$04                            ; RST
    beq _tcp_reset

    cmp #$11                            ; FIN/ACK
    beq _tcp_fin_ack

    rts

_tcp_syn_ack:
    ; stash seq number
    lda ETH_RX_FRAME_PAYLOAD+20+4       ; SEQ number
    sta REMOTE_ISN+0
    lda ETH_RX_FRAME_PAYLOAD+20+5
    sta REMOTE_ISN+1
    lda ETH_RX_FRAME_PAYLOAD+20+6
    sta REMOTE_ISN+2
    lda ETH_RX_FRAME_PAYLOAD+20+7
    sta REMOTE_ISN+3

    lda #ETH_STATE_TCP_SYNACK_RCVD
    sta ETH_STATE

    rts

_tcp_reset:
    lda #ETH_STATE_TCP_RST_RCVD
    sta ETH_STATE
    rts

_tcp_fin_ack:
    ; stash seq number
    lda ETH_RX_FRAME_PAYLOAD+20+4       ; SEQ number
    sta REMOTE_ISN+0
    lda ETH_RX_FRAME_PAYLOAD+20+5
    sta REMOTE_ISN+1
    lda ETH_RX_FRAME_PAYLOAD+20+6
    sta REMOTE_ISN+2
    lda ETH_RX_FRAME_PAYLOAD+20+7
    sta REMOTE_ISN+3

    lda #ETH_STATE_TCP_FINACK_RCVD
    sta ETH_STATE

    rts


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
ETH_TX_FRAME_PAYLOAD_SIZE
    .byte $00, $00

ETH_RX_FRAME_HEADER:
ETH_RX_FRAME_DEST_MAC:
    .byte $00, $00, $00, $00, $00, $00
ETH_RX_FRAME_SRC_MAC:
    .byte $00, $00, $00, $00, $00, $00
ETH_RX_TYPE:
    .byte $00, $00
ETH_RX_FRAME_PAYLOAD:
    .fill 1500, $00
ETH_RX_FRAME_PAYLOAD_SIZE
    .byte $00, $00
