; This code will send a broadcast packet requesting a MAC address
; ie WHO HAS IP 192.168.1.1? (ARP_REQUEST_IP)
; it then updates ETH_STATE to ARP_WAITING.  The calling routine should
; loop until a reply comes in, or timeout.

ARP_REQUEST_IP:
    .byte $00, $00, $00, $00

ARP_REQUEST:

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
    lda ETH_TX_FRAME_SRC_MAC+3
    sta ETH_TX_FRAME_PAYLOAD+11
    lda ETH_TX_FRAME_SRC_MAC+4
    sta ETH_TX_FRAME_PAYLOAD+12
    lda ETH_TX_FRAME_SRC_MAC+5
    sta ETH_TX_FRAME_PAYLOAD+13

    lda LOCAL_IP+0                  ; SPA - src IP address
    sta ETH_TX_FRAME_PAYLOAD+14
    lda LOCAL_IP+1
    sta ETH_TX_FRAME_PAYLOAD+15
    lda LOCAL_IP+2
    sta ETH_TX_FRAME_PAYLOAD+16
    lda LOCAL_IP+3
    sta ETH_TX_FRAME_PAYLOAD+17

    lda #$00                        ; THA - target mac address (we dont know it yet!)
    sta ETH_TX_FRAME_PAYLOAD+18
    sta ETH_TX_FRAME_PAYLOAD+19
    sta ETH_TX_FRAME_PAYLOAD+20
    sta ETH_TX_FRAME_PAYLOAD+21
    sta ETH_TX_FRAME_PAYLOAD+22
    sta ETH_TX_FRAME_PAYLOAD+23


    lda ARP_REQUEST_IP+0                 ; TPA - target IP address
    sta ETH_TX_FRAME_PAYLOAD+24
    lda ARP_REQUEST_IP+1
    sta ETH_TX_FRAME_PAYLOAD+25
    lda ARP_REQUEST_IP+2
    sta ETH_TX_FRAME_PAYLOAD+26
    lda ARP_REQUEST_IP+3
    sta ETH_TX_FRAME_PAYLOAD+27

    lda #$2a                    ; 14+28 = 42 ($2a) byte total packet length
    sta ETH_TX_LEN_LSB
    lda #$00
    sta ETH_TX_LEN_MSB

    jsr ETH_PACKET_SEND
    lda #$01                    ; set state to ARP_WAITING
    sta ETH_STATE

    rts

; This routine will send a reply to ARP requests made by other machines 
; on the local network.

ARP_REPLY:

_check_target_ip:
    ldx #$04                            ; count = 4
_loop_compare2:
    dex
    lda LOCAL_IP,x                      ; local IP address byte
    cmp ETH_RX_FRAME_PAYLOAD+24,x
    bne _not_ours
    cpx #$00
    bne _loop_compare2
    jmp _build_reply
_not_ours:
    rts

