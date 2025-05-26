
ARP_BUILD_REQUEST:

    ; destination broadcast
    lda #$ff
    sta ETH_TX_FRAME_DEST_MAC
    sta ETH_TX_FRAME_DEST_MAC+1
    sta ETH_TX_FRAME_DEST_MAC+2
    sta ETH_TX_FRAME_DEST_MAC+3
    sta ETH_TX_FRAME_DEST_MAC+4
    sta ETH_TX_FRAME_DEST_MAC+5

    ; ETH_TYPE = $0806
    lda #$08
    sta ETH_TX_TYPE
    lda #$06
    sta ETH_TX_TYPE + 1

    ; build ARP header

    lda #$00
    sta ETH_TX_FRAME_PAYLOAD+0     ; HTYPE - hardware type = 1 (Ethernet)
    lda #$01                    
    sta ETH_TX_FRAME_PAYLOAD+1

    lda #$08
    sta ETH_TX_FRAME_PAYLOAD+2     ; PTYPE - protocol type = 0x0800 (ipv4)
    lda #$00
    sta ETH_TX_FRAME_PAYLOAD+3

    lda #$06
    sta ETH_TX_FRAME_PAYLOAD+4     ; HLEN - hardware size (mac address = 6 bytes)
    lda #$04
    sta ETH_TX_FRAME_PAYLOAD+5     ; PLEN - protocol size (ipv4 = 4 bytes)

    lda #$00
    sta ETH_TX_FRAME_PAYLOAD+6     ; OPER - opcode 1 = request
    lda #$01
    sta ETH_TX_FRAME_PAYLOAD+7
    
    lda ETH_TX_FRAME_SRC_MAC+0     ; SHA - src mac address
    sta ETH_TX_FRAME_PAYLOAD+8
    lda ETH_TX_FRAME_SRC_MAC+1
    sta ETH_TX_FRAME_PAYLOAD+9
    lda ETH_TX_FRAME_SRC_MAC+2
    sta ETH_TX_FRAME_PAYLOAD+10
    lda ETH_TX_FRAME_PAYLOAD+3
    sta ETH_TX_FRAME_PAYLOAD+11
    lda ETH_TX_FRAME_PAYLOAD+4
    sta ETH_TX_FRAME_PAYLOAD+12
    lda ETH_TX_FRAME_PAYLOAD+5
    sta ETH_TX_FRAME_PAYLOAD+13

    lda LOCAL_IP+0                  ; SPA - src IP address
    sta ETH_TX_FRAME_PAYLOAD+14
    lda LOCAL_IP+1
    sta ETH_TX_FRAME_PAYLOAD+15
    lda LOCAL_IP+2
    sta ETH_TX_FRAME_PAYLOAD+16
    lda LOCAL_IP+3
    sta ETH_TX_FRAME_PAYLOAD+17

    lda #$00                        ; THA - target mac address
    sta ETH_TX_FRAME_PAYLOAD+18
    sta ETH_TX_FRAME_PAYLOAD+19
    sta ETH_TX_FRAME_PAYLOAD+20
    sta ETH_TX_FRAME_PAYLOAD+21
    sta ETH_TX_FRAME_PAYLOAD+22
    sta ETH_TX_FRAME_PAYLOAD+23


    lda REMOTE_IP+0                 ; TPA - target IP address
    sta ETH_TX_FRAME_PAYLOAD+24
    lda REMOTE_IP+1
    sta ETH_TX_FRAME_PAYLOAD+25
    lda REMOTE_IP+2
    sta ETH_TX_FRAME_PAYLOAD+26
    lda REMOTE_IP+3
    sta ETH_TX_FRAME_PAYLOAD+27

    lda #$2a                    ; 42 ($2a) byte packet length
    sta ETH_TX_LEN_LSB
    lda #$00
    sta ETH_TX_LEN_MSB

    rts
;==============================================================================
ARP_RESPONSE_HANDLER:

    ldx #$06                            ; count = 6
_loop_compare:
    dex
    lda ETH_TX_FRAME_SRC_MAC,x          ; local MAC byte
    cmp ETH_RX_FRAME_DEST_MAC,x
    bne _check_broadcast
    cpx #$00
    bne _loop_compare
    jmp _do_reply

_check_broadcast:
    ldx #$06
    lda #$ff
_loop_bcast:
    dex
    cmp ETH_RX_FRAME_DEST_MAC,x
    bne _not_ours
    cpx #$00
    bne _loop_bcast

    jmp _check_target_ip

_not_ours:
    rts

_check_target_ip:
    ldx #$04                            ; count = 4
_loop_compare2:
    dex
    lda LOCAL_IP,x                      ; local IP address byte
    cmp ETH_RX_FRAME_PAYLOAD+24,x
    bne _not_ours
    cpx #$00
    bne _loop_compare2
    jmp _do_reply

