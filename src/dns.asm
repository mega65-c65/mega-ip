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

; public result
DNS_RESULT_IP:          .byte $00, $00, $00, $00

; internal state
DNS_STATE:              .byte $00
DNS_RETRY_LEFT:         .byte $00
DNS_RETRY_TICKS:        .byte $00
DNS_LAST_BACKOFF:       .byte $00

; message id + client port (ephemeral: $C000 | client_hi)
DNS_MSG_ID_HI:          .byte $00
DNS_MSG_ID_LO:          .byte $00
DNS_CLIENT_PORT_HI:     .byte $31   ; starts at $31 → $C131, increment each query

; packed QNAME buffer (max 128)
DNS_QNAME:              .fill 128, $00
DNS_QNAME_LEN:          .byte $00

DNS_ARP_DEFERS:         .byte 40   ; ~40 quick defers then give up

DEBUG:                  .byte $00

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
    ; src port = ($C0 | (DNS_CLIENT_PORT_HI & $3F)) : $00
    lda DNS_CLIENT_PORT_HI
    and #$3F
    ora #$C0
    sta ETH_TX_FRAME_PAYLOAD+20+UDP_HDR_SRC_HI
    lda #$00
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
    jsr DNS_SEND_UDP
    clc                 ; C=0 - sent
    rts

_no_send:
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
    sta _lbl_len
    sta _lbl_pos            ; where to write current label length (starts at 0)

_next:
_hn_abs:                    ; self-modified: LDA $xxxx,Y
    .byte $B9, $00, $00
    beq _end
    cmp #'.'
    beq _dot

    ; copy char
    cpx #128
    bcs _toolong
    sta DNS_QNAME,x
    inx

    inc _lbl_len
    lda _lbl_len
    cmp #64                 ; RFC: label length <=63
    bcs _toolong
    iny
    bne _next
    inc _hn_abs+2
    inc _hn_abs2+2
    jmp _next

_dot:
    ; if _lbl_len == 0, either root "." (at start) or invalid ".."
    lda _lbl_len
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
    lda _lbl_pos
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
    ldy _lbl_pos
    lda _lbl_len
    sta DNS_QNAME,y                ; write length at current label slot
    pla
    tay

    ; start next label at current X
    stx _lbl_pos
    lda #0
    sta _lbl_len
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
    ldy _lbl_pos
    lda _lbl_len
    sta DNS_QNAME,y

    ; append single terminator iff last label wasn’t already empty
    lda _lbl_len
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

_lbl_len:  .byte 0
_lbl_pos:  .byte 0

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
    sta DNS_RESULT_IP+0
    sta DNS_RESULT_IP+1
    sta DNS_RESULT_IP+2
    sta DNS_RESULT_IP+3

    lda #<host_str
    ldx #>host_str
    jsr DNS_PACK_HOSTNAME
    bcs _start_fail

    inc DNS_CLIENT_PORT_HI          ; <<< move the rotation here

    lda #DNS_MAX_RETRIES
    sta DNS_RETRY_LEFT
    lda #DNS_TIMEOUT_TICKS_BASE
    sta DNS_RETRY_TICKS
    lda #DNS_TIMEOUT_TICKS_BASE
    sta DNS_LAST_BACKOFF
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
    lda #DNS_STATE_FAIL
    sta DNS_STATE
_tick_done:
    rts

;===========================================================
; DNS_UDP_IN — minimal: extract first A record IPv4 and exit
;===========================================================
DNS_UDP_IN:

lda #$00
sta DEBUG

    ; Ignore only if already completed
    lda DNS_STATE
    cmp #DNS_STATE_DONE
    beq _not_dns

    ; ---- IHL (IP header length in bytes) ----
    lda ETH_RX_FRAME_PAYLOAD+0
    and #$0F
    asl
    asl
    sta ihl

    ldy ihl
    lda DNS_CLIENT_PORT_HI
    and #$3F
    ora #$C0
    sta expected_port_hi
    lda ETH_RX_FRAME_PAYLOAD+2,y
    cmp expected_port_hi
    bne _not_dns
    lda ETH_RX_FRAME_PAYLOAD+3,y
    cmp #$00
    bne _not_dns

