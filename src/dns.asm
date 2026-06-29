;===========================================================
; Minimal UDP + DNS (A-record) resolver for MEGA65 stack
; - UDP checksum = 0 (allowed for IPv4)
; - Non-blocking resend/backoff like ARP
; - Uses PRIMARY_DNS as server
;===========================================================

; ---- UDP header struct offsets (relative to IP payload base) ----
UDP_HDR_SRC_HI          = 0
UDP_HDR_SRC_LO          = 1
UDP_HDR_DST_HI          = 2
UDP_HDR_DST_LO          = 3
UDP_HDR_LEN_HI          = 4
UDP_HDR_LEN_LO          = 5
UDP_HDR_CHK_HI          = 6
UDP_HDR_CHK_LO          = 7
UDP_DATA_BASE           = 8            ; UDP payload starts here

; ---- DNS ----
DNS_PORT                = 53
DNS_STATE_IDLE          = $00
DNS_STATE_WAIT          = $01
DNS_STATE_DONE          = $02
DNS_STATE_FAIL          = $03

DNS_TIMEOUT_TICKS_BASE  = 2     ; ~2 ticks between (re)sends, grows linearly
DNS_MAX_RETRIES         = 8
DNS_TICK_FRAMES         = 6

; public result
DNS_RESULT_IP:          .byte $00, $00, $00, $00

; internal state
DNS_STATE:              .byte $00
DNS_RETRY_LEFT:         .byte $00
DNS_RETRY_TICKS:        .byte $00
DNS_LAST_BACKOFF:       .byte $00
DNS_FRAME_TICKS:        .byte $00
DNS_LAST_RASTER_LO:     .byte $00
DNS_LAST_RASTER_HI:     .byte $00

; message id + client port (ephemeral: $C000-$DFFF)
DNS_MSG_ID_HI:          .byte $00
DNS_MSG_ID_LO:          .byte $00
DNS_CLIENT_PORT_HI:     .byte $31
DNS_CLIENT_PORT_LO:     .byte $53

; packed QNAME buffer (max 128)
DNS_QNAME:              .fill 128, $00
DNS_QNAME_LEN:          .byte $00

DNS_ARP_DEFERS:         .byte 40   ; ~40 quick defers then give up

DNS_DEBUG_STAGE:        .byte $00
DNS_QUERY_TX_OK:        .byte $00
DNS_QUERY_TX_FAIL:      .byte $00
DNS_RX_HITS:            .byte $00
DNS_ARP_WAIT_COUNT:     .byte $00
DNS_PARSE_FAILS:        .byte $00
DNS_RAW_RX_COUNT:       .byte $00
DNS_IPV4_RX_COUNT:      .byte $00
DNS_UDP_RX_COUNT:       .byte $00
DNS_NOT_FOR_US_COUNT:   .byte $00

;===========================================================
; BUILD + SEND a UDP/IPv4 packet in ETH_TX_FRAME_*
; Inputs:
;   - IP dst = DNS server (PRIMARY_DNS[0..3])
;   - UDP src/dst/len are already staged in header area below
;   - UDP payload already copied starting at +20+8
;===========================================================
DNS_SEND_UDP:
    ; ---- EtherType ----
    lda #$08
    sta ETH_TX_TYPE
    lda #$00
    sta ETH_TX_TYPE+1

    ; ---- Setup IPv4 header for UDP ----
    ; Fill generic fields in IPV4_HEADER block
    lda #$11                      ; protocol UDP
    sta IPV4_HDR_PROTO

    ; src IP
    lda LOCAL_IP+0
    sta IPV4_HDR_SRC_IP+0
    lda LOCAL_IP+1
    sta IPV4_HDR_SRC_IP+1
    lda LOCAL_IP+2
    sta IPV4_HDR_SRC_IP+2
    lda LOCAL_IP+3
    sta IPV4_HDR_SRC_IP+3

    ; dst IP = PRIMARY_DNS (server)
    lda PRIMARY_DNS+0
    sta IPV4_HDR_DST_IP+0
    lda PRIMARY_DNS+1
    sta IPV4_HDR_DST_IP+1
    lda PRIMARY_DNS+2
    sta IPV4_HDR_DST_IP+2
    lda PRIMARY_DNS+3
    sta IPV4_HDR_DST_IP+3

    ; total IP length = 20 (IP) + UDP_len (header+data)
    lda ETH_TX_FRAME_PAYLOAD+20+UDP_HDR_LEN_HI
    sta IPV4_HDR_LEN
    lda ETH_TX_FRAME_PAYLOAD+20+UDP_HDR_LEN_LO
    sta IPV4_HDR_LEN+1
    ; Add 20
    clc
    lda IPV4_HDR_LEN+1
    adc #20
    sta IPV4_HDR_LEN+1
    lda IPV4_HDR_LEN
    adc #0
    sta IPV4_HDR_LEN

    ; DF=1, offset=0
    lda #$40
    sta IPV4_HDR_FLGS_OFFS
    lda #$00
    sta IPV4_HDR_FLGS_OFFS+1

    ; compute IPv4 checksum
    jsr CALC_IPV4_CHECKSUM

    ; Copy IP header (20B) to TX payload (same as BUILD_IPV4_HEADER does)
    ldx #0
