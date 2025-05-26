DHCPDICOVER_BUILD_REQUEST:

        ; destination broadcast
        lda #$ff
        sta ETH_TX_FRAME_DEST_MAC
        sta ETH_TX_FRAME_DEST_MAC+1
        sta ETH_TX_FRAME_DEST_MAC+2
        sta ETH_TX_FRAME_DEST_MAC+3
        sta ETH_TX_FRAME_DEST_MAC+4
        sta ETH_TX_FRAME_DEST_MAC+5

        ; ETH_TYPE = $0800
        lda #$08
        sta ETH_TX_TYPE
        lda #$00
        sta ETH_TX_TYPE + 1

        ; build IPv4 header

        lda #$45
        sta ETH_TX_FRAME_PAYLOAD+0     ; Version/IHL

        lda #$00                   
        sta ETH_TX_FRAME_PAYLOAD+1     ; DSCP/ECN

        lda #$01
        sta ETH_TX_FRAME_PAYLOAD+2     ; total length (328 bytes)
        lda #$48
        sta ETH_TX_FRAME_PAYLOAD+3

        lda #$a1
        sta ETH_TX_FRAME_PAYLOAD+4     ; Identification
        lda #$b2
        sta ETH_TX_FRAME_PAYLOAD+5

        lda #$00
        sta ETH_TX_FRAME_PAYLOAD+6     ; flags/frag offset
        lda #$00
        sta ETH_TX_FRAME_PAYLOAD+7
        
        lda #$80                    ; TTL (128 hops)
        sta ETH_TX_FRAME_PAYLOAD+8

        lda #$11                    ; Protocol (UDP 17)
        sta ETH_TX_FRAME_PAYLOAD+9

        lda #$c3                    ; header checksum (1st 20 bytes)
        sta ETH_TX_FRAME_PAYLOAD+10
        lda #$d4
        sta ETH_TX_FRAME_PAYLOAD+11

        lda #$00                    ; source IP (0.0.0.0 for dhcp)
        sta ETH_TX_FRAME_PAYLOAD+12
        sta ETH_TX_FRAME_PAYLOAD+13
        sta ETH_TX_FRAME_PAYLOAD+14
        sta ETH_TX_FRAME_PAYLOAD+15

        lda #$ff                    ; dest IP (255.255.255.255)
        sta ETH_TX_FRAME_PAYLOAD+16
        sta ETH_TX_FRAME_PAYLOAD+17
        sta ETH_TX_FRAME_PAYLOAD+18
        sta ETH_TX_FRAME_PAYLOAD+19

        ; UDP Header

        lda #$00                    ; source port (68 DHCP client)
        sta ETH_TX_FRAME_PAYLOAD+20
        lda #$44
        sta ETH_TX_FRAME_PAYLOAD+21

        lda #$00                    ; dest port (67 DHCP server)
        sta ETH_TX_FRAME_PAYLOAD+22
        lda #$43
        sta ETH_TX_FRAME_PAYLOAD+23

        lda #$01                    ; length (308 bytes)
        sta ETH_TX_FRAME_PAYLOAD+24
        lda #$34
        sta ETH_TX_FRAME_PAYLOAD+25

        lda #$00                    ; checksum - optional, often zero
        sta ETH_TX_FRAME_PAYLOAD+26
        lda #$00
        sta ETH_TX_FRAME_PAYLOAD+27

        ; BOOTP / DHCP header
        
        lda #$01                    ; op = BOOTREQUEST
        sta ETH_TX_FRAME_PAYLOAD+28

        lda #$01                    ; htype = Ethernet (10mb)
        sta ETH_TX_FRAME_PAYLOAD+29

        lda #$06                    ; hlen (hardware addr length = mac, 6)
        sta ETH_TX_FRAME_PAYLOAD+30

        lda #$00                    ; hops = client doesnt forward
        sta ETH_TX_FRAME_PAYLOAD+31

        lda #$39                    ; xid = transaction id (random)
        sta ETH_TX_FRAME_PAYLOAD+32
        lda #$03
        sta ETH_TX_FRAME_PAYLOAD+33
        lda #$f3
        sta ETH_TX_FRAME_PAYLOAD+34
        lda #$26
        sta ETH_TX_FRAME_PAYLOAD+35

        lda #$00                    ; secs = seconds since start
        sta ETH_TX_FRAME_PAYLOAD+36
        sta ETH_TX_FRAME_PAYLOAD+37

        lda #$80                    ; flags = broadcast response
        sta ETH_TX_FRAME_PAYLOAD+38
        lda #$00
        sta ETH_TX_FRAME_PAYLOAD+39

        lda #$00                    ; ciaddr - client ip (none yet)
        sta ETH_TX_FRAME_PAYLOAD+40
        sta ETH_TX_FRAME_PAYLOAD+41
        sta ETH_TX_FRAME_PAYLOAD+42
        sta ETH_TX_FRAME_PAYLOAD+43

        lda #$00                    ; yiaddr - your ip (server will fill)
        sta ETH_TX_FRAME_PAYLOAD+44
        sta ETH_TX_FRAME_PAYLOAD+45
        sta ETH_TX_FRAME_PAYLOAD+46
        sta ETH_TX_FRAME_PAYLOAD+47

        lda #$00                    ; siaddr - next server IP
        sta ETH_TX_FRAME_PAYLOAD+48
        sta ETH_TX_FRAME_PAYLOAD+49
        sta ETH_TX_FRAME_PAYLOAD+50
        sta ETH_TX_FRAME_PAYLOAD+51

        lda #$00                    ; diaddr - relay agent IP
        sta ETH_TX_FRAME_PAYLOAD+52
        sta ETH_TX_FRAME_PAYLOAD+53
        sta ETH_TX_FRAME_PAYLOAD+54
        sta ETH_TX_FRAME_PAYLOAD+55

        lda ETH_TX_FRAME_SRC_MAC+0     ; chaddr - client MAC + padding
        sta ETH_TX_FRAME_PAYLOAD+56
        lda ETH_TX_FRAME_SRC_MAC+1
        sta ETH_TX_FRAME_PAYLOAD+57
        lda ETH_TX_FRAME_SRC_MAC+2
        sta ETH_TX_FRAME_PAYLOAD+58
        lda ETH_TX_FRAME_SRC_MAC+3
        sta ETH_TX_FRAME_PAYLOAD+59
        lda ETH_TX_FRAME_SRC_MAC+4
        sta ETH_TX_FRAME_PAYLOAD+60
        lda ETH_TX_FRAME_SRC_MAC+5
        sta ETH_TX_FRAME_PAYLOAD+61
        lda #$00
        sta ETH_TX_FRAME_PAYLOAD+62
        sta ETH_TX_FRAME_PAYLOAD+63
        sta ETH_TX_FRAME_PAYLOAD+64
        sta ETH_TX_FRAME_PAYLOAD+65
        sta ETH_TX_FRAME_PAYLOAD+66
        sta ETH_TX_FRAME_PAYLOAD+67
        sta ETH_TX_FRAME_PAYLOAD+68
        sta ETH_TX_FRAME_PAYLOAD+69
        sta ETH_TX_FRAME_PAYLOAD+70
        sta ETH_TX_FRAME_PAYLOAD+71

        ldx #$3f                    ; sname = server host name (64 bytes, zero filled)
        lda #$00
