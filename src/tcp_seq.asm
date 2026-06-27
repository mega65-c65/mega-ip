;=============================================================================
; TCP 32-bit modular sequence comparisons
;=============================================================================
; Lives in the fixed gap before the BASIC-visible data block.
* = $4b0b

; Out: A=$ff if SEG.SEQ < RCV.NXT, A=$00 if equal, A=$01 if greater.
;      N/Z reflect A for BMI/BEQ callers.
TCP_SEQ_CMP_SEG_SEQ_REMOTE:
    sec
    lda SEG_SEQ+3
    sbc REMOTE_ISN+3
    sta TCP_SEQ_DIFF+3
    lda SEG_SEQ+2
    sbc REMOTE_ISN+2
    sta TCP_SEQ_DIFF+2
    lda SEG_SEQ+1
    sbc REMOTE_ISN+1
    sta TCP_SEQ_DIFF+1
    lda SEG_SEQ+0
    sbc REMOTE_ISN+0
    sta TCP_SEQ_DIFF+0
    jmp TCP_SEQ_FINISH_CMP

; Out: A compares SEG.ACK to SND.UNA for pending data.
TCP_SEQ_CMP_SEG_ACK_TX_UNACK_SEQ:
    sec
    lda SEG_ACK+3
    sbc TX_UNACK_SEQ+3
    sta TCP_SEQ_DIFF+3
    lda SEG_ACK+2
    sbc TX_UNACK_SEQ+2
    sta TCP_SEQ_DIFF+2
    lda SEG_ACK+1
    sbc TX_UNACK_SEQ+1
    sta TCP_SEQ_DIFF+1
    lda SEG_ACK+0
    sbc TX_UNACK_SEQ+0
    sta TCP_SEQ_DIFF+0
    jmp TCP_SEQ_FINISH_CMP

; Out: A compares SEG.ACK to SND.NXT.
TCP_SEQ_CMP_SEG_ACK_LOCAL_ISN:
    sec
    lda SEG_ACK+3
    sbc LOCAL_ISN+3
    sta TCP_SEQ_DIFF+3
    lda SEG_ACK+2
    sbc LOCAL_ISN+2
    sta TCP_SEQ_DIFF+2
    lda SEG_ACK+1
    sbc LOCAL_ISN+1
    sta TCP_SEQ_DIFF+1
    lda SEG_ACK+0
    sbc LOCAL_ISN+0
    sta TCP_SEQ_DIFF+0
    jmp TCP_SEQ_FINISH_CMP

; Out: A compares SEG.ACK to the ACK needed to retire pending data.
TCP_SEQ_CMP_SEG_ACK_TX_EXPECT:
    sec
    lda SEG_ACK+3
    sbc TX_UNACK_EXPECT_ACK+3
    sta TCP_SEQ_DIFF+3
    lda SEG_ACK+2
    sbc TX_UNACK_EXPECT_ACK+2
    sta TCP_SEQ_DIFF+2
    lda SEG_ACK+1
    sbc TX_UNACK_EXPECT_ACK+1
    sta TCP_SEQ_DIFF+1
    lda SEG_ACK+0
    sbc TX_UNACK_EXPECT_ACK+0
    sta TCP_SEQ_DIFF+0
    jmp TCP_SEQ_FINISH_CMP

TCP_SEQ_FINISH_CMP:
    lda TCP_SEQ_DIFF+0
    ora TCP_SEQ_DIFF+1
    ora TCP_SEQ_DIFF+2
    ora TCP_SEQ_DIFF+3
    beq TCP_SEQ_CMP_EQUAL
    lda TCP_SEQ_DIFF+0
    bmi TCP_SEQ_CMP_LESS
    lda #$01
    rts

TCP_SEQ_CMP_LESS:
    lda #$ff
    rts

TCP_SEQ_CMP_EQUAL:
    lda #$00
    rts

TCP_SEQ_DIFF: .byte $00, $00, $00, $00
