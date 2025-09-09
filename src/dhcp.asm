; ---------------- DHCP / UDP constants ----------------
UDP_PROTO                   = $11
UDP_PORT_DHCP_SERVER        = 67
UDP_PORT_DHCP_CLIENT        = 68

BOOTP_OP_BOOTREQUEST        = 1
BOOTP_OP_BOOTREPLY          = 2

DHCP_MAGIC_0                = $63
DHCP_MAGIC_1                = $82
DHCP_MAGIC_2                = $53
DHCP_MAGIC_3                = $63

; DHCP option codes
DHCP_OPT_MESSAGE_TYPE       = 53
DHCP_OPT_REQUESTED_IP       = 50
DHCP_OPT_SERVER_ID          = 54
DHCP_OPT_PARAM_REQ_LIST     = 55
DHCP_OPT_SUBNET_MASK        = 1
DHCPopt_router             = 3
DHCPopt_dns                = 6
DHCP_OPT_LEASE_TIME         = 51
DHCP_OPT_END                = 255

; DHCP message types
DHCPDISCOVER                = 1
DHCPOFFER                   = 2
DHCPREQUEST                 = 3
DHCPDECLINE                 = 4
DHCPACK                     = 5
DHCPNAK                     = 6

; States
DHCP_STATE_OFF              = $00
DHCP_STATE_DISCOVER_SENT    = $01
DHCP_STATE_OFFER_SEEN       = $02
DHCP_STATE_REQUEST_SENT     = $03
DHCP_STATE_BOUND            = $04
DHCP_STATE_FAILED           = $7F

; BOOTP/DHCP fixed header sizes
BOOTP_FIXED_SIZE            = 236          ; up to 'options' field

; Workspace
DHCP_IN_PROGRESS:           .byte 0
DHCP_STATE:                 .byte $00
DHCP_RETRY_TICKS:           .byte $00
DHCP_RETRY_BACKOFF:         .byte $20      ; ~3–4s initial (you tick at 100ms)
DHCP_XID:                   .byte $12,$34,$56,$78
DHCP_SERVER_ID:             .byte $00,$00,$00,$00
DHCP_OFFER_IP:              .byte $00,$00,$00,$00  ; yiaddr from OFFER
DHCP_LEASE_SECS:            .byte $00,$00,$00,$00
;DNS_SERVER:                 .byte $00,$00,$00,$00  ; new: primary DNS
DHCP_FLAGS:                 .byte $80,$00           ; broadcast bit 0x8000
DHCP_OPT_END_OFS:           .byte 0
DHCP_IP_IHL_BYTES:          .byte 20       ; holds IP header length in bytes
DHCP_OPTS_PTR_LO:           .byte 0
DHCP_OPTS_PTR_HI:           .byte 0
DHCP_OPTS_BASE_LO           .byte 0
DHCP_OPTS_BASE_HI           .byte 0
DHCP_OPTS_MAXY              .byte 0
pl_len:                     .byte 0,0
n2hi:                       .byte 0
n2lo:                       .byte 0
sum_hi:                     .byte 0
sum_lo:                     .byte 0
sum_ex:                     .byte 0
rem_lo:                     .byte 0
rem_hi:                     .byte 0
opt_mask:                   .byte 0,0,0,0
opt_router:                 .byte 0,0,0,0
opt_dns:                    .byte 0,0,0,0
dhcp_msg_type:              .byte 0

DHCP_RX_ACCEPTS: .byte 0
DHCP_UDP68_HITS: .byte 0
DHCP_ACK_SEEN: .byte 0
DHCP_NAK_SEEN: .byte 0

;=============================================================================
; Start DHCP (non-blocking). Safe to call any time; it will restart if needed
;=============================================================================
ETH_DHCP_START:

    ; clear from previous run
    lda #$00
    sta dhcp_msg_type
    ldy #$00
_loop:
    sta DHCP_SERVER_ID,y
    sta DHCP_OFFER_IP,y
    sta DHCP_LEASE_SECS,y
    sta LOCAL_IP,Y
    sta GATEWAY_IP,Y
    sta SUBNET_MASK,Y
    sta PRIMARY_DNS,Y
    sta opt_mask,y
    sta opt_router,y
    sta opt_dns,y
    iny
    cpy #$04
    bne _loop

    ; Make XID unique per start (simple 32-bit increment)
    ldx #3
_inc_xid:
    inc DHCP_XID,x
    bne _xid_ok
    dex
    bpl _inc_xid
_xid_ok:

    lda #$80
    sta DHCP_FLAGS
    lda #$00
    sta DHCP_FLAGS+1

    lda #DHCP_STATE_OFF
    sta DHCP_STATE

    lda #$00
    sta DHCP_RETRY_TICKS
    lda #$20
    sta DHCP_RETRY_BACKOFF

    lda #1
    sta DHCP_IN_PROGRESS

    jsr DHCP_SEND_DISCOVER
    lda #DHCP_STATE_DISCOVER_SENT
    sta DHCP_STATE

    rts