inc DEBUG

    ; ---- UDP source port == 53 ----
    lda ETH_RX_FRAME_PAYLOAD+0,y    ; src port hi
    cmp #$00
    bne _not_dns
    lda ETH_RX_FRAME_PAYLOAD+1,y    ; src port lo
    cmp #$35
    bne _not_dns

inc DEBUG

    ; Check IPv4 src = PRIMARY_DNS
    ldx #3
_sipchk:
    lda ETH_RX_FRAME_PAYLOAD+12,x     ; IPv4 src at +12..+15
    cmp PRIMARY_DNS,x
    bne _not_dns
    dex
    bpl _sipchk

inc DEBUG

    ; ---- Patch ABS bases to DNS payload (IP+IHL+8) ----
    ; this avoids the use of zero page
    lda #<ETH_RX_FRAME_PAYLOAD+UDP_DATA_BASE
    clc
    adc ihl
    sta _rd_dnsid_hi+1
    sta _rd_dnsid_lo+1
    sta _rd_type_hi+1
    sta _rd_type_lo+1
    sta _rd_class_hi+1
    sta _rd_class_lo+1
    sta _rd_rdlen_hi+1
    sta _rd_rdlen_lo+1
    sta _rd_a0+1
    sta _rd_a1+1
    sta _rd_a2+1
    sta _rd_a3+1
    sta _rd_anc_hi+1
    sta _rd_anc_lo+1
    sta _rd_copy_abs+1
    sta _rd_copy_abs2+1
    sta _rd_ptrlo_from_copy+1
    sta _rd_flags_hi+1
    sta _rd_flags_hi2+1
    sta _rd_flags_lo+1
    sta _rd_nbyte+1
    sta _rd_nbyte+1
    sta _rd_peek+1
    sta _rd_win+1 

    lda #>ETH_RX_FRAME_PAYLOAD+UDP_DATA_BASE
    adc #$00
    sta _rd_dnsid_hi+2
    sta _rd_dnsid_lo+2
    sta _rd_type_hi+2
    sta _rd_type_lo+2
    sta _rd_class_hi+2
    sta _rd_class_lo+2
    sta _rd_rdlen_hi+2
    sta _rd_rdlen_lo+2
    sta _rd_a0+2
    sta _rd_a1+2
    sta _rd_a2+2
    sta _rd_a3+2
    sta _rd_anc_hi+2
    sta _rd_anc_lo+2
    sta _rd_copy_abs+2
    sta _rd_copy_abs2+2
    sta _rd_ptrlo_from_copy+2
    sta _rd_flags_hi+2
    sta _rd_flags_hi2+2
    sta _rd_flags_lo+2
    sta _rd_nbyte+2
    sta _rd_peek+2
    sta _rd_win+2 

    ; ---- ID must match (so it’s for our query) ----
    ldy #0
_rd_dnsid_hi: 
    .byte $B9, $00, $00
    cmp DNS_MSG_ID_HI
    bne _not_dns
    jsr _ADV_INY

_rd_dnsid_lo: 
    .byte $B9, $00, $00
    cmp DNS_MSG_ID_LO
    bne _not_dns

inc DEBUG

    ; ---- RCODE/QR/TC sanity check
    ; Flags sanity: QR=1, TC=0, RCODE=0
    ldy #2
_rd_flags_hi: 
    .byte $B9, $00, $00     ; QR bit check.  Query (0) or Response (1)
    and #%10000000          
    beq _not_dns            ; not a response, bail
    ldy #2