_build_reply:
    ; ---------------------------
    ; Ethernet header (14 bytes)
    ; dst = requester MAC
    lda ETH_RX_FRAME_SRC_MAC+0
    sta ARP_REPLY_PACKET+0
    lda ETH_RX_FRAME_SRC_MAC+1
    sta ARP_REPLY_PACKET+1
    lda ETH_RX_FRAME_SRC_MAC+2
    sta ARP_REPLY_PACKET+2
    lda ETH_RX_FRAME_SRC_MAC+3
    sta ARP_REPLY_PACKET+3
    lda ETH_RX_FRAME_SRC_MAC+4
    sta ARP_REPLY_PACKET+4
    lda ETH_RX_FRAME_SRC_MAC+5
    sta ARP_REPLY_PACKET+5

    ; src = our MAC (read from controller regs, not TX buffer)
    lda MEGA65_ETH_MAC+0
    sta ARP_REPLY_PACKET+6
    lda MEGA65_ETH_MAC+1
    sta ARP_REPLY_PACKET+7
    lda MEGA65_ETH_MAC+2
    sta ARP_REPLY_PACKET+8
    lda MEGA65_ETH_MAC+3
    sta ARP_REPLY_PACKET+9
    lda MEGA65_ETH_MAC+4
    sta ARP_REPLY_PACKET+10
    lda MEGA65_ETH_MAC+5
    sta ARP_REPLY_PACKET+11

    ; ethertype = 0x0806 (ARP)
    lda #$08
    sta ARP_REPLY_PACKET+12
    lda #$06
    sta ARP_REPLY_PACKET+13

    ; ---------------------------
    ; ARP payload (28 bytes) at +14

    ; HTYPE = 0x0001 (Ethernet)
    lda #$00
    sta ARP_REPLY_PACKET+14
    lda #$01
    sta ARP_REPLY_PACKET+15

    ; PTYPE = 0x0800 (IPv4)
    lda #$08
    sta ARP_REPLY_PACKET+16
    lda #$00
    sta ARP_REPLY_PACKET+17

    ; HLEN = 6, PLEN = 4
    lda #$06
    sta ARP_REPLY_PACKET+18
    lda #$04
    sta ARP_REPLY_PACKET+19

    ; OPER = 0x0002 (reply)
    lda #$00
    sta ARP_REPLY_PACKET+20
    lda #$02
    sta ARP_REPLY_PACKET+21

    ; SHA = our MAC
    lda MEGA65_ETH_MAC+0
    sta ARP_REPLY_PACKET+22
    lda MEGA65_ETH_MAC+1
    sta ARP_REPLY_PACKET+23
    lda MEGA65_ETH_MAC+2
    sta ARP_REPLY_PACKET+24
    lda MEGA65_ETH_MAC+3
    sta ARP_REPLY_PACKET+25
    lda MEGA65_ETH_MAC+4
    sta ARP_REPLY_PACKET+26
    lda MEGA65_ETH_MAC+5
    sta ARP_REPLY_PACKET+27

    ; SPA = our IP
    lda LOCAL_IP+0
    sta ARP_REPLY_PACKET+28
    lda LOCAL_IP+1
    sta ARP_REPLY_PACKET+29
    lda LOCAL_IP+2
    sta ARP_REPLY_PACKET+30
    lda LOCAL_IP+3
    sta ARP_REPLY_PACKET+31

    ; THA = requester MAC
    lda ETH_RX_FRAME_SRC_MAC+0
    sta ARP_REPLY_PACKET+32
    lda ETH_RX_FRAME_SRC_MAC+1
    sta ARP_REPLY_PACKET+33
    lda ETH_RX_FRAME_SRC_MAC+2
    sta ARP_REPLY_PACKET+34
    lda ETH_RX_FRAME_SRC_MAC+3
    sta ARP_REPLY_PACKET+35
    lda ETH_RX_FRAME_SRC_MAC+4
    sta ARP_REPLY_PACKET+36
    lda ETH_RX_FRAME_SRC_MAC+5
    sta ARP_REPLY_PACKET+37

    ; TPA = requester’s SPA (from the ARP request payload)
    lda ETH_RX_FRAME_PAYLOAD+14
    sta ARP_REPLY_PACKET+38
    lda ETH_RX_FRAME_PAYLOAD+15
    sta ARP_REPLY_PACKET+39
    lda ETH_RX_FRAME_PAYLOAD+16
    sta ARP_REPLY_PACKET+40
    lda ETH_RX_FRAME_PAYLOAD+17
    sta ARP_REPLY_PACKET+41

    ; Defer send to mainline
    lda #$01
    sta ARP_REPLY_PENDING

    rts


; This routine will update the ARP cache and flip ETH_STATE back to IDLE
; This is when my machine does a WHO HAS IP 192.168.1.100?
ARP_UPDATE_CACHE:

    lda #$00
    sta ETH_STATE

    ; find available slot
    ldx #$00
_loop1
    lda ARP_CACHE, x
    beq _found_slot
    txa
    clc
    adc #$0b                        ; jump 11 bytes ahead to ttl byte
    cmp #$58                        ; > 8 entries... just use slot 0
    beq _use_slot_zero
    tax
    jmp _loop1
    
_use_slot_zero
    ldx #$00                        ; slot 0 will be used