_cpy_ip:
    lda IPV4_HEADER,x
    sta ETH_TX_FRAME_PAYLOAD,x
    inx
    cpx #20
    bne _cpy_ip

    ; ---- Final frame length: 14 + IP length ----
    lda IPV4_HDR_LEN+1
    clc
    adc #14
    sta ETH_TX_LEN_LSB
    lda IPV4_HDR_LEN
    adc #0
    sta ETH_TX_LEN_MSB

    ; Send
    jsr ETH_PACKET_SEND
    rts

;===========================================================
; Build and send one DNS query for QNAME in DNS_QNAME
; Uses (and bumps) DNS_MSG_ID, DNS_CLIENT_PORT_HI
;===========================================================
DNS_SEND_QUERY:
    lda #$01
    sta DNS_DEBUG_STAGE

    ; ARP must be ready first (non-blocking)
    jsr DNS_ENSURE_ARP_READY
    bcs _no_send          ; not ready → tick will retry

    ; ---- compose DNS header+question at UDP payload base ----
    ; Layout (DNS):
    ;  0..1  ID
    ;  2..3  Flags (RD=1)
    ;  4..5  QDCOUNT=1
    ;  6..7  ANCOUNT=0
    ;  8..9  NSCOUNT=0
    ; 10..11 ARCOUNT=0
    ; 12..   QNAME (packed), then QTYPE=1, QCLASS=1

    ; Write ID
    lda DNS_MSG_ID_HI
    sta ETH_TX_FRAME_PAYLOAD+20+UDP_DATA_BASE+0
    lda DNS_MSG_ID_LO
    sta ETH_TX_FRAME_PAYLOAD+20+UDP_DATA_BASE+1
    ; Flags: RD=1 => 0x0100
    lda #$01
    sta ETH_TX_FRAME_PAYLOAD+20+UDP_DATA_BASE+2
    lda #$00
    sta ETH_TX_FRAME_PAYLOAD+20+UDP_DATA_BASE+3
    ; QD=1
    lda #$00
    sta ETH_TX_FRAME_PAYLOAD+20+UDP_DATA_BASE+4
    lda #$01
    sta ETH_TX_FRAME_PAYLOAD+20+UDP_DATA_BASE+5
    ; AN=NS=AR = 0
    lda #$00
    sta ETH_TX_FRAME_PAYLOAD+20+UDP_DATA_BASE+6
    sta ETH_TX_FRAME_PAYLOAD+20+UDP_DATA_BASE+7
    sta ETH_TX_FRAME_PAYLOAD+20+UDP_DATA_BASE+8
    sta ETH_TX_FRAME_PAYLOAD+20+UDP_DATA_BASE+9
    sta ETH_TX_FRAME_PAYLOAD+20+UDP_DATA_BASE+10
    sta ETH_TX_FRAME_PAYLOAD+20+UDP_DATA_BASE+11

    ; copy QNAME
    ldx #0
_qcpy:
    lda DNS_QNAME,x
    sta ETH_TX_FRAME_PAYLOAD+20+UDP_DATA_BASE+12,x
    inx
    cpx DNS_QNAME_LEN
    bne _qcpy

    ; zero label terminator included in DNS_QNAME (so DNS_QNAME_LEN includes it)
    ; append QTYPE=A(1), QCLASS=IN(1)
    lda #$00
    sta ETH_TX_FRAME_PAYLOAD+20+UDP_DATA_BASE+12,x   ; QTYPE hi
    inx
    lda #$01
    sta ETH_TX_FRAME_PAYLOAD+20+UDP_DATA_BASE+12,x   ; QTYPE lo
    inx
    lda #$00
    sta ETH_TX_FRAME_PAYLOAD+20+UDP_DATA_BASE+12,x   ; QCLASS hi
    inx
    lda #$01
    sta ETH_TX_FRAME_PAYLOAD+20+UDP_DATA_BASE+12,x   ; QCLASS lo
    inx

    ; x = dns payload tail (QNAME incl. 0 + QTYPE/QCLASS = qtail)
    stx _dns_pay_len

    ; ---- UDP header fields ----
    ; ...
    ; UDP length = 8 + (12 + qtail) = 20 + qtail
    lda _dns_pay_len
    clc
    adc #20            ; was #8
    sta ETH_TX_FRAME_PAYLOAD+20+UDP_HDR_LEN_LO
    lda #0
    adc #0
    sta ETH_TX_FRAME_PAYLOAD+20+UDP_HDR_LEN_HI

    ; ---- UDP header fields ----
    ; src port = ($C0 | (DNS_CLIENT_PORT_HI & $1F)) : rotating low byte
    lda DNS_CLIENT_PORT_HI
    and #$1F
    ora #$C0
    sta ETH_TX_FRAME_PAYLOAD+20+UDP_HDR_SRC_HI
    lda DNS_CLIENT_PORT_LO
    sta ETH_TX_FRAME_PAYLOAD+20+UDP_HDR_SRC_LO

    ; dst port = 53
    lda #>(DNS_PORT)
    sta ETH_TX_FRAME_PAYLOAD+20+UDP_HDR_DST_HI
    lda #<(DNS_PORT)
    sta ETH_TX_FRAME_PAYLOAD+20+UDP_HDR_DST_LO

    ; checksum = 0 (IPv4 allowed)
    lda #0
    sta ETH_TX_FRAME_PAYLOAD+20+UDP_HDR_CHK_HI
    sta ETH_TX_FRAME_PAYLOAD+20+UDP_HDR_CHK_LO

    ; ---- Build IPv4+send ----
    lda #$02
    sta DNS_DEBUG_STAGE
    jsr DNS_SEND_UDP
    bcs _tx_fail
    inc DNS_QUERY_TX_OK
    lda #$03
    sta DNS_DEBUG_STAGE
    clc                 ; C=0 - sent
    rts