;=============================================================================
; Drive DHCP (call from your main poll loop; never blocks)
;=============================================================================
ETH_DHCP_POLL:
    jsr ETH_RCV                        ; keep RX flowing
    jsr DHCP_TICK
    lda DHCP_STATE
    rts

;=============================================================================
;
;=============================================================================
ETH_GET_DHCP_STATE:
    lda DHCP_STATE
    rts


;=============================================================================
;
;=============================================================================
DHCP_TICK:
    ; only act while not yet BOUND or FAILED
    lda DHCP_STATE
    cmp #DHCP_STATE_BOUND
    beq _done
    cmp #DHCP_STATE_FAILED
    beq _done

    ; simple 100ms tick backoff
    jsr ETH_WAIT_100MS
    inc DHCP_RETRY_TICKS
    lda DHCP_RETRY_TICKS
    cmp DHCP_RETRY_BACKOFF
    bcc _done

    lda #$00
    sta DHCP_RETRY_TICKS

    lda DHCP_STATE
    cmp #DHCP_STATE_DISCOVER_SENT
    beq _resend_discover
    cmp #DHCP_STATE_OFFER_SEEN
    beq _resend_request
    cmp #DHCP_STATE_REQUEST_SENT
    beq _resend_request
    jmp _done

_resend_discover:
    jsr DHCP_SEND_DISCOVER
    jsr DHCP_BACKOFF
    rts

_resend_request:
    jsr DHCP_SEND_REQUEST
    jsr DHCP_BACKOFF
    rts

_done:
    rts

;=============================================================================
;
;=============================================================================
DHCP_BACKOFF:
    ; exponential-ish up to ~6–8s
    lda DHCP_RETRY_BACKOFF
    asl
    cmp #$80
    bcc +
    lda #$80
+   sta DHCP_RETRY_BACKOFF
    rts


;=============================================================================
; DHCP DISCOVER
;=============================================================================
DHCP_SEND_DISCOVER:
    ; BOOTP fixed section in ETH_TX_FRAME_PAYLOAD after IP+UDP headers.
    ; We’ll layout as: [Ether(14)] [IP(20)] [UDP(8)] [BOOTP(236)] [cookie(4)] [options]
    jsr DHCP_BUILD_BOOTP_COMMON
    ; op = 1 (request)
    lda #BOOTP_OP_BOOTREQUEST
    sta ETH_TX_FRAME_PAYLOAD+20+8+0  ; op
    ; fill magic cookie
    lda #DHCP_MAGIC_0
    sta ETH_TX_FRAME_PAYLOAD+20+8+236
    lda #DHCP_MAGIC_1
    sta ETH_TX_FRAME_PAYLOAD+20+8+237
    lda #DHCP_MAGIC_2
    sta ETH_TX_FRAME_PAYLOAD+20+8+238
    lda #DHCP_MAGIC_3
    sta ETH_TX_FRAME_PAYLOAD+20+8+239

    ; ---- options ----
    ldx #$00
    ; 53 = message type : DHCPDISCOVER
    lda #DHCP_OPT_MESSAGE_TYPE
    jsr opt_put_code
    lda #$01
    jsr opt_put_len
    lda #DHCPDISCOVER
    jsr opt_put_byte

    ; 55 = parameter request list (mask, router, dns, lease, mtu)
    lda #DHCP_OPT_PARAM_REQ_LIST
    jsr opt_put_code
    lda #$05
    jsr opt_put_len
    lda #DHCP_OPT_SUBNET_MASK
    jsr opt_put_byte
    lda #DHCPopt_router
    jsr opt_put_byte
    lda #DHCPopt_dns
    jsr opt_put_byte
    lda #DHCP_OPT_LEASE_TIME
    jsr opt_put_byte
    lda #$1a
    jsr opt_put_byte                    ; interface MTU

    ; 61 = client identifier (type 01 + MAC)
    lda #$3d                           ; 61
    jsr opt_put_code
    lda #$07                           ; len=7 (htype 1 + 6 bytes MAC)
    jsr opt_put_len
    lda #$01                           ; htype=Ethernet (1)
    jsr opt_put_byte
    ldy #$00
-   lda ETH_TX_FRAME_SRC_MAC,y
    jsr opt_put_byte
    iny
    cpy #6
    bne -

    ; 255 = end
    lda #DHCP_OPT_END
    jsr opt_put_code

    ; Compute total UDP payload length = 236 + 4 + options_len
    stx DHCP_OPT_END_OFS               ; keep for size calc
    lda #<(BOOTP_FIXED_SIZE+4)         ; base (236 + 4 cookie)
    clc
    adc DHCP_OPT_END_OFS
    sta pl_len
    lda #>(BOOTP_FIXED_SIZE+4)
    adc #$00
    sta pl_len+1

    ; Build IP/UDP for broadcast 0.0.0.0 -> 255.255.255.255, 68->67
    jsr DHCP_BUILD_IPV4_UDP_BROADCAST
    jsr UDP_WRITE_LENGTH_AND_CHECKSUM

    ; Frame length = 14 + 20 + 8 + payload
    lda pl_len
    clc
    adc #<(14+20+8)
    sta ETH_TX_LEN_LSB
    lda pl_len+1
    adc #>(14+20+8)
    sta ETH_TX_LEN_MSB

    ; Set destination MAC = FF:FF:FF:FF:FF:FF
    ldy #0
    lda #$ff