_found_slot:
    lda #$ff                        ; set slot TTL
    sta ARP_CACHE+0, x

    ; save the IP address
    lda ETH_RX_FRAME_PAYLOAD+14
    sta ARP_CACHE+1, x
    lda ETH_RX_FRAME_PAYLOAD+15
    sta ARP_CACHE+2, x
    lda ETH_RX_FRAME_PAYLOAD+16
    sta ARP_CACHE+3, x
    lda ETH_RX_FRAME_PAYLOAD+17
    sta ARP_CACHE+4, x

    ; save the mac address
    lda ETH_RX_FRAME_PAYLOAD+8
    sta ARP_CACHE+5, x
    lda ETH_RX_FRAME_PAYLOAD+9
    sta ARP_CACHE+6, x
    lda ETH_RX_FRAME_PAYLOAD+10
    sta ARP_CACHE+7, x
    lda ETH_RX_FRAME_PAYLOAD+11
    sta ARP_CACHE+8, x
    lda ETH_RX_FRAME_PAYLOAD+12
    sta ARP_CACHE+9, x
    lda ETH_RX_FRAME_PAYLOAD+13
    sta ARP_CACHE+10, x

    lda #$00                            ; set state back to IDLE
    sta ETH_STATE

    rts

; This routine is called to query the cache for ARP_QUERY_IP address, 
; and retrieve the mac address if its there.
; It will place the mac in the TX MAC DEST fields and A=1
; if not found, it will put zeros in TX MAC DEST fields and A=0

ARP_QUERY_IP:
    .byte $00, $00, $00, $00

ARP_QUERY_CACHE:

    ldx #$00
_loop1
    lda ARP_CACHE+0, x                  ; if this slot is empty or expired, skip it
    beq _next_cache
    lda ARP_CACHE+1, x
    cmp ARP_QUERY_IP+0
    bne _next_cache
    lda ARP_CACHE+2, x
    cmp ARP_QUERY_IP+1
    bne _next_cache
    lda ARP_CACHE+3, x
    cmp ARP_QUERY_IP+2
    bne _next_cache
    lda ARP_CACHE+4, x
    cmp ARP_QUERY_IP+3
    bne _next_cache

    ; IP address found.  Use associated MAC address
    lda ARP_CACHE+5, x
    sta ETH_TX_FRAME_DEST_MAC+0
    lda ARP_CACHE+6, x
    sta ETH_TX_FRAME_DEST_MAC+1
    lda ARP_CACHE+7, x
    sta ETH_TX_FRAME_DEST_MAC+2
    lda ARP_CACHE+8, x
    sta ETH_TX_FRAME_DEST_MAC+3
    lda ARP_CACHE+9, x
    sta ETH_TX_FRAME_DEST_MAC+4
    lda ARP_CACHE+10, x
    sta ETH_TX_FRAME_DEST_MAC+5

    lda #$ff                        ; retain this cache entry
    sta ARP_CACHE+0, x

    lda #$01                        ; flag for hit
    rts

_next_cache:
    txa
    clc
    adc #$0b                        ; jump 11 bytes ahead to ttl byte
    cmp #$58                        ; have we gone out of bounds?
    beq _cache_miss
    tax
    jmp _loop1

_cache_miss:

    ; IP address NOT found.  clear TX DEST MAC address in TX buffer
    lda #$00
    sta ETH_TX_FRAME_DEST_MAC+0
    sta ETH_TX_FRAME_DEST_MAC+1
    sta ETH_TX_FRAME_DEST_MAC+2
    sta ETH_TX_FRAME_DEST_MAC+3
    sta ETH_TX_FRAME_DEST_MAC+4
    sta ETH_TX_FRAME_DEST_MAC+5

    lda #$00                        ; flag for miss
    rts

ARP_PURGE_TICK:
    .byte $00

; routine called by irq to countdown the first byte of each cache record
; a zero byte indicates its a free slot
ARP_CACHE_PURGE:
    
    inc ARP_PURGE_TICK
    lda ARP_PURGE_TICK
    cmp #60
    bne _done                       ; only purge once every 60 IRQs (~1 s)
    lda #$00
    sta ARP_PURGE_TICK

    ldx #$00
_loop1
    lda ARP_CACHE+0, x
    beq _next_cache                 ; this slot already expired.  skip it

    sec
    sbc #$01
    sta ARP_CACHE+0, x

_next_cache:
    txa
    clc
    adc #$0b                        ; jump 11 bytes ahead to ttl byte
    cmp #$58                        ; have we gone out of bounds?
    beq _done
    tax
    jmp _loop1

_done:
    rts


ARP_CACHE:
    ;     ttl  ip                  mac
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    


; Deferred ARP reply frame (42 bytes)
ARP_REPLY_PACKET:
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00
    .byte $00, $00

ARP_REPLY_PENDING:
    .byte $00