_tx_fail:
    inc DNS_QUERY_TX_FAIL
    lda #$04
    sta DNS_DEBUG_STAGE
    sec
    rts

_no_send:
    inc DNS_ARP_WAIT_COUNT
    lda #$05
    sta DNS_DEBUG_STAGE
    sec                 ; C=1 - not sent
    rts

_dns_pay_len: .byte 0

;===========================================================
; Pack C-string hostname → DNS_QNAME (no zero-page required)
; In: A=lo, X=hi pointer to 0-terminated host
; Out: C=0 ok, C=1 error (label>63 or buffer>127)
;===========================================================
DNS_PACK_HOSTNAME:
    ; Patch absolute base for LDA abs,Y
    sta _hn_abs+1
    stx _hn_abs+2
    sta _hn_abs2+1          ; <- patch the peek reader too
    stx _hn_abs2+2

    ldy #0                  ; input index
    ldx #1                  ; output index (skip first length)
    lda #0
    sta DNS_QNAME+0         ; placeholder for first label length
    sta DNS_PACK_LBL_LEN
    sta DNS_PACK_LBL_POS            ; where to write current label length (starts at 0)

_next:
_hn_abs:                    ; self-modified: LDA $xxxx,Y
    .byte $B9, $00, $00
    beq _end
    jsr DNS_HOST_CHAR_TO_ASCII
    bcc _char_ok

    sty DNS_ARP_WAIT_COUNT
    sta DNS_PARSE_FAILS
    jmp _toolong

_char_ok:
    cmp #'.'
    beq _dot

    ; copy char
    cpx #128
    bcs _toolong
    sta DNS_QNAME,x
    inx

    inc DNS_PACK_LBL_LEN
    lda DNS_PACK_LBL_LEN
    cmp #64                 ; RFC: label length <=63
    bcs _toolong
    iny
    bne _next
    inc _hn_abs+2
    inc _hn_abs2+2
    jmp _next

_dot:
    ; if DNS_PACK_LBL_LEN == 0, either root "." (at start) or invalid ".."
    lda DNS_PACK_LBL_LEN
    bne _dot_normal

    ; peek next char after '.' with page-wrap handling
    tya
    pha
    lda #0
    sta TMP0                        ; TMP0=1 if we wrap+inc high byte
    iny
    bne +
    inc _hn_abs+2
    inc _hn_abs2+2
    inc TMP0
+
_hn_abs2:                           ; self-modified: LDA $xxxx,Y (same base)
    .byte $B9, $00, $00
    beq _root_if_first              ; '.' followed by NUL

    ; mid-string empty label ("..") => error
    pla
    tay
    lda TMP0
    beq +
    dec _hn_abs+2
    dec _hn_abs2+2

+   sec
    rts

_root_if_first:
    ; accept bare "." only if it's the very first label
    lda DNS_PACK_LBL_POS
    bne _empty_label_error

    ; emit a single zero octet and return OK
    lda #0
    sta DNS_QNAME+0
    lda #1
    sta DNS_QNAME_LEN
    pla
    tay
    lda TMP0
    beq +
    dec _hn_abs+2
    dec _hn_abs2+2

+   clc
    rts

_empty_label_error:
    ; ".<NUL>" but not at start => invalid
    pla
    tay
    lda TMP0
    beq +
    dec _hn_abs+2
    dec _hn_abs2+2

+   sec
    rts

_dot_normal:
    tya
    pha
    ldy DNS_PACK_LBL_POS
    lda DNS_PACK_LBL_LEN
    sta DNS_QNAME,y                ; write length at current label slot
    pla
    tay

    ; start next label at current X
    stx DNS_PACK_LBL_POS
    lda #0
    sta DNS_PACK_LBL_LEN
    cpx #128
    bcs _toolong
    sta DNS_QNAME,x                ; placeholder for next label length
    inx
    iny
    bne _next
    inc _hn_abs+2
    inc _hn_abs2+2
    jmp _next

_end:
    ; write last label length
    ldy DNS_PACK_LBL_POS
    lda DNS_PACK_LBL_LEN
    sta DNS_QNAME,y

    ; append single terminator iff last label wasn’t already empty
    lda DNS_PACK_LBL_LEN
    beq +
    lda #0
    cpx #128
    bcs _toolong
    sta DNS_QNAME,x
    inx
+
    stx DNS_QNAME_LEN
    clc
    rts

_toolong:
    sec
    rts

DNS_HOST_CHAR_TO_ASCII:
    sta TMP0
    cmp #$80
    bcc DNS_HOST_NOT_HIGH_BIT
    and #$7F

DNS_HOST_NOT_HIGH_BIT:
    cmp #'A'
    bcc DNS_HOST_NOT_UPPER
    cmp #'Z'+1
    bcs DNS_HOST_NOT_UPPER
    ora #$20
    clc
    rts

DNS_HOST_NOT_UPPER:
    cmp #'a'
    bcc DNS_HOST_NOT_LOWER
    cmp #'z'+1
    bcs DNS_HOST_NOT_LOWER
    clc
    rts

