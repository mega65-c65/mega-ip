
.include "macros.asm"
.include "mega65.asm"


.cpu "45gs02"

EXEC_BANK = $04     ; code is running from $42000
*=$2000

    ; Jump table for various functions
    jmp ETH_INIT
    jmp ETH_PACKET_SEND
    jmp ARP_BUILD_REQUEST
    jmp DHCPDICOVER_BUILD_REQUEST

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



ETH_PROMISCUOUS:
    .byte $00

ETH_TX_LEN_LSB:
    .byte $00
ETH_TX_LEN_MSB:
    .byte $00

LOCAL_IP:
    .byte 192, 168, 1, 75

REMOTE_IP:
    .byte 192, 168, 1, 1

MEGA65_IO_ENABLE:

    lda #$47
    sta MEGA65_IO_MODE
    lda #$53
    sta MEGA65_IO_MODE
    rts

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


; Ethernet clear to send
ETH_WAIT_CLEAR_TO_SEND:

    ;lda MEGA65_ETH_CTRL1        ; test if bit 7 is set
    ;ora #$80
    ;sta MEGA65_ETH_CTRL1
    
-   lda MEGA65_ETH_CTRL1
    and #$80
    beq -
    rts


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


BUILD_IPV4_HEADER:

ipv4_header_struct    .struct
ihl         .byte $45
dscp        .byte $00
length      .word $0148
ident       .word $a1b2
flags       .word $0000
ttl         .byte $80
protocol    .byte $11
checksum    .word $0000
src_ip      .byte $00, $00, $00, $00
dest_ip     .byte $00, $00, $00, $00
.endstruct

IPV4_HDR    .dstruct ipv4_header_struct

    lda #$00
    sta IPV4_HDR.ihl

    rts

.include "arp.asm"
.include "dhcp.asm"

*=$4000
ETH_RCV:
    ; IRQ routine
    lda MEGA65_ETH_CTRL2
    and #%00100000          ; check RX bit for waiting frame
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
    cmp #$08                    ; is packet $08xx?
    bne _unknown_packet         ; no - ignore this packet

_is_arp_packet:
    lda ETH_RX_TYPE+1
    cmp #$06                    ; is packet $0806 (ARP)?
    bne _is_tcp_packet
    jsr ARP_RESPONSE_HANDLER
    rts

_is_tcp_packet:

_unknown_packet:
    rts

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
    .word 0

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
    .word 0
