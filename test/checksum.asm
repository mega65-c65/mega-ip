*=$c000

BUILD_IPV4_CHECKSUM:
    ; 1) Zero out the checksum field
    lda #$00
    sta IPV4_HDR_CHKSM
    lda #$00
    sta IPV4_HDR_CHKSM+1

    ; 2) Clear our 16-bit accumulator (lo byte + hi byte)
    lda #$00
    sta ipv4_sum_lo
    sta ipv4_sum_hi

    ; 3) Sum each of the ten 16-bit words (20 bytes total)
    ldx #10                 ; we have 10 words in a 20-byte header
    ldy #$00                ; Y = offset into IPV4_HEADER (0,2,4,...,18)

_sum_word:
    ; 3a) load low byte of word
    lda IPV4_HEADER,Y
    clc
    adc ipv4_sum_lo         ; (acc_lo += low_byte)
    sta ipv4_sum_lo         ; keep only low 8 bits
    bcc _no_carry_lo        ; if no carry out of low, skip
    inc ipv4_sum_hi         ; else, carry 1 into high accumulator

_no_carry_lo:
    ; 3b) load high byte of word
    iny                     ; move Y from low‐byte to high‐byte
    lda IPV4_HEADER,Y
    clc
    adc ipv4_sum_hi         ; (acc_hi += high_byte)
    sta ipv4_sum_hi         ; keep only low 8 bits
    bcc _no_carry_hi        ; if no carry out of high, skip
    ; folded carry out of bit-15: wrap back into acc_lo
    inc ipv4_sum_lo

_no_carry_hi:
    ; 3c) advance Y to next word (byte offset 0→2, 2→4, ..., 18→20)
    iny                     ; Y was at high-byte index, now goes to next low-byte
    dex                     ; decrement word count
    bne _sum_word

    ; 4) If adding acc_hi into acc_lo caused another carry, fold again
    lda ipv4_sum_lo
    clc
    adc ipv4_sum_hi
    sta ipv4_sum_lo
    bcc _fold_done
    ; carry out of bit 7 (really this is a carry out of 16 bits if acc_hi+acc_lo > 0xFF),
    ; wrap it right back into low 8 bits (acc_lo)
    inc ipv4_sum_lo

_fold_done:
    ; 5) One’s complement of the 16-bit sum
    lda ipv4_sum_hi
    eor #$FF
    sta IPV4_HDR_CHKSM         ; store high byte of final checksum
    lda ipv4_sum_lo
    eor #$FF
    sta IPV4_HDR_CHKSM+1       ; store low byte

    rts

CHECKSUM2:

    ; clear results
    lda #$00
    sta reslo
    sta reshi
    sta resex

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
    sta num1hi
    iny
    lda IPV4_HEADER,y
    sta num1lo
    iny
    lda IPV4_HEADER,Y
    sta num2hi
    iny
    lda IPV4_HEADER,Y
    sta num2lo
    jsr _addwords

_loop
    lda reslo
    sta num1lo
    lda reshi
    sta num1hi

    iny
    lda IPV4_HEADER,Y
    sta num2hi
    iny
    lda IPV4_HEADER,Y
    sta num2lo
    jsr _addwords

    inx
    cpx #$08
    beq _add_overflow
    jmp _loop

_add_overflow:
    lda reslo               ; add overflow byte 24 back into the result
    sta num1lo
    lda reshi
    sta num1hi
    lda resex
    clc
    adc num1lo
    sta num1lo
    lda num1hi
    adc #$00
    sta num1hi

    lda num1lo              ; move result to 2nd value
    sta num2lo
    lda num1hi
    sta num2hi
    lda #$ff                ; subtract value from $ffff
    sta num1lo
    sta num1hi
    jsr _subwords           ; final in reslo/reshi


    rts



_addwords	
    clc				; clear carry
	lda num1lo
	adc num2lo
	sta reslo			; store sum of LSBs
	lda num1hi
	adc num2hi			; add the MSBs using carry from
	sta reshi			; the previous calculation
    lda resex
    adc #$00
    sta resex
    rts

_subwords:
    lda #$00
    sta reslo
    sta reshi
    sta resex

    sec				    ; set carry for borrow purpose
	lda num1lo
	sbc num2lo			; perform subtraction on the LSBs
	sta reslo
	lda num1hi			; do the same for the MSBs, with carry
	sbc num2hi			; set according to the previous result
	sta reshi
	rts

num1lo: .byte $00
num1hi: .byte $00
num2lo: .byte $00
num2hi: .byte $00
reslo: .byte $00
reshi: .byte $00
resex: .byte $00

; IPv4 checksum accumulators
ipv4_sum_lo: .byte 0
ipv4_sum_hi: .byte 0

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

;4500+0028+0000+0000+8006+0000+c0a8+014b+c0a8+0101 = 248ca
;2+48ca = 48cc
;ffff-48cc=b733