DNS_HOST_NOT_LOWER:
    cmp #'0'
    bcc DNS_HOST_NOT_DIGIT
    cmp #'9'+1
    bcs DNS_HOST_NOT_DIGIT
    clc
    rts

DNS_HOST_NOT_DIGIT:
    cmp #'.'
    beq DNS_HOST_OK_CHAR
    cmp #'-'
    beq DNS_HOST_OK_CHAR
DNS_HOST_BAD_CHAR:
    lda TMP0
    sec
    rts

DNS_HOST_OK_CHAR:
    clc
    rts

DNS_PACK_LBL_LEN:  .byte 0
DNS_PACK_LBL_POS:  .byte 0

;===========================================================
; Decide ARP next-hop and ensure ETH_TX_FRAME_DEST_MAC is ready
; C=0 if ready to send, C=1 if ARP in progress/not ready
;===========================================================
DNS_ENSURE_ARP_READY:
    ; decide next-hop IP → ARP_QUERY_IP[0..3]
    ldx #3
_dns_netloop:
    lda PRIMARY_DNS,x
    and SUBNET_MASK,x
    sta _dns_tmp
    lda LOCAL_IP,x
    and SUBNET_MASK,x
    cmp _dns_tmp
    bne _use_gw
    dex
    bpl _dns_netloop
    ; same net → use PRIMARY_DNS
    ldx #3
_copy_dns_ip:
    lda PRIMARY_DNS,x
    sta ARP_QUERY_IP,x
    dex
    bpl _copy_dns_ip
    jmp _have_nexthop
_use_gw:
    ldx #3
_copy_gw_ip:
    lda GATEWAY_IP,x
    sta ARP_QUERY_IP,x
    dex
    bpl _copy_gw_ip

_have_nexthop:
    ; cache?
    jsr ARP_QUERY_CACHE
    bne _ready

    ; no MAC yet → if not already waiting, start ARP
    lda ETH_STATE
    cmp #ETH_STATE_ARP_WAITING
    beq _not_ready

    ; mirror ARP_QUERY_IP → ARP_REQUEST_IP and kick ARP
    ldx #3
_cpy_req:
    lda ARP_QUERY_IP,x
    sta ARP_REQUEST_IP,x
    dex
    bpl _cpy_req
    jsr ARP_REQUEST
_not_ready:
    sec         ; C=1 not ready
    rts
_ready:
    clc         ; C=0 MAC ready, ETH_TX_FRAME_DEST_MAC populated
    rts

_dns_tmp: .byte 0

;===========================================================
; Public: start a resolve (from host_str)
; - Packs QNAME
; - Arms retry state
; - Sends first query
;===========================================================
DNS_RESOLVE_START:

    lda #40
    sta DNS_ARP_DEFERS

    ; clear previous result
    lda #0
    sta DNS_DEBUG_STAGE
    sta DNS_QUERY_TX_OK
    sta DNS_QUERY_TX_FAIL
    sta DNS_RX_HITS
    sta DNS_ARP_WAIT_COUNT
    sta DNS_PARSE_FAILS
    sta DNS_RAW_RX_COUNT
    sta DNS_IPV4_RX_COUNT
    sta DNS_UDP_RX_COUNT
    sta DNS_NOT_FOR_US_COUNT
    sta DNS_RESULT_IP+0
    sta DNS_RESULT_IP+1
    sta DNS_RESULT_IP+2
    sta DNS_RESULT_IP+3

    lda #$10
    sta DNS_DEBUG_STAGE

    lda #<host_str
    ldx #>host_str
    jsr DNS_PACK_HOSTNAME
    bcc _pack_ok
    lda #$11
    sta DNS_DEBUG_STAGE
    jmp _start_fail

_pack_ok:

    inc DNS_CLIENT_PORT_HI
    lda DNS_CLIENT_PORT_LO
    clc
    adc #$3D
    sta DNS_CLIENT_PORT_LO
    bcc _dns_port_ok
    inc DNS_CLIENT_PORT_HI
_dns_port_ok:

    lda #DNS_MAX_RETRIES
    sta DNS_RETRY_LEFT
    lda #DNS_TIMEOUT_TICKS_BASE
    sta DNS_RETRY_TICKS
    lda #DNS_TIMEOUT_TICKS_BASE
    sta DNS_LAST_BACKOFF
    lda #DNS_TICK_FRAMES
    sta DNS_FRAME_TICKS
    jsr ARP_READ_RASTER
    lda ARP_CUR_RASTER_LO
    sta DNS_LAST_RASTER_LO
    lda ARP_CUR_RASTER_HI
    sta DNS_LAST_RASTER_HI
    lda #DNS_STATE_WAIT
    sta DNS_STATE

    lda DNS_MSG_ID_LO
    clc
    adc #1
    sta DNS_MSG_ID_LO
    lda DNS_MSG_ID_HI
    adc #0
    sta DNS_MSG_ID_HI

    jsr DNS_SEND_QUERY

    clc
    rts
_start_fail:
    lda #DNS_STATE_FAIL
    sta DNS_STATE
    ; zero result on fail too (optional but nice)
    lda #0
    sta DNS_RESULT_IP+0
    sta DNS_RESULT_IP+1
    sta DNS_RESULT_IP+2
    sta DNS_RESULT_IP+3
    sec
    rts