_rd_flags_hi2: 
    .byte $B9, $00, $00     ; get TC (truncated) setting
    and #%00000010
    bne _not_dns            ; truncated -> silently ignore truncated replies 
    ldy #3
_rd_flags_lo:   
    .byte $B9, $00, $00     ; get RCODE (Response Code) 0=No Error, 1=Format Error, 2=Server Failed to Process, 
    and #$0F                ; 3=Domain Doesnt Exist, 4=Not Implemented,5=Svr Refused
    bne _fail               ; non-zero RCODE -> fail

inc DEBUG

    ; Get ANCOUNT - 16 bit field that tells how many Resource Records
    ; are in the Answer section of the message
    ldy #6
_rd_anc_hi: 
    .byte $B9, $00, $00
    sta TMP0
    jsr _ADV_INY
_rd_anc_lo: 
    .byte $B9, $00, $00
    sta TMP1
    lda TMP0
    beq _lo_only
    lda #$FF
    sta ans_left
    bne _have_ans
_lo_only:
    lda TMP1
    beq _fail
    sta ans_left

inc DEBUG

_have_ans:
    ; ==== Skip Original Question using the same NAME skipper ====
    ; QTYPE = 1 for IPV4, QCLASS = 1 for Internet
    ldy #12                    ; start of QNAME in DNS payload
    jsr _DNS_SKIP_NAME
    bcs _fail                  ; malformed QNAME -> fail

    ; advance beyond QTYPE (2 bytes) and QCLASS (2 bytes)
    jsr _ADV_INY               ; QTYPE hi
    jsr _ADV_INY               ; QTYPE lo
    jsr _ADV_INY               ; QCLASS hi
    jsr _ADV_INY               ; QCLASS lo

    ; Y is at supposed start of first Answer NAME
    ; Expected = 12 + DNS_QNAME_LEN + 4
    lda DNS_QNAME_LEN
    clc
    adc #12+4
    sta TMP0                    ; expected low (fits in one byte for small names)
    sty TMP1                    ; actual Y
    ; log both to inspect
    sta DNS_EXP_ANS_Y           ; <--- DEBUG
    sty DNS_ACT_ANS_Y           ; <--- DEBUG


inc DEBUG

    lda #0
    sta seen_cname

    ; Y now at first Answer NAME
    ; ================== ANSWER SCAN LOOP ==================
_next_answer:

    ; DEBUG Start
    ; --- dump 6 bytes starting at BASE+Y into DNS_WIN[0..5] ---
    tya
    pha
    ldx #0
_dwin:
_rd_win:                          ; LDA abs,Y (patched above)
    .byte $B9, $00, $00
    sta DNS_WIN,x
    jsr _ADV_INY                  ; advance Y with wrap fixups
    inx
    cpx #6
    bne _dwin
    pla
    tay
    ; DEBUG End

_rd_peek:                           ; LDA abs,Y (patch same as _rd_nbyte)
    .byte $B9, $00, $00
    sta ANS_DBG_BYTE                ; <--- DEBUG: log the first answer octet
    sty ANS_DBG_Y                   ; <--- DEBUG: log the Y at answer start

    and #$C0
    cmp #$C0
    bne _use_skipper
    ; direct pointer: C0 xx
    jsr _ADV_INY
    jsr _ADV_INY
    jmp _after_name

_use_skipper:
    jsr _DNS_SKIP_NAME
    bcc _after_name
    jmp _fail

_after_name:

inc DEBUG
    ; ============================================================
    ; TYPE (2) - 1=ipv4, 5=CNAME
_rd_type_hi: 
    .byte $B9, $00, $00
    sta DNS_DBG_TYPE_HI             ; <--- DEBUG
    jsr _ADV_INY
_rd_type_lo: 
    .byte $B9, $00, $00
    sta DNS_DBG_TYPE_LO             ; <--- DEBUG
    sta tmp_type                    ; save type lo

    ; ============================================================
    ; CLASS (2) - 1=internet
    jsr _ADV_INY