_do_reply:
    ; destination broadcast (pull from src in RX buffer)
    lda ETH_RX_FRAME_SRC_MAC+0
    sta ETH_TX_FRAME_DEST_MAC+0
    lda ETH_RX_FRAME_SRC_MAC+1
    sta ETH_TX_FRAME_DEST_MAC+1
    lda ETH_RX_FRAME_SRC_MAC+2
    sta ETH_TX_FRAME_DEST_MAC+2
    lda ETH_RX_FRAME_SRC_MAC+3
    sta ETH_TX_FRAME_DEST_MAC+3
    lda ETH_RX_FRAME_SRC_MAC+4
    sta ETH_TX_FRAME_DEST_MAC+4
    lda ETH_RX_FRAME_SRC_MAC+5
    sta ETH_TX_FRAME_DEST_MAC+5

    ; ETH_TYPE = $0806
    lda #$08
    sta ETH_TX_TYPE
    lda #$06
    sta ETH_TX_TYPE + 1

    ; build ARP header

    lda #$00
    sta ETH_TX_FRAME_PAYLOAD+0     ; HTYPE - hardware type = 1 (Ethernet)
    lda #$01                    
    sta ETH_TX_FRAME_PAYLOAD+1

    lda #$08
    sta ETH_TX_FRAME_PAYLOAD+2     ; PTYPE - protocol type = 0x0800 (ipv4)
    lda #$00
    sta ETH_TX_FRAME_PAYLOAD+3

    lda #$06
    sta ETH_TX_FRAME_PAYLOAD+4     ; HLEN - hardware size (mac address = 6 bytes)
    lda #$04
    sta ETH_TX_FRAME_PAYLOAD+5     ; PLEN - protocol size (ipv4 = 4 bytes)

    lda #$00
    sta ETH_TX_FRAME_PAYLOAD+6     ; OPER - opcode 2 = response
    lda #$02
    sta ETH_TX_FRAME_PAYLOAD+7
    
    lda ETH_TX_FRAME_SRC_MAC+0     ; SHA - src mac address
    sta ETH_TX_FRAME_PAYLOAD+8
    lda ETH_TX_FRAME_SRC_MAC+1
    sta ETH_TX_FRAME_PAYLOAD+9
    lda ETH_TX_FRAME_SRC_MAC+2
    sta ETH_TX_FRAME_PAYLOAD+10
    lda ETH_TX_FRAME_PAYLOAD+3
    sta ETH_TX_FRAME_PAYLOAD+11
    lda ETH_TX_FRAME_PAYLOAD+4
    sta ETH_TX_FRAME_PAYLOAD+12
    lda ETH_TX_FRAME_PAYLOAD+5
    sta ETH_TX_FRAME_PAYLOAD+13

    lda LOCAL_IP+0                  ; SPA - src IP address  192.168.1.77
    sta ETH_TX_FRAME_PAYLOAD+14
    lda LOCAL_IP+1
    sta ETH_TX_FRAME_PAYLOAD+15
    lda LOCAL_IP+2
    sta ETH_TX_FRAME_PAYLOAD+16
    lda LOCAL_IP+3
    sta ETH_TX_FRAME_PAYLOAD+17

    lda ETH_RX_FRAME_SRC_MAC+0      ; THA - target mac address
    sta ETH_TX_FRAME_PAYLOAD+18
    lda ETH_RX_FRAME_SRC_MAC+1
    sta ETH_TX_FRAME_PAYLOAD+19
    lda ETH_RX_FRAME_SRC_MAC+2
    sta ETH_TX_FRAME_PAYLOAD+20
    lda ETH_RX_FRAME_SRC_MAC+3
    sta ETH_TX_FRAME_PAYLOAD+21
    lda ETH_RX_FRAME_SRC_MAC+4
    sta ETH_TX_FRAME_PAYLOAD+22
    lda ETH_RX_FRAME_SRC_MAC+5
    sta ETH_TX_FRAME_PAYLOAD+23


    lda REMOTE_IP+0                 ; TPA - target IP address 192.168.1.1
    sta ETH_TX_FRAME_PAYLOAD+24
    lda REMOTE_IP+1
    sta ETH_TX_FRAME_PAYLOAD+25
    lda REMOTE_IP+2
    sta ETH_TX_FRAME_PAYLOAD+26
    lda REMOTE_IP+3
    sta ETH_TX_FRAME_PAYLOAD+27

    lda #$2a                        ; 42 ($2a) byte packet length
    sta ETH_TX_LEN_LSB
    lda #$00
    sta ETH_TX_LEN_MSB

    jmp ETH_PACKET_SEND

    rts