;===========================================================
; Poller (optional): returns A=status: 0=idle,1=wait,2=done,3=fail
;===========================================================
DNS_POLL:
    lda DNS_STATE
    rts

;===========================================================
; Drive DNS retries (call from ETH_STATUS_POLL)
;===========================================================
DNS_TICK:
    lda DNS_STATE
    cmp #DNS_STATE_WAIT
    bne _tick_done

    jsr DNS_FRAME_TICK
    bcc _tick_done

    lda DNS_RETRY_TICKS
    beq _expired
    dec DNS_RETRY_TICKS
    rts

_expired:
    ; Out of retries?
    lda DNS_RETRY_LEFT
    beq _give_up

    ; If ARP isn't ready, don't burn a retry; try again soon
    jsr DNS_ENSURE_ARP_READY
    bcs _defer                 ; C=1 → not ready

    dec DNS_RETRY_LEFT
    lda DNS_LAST_BACKOFF
    clc
    adc #1
    sta DNS_LAST_BACKOFF
    lda DNS_LAST_BACKOFF
    sta DNS_RETRY_TICKS
    jsr DNS_SEND_QUERY
    rts

_defer:
    lda DNS_ARP_DEFERS
    beq _give_up
    dec DNS_ARP_DEFERS
    lda #DNS_TIMEOUT_TICKS_BASE     ;#1
    sta DNS_RETRY_TICKS
    rts

_give_up:
    lda #$f1
    sta DNS_DEBUG_STAGE
    lda #DNS_STATE_FAIL
    sta DNS_STATE
_tick_done:
    rts

DNS_FRAME_TICK:
    jsr ARP_READ_RASTER

    lda ARP_CUR_RASTER_HI
    cmp DNS_LAST_RASTER_HI
    bcc _dns_frame_elapsed
    bne _dns_no_frame

    lda ARP_CUR_RASTER_LO
    cmp DNS_LAST_RASTER_LO
    bcc _dns_frame_elapsed

_dns_no_frame:
    lda ARP_CUR_RASTER_LO
    sta DNS_LAST_RASTER_LO
    lda ARP_CUR_RASTER_HI
    sta DNS_LAST_RASTER_HI
    clc
    rts

_dns_frame_elapsed:
    lda ARP_CUR_RASTER_LO
    sta DNS_LAST_RASTER_LO
    lda ARP_CUR_RASTER_HI
    sta DNS_LAST_RASTER_HI

    lda DNS_FRAME_TICKS
    beq _dns_emit_tick
    dec DNS_FRAME_TICKS
    beq _dns_emit_tick
    clc
    rts

_dns_emit_tick:
    lda #DNS_TICK_FRAMES
    sta DNS_FRAME_TICKS
    sec
    rts

;===========================================================
; DNS_UDP_IN — minimal: extract first A record IPv4 and exit
;===========================================================
DNS_UDP_IN:
    lda DNS_STATE
    cmp #DNS_STATE_WAIT
    bne DNS2_NOT_DNS
    inc DNS_RX_HITS
    lda #$10
    sta DNS_DEBUG_STAGE

    ; ---- IHL (IP header length in bytes) ----
    lda ETH_RX_FRAME_PAYLOAD+0
    and #$0F
    asl
    asl
    sta ihl

    ; UDP destination port must match our rotating DNS client port.
    ldy ihl
    lda DNS_CLIENT_PORT_HI
    and #$1F
    ora #$C0
    sta expected_port_hi
    lda ETH_RX_FRAME_PAYLOAD+2,y
    cmp expected_port_hi
    bne DNS2_NOT_DNS
    lda ETH_RX_FRAME_PAYLOAD+3,y
    cmp DNS_CLIENT_PORT_LO
    bne DNS2_NOT_DNS

    lda #$11
    sta DNS_DEBUG_STAGE
    ; UDP source port must be 53.
    lda ETH_RX_FRAME_PAYLOAD+0,y
    cmp #$00
    bne DNS2_NOT_DNS
    lda ETH_RX_FRAME_PAYLOAD+1,y
    cmp #DNS_PORT
    bne DNS2_NOT_DNS

    ; IPv4 source must be the configured resolver.
    ldx #3
DNS2_SRC_CHECK:
    lda ETH_RX_FRAME_PAYLOAD+12,x
    cmp PRIMARY_DNS,x
    bne DNS2_NOT_DNS
    dex
    bpl DNS2_SRC_CHECK

    lda #$12
    sta DNS_DEBUG_STAGE
    lda #$00
    sta DNS2_BOUNDS_FAIL

    ; DNS payload length = UDP length - 8 byte UDP header.
    lda ETH_RX_FRAME_PAYLOAD+UDP_HDR_LEN_LO,y
    sec
    sbc #UDP_DATA_BASE
    sta DNS2_SKIP_LO
    lda ETH_RX_FRAME_PAYLOAD+UDP_HDR_LEN_HI,y
    sbc #$00
    bcc DNS2_FAIL
    sta DNS2_SKIP_HI
    bne DNS2_UDP_LEN_OK
    lda DNS2_SKIP_LO
    cmp #$0c
    bcc DNS2_FAIL

    ; Actual DNS payload available = IPv4 total length - IHL - UDP header.
    lda IPV4_RX_TOTAL_LO
    sec
    sbc ihl
    sta DNS2_PTR_LO
    lda IPV4_RX_TOTAL_HI
    sbc #$00
    bcc DNS2_FAIL
    sta DNS2_PTR_HI
    lda DNS2_PTR_LO
    sec
    sbc #UDP_DATA_BASE
    sta DNS2_PTR_LO
    lda DNS2_PTR_HI
    sbc #$00
    bcc DNS2_FAIL
    sta DNS2_PTR_HI
    bne DNS2_REAL_LEN_OK
    lda DNS2_PTR_LO
    cmp #$0c
    bcc DNS2_FAIL