_rd_class_hi: 
    .byte $B9, $00, $00
    sta DNS_DBG_CLASS_HI            ; <--- DEBUG
    jsr _ADV_INY
_rd_class_lo: 
    .byte $B9, $00, $00
    sta DNS_DBG_CLASS_LO            ; <--- DEBUG
    sta tmp_class_lo                ; save class lo

    ; move to first TTL byte
    jsr _ADV_INY

    ; skip TTL (4)
    ldx #$04 
-   jsr _ADV_INY
    dex
    bne -

inc DEBUG

    ; ============================================================
    ; RDLEN (2)
_rd_rdlen_hi: 
    .byte $B9, $00, $00
    sta DNS_DBG_RDLEN_HI            ; <--- DEBUG
    sta tmp_rdlen_hi
    jsr _ADV_INY
_rd_rdlen_lo: 
    .byte $B9, $00, $00
    sta DNS_DBG_RDLEN_LO            ; <--- DEBUG   
    sta tmp_rdlen_lo

    ; Fast path: TYPE=A (1), CLASS=IN (1), RDLEN=4
    lda tmp_type
    cmp #$01
    bne _maybe_cname
    lda tmp_class_lo
    cmp #$01
    bne _skip_rdata

    ; sanity: A must have RDLEN = 4
    lda tmp_rdlen_hi
    bne _skip_rdata
    lda tmp_rdlen_lo
    cmp #$04
    bne _skip_rdata

inc DEBUG

    ; FINALLY we have the IP address
_read_ipv4:
    ; read 4-byte RDATA (IPv4)
    jsr _ADV_INY
_rd_a0: 
    .byte $B9, $00, $00
    sta DNS_RESULT_IP+0
    jsr _ADV_INY
_rd_a1: 
    .byte $B9, $00, $00
    sta DNS_RESULT_IP+1
    jsr _ADV_INY
_rd_a2:
    .byte $B9, $00, $00
    sta DNS_RESULT_IP+2
    jsr _ADV_INY
_rd_a3: 
    .byte $B9, $00, $00
    sta DNS_RESULT_IP+3

    lda #DNS_STATE_DONE
    sta DNS_STATE
    rts

    ; ================================================================
    ; CNAME encountered... request again..

_maybe_cname:
    ; ---- embedded CNAME copy (TYPE=5) ----
    lda tmp_type
    cmp #$05
    bne _skip_rdata
lda #$AA
sta DEBUG                       ; DEBUG - “entered CNAME branch”
    lda tmp_class_lo
    cmp #$01
    bne _skip_rdata             ; only process IN CNAMEs

    ; Save current Y, then move to first RDATA byte
    sty y_save
    jsr _ADV_INY_PTR

    ; ----- Copy name at BASE+Y → DNS_QNAME (handles compression) -----
    lda #0
    sta q_out
    sta q_guard

_c_copy_next:
_rd_copy_abs: 
    .byte $B9, $00, $00     ; A = len/0 or C0|hi6
    beq _c_done_zero
inc DEBUG
    tax
    and #$C0
    cmp #$C0
    beq _c_ptr_from_copy

    ; plain label
    txa
    and #$3F
    beq _c_malformed
inc DEBUG
    sta lbl_len

    ; write length
    ldx q_out
    cpx #127
    bcs _c_malformed
inc DEBUG
    lda lbl_len
    sta DNS_QNAME,x
    inx
    stx q_out

    ; copy label bytes
    jsr _ADV_INY_PTR
    lda lbl_len
    sta lbl_cnt
_c_copy_lbl:
_rd_copy_abs2:
    .byte $B9, $00, $00
    ldx q_out
    cpx #127
    bcs _c_malformed
    sta DNS_QNAME,x
    inx
    stx q_out
    jsr _ADV_INY_PTR
    dec lbl_cnt
    bne _c_copy_lbl

    inc q_guard
    lda q_guard
    cmp #40
    bcs _c_malformed
    jmp _c_copy_next