_bcast_fill:
    sta ETH_TX_FRAME_DEST_MAC,y
    iny
    cpy #6
    bne _bcast_fill

    jsr ETH_PACKET_SEND
    rts



;=============================================================================
; DHCP REQUEST
; (uses DHCP_SERVER_ID and DHCP_OFFER_IP captured from OFFER)
;=============================================================================
DHCP_SEND_REQUEST:
    jsr DHCP_BUILD_BOOTP_COMMON
    lda #BOOTP_OP_BOOTREQUEST
    sta ETH_TX_FRAME_PAYLOAD+20+8+0
    ; magic
    lda #DHCP_MAGIC_0
    sta ETH_TX_FRAME_PAYLOAD+20+8+236
    lda #DHCP_MAGIC_1
    sta ETH_TX_FRAME_PAYLOAD+20+8+237
    lda #DHCP_MAGIC_2
    sta ETH_TX_FRAME_PAYLOAD+20+8+238
    lda #DHCP_MAGIC_3
    sta ETH_TX_FRAME_PAYLOAD+20+8+239

    ; options
    ldx #$00
    ; 53 = REQUEST
    lda #DHCP_OPT_MESSAGE_TYPE
    jsr opt_put_code
    lda #$01
    jsr opt_put_len
    lda #DHCPREQUEST
    jsr opt_put_byte
    ; 50 = requested IP
    lda #DHCP_OPT_REQUESTED_IP
    jsr opt_put_code
    lda #$04
    jsr opt_put_len
    ldy #$00
-   lda DHCP_OFFER_IP,y
    jsr opt_put_byte
    iny
    cpy #4
    bne -
    ; 54 = server identifier (only if we captured it)
    lda DHCP_SERVER_ID+0
    ora DHCP_SERVER_ID+1
    ora DHCP_SERVER_ID+2
    ora DHCP_SERVER_ID+3
    beq _skip_svid

    lda #DHCP_OPT_SERVER_ID
    jsr opt_put_code
    lda #$04
    jsr opt_put_len
    ldy #$00
-   lda DHCP_SERVER_ID,y
    jsr opt_put_byte
    iny
    cpy #4
    bne -
_skip_svid:
    ; 61 = client id (01+MAC)
    lda #$3d
    jsr opt_put_code
    lda #$07
    jsr opt_put_len
    lda #$01
    jsr opt_put_byte
    ldy #$00
-   lda ETH_TX_FRAME_SRC_MAC,y
    jsr opt_put_byte
    iny
    cpy #6
    bne -

    ; 255
    lda #DHCP_OPT_END
    jsr opt_put_code

    ; payload len
    stx DHCP_OPT_END_OFS
    lda #<(BOOTP_FIXED_SIZE+4)
    clc
    adc DHCP_OPT_END_OFS
    sta pl_len
    lda #>(BOOTP_FIXED_SIZE+4)
    adc #$00
    sta pl_len+1

    jsr DHCP_BUILD_IPV4_UDP_BROADCAST
    jsr UDP_WRITE_LENGTH_AND_CHECKSUM

    lda pl_len
    clc
    adc #<(14+20+8)
    sta ETH_TX_LEN_LSB
    lda pl_len+1
    adc #>(14+20+8)
    sta ETH_TX_LEN_MSB

    ; Set destination MAC = FF:FF:FF:FF:FF:FF
    ldy #0
    lda #$ff
_bcast_fill:
    sta ETH_TX_FRAME_DEST_MAC,y
    iny
    cpy #6
    bne _bcast_fill

    jsr ETH_PACKET_SEND
    rts

;=============================================================================
; Common BOOTP body (zeros/fields, chaddr, xid, flags)
;=============================================================================
DHCP_BUILD_BOOTP_COMMON:
    ; zero the whole BOOTP+cookie+opts area first (keep it simple)
    ldy #$00
    lda #$00
_clear:
    sta ETH_TX_FRAME_PAYLOAD+20+8,y
    iny
    cpy #$F0          ; 240 bytes (236 + 4 cookie), options set later
    bne _clear

    ; htype=1, hlen=6, hops=0
    lda #$01
    sta ETH_TX_FRAME_PAYLOAD+20+8+1      ; htype
    lda #$06
    sta ETH_TX_FRAME_PAYLOAD+20+8+2      ; hlen
    ; xid
    lda DHCP_XID+0
    sta ETH_TX_FRAME_PAYLOAD+20+8+$04
    lda DHCP_XID+1
    sta ETH_TX_FRAME_PAYLOAD+20+8+$05
    lda DHCP_XID+2
    sta ETH_TX_FRAME_PAYLOAD+20+8+$06
    lda DHCP_XID+3
    sta ETH_TX_FRAME_PAYLOAD+20+8+$07
    ; flags (broadcast)
    lda DHCP_FLAGS+0
    sta ETH_TX_FRAME_PAYLOAD+20+8+$0A
    lda DHCP_FLAGS+1
    sta ETH_TX_FRAME_PAYLOAD+20+8+$0B
    ; chaddr (client MAC) starts at +28, 16 bytes field but we write 6
    ldy #$00