DNS2_REAL_LEN_OK:
    ; Clamp claimed UDP payload length to the real bytes in the IPv4 datagram.
    lda DNS2_PTR_HI
    cmp DNS2_SKIP_HI
    bcc DNS2_CLAMP_LEN
    bne DNS2_UDP_LEN_OK
    lda DNS2_PTR_LO
    cmp DNS2_SKIP_LO
    bcs DNS2_UDP_LEN_OK

DNS2_CLAMP_LEN:
    lda DNS2_PTR_LO
    sta DNS2_SKIP_LO
    lda DNS2_PTR_HI
    sta DNS2_SKIP_HI

DNS2_UDP_LEN_OK:
    ; Reader base = first byte of DNS payload.
    lda #<ETH_RX_FRAME_PAYLOAD+UDP_DATA_BASE
    clc
    adc ihl
    sta DNS2_BASE_LO
    sta DNS2_RD_LO
    lda #>ETH_RX_FRAME_PAYLOAD+UDP_DATA_BASE
    adc #$00
    sta DNS2_BASE_HI
    sta DNS2_RD_HI
    lda DNS2_BASE_LO
    clc
    adc DNS2_SKIP_LO
    sta DNS2_END_LO
    lda DNS2_BASE_HI
    adc DNS2_SKIP_HI
    sta DNS2_END_HI

    ; Transaction ID.
    jsr DNS2_READ_BYTE
    cmp DNS_MSG_ID_HI
    bne DNS2_NOT_DNS
    jsr DNS2_READ_BYTE
    cmp DNS_MSG_ID_LO
    bne DNS2_NOT_DNS

    lda #$13
    sta DNS_DEBUG_STAGE
    ; Flags: QR=1, TC=0, RCODE=0.
    jsr DNS2_READ_BYTE
    sta DNS2_FLAGS_HI
    jsr DNS2_READ_BYTE
    sta DNS2_FLAGS_LO
    lda DNS2_FLAGS_HI
    and #%10000000
    beq DNS2_NOT_DNS
    lda DNS2_FLAGS_HI
    and #%00000010
    bne DNS2_FAIL
    lda DNS2_FLAGS_LO
    and #$0F
    bne DNS2_FAIL

    lda #$14
    sta DNS_DEBUG_STAGE
    ; QDCOUNT.
    jsr DNS2_READ_BYTE
    bne DNS2_FAIL
    jsr DNS2_READ_BYTE
    sta DNS2_QD_LEFT
    beq DNS2_FAIL

    ; ANCOUNT.
    jsr DNS2_READ_BYTE
    sta DNS2_ANS_HI
    jsr DNS2_READ_BYTE
    sta DNS2_ANS_LEFT

    ; NSCOUNT.
    jsr DNS2_READ_BYTE
    sta DNS2_NS_HI
    jsr DNS2_READ_BYTE
    sta DNS2_NS_LEFT

    ; ARCOUNT.
    jsr DNS2_READ_BYTE
    sta DNS2_AR_HI
    jsr DNS2_READ_BYTE
    sta DNS2_AR_LEFT

DNS2_SKIP_QUESTIONS:
    lda DNS2_QD_LEFT
    beq DNS2_PREP_ANSWERS
    jsr DNS2_SKIP_NAME
    bcs DNS2_FAIL
    lda #$04
    ldx #$00
    jsr DNS2_SKIP_BYTES
    bcs DNS2_FAIL
    dec DNS2_QD_LEFT
    jmp DNS2_SKIP_QUESTIONS

DNS2_PREP_ANSWERS:
    lda DNS2_ANS_HI
    beq DNS2_ANS_LOW_ONLY
    lda #$FF
    sta DNS2_ANS_LEFT
DNS2_ANS_LOW_ONLY:
    lda DNS2_ANS_LEFT
    beq DNS2_FAIL
    lda #$00
    sta seen_cname

    lda #$15
    sta DNS_DEBUG_STAGE
DNS2_ANSWER_LOOP:
    jsr DNS2_SKIP_NAME
    bcs DNS2_FAIL

    jsr DNS2_READ_BYTE
    sta DNS2_TYPE_HI
    jsr DNS2_READ_BYTE
    sta DNS2_TYPE_LO
    jsr DNS2_READ_BYTE
    sta DNS2_CLASS_HI
    jsr DNS2_READ_BYTE
    sta DNS2_CLASS_LO

    lda #$04
    ldx #$00
    jsr DNS2_SKIP_BYTES
    bcs DNS2_FAIL

    jsr DNS2_READ_BYTE
    sta DNS2_RDLEN_HI
    jsr DNS2_READ_BYTE
    sta DNS2_RDLEN_LO

    lda DNS2_TYPE_HI
    bne DNS2_SKIP_RDATA
    lda DNS2_TYPE_LO
    cmp #$05
    beq DNS2_CHECK_CNAME
    cmp #$01
    bne DNS2_SKIP_RDATA