_c_ptr_from_copy:
    ; first pointer byte was in X
    txa
    and #$3F
    sta ptr_hi                   ; hi6
    jsr _ADV_INY_PTR
_rd_ptrlo_from_copy:
    .byte $B9, $00, $00          ; low 8
    sta ptr_lo

    ; absolute pointer = BASE + offset
    lda _rd_copy_abs+1
    clc
    adc ptr_lo
    sta ptr_lo
    lda _rd_copy_abs+2
    adc ptr_hi
    sta ptr_hi

    ; point pointer-readers to absolute target; Y=0 for walk
    lda ptr_lo
    sta _rd_ptr_abs+1
    sta _rd_ptr_abs2+1
    sta _rd_ptr_abs3+1
    lda ptr_hi
    sta _rd_ptr_abs+2
    sta _rd_ptr_abs2+2
    sta _rd_ptr_abs3+2
    ldy #0

_c_ptr_walk:
_rd_ptr_abs: 
    .byte $B9, $00, $00
    beq _c_done_zero
    tax
    and #$C0
    cmp #$C0
    beq _c_ptr_follow

    ; plain label at ptr target
    txa
    and #$3F
    beq _c_malformed
    sta lbl_len

    ; write length
    ldx q_out
    cpx #127
    bcs _c_malformed
    lda lbl_len
    sta DNS_QNAME,x
    inx
    stx q_out

    ; copy bytes
    jsr _ADV_INY_PTR
    lda lbl_len
    sta lbl_cnt
_c_ptr_copy_lbl:
_rd_ptr_abs2:
    .byte $B9, $00, $00
    ldx q_out
    cpx #127
    bcs _c_malformed
    sta DNS_QNAME,x
    inx
    stx q_out
    jsr _ADV_INY_PTR
    dec lbl_cnt
    bne _c_ptr_copy_lbl

    inc q_guard
    lda q_guard
    cmp #40
    bcs _c_malformed
    jmp _c_ptr_walk

_c_ptr_follow:
inc DEBUG
    ; follow subsequent pointer
    txa
    and #$3F
    sta ptr_hi
    jsr _ADV_INY_PTR
_rd_ptr_abs3:.byte $B9, $00, $00
    sta ptr_lo

    ; recompute absolute and update reader
    lda _rd_copy_abs+1
    clc
    adc ptr_lo
    sta ptr_lo
    lda _rd_copy_abs+2
    adc ptr_hi
    sta ptr_hi
    lda ptr_lo
    sta _rd_ptr_abs+1
    sta _rd_ptr_abs2+1
    sta _rd_ptr_abs3+1
    lda ptr_hi
    sta _rd_ptr_abs+2
    sta _rd_ptr_abs2+2
    sta _rd_ptr_abs3+2
    ldy #0
    jmp _c_ptr_walk

_c_done_zero:
    ; trailing zero, set length
    ldx q_out
    cpx #128
    bcs _c_malformed
    lda #0
    sta DNS_QNAME,x
    inx
    stx DNS_QNAME_LEN
    jmp _c_ok

_c_malformed:
    lda #$50
    sta DEBUG                   ; <--- DEBUG
    jmp _fail

_c_ok:
    ; restore Y to start of RDATA and skip RDLEN bytes
    ldy y_save
    jsr _ADV_INY
    lda tmp_rdlen_lo
    sta TMP0
    lda tmp_rdlen_hi
    sta TMP1
_cskip16:
    lda TMP0
    ora TMP1
    beq _cskip_done
    jsr _ADV_INY
    dec TMP0
    lda TMP0
    cmp #$FF        ; did underflow?
    bne _cskip16
    dec TMP1
    jmp _cskip16