-   lda ETH_TX_FRAME_SRC_MAC,y
    sta ETH_TX_FRAME_PAYLOAD+20+8+28,y
    iny
    cpy #6
    bne -
    rts

; Option write helpers — options start at offset 240, X tracks running length
opt_put_code:
    sta ETH_TX_FRAME_PAYLOAD+20+8+240,x
    inx
    rts
opt_put_len:
    sta ETH_TX_FRAME_PAYLOAD+20+8+240,x
    inx
    rts
opt_put_byte:
    sta ETH_TX_FRAME_PAYLOAD+20+8+240,x
    inx
    rts

;=============================================================================
; Build IPv4 header for broadcast DHCP (src 0.0.0.0, dst 255.255.255.255)
;=============================================================================
DHCP_BUILD_IPV4_UDP_BROADCAST:
    ; Ethernet type = IPv4
    lda #$08
    sta ETH_TX_TYPE
    lda #$00
    sta ETH_TX_TYPE+1

    ; --- Write IPv4 header directly into ETH_TX_FRAME_PAYLOAD (20 bytes) ---
    ; Version/IHL
    lda #$45
    sta ETH_TX_FRAME_PAYLOAD+0
    ; DSCP/ECN
    lda #$00
    sta ETH_TX_FRAME_PAYLOAD+1
    ; Total length (filled after UDP length known) – init now:
    lda #$00
    sta ETH_TX_FRAME_PAYLOAD+2
    lda #$00
    sta ETH_TX_FRAME_PAYLOAD+3
    ; Identification
    lda #$00
    sta ETH_TX_FRAME_PAYLOAD+4
    lda #$00
    sta ETH_TX_FRAME_PAYLOAD+5
    ; Flags/Fragment (DF)
    lda #$40
    sta ETH_TX_FRAME_PAYLOAD+6
    lda #$00
    sta ETH_TX_FRAME_PAYLOAD+7
    ; TTL
    lda #$40
    sta ETH_TX_FRAME_PAYLOAD+8
    ; Protocol = UDP
    lda #UDP_PROTO
    sta ETH_TX_FRAME_PAYLOAD+9
    ; Checksum zero for now
    lda #$00
    sta ETH_TX_FRAME_PAYLOAD+10
    lda #$00
    sta ETH_TX_FRAME_PAYLOAD+11
    ; Src IP = 0.0.0.0
    lda #$00
    sta ETH_TX_FRAME_PAYLOAD+12
    sta ETH_TX_FRAME_PAYLOAD+13
    sta ETH_TX_FRAME_PAYLOAD+14
    sta ETH_TX_FRAME_PAYLOAD+15
    ; Dst IP = 255.255.255.255
    lda #$FF
    sta ETH_TX_FRAME_PAYLOAD+16
    sta ETH_TX_FRAME_PAYLOAD+17
    sta ETH_TX_FRAME_PAYLOAD+18
    sta ETH_TX_FRAME_PAYLOAD+19

    ; --- UDP header at +20 ---
    ; src port 68
    lda #>(UDP_PORT_DHCP_CLIENT)
    sta ETH_TX_FRAME_PAYLOAD+20+0
    lda #<(UDP_PORT_DHCP_CLIENT)
    sta ETH_TX_FRAME_PAYLOAD+20+1
    ; dst port 67
    lda #>(UDP_PORT_DHCP_SERVER)
    sta ETH_TX_FRAME_PAYLOAD+20+2
    lda #<(UDP_PORT_DHCP_SERVER)
    sta ETH_TX_FRAME_PAYLOAD+20+3
    ; length and checksum filled by UDP_WRITE_LENGTH_AND_CHECKSUM
    lda #$00
    sta ETH_TX_FRAME_PAYLOAD+20+4
    sta ETH_TX_FRAME_PAYLOAD+20+5
    sta ETH_TX_FRAME_PAYLOAD+20+6
    sta ETH_TX_FRAME_PAYLOAD+20+7
    rts

;=============================================================================
;
;=============================================================================
UDP_WRITE_LENGTH_AND_CHECKSUM:
    ; UDP length = 8 + payload length (pl_len)
    lda pl_len
    clc
    adc #8
    sta ETH_TX_FRAME_PAYLOAD+20+5
    lda pl_len+1
    adc #0
    sta ETH_TX_FRAME_PAYLOAD+20+4

    ; IP total length = 20 + UDP length
    lda ETH_TX_FRAME_PAYLOAD+20+5
    clc
    adc #20
    sta ETH_TX_FRAME_PAYLOAD+3
    lda ETH_TX_FRAME_PAYLOAD+20+4
    adc #0
    sta ETH_TX_FRAME_PAYLOAD+2

    ; IPv4 header checksum (over first 20 bytes)
    jsr UDP_CALC_IPHDR_CHECKSUM

    ; UDP checksum (pseudo header + UDP hdr + data)
    jsr UDP_CALC_CHECKSUM
    rts