DNS2_CHECK_A:
    lda DNS2_CLASS_HI
    bne DNS2_SKIP_RDATA
    lda DNS2_CLASS_LO
    cmp #$01
    bne DNS2_SKIP_RDATA
    lda DNS2_RDLEN_HI
    bne DNS2_SKIP_RDATA
    lda DNS2_RDLEN_LO
    cmp #$04
    bne DNS2_SKIP_RDATA

    jmp DNS2_ACCEPT_A

DNS2_CHECK_CNAME:
    lda DNS2_CLASS_HI
    bne DNS2_SKIP_RDATA
    lda DNS2_CLASS_LO
    cmp #$01
    bne DNS2_SKIP_RDATA
    jsr DNS2_COPY_CNAME_RDATA
    bcs DNS2_FAIL
    lda #$01
    sta seen_cname

DNS2_SKIP_RDATA:
    lda DNS2_RDLEN_LO
    ldx DNS2_RDLEN_HI
    jsr DNS2_SKIP_BYTES
    bcs DNS2_FAIL
    dec DNS2_ANS_LEFT
    bne DNS2_ANSWER_LOOP
    lda seen_cname
    bne DNS2_PREP_AUTHORITY

DNS2_FAIL:
    inc DNS_PARSE_FAILS
    lda #DNS_STATE_FAIL
    sta DNS_STATE
DNS2_NOT_DNS:
    rts

DNS2_ACCEPT_A:
    jsr DNS2_READ_BYTE
    sta DNS_RESULT_IP+0
    jsr DNS2_READ_BYTE
    sta DNS_RESULT_IP+1
    jsr DNS2_READ_BYTE
    sta DNS_RESULT_IP+2
    jsr DNS2_READ_BYTE
    sta DNS_RESULT_IP+3
    lda DNS2_BOUNDS_FAIL
    bne DNS2_FAIL
    lda #DNS_STATE_DONE
    sta DNS_STATE
    lda #$20
    sta DNS_DEBUG_STAGE
    rts

DNS2_PREP_AUTHORITY:
    lda DNS2_NS_HI
    beq DNS2_NS_LOW_ONLY
    lda #$FF
    sta DNS2_NS_LEFT
DNS2_NS_LOW_ONLY:
    lda DNS2_NS_LEFT
    beq DNS2_PREP_ADDITIONAL

    lda #$17
    sta DNS_DEBUG_STAGE

DNS2_AUTHORITY_LOOP:
    jsr DNS2_SKIP_RR
    bcs DNS2_FAIL
    dec DNS2_NS_LEFT
    bne DNS2_AUTHORITY_LOOP

DNS2_PREP_ADDITIONAL:
    lda DNS2_AR_HI
    beq DNS2_AR_LOW_ONLY
    lda #$FF
    sta DNS2_AR_LEFT
DNS2_AR_LOW_ONLY:
    lda DNS2_AR_LEFT
    beq DNS2_REQUERY_CNAME

    lda #$16
    sta DNS_DEBUG_STAGE

DNS2_ADDITIONAL_LOOP:
    jsr DNS2_SKIP_NAME
    bcs DNS2_FAIL

    jsr DNS2_READ_BYTE
    sta DNS2_TYPE_HI
    jsr DNS2_READ_BYTE
    sta DNS2_TYPE_LO
    jsr DNS2_READ_BYTE
    sta DNS2_CLASS_HI
    jsr DNS2_READ_BYTE
    sta DNS2_CLASS_LO

    lda #$04
    ldx #$00
    jsr DNS2_SKIP_BYTES
    bcs DNS2_FAIL

    jsr DNS2_READ_BYTE
    sta DNS2_RDLEN_HI
    jsr DNS2_READ_BYTE
    sta DNS2_RDLEN_LO

    lda DNS2_TYPE_HI
    bne DNS2_SKIP_AR_RDATA
    lda DNS2_TYPE_LO
    cmp #$01
    bne DNS2_SKIP_AR_RDATA
    lda DNS2_CLASS_HI
    bne DNS2_SKIP_AR_RDATA
    lda DNS2_CLASS_LO
    cmp #$01
    bne DNS2_SKIP_AR_RDATA
    lda DNS2_RDLEN_HI
    bne DNS2_SKIP_AR_RDATA
    lda DNS2_RDLEN_LO
    cmp #$04
    bne DNS2_SKIP_AR_RDATA

    jmp DNS2_ACCEPT_A

DNS2_SKIP_AR_RDATA:
    lda DNS2_RDLEN_LO
    ldx DNS2_RDLEN_HI
    jsr DNS2_SKIP_BYTES
    bcs DNS2_FAIL
    dec DNS2_AR_LEFT
    bne DNS2_ADDITIONAL_LOOP
    jmp DNS2_REQUERY_CNAME

DNS2_SKIP_RR:
    jsr DNS2_SKIP_NAME
    bcs DNS2_SKIP_RR_BAD

    ; TYPE(2) + CLASS(2) + TTL(4)
    lda #$08
    ldx #$00
    jsr DNS2_SKIP_BYTES
    bcs DNS2_SKIP_RR_BAD

    jsr DNS2_READ_BYTE
    sta DNS2_RDLEN_HI
    jsr DNS2_READ_BYTE
    sta DNS2_RDLEN_LO

    lda DNS2_RDLEN_LO
    ldx DNS2_RDLEN_HI
    jsr DNS2_SKIP_BYTES
    bcs DNS2_SKIP_RR_BAD
    lda DNS2_BOUNDS_FAIL
    bne DNS2_SKIP_RR_BAD
    clc
    rts