_cskip_done:

    ; mark that we saw a CNAME
    lda #1
    sta seen_cname

    ; continue scanning remaining answers for a direct A
    dec ans_left
    bne _next_answer

    ; no more answers: if we saw a CNAME, re-query canonical name now
    lda seen_cname
    beq _fail
inc DEBUG
    ; ---- Re-arm retries/backoff and send new query (same client port) ----
    lda #DNS_MAX_RETRIES
    sta DNS_RETRY_LEFT
    lda #DNS_TIMEOUT_TICKS_BASE
    sta DNS_RETRY_TICKS
    lda #DNS_TIMEOUT_TICKS_BASE
    sta DNS_LAST_BACKOFF
    ; bump message ID
    inc DNS_MSG_ID_LO
    bne _id_ok
    inc DNS_MSG_ID_HI
_id_ok:
    lda #DNS_STATE_WAIT
    sta DNS_STATE
    jsr DNS_SEND_QUERY
    bcc _cname_sent

    ; ARP not ready → retry very soon, keep WAIT
    lda #1
    sta DNS_RETRY_TICKS
    lda #40
    sta DNS_ARP_DEFERS
    rts

_cname_sent
    lda #$30
    sta DEBUG                   ; <--- DEBUG
    rts

    ; Skip RDATA using 16-bit length in TMP1:TMP0

_skip_rdata:
    jsr _ADV_INY
    lda tmp_rdlen_lo
    sta TMP0
    lda tmp_rdlen_hi
    sta TMP1
_skip16:
    lda TMP0
    ora TMP1
    beq _skip_done
    jsr _ADV_INY
    dec TMP0
    lda TMP0
    cmp #$FF                    ; did low underflow?
    bne _skip16
    dec TMP1
    jmp _skip16
_skip_done:

    ; Next answer?
    dec ans_left
    bne _next_answer

    ; >>> re-query if we saw a CNAME anywhere <<<
    lda seen_cname
    beq _fail

    ; ---- Re-arm retries/backoff and send new query (same client port) ----
    lda #DNS_MAX_RETRIES
    sta DNS_RETRY_LEFT
    lda #DNS_TIMEOUT_TICKS_BASE
    sta DNS_RETRY_TICKS
    lda #DNS_TIMEOUT_TICKS_BASE
    sta DNS_LAST_BACKOFF
    lda #DNS_STATE_WAIT
    sta DNS_STATE
    inc DNS_MSG_ID_LO
    bne _id_ok2
    inc DNS_MSG_ID_HI
_id_ok2:
    lda #DNS_STATE_WAIT
    sta DNS_STATE
    jsr DNS_SEND_QUERY
    bcc _cname_sent2

    ; ARP not ready → retry very soon, keep WAIT
    lda #1
    sta DNS_RETRY_TICKS
    lda #40
    sta DNS_ARP_DEFERS
    rts
_cname_sent2
    rts

    ; ---------------- FAIL/NOT-DNS EXITS ----------------
_fail:
    lda #DNS_STATE_FAIL
    sta DNS_STATE
    rts

_not_dns:
    rts

; === Skip a DNS NAME at BASE+Y (labels and/or compression). 
; On return: Y = first byte after NAME, C=0 OK, C=1 malformed
_DNS_SKIP_NAME:
    clc                         ; default to success

_rd_nbyte:                      ; LDA abs,Y (patched to DNS base)
    .byte $B9, $00, $00

    sta DNS_DBG_BYTE            ; DEBUG - log offending octet
    sty DNS_DBG_Y               ; DEBUG - log Y (offset within DNS payload)


    tax
    beq _name_zero              ; 00 => end of name

    txa
    and #$C0
    beq _name_label             ; 00xxxxxx => length byte (1..63)
    cmp #$C0
    beq _name_ptr               ; 11xxxxxx => 2-byte pointer

    ; 01xxxxxx or 10xxxxxx => invalid
    ; invalid top bits case
    ; A currently holds (X & $C0), but we want the raw byte that caused it.
    txa
    sta DNS_FAIL_BYTE
    sty DNS_FAIL_Y
    sec
    rts