;=============================================================================
; IPv4 header checksum (20 bytes at ETH_TX_FRAME_PAYLOAD)
;=============================================================================
UDP_CALC_IPHDR_CHECKSUM:
    lda #$00
    sta sum_hi
    sta sum_lo
    sta sum_ex
    ldy #0
    ldx #10            ; 10 words
_lpih:
    lda ETH_TX_FRAME_PAYLOAD,y      ; hi
    sta n2hi
    iny
    lda ETH_TX_FRAME_PAYLOAD,y      ; lo
    sta n2lo
    iny
    jsr sum_add
    dex
    bne _lpih
    jsr sum_fold_ffff
    lda sum_hi
    sta ETH_TX_FRAME_PAYLOAD+10
    lda sum_lo
    sta ETH_TX_FRAME_PAYLOAD+11
    rts

;=============================================================================
; UDP checksum over pseudo hdr + UDP hdr + data
;=============================================================================
UDP_CALC_CHECKSUM:
    ; zero checksum field first
    lda #$00
    sta ETH_TX_FRAME_PAYLOAD+20+6
    sta ETH_TX_FRAME_PAYLOAD+20+7

    lda #$00
    sta sum_hi
    sta sum_lo
    sta sum_ex

    ; pseudo header: src(4) + dst(4) + zero(1) + proto(1) + udp_len(2)
    ; src/dst already present at offsets 12..19
    ldy #12
    ldx #4
_ph_s:
-   lda ETH_TX_FRAME_PAYLOAD,y
    sta n2hi
    iny
    lda ETH_TX_FRAME_PAYLOAD,y
    sta n2lo
    iny
    jsr sum_add
    dex
    bne -

    ; zero + proto
    lda #$00
    sta n2hi
    lda #UDP_PROTO
    sta n2lo
    jsr sum_add

    ; udp length
    lda ETH_TX_FRAME_PAYLOAD+20+4
    sta n2hi
    lda ETH_TX_FRAME_PAYLOAD+20+5
    sta n2lo
    jsr sum_add

    ; UDP header (8 bytes)
    ldy #20
    ldx #4
-   lda ETH_TX_FRAME_PAYLOAD,y
    sta n2hi
    iny
    lda ETH_TX_FRAME_PAYLOAD,y
    sta n2lo
    iny
    jsr sum_add
    dex
    bne -

    ; ---------------- UDP payload (no ZP; self-mod absolute) ----------------
    ; Initialize self-modifying operands to payload base (ETH_TX_FRAME_PAYLOAD+28)
    lda #< (ETH_TX_FRAME_PAYLOAD+28)
    sta _PAY_RD1+1
    sta _PAY_RD2+1
    lda #> (ETH_TX_FRAME_PAYLOAD+28)
    sta _PAY_RD1+2
    sta _PAY_RD2+2

    ; Remaining byte count = pl_len
    lda pl_len
    sta rem_lo
    lda pl_len+1
    sta rem_hi

_udpw_loop:
    ; while remaining >= 2
    lda rem_hi
    bne _have_two
    lda rem_lo
    cmp #2
    bcc _maybe_odd
_have_two:
    ; RD2 points to RD1+1
    lda _PAY_RD1+1
    clc
    adc #1
    sta _PAY_RD2+1
    lda _PAY_RD1+2
    adc #0
    sta _PAY_RD2+2

_PAY_RD1: 
    lda $FFFF         ; <-- self-modified operand (hi byte of word)
    sta n2hi
_PAY_RD2: 
    lda $FFFF         ; <-- self-modified operand (lo byte of word)
    sta n2lo
    jsr sum_add

    ; advance RD1 by +2 (RD2 will be re-derived next iteration)
    lda _PAY_RD1+1
    clc
    adc #2
    sta _PAY_RD1+1
    lda _PAY_RD1+2
    adc #0
    sta _PAY_RD1+2

    ; remaining -= 2
    sec
    lda rem_lo
    sbc #2
    sta rem_lo
    lda rem_hi
    sbc #0
    sta rem_hi
    jmp _udpw_loop

_maybe_odd:
    ; if exactly 1 byte left, pad with 0
    lda rem_lo
    beq _done0

    ; RD1 already at next byte; mirror its operand into PAY_RDL
    lda _PAY_RD1+1
    sta _PAY_RDL+1
    lda _PAY_RD1+2
    sta _PAY_RDL+2
_PAY_RDL: 
    lda $FFFF         ; reads the single remaining byte
    sta n2hi
    lda #$00
    sta n2lo
    jsr sum_add
    ; (no need to bump operands further)

_done0:
    jsr sum_fold_ffff

    ; If checksum is 0x0000, put 0xFFFF per UDP rules
    lda sum_hi
    ora sum_lo
    bne +
    lda #$ff
    sta sum_hi
    sta sum_lo