DNS2_SKIP_RR_BAD:
    sec
    rts

DNS2_SKIP_NAME:
    lda #$00
    sta DNS2_NAME_GUARD
DNS2_NAME_LOOP:
    inc DNS2_NAME_GUARD
    lda DNS2_NAME_GUARD
    cmp #$40
    bcs DNS2_NAME_BAD

    jsr DNS2_READ_BYTE
    beq DNS2_NAME_DONE
    tax
    and #$C0
    beq DNS2_NAME_LABEL
    cmp #$C0
    beq DNS2_NAME_POINTER
    jmp DNS2_NAME_BAD

DNS2_NAME_LABEL:
    txa
    and #$3F
    beq DNS2_NAME_BAD
    ldx #$00
    jsr DNS2_SKIP_BYTES
    bcs DNS2_NAME_BAD
    jmp DNS2_NAME_LOOP

DNS2_NAME_POINTER:
    jsr DNS2_READ_BYTE
DNS2_NAME_DONE:
    lda DNS2_BOUNDS_FAIL
    bne DNS2_NAME_BAD
    clc
    rts

DNS2_NAME_BAD:
    sec
    rts

DNS2_SKIP_BYTES:
    sta DNS2_SKIP_LO
    stx DNS2_SKIP_HI
    lda DNS2_RD_LO
    clc
    adc DNS2_SKIP_LO
    sta DNS2_PTR_LO
    lda DNS2_RD_HI
    adc DNS2_SKIP_HI
    bcs DNS2_SKIP_BAD
    sta DNS2_PTR_HI
    lda DNS2_PTR_HI
    cmp DNS2_END_HI
    bcc DNS2_SKIP_DONE
    bne DNS2_SKIP_BAD
    lda DNS2_PTR_LO
    cmp DNS2_END_LO
    beq DNS2_SKIP_DONE
    bcs DNS2_SKIP_BAD

DNS2_SKIP_DONE:
    lda DNS2_PTR_LO
    sta DNS2_RD_LO
    lda DNS2_PTR_HI
    sta DNS2_RD_HI
    clc
    rts

DNS2_SKIP_BAD:
    lda #$01
    sta DNS2_BOUNDS_FAIL
    sec
    rts

DNS2_READ_BYTE:
    lda DNS2_RD_HI
    cmp DNS2_END_HI
    bcc DNS2_READ_OK
    bne DNS2_READ_BAD
    lda DNS2_RD_LO
    cmp DNS2_END_LO
    bcc DNS2_READ_OK

DNS2_READ_BAD:
    lda #$01
    sta DNS2_BOUNDS_FAIL
    lda #$00
    sec
    rts

DNS2_READ_OK:
    lda DNS2_RD_LO
    sta DNS2_READ_ABS+1
    lda DNS2_RD_HI
    sta DNS2_READ_ABS+2
DNS2_READ_ABS:
    lda $ffff
    pha
    inc DNS2_RD_LO
    bne DNS2_READ_ADV_DONE
    inc DNS2_RD_HI
DNS2_READ_ADV_DONE:
    pla
    clc
    rts

; Legacy self-modifying DNS parser removed. DNS2 uses explicit reader pointers so page wraps do not mutate the DNS message base.

_dns_ofs_base       = UDP_DATA_BASE
_dns_ofs_flags      = UDP_DATA_BASE + 2
_dns_ofs_ancount    = UDP_DATA_BASE + 6
_dns_ofs_qdcount    = UDP_DATA_BASE + 4

ihl:                .byte $00
expected_port_hi:   .byte $00
q_out:              .byte $00
q_guard:            .byte $00
lbl_len:            .byte $00
seen_cname:         .byte $00
ptr_hi:             .byte $00
ptr_lo:             .byte $00
lbl_cnt:            .byte $00
TMP0:               .byte $00

DNS2_BASE_LO:       .byte $00
DNS2_BASE_HI:       .byte $00
DNS2_RD_LO:         .byte $00
DNS2_RD_HI:         .byte $00
DNS2_END_LO:        .byte $00
DNS2_END_HI:        .byte $00
DNS2_FLAGS_HI:      .byte $00
DNS2_FLAGS_LO:      .byte $00
DNS2_QD_LEFT:       .byte $00
DNS2_ANS_HI:        .byte $00
DNS2_ANS_LEFT:      .byte $00
DNS2_NS_HI:         .byte $00
DNS2_NS_LEFT:       .byte $00
DNS2_AR_HI:         .byte $00
DNS2_AR_LEFT:       .byte $00
DNS2_TYPE_HI:       .byte $00
DNS2_TYPE_LO:       .byte $00
DNS2_CLASS_HI:      .byte $00
DNS2_CLASS_LO:      .byte $00
DNS2_RDLEN_HI:      .byte $00
DNS2_RDLEN_LO:      .byte $00
DNS2_SKIP_LO:       .byte $00
DNS2_SKIP_HI:       .byte $00
DNS2_PTR_LO:        .byte $00
DNS2_PTR_HI:        .byte $00
DNS2_BOUNDS_FAIL:   .byte $00
DNS2_NAME_GUARD:    .byte $00
DNS2_NAME_LO:       .byte $00
DNS2_NAME_HI:       .byte $00