_name_label:
    txa
    and #$3F
    beq _bad
    cmp #64
    bcs _bad

    jsr _ADV_INY                   ; consume the length byte
    tax                            ; X = length
-   jsr _ADV_INY                   ; consume label bytes
    dex
    bne -
    jmp _DNS_SKIP_NAME              ; next piece (label / ptr / zero)

_name_ptr:
    jsr _ADV_INY                   ; consume both pointer bytes
    jsr _ADV_INY
    ; C already clear from top
    rts

_name_zero:
    jsr _ADV_INY                   ; consume the trailing zero
    ; C already clear from top
    rts

_bad:
    ; A currently holds length (X & $3F) or 0.
    txa
    sta DNS_FAIL_BYTE
    sty DNS_FAIL_Y
    sec
    rts


_ADV_INY:
    iny
    bne _ret
    ; Y wrapped → advance the high byte of every ABS base you'll use next
    inc _rd_dnsid_hi+2
    inc _rd_dnsid_lo+2
    inc _rd_type_hi+2
    inc _rd_type_lo+2
    inc _rd_class_hi+2
    inc _rd_class_lo+2
    inc _rd_rdlen_hi+2
    inc _rd_rdlen_lo+2
    inc _rd_a0+2
    inc _rd_a1+2
    inc _rd_a2+2
    inc _rd_a3+2
    inc _rd_anc_hi+2
    inc _rd_anc_lo+2
    inc _rd_flags_hi+2
    inc _rd_flags_hi2+2
    inc _rd_flags_lo+2
    inc _rd_nbyte+2
    inc _rd_peek+2
    inc _rd_win+2 
_ret:
    rts

; Pointer-walk / compressed-name copy only
_ADV_INY_PTR:
    iny
    bne _retp
    inc _rd_copy_abs+2
    inc _rd_copy_abs2+2
    inc _rd_ptrlo_from_copy+2
    inc _rd_ptr_abs+2
    inc _rd_ptr_abs2+2
    inc _rd_ptr_abs3+2
_retp:
    rts

_dns_ofs_base       = UDP_DATA_BASE
_dns_ofs_flags      = UDP_DATA_BASE + 2
_dns_ofs_ancount    = UDP_DATA_BASE + 6
_dns_ofs_qdcount    = UDP_DATA_BASE + 4

ihl:                .byte $00
ans_left:           .byte $00
tmp_type:           .byte $00
tmp_class_lo:       .byte $00
tmp_rdlen_hi:       .byte $00
tmp_rdlen_lo:       .byte $00
expected_port_hi:   .byte $00
q_out:              .byte $00
q_guard:            .byte $00
lbl_len:            .byte $00
seen_cname:         .byte $00
y_save:             .byte $00
ptr_hi:             .byte $00
ptr_lo:             .byte $00
lbl_cnt:            .byte $00
TMP0:               .byte $00
TMP1:               .byte $00

DNS_DBG_Y:          .byte $00
DNS_DBG_BYTE:       .byte $00
ANS_DBG_Y:          .byte $00
ANS_DBG_BYTE:       .byte $00
DNS_EXP_ANS_Y:      .byte $00
DNS_ACT_ANS_Y:      .byte $00
DNS_FAIL_BYTE:      .byte $00
DNS_FAIL_Y:         .byte $00
DNS_WIN:            .byte $00, $00, $00, $00, $00, $00
DNS_DBG_TYPE_HI:    .byte $00
DNS_DBG_TYPE_LO:    .byte $00
DNS_DBG_CLASS_HI:   .byte $00
DNS_DBG_CLASS_LO:   .byte $00
DNS_DBG_RDLEN_HI:   .byte $00
DNS_DBG_RDLEN_LO:   .byte $00