+
    lda sum_hi
    sta ETH_TX_FRAME_PAYLOAD+20+6
    lda sum_lo
    sta ETH_TX_FRAME_PAYLOAD+20+7
    rts

    ; ---- 16-bit adder with carry tracking (sum_lo/sum_hi/sum_ex) ----
sum_add:
    clc
    lda sum_lo
    adc n2lo
    sta sum_lo
    lda sum_hi
    adc n2hi
    sta sum_hi
    lda sum_ex
    adc #$00
    sta sum_ex
    rts

sum_fold_ffff:
    ; add overflow byte back in, then 1's complement
    lda sum_lo
    sta n2lo
    lda sum_hi
    sta n2hi
    lda sum_ex
    clc
    adc n2lo
    sta n2lo
    lda n2hi
    adc #$00
    sta n2hi
    ; end-around carry if needed
    bcc +
    inc n2lo
    bne +
    inc n2hi
+
    lda #$ff
    sec
    sbc n2hi
    sta sum_hi
    lda #$ff
    sbc n2lo
    sta sum_lo
    rts



;=============================================================================
; Handle inbound DHCP packets (UDP dst 68) in mainline
; Expects IPv4 + UDP already validated by your RX path.
;=============================================================================
DHCP_ON_UDP:

    ldy DHCP_IP_IHL_BYTES        ; Y = IP header length in bytes

    ; Verify BOOTP op=2 (reply)
    lda ETH_RX_FRAME_PAYLOAD+8+0,y
    cmp #BOOTP_OP_BOOTREPLY
    bne _out

    ; Check XID matches ours
    lda ETH_RX_FRAME_PAYLOAD+8+$04,y
    cmp DHCP_XID+0
    bne _out
    lda ETH_RX_FRAME_PAYLOAD+8+$05,y
    cmp DHCP_XID+1
    bne _out
    lda ETH_RX_FRAME_PAYLOAD+8+$06,y
    cmp DHCP_XID+2
    bne _out
    lda ETH_RX_FRAME_PAYLOAD+8+$07,y
    cmp DHCP_XID+3
    bne _out

    ; yiaddr → candidate IP (for OFFER/ACK)
    lda ETH_RX_FRAME_PAYLOAD+8+$10,y
    sta DHCP_OFFER_IP+0
    lda ETH_RX_FRAME_PAYLOAD+8+$11,y
    sta DHCP_OFFER_IP+1
    lda ETH_RX_FRAME_PAYLOAD+8+$12,y
    sta DHCP_OFFER_IP+2
    lda ETH_RX_FRAME_PAYLOAD+8+$13,y
    sta DHCP_OFFER_IP+3

    ; Must have magic cookie
    lda ETH_RX_FRAME_PAYLOAD+8+236,y
    cmp #DHCP_MAGIC_0
    bne _out
    lda ETH_RX_FRAME_PAYLOAD+8+237,y
    cmp #DHCP_MAGIC_1
    bne _out
    lda ETH_RX_FRAME_PAYLOAD+8+238,y
    cmp #DHCP_MAGIC_2
    bne _out
    lda ETH_RX_FRAME_PAYLOAD+8+239,y
    cmp #DHCP_MAGIC_3
    bne _out

    ; Parse options TLV
    jsr DHCP_PARSE_OPTIONS

    ; Branch by message type
    lda dhcp_msg_type
    cmp #DHCPOFFER
    beq _got_offer
    cmp #DHCPACK
    beq _got_ack
    cmp #DHCPNAK
    beq _got_nak
    rts

_got_offer:
    ; record server id if present; then send REQUEST
    lda #DHCP_STATE_OFFER_SEEN
    sta DHCP_STATE

; Fallback: if SERVER_ID == 0.0.0.0, use IP source address from this OFFER
    ldy #0
    lda DHCP_SERVER_ID+0
    ora DHCP_SERVER_ID+1
    ora DHCP_SERVER_ID+2
    ora DHCP_SERVER_ID+3
    bne _srv_ok

    ; IP source is at ETH_RX_FRAME_PAYLOAD+12..15 (base = start of IP header)
    lda ETH_RX_FRAME_PAYLOAD+12
    sta DHCP_SERVER_ID+0
    lda ETH_RX_FRAME_PAYLOAD+13
    sta DHCP_SERVER_ID+1
    lda ETH_RX_FRAME_PAYLOAD+14
    sta DHCP_SERVER_ID+2
    lda ETH_RX_FRAME_PAYLOAD+15
    sta DHCP_SERVER_ID+3

_srv_ok:
    jsr DHCP_SEND_REQUEST
    lda #DHCP_STATE_REQUEST_SENT
    sta DHCP_STATE
    lda #$00
    sta DHCP_RETRY_TICKS
    rts

_got_ack:
inc DHCP_ACK_SEEN
    ; apply config: LOCAL_IP, SUBNET_MASK, ROUTER (gateway), DNS
    ldy #0
