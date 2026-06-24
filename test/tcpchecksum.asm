*=$c000

BUILD_TCP_CHECKSUM:

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

IPV4_HEADER:
IPV4_HDR_IHL:       .byte $45                   ; 0100 (Version 4) | 0101 (min 5, max 15)                   
IPV4_HDR_DSCP:      .byte $00                   ; Type of service (Low delay, High throuput, Relibility)
IPV4_HDR_LEN:       .byte $00, $28              ; Length of header + data (16 bits) 0-65535
IPV4_HDR_IDEN:      .byte $00, $00              ; unique packet id    
IPV4_HDR_FLGS_OFFS: .byte $00, $00              ; 3 flags, 1 bit each =  reserved (zero), do not fragment, more fragments
IPV4_HDR_TTL:       .byte $80                   ; time to live hops to dest
IPV4_HDR_PROTO:     .byte $06                   ; name of protocol for which data to be passed (ICMP=$01, TCP=$06, UDP=$11)
IPV4_HDR_CHKSM:     .byte $00, $00              ; 16 bit header checksum
IPV4_HDR_SRC_IP:    .byte $c0, $a8, $01, $4b    ; source IP address
IPV4_HDR_DST_IP:    .byte $c0, $a8, $01, $01    ; dest IP address

TCP_DATA_SIZE:
.byte $00

TCP_PSEUDO_HDR:
.byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00, $00

TCP_HDR:
TCP_HDR_SRC_PORT:   .byte $00, $dc
TCP_HDR_DST_PORT:   .byte $00, $17
TCP_HDR_SEQ_NUM:    .byte $00, $00, $00, $00
TCP_HDR_ACK_NUM:    .byte $00, $00, $00, $00
TCP_HDR_FLGS_OFFS:  .byte $50, $02
TCP_HDR_WINDOW:     .byte $04, $00
TCP_HDR_CHKSM:      .byte $00, $00
TCP_HDR_URGNT:      .byte $00, $00
TCP_DATA:
.byte $00, $00, $00

; c0a8+014b+c0a8+0101+0006+0014= 183b6 + 00dc+0017+0000+0000+0000+0000+5002+0400+0000+0000 = 1d8ab
; 1+d8ab = d8ac
; ffff-d8ac = 2753

;4500+0028+0000+0000+8006+0000+c0a8+014b+c0a8+0101 = 248ca
;2+48ca = 48cc
;ffff-48cc=b733
