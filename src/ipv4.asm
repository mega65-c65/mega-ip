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

;=============================================================================
; Routine to calculate the ipv4 checksum
;=============================================================================
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

    ; end-around carry if that addition overflowed
    bcc _ipv4_no_final_carry
    inc _num1lo
    bne _ipv4_no_final_carry
    inc _num1hi

_ipv4_no_final_carry:
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