-   lda DHCP_OFFER_IP,y
    sta LOCAL_IP,y
    lda opt_mask,y
    sta SUBNET_MASK,y
    lda opt_router,y
    sta GATEWAY_IP,y
    lda opt_dns,y
    ;sta DNS_SERVER,y
    sta PRIMARY_DNS,y
    iny
    cpy #4
    bne -

    lda #DHCP_STATE_BOUND
    sta DHCP_STATE

    lda #0
    sta DHCP_IN_PROGRESS
    rts

_got_nak:
inc DHCP_NAK_SEEN
    lda #DHCP_STATE_FAILED
    sta DHCP_STATE

    lda #0
    sta DHCP_IN_PROGRESS
    rts

_out:
    rts

;=============================================================================
; --- Option parser: fills dhcp_msg_type, DHCP_SERVER_ID, mask/router/dns/lease
;     Bounds-checked; no zero-page; self-mod absolute,Y via DHCP_OPTS_RD_A.
;=============================================================================
DHCP_PARSE_OPTIONS:
    ; clear outputs
    lda #0
    sta dhcp_msg_type
    ldy #0
_clear4:
    sta opt_mask,y
    sta opt_router,y
    sta opt_dns,y
    sta DHCP_SERVER_ID,y
    sta DHCP_LEASE_SECS,y
    iny
    cpy #4
    bne _clear4

    ; ---- Compute options base = ETH_RX_FRAME_PAYLOAD + IHL + 8 + 240 ----
    lda #<ETH_RX_FRAME_PAYLOAD
    sta DHCP_OPTS_BASE_LO
    lda #>ETH_RX_FRAME_PAYLOAD
    sta DHCP_OPTS_BASE_HI

    ; + IHL (in bytes)
    lda DHCP_OPTS_BASE_LO
    clc
    adc DHCP_IP_IHL_BYTES
    sta DHCP_OPTS_BASE_LO
    lda DHCP_OPTS_BASE_HI
    adc #0
    sta DHCP_OPTS_BASE_HI

    ; ---- Derive UDP length (big-endian) at [IP+IHL+4..5] ----
    ldy DHCP_IP_IHL_BYTES
    lda ETH_RX_FRAME_PAYLOAD+4,y      ; UDP length hi
    sta _tmp_hi
    lda ETH_RX_FRAME_PAYLOAD+5,y      ; UDP length lo
    sta _tmp_lo

    ; udp_payload_len = udp_len - 8
    sec
    lda _tmp_lo
    sbc #8
    sta _tmp_lo
    lda _tmp_hi
    sbc #0
    sta _tmp_hi

    ; remaining options bytes = max( udp_payload_len - 240, 0 ), clamp to 255
    sec
    lda _tmp_lo
    sbc #240
    sta _tmp_lo
    lda _tmp_hi
    sbc #0
    sta _tmp_hi

    ; clamp:
    ; if negative -> 0
    ; else if >255 -> 255
    ; else -> low byte
    lda _tmp_hi
    bmi _opts_none              ; negative
    bne _opts_ff                ; > 255
    lda _tmp_lo                 ; 0..255 
    jmp _opts_store
    ;bne _opts_store
    ; exactly zero
    ;lda #$00
    ;bne _opts_store
_opts_ff:
    lda #$FF
    bne _opts_store
_opts_none:
    lda #$00
_opts_store:
    sta DHCP_OPTS_MAXY

    ; advance base pointer by +8 (UDP hdr) +240 (BOOTP+cookie) to options
    lda DHCP_OPTS_BASE_LO
    clc
    adc #8
    sta DHCP_OPTS_BASE_LO
    lda DHCP_OPTS_BASE_HI
    adc #0
    sta DHCP_OPTS_BASE_HI

    lda DHCP_OPTS_BASE_LO
    clc
    adc #240
    sta DHCP_OPTS_BASE_LO
    lda DHCP_OPTS_BASE_HI
    adc #0
    sta DHCP_OPTS_BASE_HI

    ; Patch the self-mod LDA operand once
    lda DHCP_OPTS_BASE_LO
    sta OPTRD+1
    lda DHCP_OPTS_BASE_HI
    sta OPTRD+2

    ; ---- Scan TLVs ----
    ldy #0
_next:
    ; stop if Y >= MAXY (no more option bytes inside UDP payload)
    cpy DHCP_OPTS_MAXY
    bcs _done

    jsr DHCP_OPTS_RD_A           ; A = option code
    cmp #DHCP_OPT_END
    beq _done
    cmp #$00
    beq _pad

    sta _code
    iny
    cpy DHCP_OPTS_MAXY
    bcs _done                     ; avoid overrun if malformed at end
    jsr DHCP_OPTS_RD_A           ; A = length
    sta _len
    iny

    lda _code
    cmp #DHCP_OPT_MESSAGE_TYPE
    beq _opt_msg
    cmp #DHCP_OPT_SERVER_ID
    beq _opt_svid
    cmp #DHCP_OPT_SUBNET_MASK
    beq _opt_mask
    cmp #DHCPopt_router
    beq _opt_rtr
    cmp #DHCPopt_dns
    beq _opt_dns
    cmp #DHCP_OPT_LEASE_TIME
    beq _opt_lease

    ; ---- skip unknown option: advance Y by _len, bounded ----
    ldx _len
    beq _next