_sname_loop
        sta ETH_TX_FRAME_PAYLOAD+72,x
        dex
        bne _sname_loop

        ldx #$7f                    ; file = boot file name, zero filled
        lda #$00
_file_loop
        sta ETH_TX_FRAME_PAYLOAD+136,x
        dex
        bne _file_loop

        lda #$63                    ; DHCP magic value
        sta ETH_TX_FRAME_PAYLOAD+264
        lda #$82
        sta ETH_TX_FRAME_PAYLOAD+265
        lda #$53
        sta ETH_TX_FRAME_PAYLOAD+266
        lda #$63
        sta ETH_TX_FRAME_PAYLOAD+267

        ; DHCP options

        lda #$35                    ; DHCP Msg Type 
        sta ETH_TX_FRAME_PAYLOAD+268
        lda #$01                        ; length
        sta ETH_TX_FRAME_PAYLOAD+269
        lda #$01
        sta ETH_TX_FRAME_PAYLOAD+270

        lda #$3d                    ; 61 (client id)
        sta ETH_TX_FRAME_PAYLOAD+271
        lda #$07                        ; length
        sta ETH_TX_FRAME_PAYLOAD+272
        lda #$01                        ; hw type
        sta ETH_TX_FRAME_PAYLOAD+273
        lda ETH_TX_FRAME_SRC_MAC+0
        sta ETH_TX_FRAME_PAYLOAD+274
        lda ETH_TX_FRAME_SRC_MAC+1
        sta ETH_TX_FRAME_PAYLOAD+275
        lda ETH_TX_FRAME_SRC_MAC+2
        sta ETH_TX_FRAME_PAYLOAD+276
        lda ETH_TX_FRAME_SRC_MAC+3
        sta ETH_TX_FRAME_PAYLOAD+277
        lda ETH_TX_FRAME_SRC_MAC+4
        sta ETH_TX_FRAME_PAYLOAD+278
        lda ETH_TX_FRAME_SRC_MAC+5
        sta ETH_TX_FRAME_PAYLOAD+279

        lda #$37                    ; 55 (Params requested)
        sta ETH_TX_FRAME_PAYLOAD+280
        lda #$03                        ; length
        sta ETH_TX_FRAME_PAYLOAD+281
        lda #$01                            ; mask
        sta ETH_TX_FRAME_PAYLOAD+282
        lda #$03                            ; router
        sta ETH_TX_FRAME_PAYLOAD+283
        lda #$06                            ; DNS
        sta ETH_TX_FRAME_PAYLOAD+284

        lda #$ff                    ; end of variable params
        sta ETH_TX_FRAME_PAYLOAD+285

        lda #$00                    ; UDP pad above?
        sta ETH_TX_FRAME_PAYLOAD+286

        lda #$2c                    ; byte packet length (300)
        sta ETH_TX_LEN_LSB
        lda #$01
        sta ETH_TX_LEN_MSB

        rts