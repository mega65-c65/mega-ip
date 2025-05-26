; IRQ routine

.cpu "45gs02"

* = $1600

vector = $ff8d


    ; Read vector table into memory
    sec
    ldx #<vectable
    ldy #>vectable
    jsr vector

    ; Copy the iirq vector to custom_irq's
    ; jmp instruction
    lda vectable
    sta custom_irq_return+1
    lda vectable+1
    sta custom_irq_return+2

    ; Write custom_irq address to iirq
    lda #<custom_irq
    sta vectable
    lda #>custom_irq
    sta vectable+1

    ; Install updated vector table
    clc
    ldx #<vectable
    ldy #>vectable
    jsr vector

    ; Return to BASIC
    rts

custom_irq:

    lda #$04
    sta $02
    lda #$40
    sta $03
    lda #$00
    sta $04

    lda #$04        ; set SP to disable interrupts when we get over there
    sta $05

    jsr $ff6e       ; jsrfar calls subroutine @ $44000

custom_irq_return:
    jmp $0000
custom_irq_end:


vectable:
    .fill $30