_skip_unknown:
    iny
    cpy DHCP_OPTS_MAXY
    bcs _done
    dex
    bne _skip_unknown
    jmp _next

_pad:
    iny
    cpy DHCP_OPTS_MAXY
    bcs _done
    jmp _next

_opt_msg:
    ; expect len >= 1
    lda _len
    beq _next
    cpy DHCP_OPTS_MAXY
    bcs _done
    jsr DHCP_OPTS_RD_A
    sta dhcp_msg_type
    iny
    jmp _next

_opt_svid:
    ; copy min(len,4), then skip any remainder, all bounded
    lda _len
    beq _next
    cmp #4
    bcc _svid_len_ok
    lda #4
_svid_len_ok:
    sta _cp                      ; copy count
    ldx #0
_svid_copy_loop:
    cpx _cp
    beq _svid_after_copy
    cpy DHCP_OPTS_MAXY
    bcs _done
    jsr DHCP_OPTS_RD_A
    sta DHCP_SERVER_ID,x
    iny
    inx
    bne _svid_copy_loop
_svid_after_copy:
    lda _len
    sec
    sbc _cp
    tax
_svid_skip_extra:
    cpx #0
    beq _next
    iny
    cpy DHCP_OPTS_MAXY
    bcs _done
    dex
    bne _svid_skip_extra
    jmp _next

_opt_mask:
    ; copy min(len,4), skip any remainder
    lda _len
    beq _next
    cmp #4
    bcc _mask_len_ok
    lda #4
_mask_len_ok:
    sta _cp
    ldx #0
_mask_copy_loop:
    cpx _cp
    beq _mask_after_copy
    cpy DHCP_OPTS_MAXY
    bcs _done
    jsr DHCP_OPTS_RD_A
    sta opt_mask,x
    iny
    inx
    bne _mask_copy_loop
_mask_after_copy:
    lda _len
    sec
    sbc _cp
    tax
_mask_skip_extra:
    cpx #0
    beq _next
    iny
    cpy DHCP_OPTS_MAXY
    bcs _done
    dex
    bne _mask_skip_extra
    jmp _next

_opt_rtr:
    ; copy first router only: min(len,4), then skip remainder (could be 4*N)
    lda _len
    beq _next
    cmp #4
    bcc _rtr_len_ok
    lda #4
_rtr_len_ok:
    sta _cp
    ldx #0
_rtr_copy_loop:
    cpx _cp
    beq _rtr_after_copy
    cpy DHCP_OPTS_MAXY
    bcs _done
    jsr DHCP_OPTS_RD_A
    sta opt_router,x
    iny
    inx
    bne _rtr_copy_loop
_rtr_after_copy:
    lda _len
    sec
    sbc _cp
    tax
_rtr_skip_loop:
    cpx #0
    beq _next
    iny
    cpy DHCP_OPTS_MAXY
    bcs _done
    dex
    bne _rtr_skip_loop
    jmp _next

_opt_dns:
    ; copy first DNS only: min(len,4), then skip remainder (could be 4*N)
    lda _len
    beq _next
    cmp #4
    bcc _dns_len_ok
    lda #4
_dns_len_ok:
    sta _cp
    ldx #0
_dns_copy_loop:
    cpx _cp
    beq _dns_after_copy
    cpy DHCP_OPTS_MAXY
    bcs _done
    jsr DHCP_OPTS_RD_A
    sta opt_dns,x
    iny
    inx
    bne _dns_copy_loop
_dns_after_copy:
    lda _len
    sec
    sbc _cp
    tax
_dns_skip_loop:
    cpx #0
    beq _next
    iny
    cpy DHCP_OPTS_MAXY
    bcs _done
    dex
    bne _dns_skip_loop
    jmp _next

_opt_lease:
    ; copy min(len,4), skip any remainder
    lda _len
    beq _next
    cmp #4
    bcc _lease_len_ok
    lda #4
_lease_len_ok:
    sta _cp
    ldx #0
_lease_copy_loop:
    cpx _cp
    beq _lease_after_copy
    cpy DHCP_OPTS_MAXY
    bcs _done
    jsr DHCP_OPTS_RD_A
    sta DHCP_LEASE_SECS,x
    iny
    inx
    bne _lease_copy_loop
_lease_after_copy:
    lda _len
    sec
    sbc _cp
    tax
_lease_skip_loop:
    cpx #0
    beq _next
    iny
    cpy DHCP_OPTS_MAXY
    bcs _done
    dex
    bne _lease_skip_loop
    jmp _next

_done:
    rts

_code:      .byte 0
_len:       .byte 0
_cp:        .byte 0
_tmp_hi     .byte 0
_tmp_lo     .byte 0

; Read A = *(DHCP_OPTS_BASE + Y)
DHCP_OPTS_RD_A:
OPTRD:
    lda $FFFF,y
    rts





