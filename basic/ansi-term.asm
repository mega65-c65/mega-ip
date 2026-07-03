;=============================================================================
; ANSI-TERM
; Simple 45GS02 assembly terminal for Mega-IP.
;
; The small BASIC launcher loads the CP437 font into bank 5, then loads
; eth.bin into bank 4 immediately before entering START.
; The terminal itself is machine language.
;=============================================================================

.cpu "45gs02"

; KERNAL
K_CHROUT            = $ffd2
K_GETIN             = $ffe4
K_JSRFAR            = $ff6e
K_READST            = $ffb7
K_SETLFS            = $ffba
K_SETNAM            = $ffbd
K_OPEN              = $ffc0
K_CLOSE             = $ffc3
K_CHKIN             = $ffc6
K_CHKOUT            = $ffc9
K_CLRCHN            = $ffcc
K_CHRIN             = $ffcf

; MEGA65 / VIC
BORDER_COLOR        = $d020
BACKGROUND_COLOR    = $d021
VIC_KEY             = $d02f
VIC_CTRL2           = $d031
VIC_HOTREGS         = $d05d
VIC4_SPRXMSB9       = $d05f
VIC4_SPRPTRADRLSB   = $d06c
VIC4_SPRPTRADRMSB   = $d06d
VIC4_SPRPTRBNK      = $d06e
VIC4_SPRYMSB8       = $d077
VIC4_SPRYMSB9       = $d078
CHARPTR_LO          = $d068
CHARPTR_HI          = $d069
CHARPTR_BANK        = $d06a
FRAMECOUNT          = $d7fa

SPRITE0_X           = $d000
SPRITE0_Y           = $d001
SPRITE_X_MSB        = $d010
SPRITE_ENABLE       = $d015
SPRITE_Y_EXPAND     = $d017
SPRITE_PRIORITY     = $d01b
SPRITE_MULTICOLOR   = $d01c
SPRITE_X_EXPAND     = $d01d
SPRITE0_COLOR       = $d027

SCREEN_BASE         = $0800
COLOR_BASE          = $f800
COLOR_BANK          = $01
SCREEN_COLS         = 80
SCREEN_ROWS         = 25
CURSOR_SPRITE_X0    = 24
CURSOR_SPRITE_Y0    = 50

COLOR_BLACK         = $00
COLOR_WHITE         = $01
COLOR_RED           = $02
COLOR_CYAN          = $03
COLOR_PURPLE        = $04
COLOR_GREEN         = $05
COLOR_BLUE          = $06
COLOR_YELLOW        = $07
COLOR_ORANGE        = $08
COLOR_BROWN         = $09
COLOR_LIGHT_RED     = $0a
COLOR_DARK_GREY     = $0b
COLOR_GREY          = $0c
COLOR_LIGHT_GREEN   = $0d
COLOR_LIGHT_BLUE    = $0e
COLOR_LIGHT_GREY    = $0f
ASCII_DEFAULT_COLOR = COLOR_WHITE

; C65/MEGA65 JSRFAR workspace
FAR_BANK            = $02
FAR_ADDR_HI         = $03
FAR_ADDR_LO         = $04
FAR_STATUS          = $05
FAR_ARG_A           = $06
FAR_ARG_X           = $07
FAR_ARG_Y           = $08

; 28-bit indirect pointer for staging calls into bank 4.
PTR_LO              = $fb
PTR_HI              = $fc
PTR_BANK            = $fd
PTR_TOP             = $fe

; Mega-IP public jump table, as seen inside bank 4.
MIP_INIT            = $2000
MIP_SET_GATEWAY     = $2003
MIP_SET_LOCAL_IP    = $2006
MIP_SET_LOCAL_PORT  = $2009
MIP_SET_REMOTE_IP   = $200c
MIP_SET_REMOTE_PORT = $200f
MIP_SET_SUBNET      = $2012
MIP_SET_XLATE       = $2015
MIP_DISCONNECT      = $2021
MIP_STATUS_POLL     = $2024
MIP_CONNECT_START   = $2027
MIP_CONNECT_POLL    = $202a
MIP_GET_DNS_RESULT  = $2033
MIP_GET_DNS_STATE   = $2036
MIP_DHCP_START      = $2042
MIP_DHCP_POLL       = $2045
MIP_SET_DNS         = $204b
MIP_GET_LOCAL_IP    = $204e
MIP_GET_GATEWAY     = $2051
MIP_GET_SUBNET      = $2054
MIP_GET_DNS         = $2057
MIP_GET_REMOTE_IP   = $205a
MIP_FORCE_CLOSE     = $205d

; Mega-IP ML extension table.
MIP_ML_SEND_BYTE    = $7600
MIP_DNS_START_BUF   = $760f
MIP_DNS_START_BUF_Y = $7618
MIP_ML_CALL_STAGED  = $761b
MIP_ML_RECV_BYTE    = $761e
MIP_ML_RECV_BLOCK   = $7621
MIP_DNS_DEBUG       = $7612
MIP_DNS_DEBUG2      = $7615
MIP_DNS_DEBUG3      = $7624
MIP_CONNECT_DEBUG   = $7627
MIP_CONNECT_DEBUG2  = $762a
MIP_CONNECT_DEBUG3  = $762d
MIP_TX_DEBUG2       = $7803
MIP_TX_DEBUG3       = $7806
MIP_TX_DEBUG4       = $7809
MIP_SYN_DEBUG1      = $7812
MIP_SYN_DEBUG2      = $7815
MIP_SYN_DEBUG3      = $7818
MIP_RX_DEBUG2       = $781e
MIP_RX_DEBUG3       = $7821
MIP_RX_DEBUG4       = $7824
MIP_SYNACK_DEBUG1   = $783c
MIP_SYNACK_DEBUG2   = $783f
MIP_SYNACK_DEBUG3   = $7842

; Staging block at physical bank-4 $77c0.
ML_STAGE_LO         = $77c0
ML_STAGE_HI         = $77
ML_STAGE_BANK       = $04
ML_STAGE_TARGET_LO  = 0
ML_STAGE_TARGET_HI  = 1
ML_STAGE_ARG_A      = 2
ML_STAGE_ARG_X      = 3
ML_STAGE_ARG_Y      = 4
ML_STAGE_ARG_Z      = 5

CR                  = $0d
LF                  = $0a
ESC                 = $1b
CLR                 = $93
DEL                 = $14
CTRL_W              = $17
PET_HOME            = $13
PET_DOWN            = $11
PET_MIXED           = $0e
PET_WHITE           = $05
PET_RED             = $1c
PET_CYAN            = $9f
PET_GREEN           = $1e
PET_BLUE            = $1f
PET_YELLOW          = $9e
PET_HLINE           = $c0
PET_RVS_ON          = $12
PET_RVS_OFF         = $92

CONN_CONNECTED      = %00000001
CONN_FAILED         = %00000010

DHCP_STATE_BOUND    = $04
DHCP_STATE_FAILED   = $7f
DNS_STATE_DONE      = $02
DNS_STATE_FAIL      = $03

DHCP_TIMEOUT_FRAMES = 3600
DNS_TIMEOUT_FRAMES = 3600
CONNECT_TIMEOUT_FRAMES = 1800
RX_BLOCK_MAX        = 128
MENU_STATUS_ROW     = 8
PHONE_MAX           = 32
PHONE_PAGE_SIZE     = 8
PHONE_ENTRY_SIZE    = 112
PHONE_NAME_OFF      = 0
PHONE_NAME_MAX      = 31
PHONE_HOST_OFF      = 32
PHONE_HOST_MAX      = 39
PHONE_PORT_OFF      = 72
PHONE_PORT_MAX      = 5
PHONE_TYPE_OFF      = 80
PHONE_TYPE_MAX      = 1
PHONE_USER_OFF      = 84
PHONE_USER_MAX      = 20
PHONE_LFN           = 2
PHONE_DEVICE        = 8
PHONE_SA            = 2

;-----------------------------------------------------------------------------
; BASIC launcher:
;   10 BLOAD"CP437.BIN",P($5A000),R:BLOAD"ETH.BIN",P($42000),R:SYS8448
;-----------------------------------------------------------------------------
* = $2001
    .word launcher_end
    .word 10
    .byte $fe,$11
    .byte $22
    .text "CP437.BIN"
    .byte $22,$2c
    .text "P($5A000),R"
    .byte $3a,$fe,$11
    .byte $22
    .text "ETH.BIN"
    .byte $22,$2c
    .text "P($42000),R"
    .byte $3a,$9e
    .text "8448"
    .byte 0
launcher_end:
    .word 0

* = $2100

START:
    jsr USE_DEFAULT_FONT

    lda #0
    sta BORDER_COLOR
    sta BACKGROUND_COLOR
    jsr CURSOR_SPRITE_DISABLE

    jsr DRAW_MAIN_HEADER

    lda #<MSG_RESET
    ldx #>MSG_RESET
    jsr PRINT_Z
    lda #<MIP_INIT
    ldx #>MIP_INIT
    jsr FAR_CALL_NOARGS

CONFIG_MENU:
    lda #<MSG_CONFIG
    ldx #>MSG_CONFIG
    jsr PRINT_Z
    jsr GET_KEY
    cmp #'D'
    beq DO_DHCP
    cmp #'d'
    beq DO_DHCP
    cmp #'M'
    beq DO_MANUAL
    cmp #'m'
    beq DO_MANUAL
    bra CONFIG_MENU

DO_DHCP:
    lda #<MSG_DHCP_START
    ldx #>MSG_DHCP_START
    jsr PRINT_Z
    lda #<MIP_DHCP_START
    ldx #>MIP_DHCP_START
    jsr FAR_CALL_NOARGS
    lda #$ff
    sta LAST_DHCP_STATE
    jsr RESET_DHCP_TIMEOUT

DHCP_LOOP:
    lda #<MIP_STATUS_POLL
    ldx #>MIP_STATUS_POLL
    jsr FAR_CALL_NOARGS
    lda #<MIP_DHCP_POLL
    ldx #>MIP_DHCP_POLL
    jsr FAR_CALL_NOARGS
    sta TEMP_A
    cmp LAST_DHCP_STATE
    beq DHCP_STATE_DONE
    sta LAST_DHCP_STATE
    jsr PRINT_DHCP_STATE
    jsr RESET_DHCP_TIMEOUT
DHCP_STATE_DONE:
    lda TEMP_A
    cmp #DHCP_STATE_BOUND
    beq NETWORK_READY
    cmp #DHCP_STATE_FAILED
    beq DHCP_FAILED
    jsr DEC_TIMEOUT_FRAME
    bcc DHCP_LOOP
DHCP_FAILED:
    lda #<MSG_DHCP_FAIL
    ldx #>MSG_DHCP_FAIL
    jsr PRINT_Z
    bra CONFIG_MENU

DO_MANUAL:
    lda #<MSG_LOCAL_IP
    ldx #>MSG_LOCAL_IP
    jsr READ_IP_AND_SET_LOCAL
    bcs DO_MANUAL
    lda #<MSG_GATEWAY
    ldx #>MSG_GATEWAY
    jsr READ_IP_AND_SET_GATEWAY
    bcs DO_MANUAL
    lda #<MSG_SUBNET
    ldx #>MSG_SUBNET
    jsr READ_IP_AND_SET_SUBNET
    bcs DO_MANUAL
    lda #<MSG_DNS
    ldx #>MSG_DNS
    jsr READ_IP_AND_SET_DNS
    bcs DO_MANUAL
    bra NETWORK_READY

NETWORK_READY:
    lda #<MIP_FORCE_CLOSE
    ldx #>MIP_FORCE_CLOSE
    jsr FAR_CALL_NOARGS
    jsr CLEAR_NETWORK_STATUS_AREA
NETWORK_READY_DRAW:
    lda #<MSG_NETWORK_READY
    ldx #>MSG_NETWORK_READY
    jsr PRINT_Z
    jsr PRINT_NETWORK_SETTINGS
    bra REMOTE_SETUP

TERM_MODE_MENU:
    lda #<MSG_TERM_MODE
    ldx #>MSG_TERM_MODE
    jsr PRINT_Z
    jsr GET_KEY
    cmp #'A'
    beq TERM_ASCII
    cmp #'a'
    beq TERM_ASCII
    cmp #'P'
    beq TERM_PETSCII
    cmp #'p'
    beq TERM_PETSCII
    bra TERM_MODE_MENU

TERM_ASCII:
    lda #1
    sta TERM_MODE
    jsr USE_DEFAULT_FONT
    lda #0
    jsr SET_XLATE_A
    rts

TERM_PETSCII:
    lda #0
    sta TERM_MODE
    jsr USE_DEFAULT_FONT
    lda #0
    jsr SET_XLATE_A
    rts

REMOTE_SETUP:
    lda #<MSG_CONNECT_BY
    ldx #>MSG_CONNECT_BY
    jsr PRINT_Z
    jsr GET_KEY
    cmp #'P'
    beq REMOTE_PHONEBOOK
    cmp #'p'
    beq REMOTE_PHONEBOOK
    cmp #'I'
    beq REMOTE_IP_SETUP
    cmp #'i'
    beq REMOTE_IP_SETUP
    cmp #'H'
    beq REMOTE_HOST_SETUP
    cmp #'h'
    beq REMOTE_HOST_SETUP
    bra REMOTE_SETUP

REMOTE_PHONEBOOK:
    jmp PHONEBOOK_MENU

REMOTE_IP_SETUP:
REMOTE_IP_PROMPT:
    lda #<MSG_REMOTE_IP
    ldx #>MSG_REMOTE_IP
    jsr READ_IP_AND_SET_REMOTE
    bcc PORT_SETUP
    lda LINE_LEN
    beq REMOTE_CANCEL_TO_READY
    bra REMOTE_IP_PROMPT

REMOTE_CANCEL_TO_READY:
    jsr DRAW_MAIN_HEADER
    bra NETWORK_READY_DRAW

REMOTE_HOST_SETUP:
    lda #<MSG_REMOTE_HOST
    ldx #>MSG_REMOTE_HOST
    jsr PRINT_Z
    jsr READ_LINE
    jsr RESOLVE_LINEBUF_HOST
    bcc PORT_SETUP
    bra REMOTE_SETUP

RESOLVE_LINEBUF_HOST:
    lda LINE_LEN
    bne _resolve_has_text
    lda #<MSG_BAD_HOST
    ldx #>MSG_BAD_HOST
    jsr PRINT_Z
    sec
    rts
_resolve_has_text:
    jsr PARSE_IP
    bcs _resolve_as_host
    jsr SET_REMOTE_FROM_IPBUF
    clc
    rts
_resolve_as_host:
    lda #<MSG_RESOLVING
    ldx #>MSG_RESOLVING
    jsr PRINT_Z
    jsr PRINT_LINEBUF
    lda #<MSG_QUOTE_CR
    ldx #>MSG_QUOTE_CR
    jsr PRINT_Z
    jsr DNS_START_LINEBUF
    cmp #1
    beq DNS_WAIT_START_OK
    jsr PRINT_DNS_DEBUG
    lda #<MSG_LOOKUP_FAIL
    ldx #>MSG_LOOKUP_FAIL
    jsr PRINT_Z
    sec
    rts

DNS_WAIT_START_OK:
    jsr RESET_DNS_TIMEOUT

DNS_WAIT_LOOP:
    lda #<MIP_STATUS_POLL
    ldx #>MIP_STATUS_POLL
    jsr FAR_CALL_NOARGS
    lda #<MIP_GET_DNS_STATE
    ldx #>MIP_GET_DNS_STATE
    jsr FAR_CALL_NOARGS
    cmp #DNS_STATE_DONE
    beq DNS_DONE
    cmp #DNS_STATE_FAIL
    beq DNS_FAILED
    jsr DEC_TIMEOUT_FRAME
    bcc DNS_WAIT_LOOP

DNS_FAILED:
    jsr PRINT_DNS_DEBUG
    lda #<MSG_LOOKUP_FAIL
    ldx #>MSG_LOOKUP_FAIL
    jsr PRINT_Z
    sec
    rts

DNS_DONE:
    lda #<MIP_GET_DNS_RESULT
    ldx #>MIP_GET_DNS_RESULT
    jsr GET_IPBUF_TARGET
    lda #<MSG_RESOLVED_TO
    ldx #>MSG_RESOLVED_TO
    jsr PRINT_Z
    jsr PRINT_IPBUF
    lda #CR
    jsr K_CHROUT
    jsr SET_REMOTE_FROM_IPBUF
    clc
    rts

PORT_SETUP:
    lda #<MSG_REMOTE_PORT
    ldx #>MSG_REMOTE_PORT
    jsr PRINT_Z
    jsr READ_LINE
    jsr SET_PORT_FROM_LINEBUF
    bcc PORT_SETUP_MANUAL_CONNECT
    lda #<MSG_BAD_PORT
    ldx #>MSG_BAD_PORT
    jsr PRINT_Z
    bra PORT_SETUP

PORT_SETUP_MANUAL_CONNECT:
    jsr TERM_MODE_MENU
    bra CONNECT

SET_PORT_FROM_LINEBUF:
    jsr PARSE_PORT
    bcc _set_port_ok
    sec
    rts
_set_port_ok:
    lda #<MIP_SET_REMOTE_PORT
    sta STAGE_TARGET_LO_VAR
    lda #>MIP_SET_REMOTE_PORT
    sta STAGE_TARGET_HI_VAR
    lda PORT_HI
    sta STAGE_ARG_A_VAR
    lda PORT_LO
    sta STAGE_ARG_X_VAR
    lda #0
    sta STAGE_ARG_Y_VAR
    sta STAGE_ARG_Z_VAR
    jsr STAGED_CALL
    clc
    rts

CONNECT:
    lda #<MIP_SET_LOCAL_PORT
    sta STAGE_TARGET_LO_VAR
    lda #>MIP_SET_LOCAL_PORT
    sta STAGE_TARGET_HI_VAR
    lda #$c0
    sta STAGE_ARG_A_VAR
    lda FRAMECOUNT
    eor PORT_LO
    sta STAGE_ARG_X_VAR
    lda #0
    sta STAGE_ARG_Y_VAR
    sta STAGE_ARG_Z_VAR
    jsr STAGED_CALL

    lda #<MSG_CONNECTING
    ldx #>MSG_CONNECTING
    jsr PRINT_Z
    jsr PRINT_IPBUF
    lda #<MSG_DOTS_CR
    ldx #>MSG_DOTS_CR
    jsr PRINT_Z
    lda #<MIP_CONNECT_START
    ldx #>MIP_CONNECT_START
    jsr FAR_CALL_NOARGS
    jsr RESET_CONNECT_TIMEOUT

CONNECT_LOOP:
    lda #<MIP_STATUS_POLL
    ldx #>MIP_STATUS_POLL
    jsr FAR_CALL_NOARGS
    lda #<MIP_CONNECT_POLL
    ldx #>MIP_CONNECT_POLL
    jsr FAR_CALL_NOARGS
    sta TEMP_A
    lda TEMP_A
    and #CONN_CONNECTED
    bne CONNECTED
    lda TEMP_A
    and #CONN_FAILED
    bne CONNECT_FAILED
    jsr DEC_TIMEOUT_FRAME
    bcc CONNECT_LOOP

CONNECT_FAILED:
    lda #<MSG_CONNECT_FAIL
    ldx #>MSG_CONNECT_FAIL
    jsr PRINT_Z
    jsr GET_KEY
    jsr DRAW_MAIN_HEADER
    bra NETWORK_READY_DRAW

CONNECTED:
    lda TERM_MODE
    beq CONNECTED_PETSCII
    jsr TERMINAL_RESET_PUMP_STATE
    jsr ASCII_START_SCREEN
    bra TERMINAL_LOOP

CONNECTED_PETSCII:
    jsr TERMINAL_RESET_PUMP_STATE
    lda #<MSG_CONNECTED
    ldx #>MSG_CONNECTED
    jsr PRINT_Z

TERMINAL_LOOP:
    bra CHECK_RX

CHECK_KEYBOARD:
    jsr K_GETIN
    beq CHECK_RX
    cmp #CTRL_W
    beq USER_DISCONNECT
    cmp #$88
    beq USER_DISCONNECT
    ldx TERM_MODE
    beq _send_key
    jsr SEND_ANSI_CURSOR_KEY
    bcs CHECK_RX
    jsr PETSCII_TO_ASCII_KEY
_send_key:
    jsr SEND_BYTE_A

CHECK_RX:
    jsr RECV_BLOCK
    lda RX_BLOCK_COUNT
    beq CHECK_STATUS
    lda #0
    sta RX_BLOCK_INDEX

PROCESS_RX_BLOCK:
    ldx RX_BLOCK_INDEX
    lda RX_BLOCK_BUF,x
    cmp #LF
    bne _rx_not_lf
    ldx TERM_MODE
    beq RX_BYTE_DONE
    jsr ANSI_PUT_BYTE
    bra RX_BYTE_DONE
_rx_not_lf:
    ldx TERM_MODE
    beq _rx_petscii
    jsr ANSI_PUT_BYTE
    bra RX_BYTE_DONE
_rx_petscii:
    jsr K_CHROUT
RX_BYTE_DONE:
    jsr TERMINAL_MAYBE_PUMP
    inc RX_BLOCK_INDEX
    lda RX_BLOCK_INDEX
    cmp RX_BLOCK_COUNT
    bcc PROCESS_RX_BLOCK
    lda TERM_MODE
    beq _rx_block_no_cursor
    jsr CURSOR_SPRITE_UPDATE
_rx_block_no_cursor:
    jsr TERMINAL_POLL_STATUS
    bra CHECK_RX

CHECK_STATUS:
    jsr TERMINAL_POLL_STATUS
    lda TERMINAL_EVENT
    cmp #0
    bne TERMINAL_HANDLE_EVENT
    ; STATUS_POLL can pull fresh echoed input from the NIC into the RX ring.
    ; Drain it now so a server echo is displayed before the next typed key.
    jsr RECV_BLOCK
    lda RX_BLOCK_COUNT
    beq CHECK_KEYBOARD
    lda #0
    sta RX_BLOCK_INDEX
    bra PROCESS_RX_BLOCK

TERMINAL_HANDLE_EVENT:
    lda #0
    sta TERMINAL_EVENT
    jsr DRAW_MAIN_HEADER
    lda #<MSG_TERMINATED
    ldx #>MSG_TERMINATED
    jsr PRINT_Z
    lda #<MIP_FORCE_CLOSE
    ldx #>MIP_FORCE_CLOSE
    jsr FAR_CALL_NOARGS
    bra NETWORK_READY_DRAW

USER_DISCONNECT:
    jsr DRAW_MAIN_HEADER
    lda #<MSG_DISCONNECTING
    ldx #>MSG_DISCONNECTING
    jsr PRINT_Z
    lda #<MIP_DISCONNECT
    ldx #>MIP_DISCONNECT
    jsr FAR_CALL_NOARGS
    lda #<MIP_FORCE_CLOSE
    ldx #>MIP_FORCE_CLOSE
    jsr FAR_CALL_NOARGS
    bra NETWORK_READY

TERMINAL_RESET_PUMP_STATE:
    lda #0
    sta RX_PUMP_COUNT
    sta TERMINAL_EVENT
    rts

TERMINAL_MAYBE_PUMP:
    inc RX_PUMP_COUNT
    lda RX_PUMP_COUNT
    and #$07
    bne _terminal_no_pump
    jsr TERMINAL_POLL_STATUS
_terminal_no_pump:
    rts

TERMINAL_POLL_STATUS:
    lda #<MIP_STATUS_POLL
    ldx #>MIP_STATUS_POLL
    jsr FAR_CALL_NOARGS
    cmp #0
    beq _terminal_poll_done
    ora TERMINAL_EVENT
    sta TERMINAL_EVENT
_terminal_poll_done:
    rts

RECV_BLOCK:
    lda #<MIP_ML_RECV_BLOCK
    sta STAGE_TARGET_LO_VAR
    lda #>MIP_ML_RECV_BLOCK
    sta STAGE_TARGET_HI_VAR
    lda #<RX_BLOCK_BUF
    sta STAGE_ARG_A_VAR
    lda #>RX_BLOCK_BUF
    sta STAGE_ARG_X_VAR
    lda #0
    sta STAGE_ARG_Y_VAR
    lda #RX_BLOCK_MAX
    sta STAGE_ARG_Z_VAR
    jsr STAGED_CALL
    sta RX_BLOCK_COUNT
    rts

;-----------------------------------------------------------------------------
; Phonebook
;-----------------------------------------------------------------------------
PHONEBOOK_MENU:
    jsr PHONEBOOK_LOAD
    lda #0
    sta PHONE_PAGE

PHONEBOOK_REDRAW:
    lda #0
    sta PHONE_PICK_MODE
    jsr PHONEBOOK_DRAW
    jsr PHONEBOOK_GET_KEY
    cmp #'Q'
    beq PHONEBOOK_QUIT
    cmp #'q'
    beq PHONEBOOK_QUIT
    cmp #'A'
    beq PHONEBOOK_ADD
    cmp #'a'
    beq PHONEBOOK_ADD
    cmp #'E'
    beq PHONEBOOK_EDIT
    cmp #'e'
    beq PHONEBOOK_EDIT
    cmp #'D'
    beq PHONEBOOK_DELETE
    cmp #'d'
    beq PHONEBOOK_DELETE
    cmp #'R'
    beq PHONEBOOK_MENU
    cmp #'r'
    beq PHONEBOOK_MENU
    cmp #'N'
    beq PHONEBOOK_NEXT_PAGE
    cmp #'n'
    beq PHONEBOOK_NEXT_PAGE
    cmp #'>'
    beq PHONEBOOK_NEXT_PAGE
    cmp #'.'
    beq PHONEBOOK_NEXT_PAGE
    cmp #$be
    beq PHONEBOOK_NEXT_PAGE
    cmp #'B'
    beq PHONEBOOK_PREV_PAGE
    cmp #'b'
    beq PHONEBOOK_PREV_PAGE
    cmp #'<'
    beq PHONEBOOK_PREV_PAGE
    cmp #','
    beq PHONEBOOK_PREV_PAGE
    cmp #$bc
    beq PHONEBOOK_PREV_PAGE
    cmp #'1'
    bcc PHONEBOOK_REDRAW
    cmp #'1'+PHONE_PAGE_SIZE
    bcs PHONEBOOK_REDRAW
    sec
    sbc #'1'
    sta TEMP_A
    jsr PHONEBOOK_PAGE_START
    clc
    adc TEMP_A
    cmp PHONE_COUNT
    bcs PHONEBOOK_REDRAW
    sta PHONE_INDEX
    jmp PHONEBOOK_DIAL

PHONEBOOK_NEXT_PAGE:
    jsr PHONEBOOK_TOTAL_PAGES
    sta TEMP_A
    lda PHONE_PAGE
    clc
    adc #1
    cmp TEMP_A
    bcs PHONEBOOK_REDRAW
    sta PHONE_PAGE
    jmp PHONEBOOK_REDRAW

PHONEBOOK_PREV_PAGE:
    lda PHONE_PAGE
    beq _phonebook_prev_stay
    dec PHONE_PAGE
_phonebook_prev_stay:
    jmp PHONEBOOK_REDRAW

PHONEBOOK_QUIT:
    jsr DRAW_MAIN_HEADER
    jmp NETWORK_READY_DRAW

PHONEBOOK_DRAW:
    jsr PHONEBOOK_CLAMP_PAGE
    lda #CLR
    jsr K_CHROUT
    lda #<MSG_PHONE_TITLE
    ldx #>MSG_PHONE_TITLE
    jsr PRINT_Z
    jsr PHONEBOOK_PRINT_PAGE_INFO
    lda PHONE_COUNT
    bne _phonebook_draw_entries
    lda #<MSG_PHONE_EMPTY
    ldx #>MSG_PHONE_EMPTY
    jsr PRINT_Z
    bra _phonebook_draw_cmd

_phonebook_draw_entries:
    lda #0
    sta PHONE_LINE_INDEX
    jsr PHONEBOOK_PAGE_START
    sta PHONE_WORK_INDEX
_phonebook_draw_loop:
    lda PHONE_LINE_INDEX
    cmp #PHONE_PAGE_SIZE
    beq _phonebook_draw_cmd
    lda PHONE_WORK_INDEX
    cmp PHONE_COUNT
    bcs _phonebook_draw_cmd
    sta PHONE_INDEX
    jsr PHONEBOOK_PRINT_ENTRY
    inc PHONE_LINE_INDEX
    inc PHONE_WORK_INDEX
    bra _phonebook_draw_loop

_phonebook_draw_cmd:
    lda PHONE_PICK_MODE
    beq _phonebook_draw_menu_cmd
    lda #<MSG_PHONE_PICK
    ldx #>MSG_PHONE_PICK
    bra _phonebook_draw_cmd_print
_phonebook_draw_menu_cmd:
    lda #<MSG_PHONE_COMMAND
    ldx #>MSG_PHONE_COMMAND
_phonebook_draw_cmd_print:
    jsr PRINT_Z
    rts

PHONEBOOK_PRINT_ENTRY:
    lda #PET_CYAN
    jsr K_CHROUT
    lda #' '
    jsr K_CHROUT
    lda #' '
    jsr K_CHROUT
    lda PHONE_LINE_INDEX
    clc
    adc #'1'
    jsr K_CHROUT
    lda #'.'
    jsr K_CHROUT
    lda #' '
    jsr K_CHROUT
    lda #PET_YELLOW
    jsr K_CHROUT
    jsr PHONE_SET_NAME_FIELD
    jsr PHONEBOOK_PRINT_FIELD
    lda #PET_WHITE
    jsr K_CHROUT
    lda #' '
    jsr K_CHROUT
    lda #'['
    jsr K_CHROUT
    jsr PHONE_SET_TYPE_FIELD
    jsr PHONEBOOK_PRINT_FIELD
    lda #']'
    jsr K_CHROUT
    lda #CR
    jsr K_CHROUT
    lda #<MSG_PHONE_HOST_LINE
    ldx #>MSG_PHONE_HOST_LINE
    jsr PRINT_Z
    jsr PHONE_SET_HOST_FIELD
    jsr PHONEBOOK_PRINT_FIELD
    lda #':'
    jsr K_CHROUT
    jsr PHONE_SET_PORT_FIELD
    jsr PHONEBOOK_PRINT_FIELD
    lda #CR
    jsr K_CHROUT
    rts

PHONEBOOK_PRINT_PAGE_INFO:
    lda #<MSG_PHONE_PAGE
    ldx #>MSG_PHONE_PAGE
    jsr PRINT_Z
    lda PHONE_PAGE
    clc
    adc #1
    jsr PRINT_BYTE_DEC
    lda #<MSG_PHONE_OF
    ldx #>MSG_PHONE_OF
    jsr PRINT_Z
    jsr PHONEBOOK_TOTAL_PAGES
    jsr PRINT_BYTE_DEC
    lda #CR
    jsr K_CHROUT
    lda #CR
    jmp K_CHROUT

PHONEBOOK_TOTAL_PAGES:
    lda PHONE_COUNT
    bne _phonebook_total_has_entries
    lda #1
    rts
_phonebook_total_has_entries:
    sec
    sbc #1
    lsr
    lsr
    lsr
    clc
    adc #1
    rts

PHONEBOOK_PAGE_START:
    lda PHONE_PAGE
    asl
    asl
    asl
    rts

PHONEBOOK_CLAMP_PAGE:
    jsr PHONEBOOK_TOTAL_PAGES
    sec
    sbc #1
    cmp PHONE_PAGE
    bcs _phonebook_clamp_done
    sta PHONE_PAGE
_phonebook_clamp_done:
    rts

PHONEBOOK_SET_PAGE_FOR_INDEX:
    lda PHONE_INDEX
    lsr
    lsr
    lsr
    sta PHONE_PAGE
    rts

PHONEBOOK_ADD:
    lda PHONE_COUNT
    cmp #PHONE_MAX
    bcc _phonebook_add_room
    lda #<MSG_PHONE_FULL
    ldx #>MSG_PHONE_FULL
    jsr PHONEBOOK_NOTICE
    jmp PHONEBOOK_REDRAW

_phonebook_add_room:
    sta PHONE_INDEX
    jsr PHONE_CLEAR_ENTRY
    lda #<MSG_PHONE_ADD_TITLE
    ldx #>MSG_PHONE_ADD_TITLE
    jsr PHONEBOOK_FORM_HEADER
    jsr PHONEBOOK_READ_REQUIRED_NAME
    bcs PHONEBOOK_REDRAW
    jsr PHONEBOOK_READ_REQUIRED_HOST
    bcs PHONEBOOK_REDRAW
    jsr PHONEBOOK_READ_REQUIRED_PORT
    bcs PHONEBOOK_REDRAW
    jsr PHONEBOOK_READ_REQUIRED_TYPE
    bcs PHONEBOOK_REDRAW
    jsr PHONEBOOK_READ_USER
    inc PHONE_COUNT
    jsr PHONEBOOK_SET_PAGE_FOR_INDEX
    jsr PHONEBOOK_SAVE_AND_NOTICE
    jmp PHONEBOOK_REDRAW

PHONEBOOK_EDIT:
    jsr PHONEBOOK_PICK_ENTRY
    bcs PHONEBOOK_REDRAW
    lda #<MSG_PHONE_EDIT_TITLE
    ldx #>MSG_PHONE_EDIT_TITLE
    jsr PHONEBOOK_FORM_HEADER
    lda #<MSG_PHONE_BLANK_KEEP
    ldx #>MSG_PHONE_BLANK_KEEP
    jsr PRINT_Z

    jsr PHONE_SET_NAME_FIELD
    lda #<MSG_PHONE_NAME
    ldx #>MSG_PHONE_NAME
    jsr PHONEBOOK_EDIT_FIELD

    jsr PHONE_SET_HOST_FIELD
    lda #<MSG_PHONE_HOST
    ldx #>MSG_PHONE_HOST
    jsr PHONEBOOK_EDIT_FIELD

_phonebook_edit_port:
    jsr PHONE_SET_PORT_FIELD
    lda #<MSG_PHONE_PORT
    ldx #>MSG_PHONE_PORT
    jsr PRINT_Z
    lda #'['
    jsr K_CHROUT
    jsr PHONEBOOK_PRINT_FIELD
    lda #']'
    jsr K_CHROUT
    lda #' '
    jsr K_CHROUT
    jsr READ_LINE
    lda LINE_LEN
    beq _phonebook_edit_user
    jsr PARSE_PORT
    bcs _phonebook_edit_port_bad
    jsr PHONE_COPY_LINE_TO_FIELD
    bra _phonebook_edit_user
_phonebook_edit_port_bad:
    lda #<MSG_BAD_PORT
    ldx #>MSG_BAD_PORT
    jsr PRINT_Z
    bra _phonebook_edit_port

_phonebook_edit_user:
    jsr PHONEBOOK_EDIT_TYPE
    jsr PHONE_SET_USER_FIELD
    lda #<MSG_PHONE_USER
    ldx #>MSG_PHONE_USER
    jsr PHONEBOOK_EDIT_FIELD
    jsr PHONEBOOK_SAVE_AND_NOTICE
    jmp PHONEBOOK_REDRAW

PHONEBOOK_DELETE:
    jsr PHONEBOOK_PICK_ENTRY
    bcs PHONEBOOK_REDRAW
    lda #<MSG_PHONE_DELETE_CONFIRM
    ldx #>MSG_PHONE_DELETE_CONFIRM
    jsr PRINT_Z
    jsr PHONEBOOK_GET_KEY
    cmp #'Y'
    beq _phonebook_delete_yes
    cmp #'y'
    beq _phonebook_delete_yes
    jmp PHONEBOOK_REDRAW

_phonebook_delete_yes:
    lda #CR
    jsr K_CHROUT
    jsr PHONEBOOK_DELETE_CURRENT
    jsr PHONEBOOK_SAVE_AND_NOTICE
    jmp PHONEBOOK_REDRAW

PHONEBOOK_DIAL:
    jsr PHONEBOOK_APPLY_TYPE
    jsr PHONE_SET_HOST_FIELD
    jsr PHONE_COPY_FIELD_TO_LINE
    lda #<MSG_PHONE_DIAL
    ldx #>MSG_PHONE_DIAL
    jsr PRINT_Z
    jsr PRINT_LINEBUF
    lda #CR
    jsr K_CHROUT
    jsr RESOLVE_LINEBUF_HOST
    bcc _phonebook_dial_port
    jsr PHONEBOOK_WAIT_KEY
    jmp PHONEBOOK_REDRAW

_phonebook_dial_port:
    jsr PHONE_SET_PORT_FIELD
    jsr PHONE_COPY_FIELD_TO_LINE
    jsr SET_PORT_FROM_LINEBUF
    bcc _phonebook_dial_connect
    lda #<MSG_BAD_PORT
    ldx #>MSG_BAD_PORT
    jsr PRINT_Z
    jsr PHONEBOOK_WAIT_KEY
    jmp PHONEBOOK_REDRAW

_phonebook_dial_connect:
    jmp CONNECT

PHONEBOOK_FORM_HEADER:
    pha
    txa
    pha
    lda #CLR
    jsr K_CHROUT
    pla
    tax
    pla
    jsr PRINT_Z
    rts

PHONEBOOK_READ_REQUIRED_NAME:
    jsr PHONE_SET_NAME_FIELD
_phonebook_read_name_loop:
    lda #<MSG_PHONE_NAME
    ldx #>MSG_PHONE_NAME
    jsr PRINT_Z
    jsr READ_LINE
    lda LINE_LEN
    bne _phonebook_read_name_ok
    lda #<MSG_PHONE_BAD_NAME
    ldx #>MSG_PHONE_BAD_NAME
    jsr PRINT_Z
    bra _phonebook_read_name_loop
_phonebook_read_name_ok:
    jsr PHONE_COPY_LINE_TO_FIELD
    clc
    rts

PHONEBOOK_READ_REQUIRED_HOST:
    jsr PHONE_SET_HOST_FIELD
_phonebook_read_host_loop:
    lda #<MSG_PHONE_HOST
    ldx #>MSG_PHONE_HOST
    jsr PRINT_Z
    jsr READ_LINE
    lda LINE_LEN
    bne _phonebook_read_host_ok
    lda #<MSG_BAD_HOST
    ldx #>MSG_BAD_HOST
    jsr PRINT_Z
    bra _phonebook_read_host_loop
_phonebook_read_host_ok:
    jsr PHONE_COPY_LINE_TO_FIELD
    clc
    rts

PHONEBOOK_READ_REQUIRED_PORT:
    jsr PHONE_SET_PORT_FIELD
_phonebook_read_port_loop:
    lda #<MSG_PHONE_PORT
    ldx #>MSG_PHONE_PORT
    jsr PRINT_Z
    jsr READ_LINE
    jsr PARSE_PORT
    bcc _phonebook_read_port_ok
    lda #<MSG_BAD_PORT
    ldx #>MSG_BAD_PORT
    jsr PRINT_Z
    bra _phonebook_read_port_loop
_phonebook_read_port_ok:
    jsr PHONE_COPY_LINE_TO_FIELD
    clc
    rts

PHONEBOOK_READ_REQUIRED_TYPE:
    jsr PHONE_SET_TYPE_FIELD
_phonebook_read_type_loop:
    lda #<MSG_PHONE_TYPE
    ldx #>MSG_PHONE_TYPE
    jsr PRINT_Z
    jsr READ_LINE
    jsr PHONEBOOK_VALIDATE_TYPE_LINE
    bcc _phonebook_read_type_ok
    lda #<MSG_PHONE_BAD_TYPE
    ldx #>MSG_PHONE_BAD_TYPE
    jsr PRINT_Z
    bra _phonebook_read_type_loop
_phonebook_read_type_ok:
    jsr PHONE_COPY_LINE_TO_FIELD
    clc
    rts

PHONEBOOK_READ_USER:
    jsr PHONE_SET_USER_FIELD
    lda #<MSG_PHONE_USER
    ldx #>MSG_PHONE_USER
    jsr PRINT_Z
    jsr READ_LINE
    jsr PHONE_COPY_LINE_TO_FIELD
    rts

PHONEBOOK_EDIT_FIELD:
    jsr PRINT_Z
    lda #'['
    jsr K_CHROUT
    jsr PHONEBOOK_PRINT_FIELD
    lda #']'
    jsr K_CHROUT
    lda #' '
    jsr K_CHROUT
    jsr READ_LINE
    lda LINE_LEN
    beq _phonebook_edit_keep
    jsr PHONE_COPY_LINE_TO_FIELD
_phonebook_edit_keep:
    rts

PHONEBOOK_EDIT_TYPE:
    jsr PHONE_SET_TYPE_FIELD
_phonebook_edit_type_loop:
    lda #<MSG_PHONE_TYPE
    ldx #>MSG_PHONE_TYPE
    jsr PRINT_Z
    lda #'['
    jsr K_CHROUT
    jsr PHONEBOOK_PRINT_FIELD
    lda #']'
    jsr K_CHROUT
    lda #' '
    jsr K_CHROUT
    jsr READ_LINE
    lda LINE_LEN
    beq _phonebook_edit_type_keep
    jsr PHONEBOOK_VALIDATE_TYPE_LINE
    bcc _phonebook_edit_type_store
    lda #<MSG_PHONE_BAD_TYPE
    ldx #>MSG_PHONE_BAD_TYPE
    jsr PRINT_Z
    bra _phonebook_edit_type_loop
_phonebook_edit_type_store:
    jsr PHONE_COPY_LINE_TO_FIELD
_phonebook_edit_type_keep:
    rts

PHONEBOOK_PICK_ENTRY:
    lda PHONE_COUNT
    bne _phonebook_pick_has
    lda #<MSG_PHONE_EMPTY
    ldx #>MSG_PHONE_EMPTY
    jsr PHONEBOOK_NOTICE
    sec
    rts
_phonebook_pick_has:
    lda #1
    sta PHONE_PICK_MODE
    jsr PHONEBOOK_DRAW
    lda #0
    sta PHONE_PICK_MODE
    jsr PHONEBOOK_GET_KEY
    cmp #CR
    beq _phonebook_pick_cancel
    pha
    jsr K_CHROUT
    lda #CR
    jsr K_CHROUT
    pla
    cmp #'1'
    bcc _phonebook_pick_bad
    cmp #'1'+PHONE_PAGE_SIZE
    bcs _phonebook_pick_bad
    sec
    sbc #'1'
    sta TEMP_A
    jsr PHONEBOOK_PAGE_START
    clc
    adc TEMP_A
    cmp PHONE_COUNT
    bcs _phonebook_pick_bad
    sta PHONE_INDEX
    clc
    rts
_phonebook_pick_cancel:
    sec
    rts
_phonebook_pick_bad:
    lda #<MSG_PHONE_BAD_ENTRY
    ldx #>MSG_PHONE_BAD_ENTRY
    jsr PHONEBOOK_NOTICE
    sec
    rts

PHONEBOOK_NOTICE:
    jsr PRINT_Z
    jmp PHONEBOOK_WAIT_KEY

PHONEBOOK_SAVE_AND_NOTICE:
    jsr PHONEBOOK_SAVE
    bcs _phonebook_save_fail
    lda #<MSG_PHONE_SAVED
    ldx #>MSG_PHONE_SAVED
    jsr PHONEBOOK_NOTICE
    rts
_phonebook_save_fail:
    lda #<MSG_PHONE_SAVE_FAIL
    ldx #>MSG_PHONE_SAVE_FAIL
    jsr PHONEBOOK_NOTICE
    rts

PHONEBOOK_WAIT_KEY:
    lda #<MSG_PRESS_KEY
    ldx #>MSG_PRESS_KEY
    jsr PRINT_Z
PHONEBOOK_GET_KEY:
    jsr K_GETIN
    beq PHONEBOOK_GET_KEY
    rts

PHONEBOOK_LOAD:
    lda #0
    sta PHONE_COUNT
    sta PHONE_EOF_PENDING
    jsr PHONEBOOK_OPEN_READ
    bcc _phonebook_load_loop
    rts

_phonebook_load_loop:
    jsr PHONEBOOK_READ_LINE
    bcs _phonebook_load_close
    lda LINE_LEN
    beq _phonebook_load_loop
    lda PHONE_COUNT
    cmp #PHONE_MAX
    bcs _phonebook_load_close
    sta PHONE_INDEX
    jsr PHONEBOOK_PARSE_LINE_ENTRY
    bcs _phonebook_load_loop
    inc PHONE_COUNT
    bra _phonebook_load_loop

_phonebook_load_close:
    jmp PHONEBOOK_CLOSE

PHONEBOOK_SAVE:
    jsr PHONEBOOK_OPEN_WRITE
    bcc _phonebook_save_loop_start
    sec
    rts

_phonebook_save_loop_start:
    lda #0
    sta PHONE_LINE_INDEX
_phonebook_save_loop:
    lda PHONE_LINE_INDEX
    cmp PHONE_COUNT
    beq _phonebook_save_close_ok
    sta PHONE_INDEX
    jsr PHONE_SET_NAME_FIELD
    jsr PHONEBOOK_WRITE_FIELD
    jsr PHONEBOOK_WRITE_COMMA
    jsr PHONE_SET_HOST_FIELD
    jsr PHONEBOOK_WRITE_FIELD
    jsr PHONEBOOK_WRITE_COMMA
    jsr PHONE_SET_PORT_FIELD
    jsr PHONEBOOK_WRITE_FIELD
    jsr PHONEBOOK_WRITE_COMMA
    jsr PHONE_SET_TYPE_FIELD
    jsr PHONEBOOK_WRITE_FIELD
    jsr PHONEBOOK_WRITE_COMMA
    jsr PHONE_SET_USER_FIELD
    jsr PHONEBOOK_WRITE_FIELD
    jsr PHONEBOOK_WRITE_COMMA
    lda #CR
    jsr K_CHROUT
    inc PHONE_LINE_INDEX
    bra _phonebook_save_loop

_phonebook_save_close_ok:
    jsr PHONEBOOK_CLOSE
    clc
    rts

PHONEBOOK_OPEN_READ:
    lda #PHONE_READ_NAME_END-PHONE_READ_NAME
    ldx #<PHONE_READ_NAME
    ldy #>PHONE_READ_NAME
    jsr K_SETNAM
    lda #PHONE_LFN
    ldx #PHONE_DEVICE
    ldy #PHONE_SA
    jsr K_SETLFS
    jsr K_OPEN
    jsr K_READST
    bne _phonebook_open_read_fail
    ldx #PHONE_LFN
    jsr K_CHKIN
    jsr K_READST
    bne _phonebook_open_read_fail
    clc
    rts
_phonebook_open_read_fail:
    jsr PHONEBOOK_CLOSE
    sec
    rts

PHONEBOOK_OPEN_WRITE:
    lda #PHONE_WRITE_NAME_END-PHONE_WRITE_NAME
    ldx #<PHONE_WRITE_NAME
    ldy #>PHONE_WRITE_NAME
    jsr K_SETNAM
    lda #PHONE_LFN
    ldx #PHONE_DEVICE
    ldy #PHONE_SA
    jsr K_SETLFS
    jsr K_OPEN
    ldx #PHONE_LFN
    jsr K_CHKOUT
    clc
    rts

PHONEBOOK_CLOSE:
    jsr K_CLRCHN
    lda #PHONE_LFN
    jsr K_CLOSE
    rts

PHONEBOOK_READ_LINE:
    lda PHONE_EOF_PENDING
    beq _phonebook_read_line_start
    sec
    rts
_phonebook_read_line_start:
    lda #0
    sta LINE_LEN
_phonebook_read_line_loop:
    jsr K_CHRIN
    sta TEMP_A
    jsr K_READST
    sta TEMP_HI
    beq _phonebook_read_line_check_char
    lda #1
    sta PHONE_EOF_PENDING
_phonebook_read_line_check_char:
    lda TEMP_A
    cmp #LF
    beq _phonebook_read_line_done
    cmp #CR
    beq _phonebook_read_line_done
    ldx LINE_LEN
    cpx #79
    bcs _phonebook_read_line_status
    sta LINEBUF,x
    inc LINE_LEN
_phonebook_read_line_status:
    lda TEMP_HI
    beq _phonebook_read_line_loop
    lda LINE_LEN
    beq _phonebook_read_line_eof
_phonebook_read_line_done:
    ldx LINE_LEN
    lda #0
    sta LINEBUF,x
    clc
    rts
_phonebook_read_line_eof:
    sec
    rts

PHONEBOOK_PARSE_LINE_ENTRY:
    jsr PHONE_CLEAR_ENTRY
    lda #0
    sta PHONE_LINE_INDEX
    jsr PHONE_SET_NAME_FIELD
    jsr PHONEBOOK_PARSE_FIELD
    jsr PHONE_SET_HOST_FIELD
    jsr PHONEBOOK_PARSE_FIELD
    jsr PHONE_SET_PORT_FIELD
    jsr PHONEBOOK_PARSE_FIELD
    jsr PHONE_SET_TYPE_FIELD
    jsr PHONEBOOK_PARSE_FIELD
    jsr PHONE_SET_USER_FIELD
    jsr PHONEBOOK_PARSE_FIELD
    jsr PHONE_SET_NAME_FIELD
    jsr PHONEBOOK_FIELD_EMPTY
    bcs _phonebook_parse_fail
    jsr PHONE_SET_HOST_FIELD
    jsr PHONEBOOK_FIELD_EMPTY
    bcs _phonebook_parse_fail
    jsr PHONE_SET_PORT_FIELD
    jsr PHONEBOOK_FIELD_EMPTY
    bcs _phonebook_parse_fail
    jsr PHONEBOOK_PARSE_PORT_FIELD
    bcs _phonebook_parse_fail
    jsr PHONEBOOK_NORMALIZE_TYPE_FIELD
    bcs _phonebook_parse_fail
    clc
    rts
_phonebook_parse_fail:
    sec
    rts

PHONEBOOK_PARSE_FIELD:
    jsr PHONE_FIELD_PTR
    ldy #0
    ldx PHONE_LINE_INDEX
_phonebook_parse_field_trim:
    lda LINEBUF,x
    cmp #' '
    bne _phonebook_parse_field_loop
    inx
    bra _phonebook_parse_field_trim
_phonebook_parse_field_loop:
    lda LINEBUF,x
    beq _phonebook_parse_field_done
    cmp #','
    beq _phonebook_parse_field_delim
    cmp #'|'
    beq _phonebook_parse_field_delim
    cpy PHONE_FIELD_MAX_VAR
    bcs _phonebook_parse_field_skip
    sta (PTR_LO),y
    iny
_phonebook_parse_field_skip:
    inx
    bra _phonebook_parse_field_loop
_phonebook_parse_field_delim:
    inx
_phonebook_parse_field_done:
    stx PHONE_LINE_INDEX
    lda #0
    sta (PTR_LO),y
    rts

PHONEBOOK_PARSE_PORT_FIELD:
    jsr PHONE_SET_PORT_FIELD
    jsr PHONE_COPY_FIELD_TO_LINE
    jmp PARSE_PORT

PHONEBOOK_WRITE_COMMA:
    lda #','
    jmp K_CHROUT

PHONEBOOK_VALIDATE_TYPE_LINE:
    lda LINE_LEN
    beq _phonebook_type_bad
    lda LINEBUF
    cmp #'A'
    beq _phonebook_type_a
    cmp #'a'
    beq _phonebook_type_a
    cmp #'P'
    beq _phonebook_type_p
    cmp #'p'
    beq _phonebook_type_p
_phonebook_type_bad:
    sec
    rts
_phonebook_type_a:
    lda #'A'
    bra _phonebook_type_store_line
_phonebook_type_p:
    lda #'P'
_phonebook_type_store_line:
    sta LINEBUF
    lda #1
    sta LINE_LEN
    lda #0
    sta LINEBUF+1
    clc
    rts

PHONEBOOK_NORMALIZE_TYPE_FIELD:
    jsr PHONE_SET_TYPE_FIELD
    jsr PHONE_COPY_FIELD_TO_LINE
    jsr PHONEBOOK_VALIDATE_TYPE_LINE
    bcs _phonebook_normalize_type_fail
    jsr PHONE_COPY_LINE_TO_FIELD
    clc
    rts
_phonebook_normalize_type_fail:
    sec
    rts

PHONEBOOK_APPLY_TYPE:
    jsr PHONE_SET_TYPE_FIELD
    jsr PHONE_FIELD_PTR
    ldy #0
    lda (PTR_LO),y
    cmp #'P'
    beq _phonebook_apply_petscii
    cmp #'p'
    beq _phonebook_apply_petscii
    lda #1
    sta TERM_MODE
    jsr USE_DEFAULT_FONT
    lda #0
    jmp SET_XLATE_A
_phonebook_apply_petscii:
    lda #0
    sta TERM_MODE
    jsr USE_DEFAULT_FONT
    lda #0
    jmp SET_XLATE_A

PHONEBOOK_WRITE_FIELD:
    jsr PHONE_FIELD_PTR
    ldy #0
_phonebook_write_field_loop:
    lda (PTR_LO),y
    beq _phonebook_write_field_done
    jsr K_CHROUT
    iny
    bra _phonebook_write_field_loop
_phonebook_write_field_done:
    rts

PHONEBOOK_PRINT_FIELD:
    jsr PHONE_FIELD_PTR
    ldy #0
_phonebook_print_field_loop:
    lda (PTR_LO),y
    beq _phonebook_print_field_done
    jsr ASCII_TO_PETSCII_TEXT
    jsr K_CHROUT
    iny
    bra _phonebook_print_field_loop
_phonebook_print_field_done:
    rts

PHONEBOOK_PRINT_FIELD_LIMIT:
    sta TEMP_HI
    jsr PHONE_FIELD_PTR
    ldy #0
_phonebook_print_field_limit_loop:
    cpy TEMP_HI
    bcs _phonebook_print_field_limit_done
    lda (PTR_LO),y
    beq _phonebook_print_field_limit_done
    jsr ASCII_TO_PETSCII_TEXT
    jsr K_CHROUT
    iny
    bra _phonebook_print_field_limit_loop
_phonebook_print_field_limit_done:
    rts

PHONEBOOK_FIELD_EMPTY:
    jsr PHONE_FIELD_PTR
    ldy #0
    lda (PTR_LO),y
    beq _phonebook_field_empty_yes
    clc
    rts
_phonebook_field_empty_yes:
    sec
    rts

PHONE_COPY_LINE_TO_FIELD:
    jsr PHONE_FIELD_PTR
    ldy #0
_phone_copy_line_loop:
    cpy PHONE_FIELD_MAX_VAR
    bcs _phone_copy_line_done
    lda LINEBUF,y
    beq _phone_copy_line_done
    sta (PTR_LO),y
    iny
    bra _phone_copy_line_loop
_phone_copy_line_done:
    lda #0
    sta (PTR_LO),y
    rts

PHONE_COPY_FIELD_TO_LINE:
    jsr PHONE_FIELD_PTR
    ldy #0
_phone_copy_field_loop:
    cpy PHONE_FIELD_MAX_VAR
    bcs _phone_copy_field_done
    lda (PTR_LO),y
    beq _phone_copy_field_done
    sta LINEBUF,y
    iny
    bra _phone_copy_field_loop
_phone_copy_field_done:
    sty LINE_LEN
    lda #0
    sta LINEBUF,y
    rts

PHONEBOOK_DELETE_CURRENT:
    lda PHONE_INDEX
    sta PHONE_WORK_INDEX
_phonebook_delete_loop:
    lda PHONE_WORK_INDEX
    clc
    adc #1
    cmp PHONE_COUNT
    bcs _phonebook_delete_clear_last
    sta PHONE_INDEX
    jsr PHONE_ENTRY_PTR
    lda PTR_LO
    sta PHONE_COPY_SRC_ABS+1
    lda PTR_HI
    sta PHONE_COPY_SRC_ABS+2
    lda PHONE_WORK_INDEX
    sta PHONE_INDEX
    jsr PHONE_ENTRY_PTR
    lda PTR_LO
    sta PHONE_COPY_DST_ABS+1
    lda PTR_HI
    sta PHONE_COPY_DST_ABS+2
    jsr PHONE_COPY_ENTRY_ABS
    inc PHONE_WORK_INDEX
    bra _phonebook_delete_loop

_phonebook_delete_clear_last:
    dec PHONE_COUNT
    lda PHONE_COUNT
    sta PHONE_INDEX
    jmp PHONE_CLEAR_ENTRY

PHONE_COPY_ENTRY_ABS:
    ldy #0
PHONE_COPY_ENTRY_LOOP:
PHONE_COPY_SRC_ABS:
    lda $ffff,y
PHONE_COPY_DST_ABS:
    sta $ffff,y
    iny
    cpy #PHONE_ENTRY_SIZE
    bne PHONE_COPY_ENTRY_LOOP
    rts

PHONE_CLEAR_ENTRY:
    jsr PHONE_ENTRY_PTR
    ldy #0
    lda #0
_phone_clear_entry_loop:
    sta (PTR_LO),y
    iny
    cpy #PHONE_ENTRY_SIZE
    bne _phone_clear_entry_loop
    rts

PHONE_ENTRY_PTR:
    lda #<PHONEBOOK
    sta PTR_LO
    lda #>PHONEBOOK
    sta PTR_HI
    ldx PHONE_INDEX
    beq _phone_entry_ptr_done
_phone_entry_ptr_loop:
    clc
    lda PTR_LO
    adc #PHONE_ENTRY_SIZE
    sta PTR_LO
    bcc _phone_entry_ptr_no_carry
    inc PTR_HI
_phone_entry_ptr_no_carry:
    dex
    bne _phone_entry_ptr_loop
_phone_entry_ptr_done:
    rts

PHONE_FIELD_PTR:
    jsr PHONE_ENTRY_PTR
    clc
    lda PTR_LO
    adc PHONE_FIELD_OFFSET_VAR
    sta PTR_LO
    bcc _phone_field_ptr_done
    inc PTR_HI
_phone_field_ptr_done:
    rts

PHONE_SET_NAME_FIELD:
    lda #PHONE_NAME_OFF
    sta PHONE_FIELD_OFFSET_VAR
    lda #PHONE_NAME_MAX
    sta PHONE_FIELD_MAX_VAR
    rts

PHONE_SET_HOST_FIELD:
    lda #PHONE_HOST_OFF
    sta PHONE_FIELD_OFFSET_VAR
    lda #PHONE_HOST_MAX
    sta PHONE_FIELD_MAX_VAR
    rts

PHONE_SET_PORT_FIELD:
    lda #PHONE_PORT_OFF
    sta PHONE_FIELD_OFFSET_VAR
    lda #PHONE_PORT_MAX
    sta PHONE_FIELD_MAX_VAR
    rts

PHONE_SET_TYPE_FIELD:
    lda #PHONE_TYPE_OFF
    sta PHONE_FIELD_OFFSET_VAR
    lda #PHONE_TYPE_MAX
    sta PHONE_FIELD_MAX_VAR
    rts

PHONE_SET_USER_FIELD:
    lda #PHONE_USER_OFF
    sta PHONE_FIELD_OFFSET_VAR
    lda #PHONE_USER_MAX
    sta PHONE_FIELD_MAX_VAR
    rts

;-----------------------------------------------------------------------------
; Input helpers
;-----------------------------------------------------------------------------
READ_IP_AND_SET_LOCAL:
    jsr READ_IP_PROMPT
    bcs IP_SET_DONE
    lda #<MIP_SET_LOCAL_IP
    ldx #>MIP_SET_LOCAL_IP
    bra SET_IPBUF_TARGET
READ_IP_AND_SET_GATEWAY:
    jsr READ_IP_PROMPT
    bcs IP_SET_DONE
    lda #<MIP_SET_GATEWAY
    ldx #>MIP_SET_GATEWAY
    bra SET_IPBUF_TARGET
READ_IP_AND_SET_SUBNET:
    jsr READ_IP_PROMPT
    bcs IP_SET_DONE
    lda #<MIP_SET_SUBNET
    ldx #>MIP_SET_SUBNET
    bra SET_IPBUF_TARGET
READ_IP_AND_SET_DNS:
    jsr READ_IP_PROMPT
    bcs IP_SET_DONE
    lda #<MIP_SET_DNS
    ldx #>MIP_SET_DNS
    bra SET_IPBUF_TARGET
READ_IP_AND_SET_REMOTE:
    jsr READ_IP_PROMPT
    bcs IP_SET_DONE
    lda #<MIP_SET_REMOTE_IP
    ldx #>MIP_SET_REMOTE_IP

SET_IPBUF_TARGET:
    sta STAGE_TARGET_LO_VAR
    stx STAGE_TARGET_HI_VAR
SET_IPBUF_STAGED:
    lda IPBUF+0
    sta STAGE_ARG_A_VAR
    lda IPBUF+1
    sta STAGE_ARG_X_VAR
    lda IPBUF+2
    sta STAGE_ARG_Y_VAR
    lda IPBUF+3
    sta STAGE_ARG_Z_VAR
    jsr STAGED_CALL
    clc
IP_SET_DONE:
    rts

SET_REMOTE_FROM_IPBUF:
    lda #<MIP_SET_REMOTE_IP
    sta STAGE_TARGET_LO_VAR
    lda #>MIP_SET_REMOTE_IP
    sta STAGE_TARGET_HI_VAR
    jsr SET_IPBUF_STAGED
    clc
    rts

READ_IP_PROMPT:
    jsr PRINT_Z
    jsr READ_LINE
    jsr PARSE_IP
    bcc _ip_ok
    lda #<MSG_BAD_IP
    ldx #>MSG_BAD_IP
    jsr PRINT_Z
    sec
    rts
_ip_ok:
    clc
    rts

READ_LINE:
    lda #0
    sta LINE_LEN
READ_LINE_LOOP:
    jsr K_GETIN
    beq READ_LINE_LOOP
    cmp #CR
    beq READ_LINE_DONE
    cmp #DEL
    beq READ_LINE_DEL
    cmp #32
    bcc READ_LINE_LOOP
    cmp #127
    bcs READ_LINE_LOOP
    ldx LINE_LEN
    cpx #79
    bcs READ_LINE_LOOP
    sta LINEBUF,x
    inc LINE_LEN
    jsr K_CHROUT
    bra READ_LINE_LOOP

READ_LINE_DEL:
    ldx LINE_LEN
    beq READ_LINE_LOOP
    dec LINE_LEN
    lda #DEL
    jsr K_CHROUT
    lda #' '
    jsr K_CHROUT
    lda #DEL
    jsr K_CHROUT
    bra READ_LINE_LOOP

READ_LINE_DONE:
    ldx LINE_LEN
    lda #0
    sta LINEBUF,x
    lda #CR
    jsr K_CHROUT
    rts

GET_KEY:
    jsr K_GETIN
    beq GET_KEY
    pha
    jsr K_CHROUT
    lda #CR
    jsr K_CHROUT
    pla
    rts

;-----------------------------------------------------------------------------
; Parsers
;-----------------------------------------------------------------------------
PARSE_IP:
    lda #0
    sta IPBUF+0
    sta IPBUF+1
    sta IPBUF+2
    sta IPBUF+3
    sta OCTET_INDEX
    sta CUR_VALUE
    sta DIGIT_SEEN
    ldx #0

PARSE_IP_LOOP:
    lda LINEBUF,x
    beq PARSE_IP_END
    cmp #'.'
    beq PARSE_IP_DOT
    cmp #'0'
    bcc PARSE_IP_FAIL
    cmp #'9'+1
    bcs PARSE_IP_FAIL
    sec
    sbc #'0'
    sta DIGIT_VALUE
    jsr CUR_MUL10_ADD_DIGIT
    bcs PARSE_IP_FAIL
    lda #1
    sta DIGIT_SEEN
    inx
    bra PARSE_IP_LOOP

PARSE_IP_DOT:
    lda DIGIT_SEEN
    beq PARSE_IP_FAIL
    ldy OCTET_INDEX
    cpy #3
    bcs PARSE_IP_FAIL
    lda CUR_VALUE
    sta IPBUF,y
    inc OCTET_INDEX
    lda #0
    sta CUR_VALUE
    sta DIGIT_SEEN
    inx
    bra PARSE_IP_LOOP

PARSE_IP_END:
    lda DIGIT_SEEN
    beq PARSE_IP_FAIL
    lda OCTET_INDEX
    cmp #3
    bne PARSE_IP_FAIL
    ldy OCTET_INDEX
    lda CUR_VALUE
    sta IPBUF,y
    clc
    rts

PARSE_IP_FAIL:
    sec
    rts

CUR_MUL10_ADD_DIGIT:
    lda CUR_VALUE
    asl
    bcs _cur_fail
    sta TEMP_A
    asl
    bcs _cur_fail
    asl
    bcs _cur_fail
    clc
    adc TEMP_A
    bcs _cur_fail
    clc
    adc DIGIT_VALUE
    bcs _cur_fail
    sta CUR_VALUE
    clc
    rts
_cur_fail:
    sec
    rts

PARSE_PORT:
    lda #0
    sta PORT_LO
    sta PORT_HI
    ldx #0
_port_loop:
    lda LINEBUF,x
    beq _port_end
    cmp #'0'
    bcc _port_fail
    cmp #'9'+1
    bcs _port_fail
    sec
    sbc #'0'
    sta DIGIT_VALUE
    jsr PORT_MUL10_ADD_DIGIT
    bcs _port_fail
    inx
    bra _port_loop
_port_end:
    cpx #0
    beq _port_fail
    lda PORT_LO
    ora PORT_HI
    beq _port_fail
    clc
    rts
_port_fail:
    sec
    rts

PORT_MUL10_ADD_DIGIT:
    lda PORT_LO
    asl
    sta TEMP_LO
    lda PORT_HI
    rol
    sta TEMP_HI
    bcs _port_overflow

    lda PORT_LO
    asl
    sta PORT_LO
    lda PORT_HI
    rol
    sta PORT_HI
    bcs _port_overflow
    lda PORT_LO
    asl
    sta PORT_LO
    lda PORT_HI
    rol
    sta PORT_HI
    bcs _port_overflow
    lda PORT_LO
    asl
    sta PORT_LO
    lda PORT_HI
    rol
    sta PORT_HI
    bcs _port_overflow

    lda PORT_LO
    clc
    adc TEMP_LO
    sta PORT_LO
    lda PORT_HI
    adc TEMP_HI
    sta PORT_HI
    bcs _port_overflow

    lda PORT_LO
    clc
    adc DIGIT_VALUE
    sta PORT_LO
    lda PORT_HI
    adc #0
    sta PORT_HI
    bcs _port_overflow
    clc
    rts
_port_overflow:
    sec
    rts

;-----------------------------------------------------------------------------
; Mega-IP call helpers
;-----------------------------------------------------------------------------
SET_XLATE_A:
    sta ARG_A_VAR
    lda #0
    sta ARG_X_VAR
    sta ARG_Y_VAR
    lda #<MIP_SET_XLATE
    ldx #>MIP_SET_XLATE
    jmp FAR_CALL_AXY

SEND_BYTE_A:
    sta ARG_A_VAR
    lda #0
    sta ARG_X_VAR
    sta ARG_Y_VAR
    lda #<MIP_ML_SEND_BYTE
    ldx #>MIP_ML_SEND_BYTE
    jmp FAR_CALL_AXY

SEND_ANSI_CURSOR_KEY:
    sta TEMP_A
    cmp #$91
    beq _ansi_key_up
    cmp #$11
    beq _ansi_key_down
    cmp #$1d
    beq _ansi_key_right
    cmp #$9d
    beq _ansi_key_left
    lda TEMP_A
    clc
    rts

_ansi_key_up:
    lda #'A'
    bra _ansi_key_send_final
_ansi_key_down:
    lda #'B'
    bra _ansi_key_send_final
_ansi_key_right:
    lda #'C'
    bra _ansi_key_send_final
_ansi_key_left:
    lda #'D'

_ansi_key_send_final:
    pha
    lda #ESC
    jsr SEND_BYTE_A
    lda ANSI_CURSOR_APP_MODE
    beq _ansi_key_csi
    lda #'O'
    bra _ansi_key_prefix_done
_ansi_key_csi:
    lda #'['
_ansi_key_prefix_done:
    jsr SEND_BYTE_A
    pla
    jsr SEND_BYTE_A
    sec
    rts

FAR_CALL_NOARGS:
    sta FAR_TARGET_LO_VAR
    stx FAR_TARGET_HI_VAR
    lda #0
    sta ARG_A_VAR
    sta ARG_X_VAR
    sta ARG_Y_VAR
    bra FAR_CALL

FAR_CALL_AXY:
    sta FAR_TARGET_LO_VAR
    stx FAR_TARGET_HI_VAR
FAR_CALL:
    lda #$04
    sta FAR_BANK
    lda FAR_TARGET_HI_VAR
    sta FAR_ADDR_HI
    lda FAR_TARGET_LO_VAR
    sta FAR_ADDR_LO
    lda #0
    sta FAR_STATUS
    lda ARG_A_VAR
    sta FAR_ARG_A
    lda ARG_X_VAR
    sta FAR_ARG_X
    lda ARG_Y_VAR
    sta FAR_ARG_Y
    jsr K_JSRFAR
    rts

STAGED_CALL:
    lda #<ML_STAGE_LO
    sta PTR_LO
    lda #ML_STAGE_HI
    sta PTR_HI
    lda #ML_STAGE_BANK
    sta PTR_BANK
    lda #0
    sta PTR_TOP

    ldz #ML_STAGE_TARGET_LO
    lda STAGE_TARGET_LO_VAR
    sta [PTR_LO],z
    ldz #ML_STAGE_TARGET_HI
    lda STAGE_TARGET_HI_VAR
    sta [PTR_LO],z
    ldz #ML_STAGE_ARG_A
    lda STAGE_ARG_A_VAR
    sta [PTR_LO],z
    ldz #ML_STAGE_ARG_X
    lda STAGE_ARG_X_VAR
    sta [PTR_LO],z
    ldz #ML_STAGE_ARG_Y
    lda STAGE_ARG_Y_VAR
    sta [PTR_LO],z
    ldz #ML_STAGE_ARG_Z
    lda STAGE_ARG_Z_VAR
    sta [PTR_LO],z

    lda #<MIP_ML_CALL_STAGED
    ldx #>MIP_ML_CALL_STAGED
    jmp FAR_CALL_NOARGS

GET_IPBUF_TARGET:
    sta STAGE_TARGET_LO_VAR
    stx STAGE_TARGET_HI_VAR
    lda #0
    sta STAGE_ARG_A_VAR
    sta STAGE_ARG_X_VAR
    sta STAGE_ARG_Y_VAR
    sta STAGE_ARG_Z_VAR
    jsr STAGED_CALL
    sta IPBUF+0
    stx IPBUF+1
    sty IPBUF+2
    tza
    sta IPBUF+3
    rts

DNS_START_LINEBUF:
    lda #<MIP_DNS_START_BUF
    sta STAGE_TARGET_LO_VAR
    lda #>MIP_DNS_START_BUF
    sta STAGE_TARGET_HI_VAR
    lda #<LINEBUF
    sta STAGE_ARG_A_VAR
    lda #>LINEBUF
    sta STAGE_ARG_X_VAR
    lda #$00
    sta STAGE_ARG_Y_VAR
    lda LINE_LEN
    sta STAGE_ARG_Z_VAR
    jmp STAGED_CALL

PETSCII_TO_ASCII_KEY:
    cmp #DEL
    bne _key_not_delete
    lda #$08
    rts

_key_not_delete:
    cmp #$c1
    bcc _key_maybe_lower
    cmp #$db
    bcs _key_maybe_lower
    and #$7f
    rts

_key_maybe_lower:
    cmp #$41
    bcc _key_ascii_done
    cmp #$5b
    bcs _key_ascii_done
    ora #$20
_key_ascii_done:
    rts

;-----------------------------------------------------------------------------
; Display / timing
;-----------------------------------------------------------------------------
USE_DEFAULT_FONT:
    jsr UNLOCK_VIC_IV
    lda #$00
    sta CHARPTR_LO
    lda #$10
    sta CHARPTR_HI
    lda #$00
    sta CHARPTR_BANK
    lda #$0e
    jsr K_CHROUT
    rts

USE_CP437_FONT:
    jsr UNLOCK_VIC_IV
    lda #$40
    tsb VIC_CTRL2
    lda #$80
    tsb VIC_HOTREGS
    lda #$00
    sta CHARPTR_LO
    lda #$a0
    sta CHARPTR_HI
    lda #$05
    sta CHARPTR_BANK
    rts

UNLOCK_VIC_IV:
    lda #$47
    sta VIC_KEY
    lda #$53
    sta VIC_KEY
    rts

CURSOR_SPRITE_INIT:
    jsr UNLOCK_VIC_IV
    lda #<CURSOR_SPRITE_PTRS
    sta VIC4_SPRPTRADRLSB
    lda #>CURSOR_SPRITE_PTRS
    sta VIC4_SPRPTRADRMSB
    lda #$80
    sta VIC4_SPRPTRBNK

    lda #<(CURSOR_SPRITE_SHAPE / 64)
    sta CURSOR_SPRITE_PTRS
    lda #>(CURSOR_SPRITE_SHAPE / 64)
    sta CURSOR_SPRITE_PTRS+1

    lda SPRITE_X_MSB
    and #%11111110
    sta SPRITE_X_MSB
    lda VIC4_SPRXMSB9
    and #%11111110
    sta VIC4_SPRXMSB9
    lda VIC4_SPRYMSB8
    and #%11111110
    sta VIC4_SPRYMSB8
    lda VIC4_SPRYMSB9
    and #%11111110
    sta VIC4_SPRYMSB9
    lda SPRITE_X_EXPAND
    and #%11111110
    sta SPRITE_X_EXPAND
    lda SPRITE_Y_EXPAND
    and #%11111110
    sta SPRITE_Y_EXPAND
    lda SPRITE_MULTICOLOR
    and #%11111110
    sta SPRITE_MULTICOLOR
    lda SPRITE_PRIORITY
    and #%11111110
    sta SPRITE_PRIORITY

    lda #COLOR_WHITE
    sta SPRITE0_COLOR
    jsr CURSOR_SPRITE_UPDATE
    lda SPRITE_ENABLE
    ora #%00000001
    sta SPRITE_ENABLE
    rts

CURSOR_SPRITE_DISABLE:
    lda SPRITE_ENABLE
    and #%11111110
    sta SPRITE_ENABLE
    rts

CURSOR_SPRITE_SHOW:
    jsr CURSOR_SPRITE_UPDATE
    lda SPRITE_ENABLE
    ora #%00000001
    sta SPRITE_ENABLE
    rts

CURSOR_SPRITE_UPDATE:
    lda #0
    sta CURSOR_SPRITE_X_HI
    lda ASCII_COL
    asl a
    rol CURSOR_SPRITE_X_HI
    asl a
    rol CURSOR_SPRITE_X_HI
    clc
    adc #CURSOR_SPRITE_X0
    sta SPRITE0_X
    lda CURSOR_SPRITE_X_HI
    adc #0
    beq _cursor_x_low
    lda SPRITE_X_MSB
    ora #%00000001
    sta SPRITE_X_MSB
    bra _cursor_y
_cursor_x_low:
    lda SPRITE_X_MSB
    and #%11111110
    sta SPRITE_X_MSB
_cursor_y:
    lda ASCII_ROW
    asl a
    asl a
    asl a
    clc
    adc #CURSOR_SPRITE_Y0
    sta SPRITE0_Y
    rts

PREPARE_MENU_DISPLAY:
    lda TERM_MODE
    beq _prepare_done
    jsr CURSOR_SPRITE_DISABLE
    jsr USE_DEFAULT_FONT
    lda #CLR
    jsr K_CHROUT
_prepare_done:
    rts

DRAW_MAIN_HEADER:
    jsr CURSOR_SPRITE_DISABLE
    jsr USE_DEFAULT_FONT
    lda #<MSG_TITLE
    ldx #>MSG_TITLE
    jmp PRINT_Z

ASCII_START_SCREEN:
    lda #CLR
    jsr K_CHROUT
    jsr USE_CP437_FONT
    jsr ANSI_RESET_ATTR
    jsr ASCII_CLEAR_SCREEN_HOME
    lda #0
    sta ASCII_ROW
    sta ASCII_COL
    sta ANSI_STATE
    sta ASCII_SAVED_ROW
    sta ASCII_SAVED_COL
    sta ANSI_SAVED_BRIGHT
    sta ANSI_SAVED_INVERSE
    sta ANSI_SAVED_G0_GRAPHICS
    sta ANSI_SAVED_G1_GRAPHICS
    sta ANSI_SAVED_USE_G1
    sta ANSI_ORIGIN_MODE
    sta ANSI_G0_GRAPHICS
    sta ANSI_G1_GRAPHICS
    sta ANSI_USE_G1
    sta ANSI_INTERMEDIATE
    lda #1
    sta ASCII_WRAP_MODE
    lda #ASCII_DEFAULT_COLOR
    sta ASCII_SAVED_FG_COLOR
    lda #COLOR_BLACK
    sta ASCII_SAVED_BG_COLOR
    lda #0
    sta ASCII_SCROLL_TOP
    lda #SCREEN_ROWS-1
    sta ASCII_SCROLL_BOTTOM
    jsr ASCII_RECALC_PTR
    jsr CURSOR_SPRITE_INIT
    lda #<MSG_CONNECTED
    ldx #>MSG_CONNECTED
    jsr PRINT_ASCII_Z
    jmp CURSOR_SPRITE_UPDATE

PRINT_ASCII_Z:
    sta ASCII_STR_LO
    stx ASCII_STR_HI
_ascii_print_loop:
    lda ASCII_STR_LO
    sta PTR_LO
    lda ASCII_STR_HI
    sta PTR_HI
    ldy #0
    lda (PTR_LO),y
    beq _ascii_print_done
    inc ASCII_STR_LO
    bne _ascii_print_emit
    inc ASCII_STR_HI
_ascii_print_emit:
    jsr ASCII_PUT_BYTE
    bra _ascii_print_loop
_ascii_print_done:
    rts

ANSI_PUT_BYTE:
    sta ANSI_CHAR
    lda ANSI_STATE
    beq _ansi_normal
    cmp #1
    beq ANSI_ESC_STATE
    cmp #2
    beq ANSI_CSI_STATE
    cmp #3
    beq ANSI_CHARSET_STATE
    cmp #4
    beq ANSI_OSC_STATE
    cmp #5
    beq ANSI_OSC_ESC_STATE
    lda #0
    sta ANSI_STATE

_ansi_normal:
    lda ANSI_CHAR
    cmp #ESC
    bne _ansi_emit
    lda #1
    sta ANSI_STATE
    rts

_ansi_emit:
    cmp #$9b
    beq ANSI_INIT_CSI
    cmp #$9d
    beq ANSI_INIT_OSC
    cmp #$0e
    beq ANSI_SHIFT_OUT
    cmp #$0f
    beq ANSI_SHIFT_IN
    jmp ASCII_PUT_BYTE

ANSI_ESC_STATE:
    lda ANSI_CHAR
    cmp #ESC
    beq ANSI_RESTART_ESC
    lda #0
    sta ANSI_STATE
    lda ANSI_CHAR
    cmp #'['
    beq ANSI_INIT_CSI
    cmp #']'
    beq ANSI_INIT_OSC
    cmp #'('
    beq ANSI_SELECT_G0
    cmp #')'
    beq ANSI_SELECT_G1
    cmp #'c'
    beq ANSI_FULL_RESET
    cmp #'7'
    beq ANSI_SAVE_CURSOR
    cmp #'8'
    beq ANSI_RESTORE_CURSOR
    cmp #'D'
    beq ASCII_INDEX
    cmp #'E'
    beq ASCII_NEXT_LINE
    cmp #'M'
    beq ASCII_REVERSE_INDEX
    cmp #'H'
    beq _ansi_esc_done
    cmp #'='
    beq _ansi_esc_done
    cmp #'>'
    beq _ansi_esc_done
_ansi_esc_done:
    rts

ANSI_INIT_CSI:
    lda #2
    sta ANSI_STATE
    lda #0
    sta ANSI_PARAM0
    sta ANSI_PARAM1
    sta ANSI_PARAM2
    sta ANSI_PARAM3
    sta ANSI_PARAM4
    sta ANSI_PARAM5
    sta ANSI_PARAM6
    sta ANSI_PARAM7
    sta ANSI_PARAM_CUR
    sta ANSI_PARAM_INDEX
    sta ANSI_SAW_DIGIT
    sta ANSI_PRIVATE
    sta ANSI_INTERMEDIATE
    rts

ANSI_CSI_STATE:
    lda ANSI_CHAR
    cmp #ESC
    beq ANSI_RESTART_ESC
    lda ANSI_CHAR
    cmp #'0'
    bcc _ansi_csi_not_digit
    cmp #'9'+1
    bcs _ansi_csi_not_digit
    sec
    sbc #'0'
    sta DIGIT_VALUE
    jsr ANSI_CUR_MUL10_ADD_DIGIT
    lda #1
    sta ANSI_SAW_DIGIT
    rts

_ansi_csi_not_digit:
    cmp #';'
    beq _ansi_csi_semicolon
    cmp #'?'
    beq _ansi_csi_private
    cmp #'!'
    beq _ansi_csi_intermediate
    cmp #'>'
    beq _ansi_csi_ignore
    cmp #$40
    bcc _ansi_csi_ignore
    sta ANSI_FINAL
    jsr ANSI_STORE_PARAM
    lda #0
    sta ANSI_STATE
    lda ANSI_FINAL
    cmp #'A'
    beq ANSI_CURSOR_UP
    cmp #'B'
    beq ANSI_CURSOR_DOWN
    cmp #'C'
    beq ANSI_CURSOR_RIGHT
    cmp #'D'
    beq ANSI_CURSOR_LEFT
    cmp #'E'
    beq ANSI_CURSOR_NEXT_LINE
    cmp #'F'
    beq ANSI_CURSOR_PREV_LINE
    cmp #'G'
    beq ANSI_CURSOR_HORIZONTAL
    cmp #'H'
    beq ANSI_CURSOR_POSITION
    cmp #'f'
    beq ANSI_CURSOR_POSITION
    cmp #'`'
    beq ANSI_CURSOR_HORIZONTAL
    cmp #'a'
    beq ANSI_CURSOR_RIGHT
    cmp #'d'
    beq ANSI_CURSOR_VERTICAL
    cmp #'e'
    beq ANSI_CURSOR_DOWN
    cmp #'J'
    beq ANSI_ERASE_DISPLAY
    cmp #'K'
    beq ANSI_ERASE_LINE
    cmp #'@'
    beq ANSI_INSERT_CHARS
    cmp #'P'
    beq ANSI_DELETE_CHARS
    cmp #'X'
    beq ANSI_ERASE_CHARS
    cmp #'L'
    beq ANSI_INSERT_LINES
    cmp #'M'
    beq ANSI_DELETE_LINES
    cmp #'S'
    beq ANSI_SCROLL_UP
    cmp #'T'
    beq ANSI_SCROLL_DOWN
    cmp #'Z'
    beq ANSI_CURSOR_BACK_TAB
    cmp #'g'
    beq ANSI_TAB_CLEAR
    cmp #'m'
    beq ANSI_SGR
    cmp #'n'
    beq ANSI_DSR
    cmp #'r'
    beq ANSI_SET_SCROLL_REGION
    cmp #'c'
    beq ANSI_DEVICE_ATTRIBUTES
    cmp #'h'
    beq ANSI_MODE_SET
    cmp #'l'
    beq ANSI_MODE_RESET
    cmp #'p'
    beq ANSI_SOFT_RESET
    cmp #'s'
    beq ANSI_SAVE_CURSOR
    cmp #'u'
    beq ANSI_RESTORE_CURSOR
    rts

_ansi_csi_semicolon:
    jsr ANSI_STORE_PARAM
    rts

_ansi_csi_private:
    lda #1
    sta ANSI_PRIVATE
    rts

_ansi_csi_intermediate:
    sta ANSI_INTERMEDIATE
    rts

_ansi_csi_ignore:
    rts

ANSI_RESTART_ESC:
    lda #1
    sta ANSI_STATE
    rts

ANSI_INIT_OSC:
    lda #4
    sta ANSI_STATE
    rts

ANSI_OSC_STATE:
    lda ANSI_CHAR
    cmp #$07
    beq ANSI_OSC_DONE
    cmp #$9c
    beq ANSI_OSC_DONE
    cmp #ESC
    beq ANSI_OSC_ESC
    rts

ANSI_OSC_ESC:
    lda #5
    sta ANSI_STATE
    rts

ANSI_OSC_ESC_STATE:
    lda ANSI_CHAR
    cmp #$5c
    beq ANSI_OSC_DONE
    jmp ANSI_ESC_STATE

ANSI_OSC_DONE:
    lda #0
    sta ANSI_STATE
    rts

ANSI_SELECT_G0:
    lda #0
    sta ANSI_CHARSET_TARGET
    lda #3
    sta ANSI_STATE
    rts

ANSI_SELECT_G1:
    lda #1
    sta ANSI_CHARSET_TARGET
    lda #3
    sta ANSI_STATE
    rts

ANSI_CHARSET_STATE:
    lda ANSI_CHAR
    cmp #ESC
    beq ANSI_RESTART_ESC
    lda #0
    sta ANSI_STATE
    lda ANSI_CHAR
    cmp #'0'
    beq _ansi_charset_graphics
    cmp #'B'
    beq _ansi_charset_ascii
    cmp #'A'
    beq _ansi_charset_ascii
    rts
_ansi_charset_graphics:
    lda ANSI_CHARSET_TARGET
    beq _ansi_g0_graphics
    lda #1
    sta ANSI_G1_GRAPHICS
    rts
_ansi_g0_graphics:
    lda #1
    sta ANSI_G0_GRAPHICS
    rts
_ansi_charset_ascii:
    lda ANSI_CHARSET_TARGET
    beq _ansi_g0_ascii
    lda #0
    sta ANSI_G1_GRAPHICS
    rts
_ansi_g0_ascii:
    lda #0
    sta ANSI_G0_GRAPHICS
    rts

ANSI_SHIFT_OUT:
    lda #1
    sta ANSI_USE_G1
    rts

ANSI_SHIFT_IN:
    lda #0
    sta ANSI_USE_G1
    rts

ANSI_STORE_PARAM:
    ldx ANSI_PARAM_INDEX
    cpx #0
    beq _ansi_store0
    cpx #1
    beq _ansi_store1
    cpx #2
    beq _ansi_store2
    cpx #3
    beq _ansi_store3
    cpx #4
    beq _ansi_store4
    cpx #5
    beq _ansi_store5
    cpx #6
    beq _ansi_store6
    cpx #7
    beq _ansi_store7
    bra _ansi_store_next
_ansi_store0:
    lda ANSI_PARAM_CUR
    sta ANSI_PARAM0
    bra _ansi_store_next
_ansi_store1:
    lda ANSI_PARAM_CUR
    sta ANSI_PARAM1
    bra _ansi_store_next
_ansi_store2:
    lda ANSI_PARAM_CUR
    sta ANSI_PARAM2
    bra _ansi_store_next
_ansi_store3:
    lda ANSI_PARAM_CUR
    sta ANSI_PARAM3
    bra _ansi_store_next
_ansi_store4:
    lda ANSI_PARAM_CUR
    sta ANSI_PARAM4
    bra _ansi_store_next
_ansi_store5:
    lda ANSI_PARAM_CUR
    sta ANSI_PARAM5
    bra _ansi_store_next
_ansi_store6:
    lda ANSI_PARAM_CUR
    sta ANSI_PARAM6
    bra _ansi_store_next
_ansi_store7:
    lda ANSI_PARAM_CUR
    sta ANSI_PARAM7
_ansi_store_next:
    inc ANSI_PARAM_INDEX
    lda #0
    sta ANSI_PARAM_CUR
    sta ANSI_SAW_DIGIT
    rts

ANSI_CUR_MUL10_ADD_DIGIT:
    lda ANSI_PARAM_CUR
    asl
    bcs _ansi_cur_cap
    sta TEMP_A
    asl
    bcs _ansi_cur_cap
    asl
    bcs _ansi_cur_cap
    clc
    adc TEMP_A
    bcs _ansi_cur_cap
    clc
    adc DIGIT_VALUE
    bcs _ansi_cur_cap
    sta ANSI_PARAM_CUR
    rts
_ansi_cur_cap:
    lda #$ff
    sta ANSI_PARAM_CUR
    rts

ANSI_GET_COUNT:
    lda ANSI_PARAM0
    bne _ansi_count_ok
    lda #1
_ansi_count_ok:
    sta TEMP_A
    rts

ANSI_CURSOR_UP:
    jsr ANSI_GET_COUNT
_ansi_up_loop:
    lda TEMP_A
    beq ANSI_MOVE_DONE
    lda ASCII_ROW
    cmp ASCII_SCROLL_TOP
    beq _ansi_up_dec
    bcc _ansi_up_dec
    dec ASCII_ROW
_ansi_up_dec:
    dec TEMP_A
    bra _ansi_up_loop

ANSI_CURSOR_DOWN:
    jsr ANSI_GET_COUNT
_ansi_down_loop:
    lda TEMP_A
    beq ANSI_MOVE_DONE
    lda ASCII_ROW
    cmp ASCII_SCROLL_BOTTOM
    bcs _ansi_down_dec
    inc ASCII_ROW
_ansi_down_dec:
    dec TEMP_A
    bra _ansi_down_loop

ANSI_CURSOR_RIGHT:
    jsr ANSI_GET_COUNT
_ansi_right_loop:
    lda TEMP_A
    beq ANSI_MOVE_DONE
    lda ASCII_COL
    cmp #SCREEN_COLS-1
    bcs _ansi_right_dec
    inc ASCII_COL
_ansi_right_dec:
    dec TEMP_A
    bra _ansi_right_loop

ANSI_CURSOR_LEFT:
    jsr ANSI_GET_COUNT
_ansi_left_loop:
    lda TEMP_A
    beq ANSI_MOVE_DONE
    lda ASCII_COL
    beq _ansi_left_dec
    dec ASCII_COL
_ansi_left_dec:
    dec TEMP_A
    bra _ansi_left_loop

ANSI_MOVE_DONE:
    jmp ASCII_RECALC_PTR

ANSI_CURSOR_BACK_TAB:
    jsr ANSI_GET_COUNT
_ansi_btab_loop:
    lda TEMP_A
    beq ANSI_MOVE_DONE
    lda ASCII_COL
    beq _ansi_btab_dec
    sec
    sbc #1
    and #$f8
    sta ASCII_COL
_ansi_btab_dec:
    dec TEMP_A
    bra _ansi_btab_loop

ANSI_CURSOR_NEXT_LINE:
    jsr ANSI_GET_COUNT
_ansi_cnl_loop:
    lda TEMP_A
    beq _ansi_cnl_done
    lda ASCII_ROW
    cmp ASCII_SCROLL_BOTTOM
    bcs _ansi_cnl_dec
    inc ASCII_ROW
_ansi_cnl_dec:
    dec TEMP_A
    bra _ansi_cnl_loop
_ansi_cnl_done:
    lda #0
    sta ASCII_COL
    jmp ASCII_RECALC_PTR

ANSI_CURSOR_PREV_LINE:
    jsr ANSI_GET_COUNT
_ansi_cpl_loop:
    lda TEMP_A
    beq _ansi_cpl_done
    lda ASCII_ROW
    cmp ASCII_SCROLL_TOP
    beq _ansi_cpl_dec
    bcc _ansi_cpl_dec
    dec ASCII_ROW
_ansi_cpl_dec:
    dec TEMP_A
    bra _ansi_cpl_loop
_ansi_cpl_done:
    lda #0
    sta ASCII_COL
    jmp ASCII_RECALC_PTR

ANSI_CURSOR_POSITION:
    lda ANSI_PARAM0
    bne _ansi_row_given
    lda #1
_ansi_row_given:
    sec
    sbc #1
    sta TEMP_LO
    lda ANSI_ORIGIN_MODE
    beq _ansi_row_screen
    lda TEMP_LO
    clc
    adc ASCII_SCROLL_TOP
    cmp ASCII_SCROLL_BOTTOM
    bcc _ansi_row_ok
    beq _ansi_row_ok
    lda ASCII_SCROLL_BOTTOM
    bra _ansi_row_ok
_ansi_row_screen:
    lda TEMP_LO
    cmp #SCREEN_ROWS
    bcc _ansi_row_ok
    lda #SCREEN_ROWS-1
_ansi_row_ok:
    sta ASCII_ROW

    lda ANSI_PARAM1
    bne _ansi_col_given
    lda #1
_ansi_col_given:
    sec
    sbc #1
    cmp #SCREEN_COLS
    bcc _ansi_col_ok
    lda #SCREEN_COLS-1
_ansi_col_ok:
    sta ASCII_COL
    jmp ASCII_RECALC_PTR

ANSI_CURSOR_HORIZONTAL:
    lda ANSI_PARAM0
    bne _ansi_hpa_given
    lda #1
_ansi_hpa_given:
    sec
    sbc #1
    cmp #SCREEN_COLS
    bcc _ansi_hpa_ok
    lda #SCREEN_COLS-1
_ansi_hpa_ok:
    sta ASCII_COL
    jmp ASCII_RECALC_PTR

ANSI_CURSOR_VERTICAL:
    lda ANSI_PARAM0
    bne _ansi_vpa_given
    lda #1
_ansi_vpa_given:
    sec
    sbc #1
    cmp #SCREEN_ROWS
    bcc _ansi_vpa_ok
    lda #SCREEN_ROWS-1
_ansi_vpa_ok:
    sta ASCII_ROW
    jmp ASCII_RECALC_PTR

ANSI_GET_EOL_COUNT:
    jsr ANSI_GET_COUNT
    lda #SCREEN_COLS
    sec
    sbc ASCII_COL
    sta TEMP_HI
    lda TEMP_A
    cmp TEMP_HI
    bcc _ansi_eol_count_ok
    lda TEMP_HI
    sta TEMP_A
_ansi_eol_count_ok:
    rts

ANSI_GET_ROWS_COUNT:
    jsr ANSI_GET_COUNT
    lda #SCREEN_ROWS
    sec
    sbc ASCII_ROW
    sta TEMP_HI
    lda TEMP_A
    cmp TEMP_HI
    bcc _ansi_rows_count_ok
    lda TEMP_HI
    sta TEMP_A
_ansi_rows_count_ok:
    rts

ANSI_GET_SCREEN_COUNT:
    jsr ANSI_GET_COUNT
    lda TEMP_A
    cmp #SCREEN_ROWS
    bcc _ansi_screen_count_ok
    lda #SCREEN_ROWS
    sta TEMP_A
_ansi_screen_count_ok:
    rts

ANSI_INSERT_CHARS:
    jsr ANSI_GET_EOL_COUNT
    lda TEMP_A
    beq _ansi_ich_done
    sta ASCII_WORK_COUNT
    lda ASCII_ROW
    sta ASCII_SRC_ROW
    sta ASCII_DST_ROW
    lda #SCREEN_COLS-1
    sta ASCII_WORK_DST_COL
_ansi_ich_copy:
    lda ASCII_WORK_DST_COL
    sec
    sbc ASCII_WORK_COUNT
    cmp ASCII_COL
    bcc _ansi_ich_clear
    sta ASCII_WORK_COL
    jsr ASCII_READ_SRC_CELL
    lda ASCII_WORK_DST_COL
    sta ASCII_WORK_COL
    jsr ASCII_WRITE_DST_CELL
    lda ASCII_WORK_DST_COL
    beq _ansi_ich_clear
    dec ASCII_WORK_DST_COL
    bra _ansi_ich_copy
_ansi_ich_clear:
    lda ASCII_COL
    sta TEMP_LO
    lda ASCII_WORK_COUNT
    sta TEMP_HI
    jsr ASCII_CLEAR_LINE_RANGE
_ansi_ich_done:
    jmp ASCII_RECALC_PTR

ANSI_DELETE_CHARS:
    jsr ANSI_GET_EOL_COUNT
    lda TEMP_A
    beq _ansi_dch_done
    sta ASCII_WORK_COUNT
    lda ASCII_ROW
    sta ASCII_SRC_ROW
    sta ASCII_DST_ROW
    lda ASCII_COL
    sta ASCII_WORK_DST_COL
_ansi_dch_copy:
    lda ASCII_WORK_DST_COL
    clc
    adc ASCII_WORK_COUNT
    cmp #SCREEN_COLS
    bcs _ansi_dch_clear
    sta ASCII_WORK_COL
    jsr ASCII_READ_SRC_CELL
    lda ASCII_WORK_DST_COL
    sta ASCII_WORK_COL
    jsr ASCII_WRITE_DST_CELL
    inc ASCII_WORK_DST_COL
    bra _ansi_dch_copy
_ansi_dch_clear:
    lda #SCREEN_COLS
    sec
    sbc ASCII_WORK_COUNT
    sta TEMP_LO
    lda ASCII_WORK_COUNT
    sta TEMP_HI
    jsr ASCII_CLEAR_LINE_RANGE
_ansi_dch_done:
    jmp ASCII_RECALC_PTR

ANSI_ERASE_CHARS:
    jsr ANSI_GET_EOL_COUNT
    lda TEMP_A
    beq _ansi_ech_done
    lda ASCII_COL
    sta TEMP_LO
    lda TEMP_A
    sta TEMP_HI
    jsr ASCII_CLEAR_LINE_RANGE
_ansi_ech_done:
    jmp ASCII_RECALC_PTR

ANSI_INSERT_LINES:
    jsr ANSI_GET_ROWS_COUNT
    lda TEMP_A
    beq _ansi_il_done
    sta ASCII_WORK_COUNT
    lda #SCREEN_ROWS-1
    sta ASCII_DST_ROW
_ansi_il_copy:
    lda ASCII_DST_ROW
    sec
    sbc ASCII_WORK_COUNT
    cmp ASCII_ROW
    bcc _ansi_il_clear
    sta ASCII_SRC_ROW
    jsr ASCII_COPY_SRC_TO_DST_ROW
    lda ASCII_DST_ROW
    beq _ansi_il_clear
    dec ASCII_DST_ROW
    bra _ansi_il_copy
_ansi_il_clear:
    lda ASCII_ROW
    sta ASCII_DST_ROW
    lda ASCII_WORK_COUNT
    sta TEMP_A
_ansi_il_clear_loop:
    lda TEMP_A
    beq _ansi_il_done
    jsr ASCII_CLEAR_DST_ROW
    inc ASCII_DST_ROW
    dec TEMP_A
    bra _ansi_il_clear_loop
_ansi_il_done:
    jmp ASCII_RECALC_PTR

ANSI_DELETE_LINES:
    jsr ANSI_GET_ROWS_COUNT
    lda TEMP_A
    beq _ansi_dl_done
    sta ASCII_WORK_COUNT
    lda ASCII_ROW
    sta ASCII_DST_ROW
_ansi_dl_copy:
    lda ASCII_DST_ROW
    clc
    adc ASCII_WORK_COUNT
    cmp #SCREEN_ROWS
    bcs _ansi_dl_clear
    sta ASCII_SRC_ROW
    jsr ASCII_COPY_SRC_TO_DST_ROW
    inc ASCII_DST_ROW
    bra _ansi_dl_copy
_ansi_dl_clear:
    lda ASCII_WORK_COUNT
    sta TEMP_A
_ansi_dl_clear_loop:
    lda TEMP_A
    beq _ansi_dl_done
    jsr ASCII_CLEAR_DST_ROW
    inc ASCII_DST_ROW
    dec TEMP_A
    bra _ansi_dl_clear_loop
_ansi_dl_done:
    jmp ASCII_RECALC_PTR

ANSI_SCROLL_UP:
    jsr ANSI_GET_SCREEN_COUNT
    lda TEMP_A
    beq _ansi_su_done
    sta ASCII_WORK_COUNT
    lda #0
    sta ASCII_DST_ROW
_ansi_su_copy:
    lda ASCII_DST_ROW
    clc
    adc ASCII_WORK_COUNT
    cmp #SCREEN_ROWS
    bcs _ansi_su_clear
    sta ASCII_SRC_ROW
    jsr ASCII_COPY_SRC_TO_DST_ROW
    inc ASCII_DST_ROW
    bra _ansi_su_copy
_ansi_su_clear:
    lda ASCII_WORK_COUNT
    sta TEMP_A
_ansi_su_clear_loop:
    lda TEMP_A
    beq _ansi_su_done
    jsr ASCII_CLEAR_DST_ROW
    inc ASCII_DST_ROW
    dec TEMP_A
    bra _ansi_su_clear_loop
_ansi_su_done:
    jmp ASCII_RECALC_PTR

ANSI_SCROLL_DOWN:
    jsr ANSI_GET_SCREEN_COUNT
    lda TEMP_A
    beq _ansi_sd_done
    sta ASCII_WORK_COUNT
    lda #SCREEN_ROWS-1
    sta ASCII_DST_ROW
_ansi_sd_copy:
    lda ASCII_DST_ROW
    sec
    sbc ASCII_WORK_COUNT
    bcc _ansi_sd_clear
    sta ASCII_SRC_ROW
    jsr ASCII_COPY_SRC_TO_DST_ROW
    lda ASCII_DST_ROW
    beq _ansi_sd_clear
    dec ASCII_DST_ROW
    bra _ansi_sd_copy
_ansi_sd_clear:
    lda #0
    sta ASCII_DST_ROW
    lda ASCII_WORK_COUNT
    sta TEMP_A
_ansi_sd_clear_loop:
    lda TEMP_A
    beq _ansi_sd_done
    jsr ASCII_CLEAR_DST_ROW
    inc ASCII_DST_ROW
    dec TEMP_A
    bra _ansi_sd_clear_loop
_ansi_sd_done:
    jmp ASCII_RECALC_PTR

ANSI_ERASE_LINE:
    lda ANSI_PARAM0
    cmp #1
    beq _ansi_el_start
    cmp #2
    beq _ansi_el_all

    lda ASCII_COL
    sta TEMP_LO
    lda #SCREEN_COLS
    sec
    sbc ASCII_COL
    sta TEMP_HI
    jmp ASCII_CLEAR_LINE_RANGE

_ansi_el_start:
    lda #0
    sta TEMP_LO
    lda ASCII_COL
    clc
    adc #1
    sta TEMP_HI
    jmp ASCII_CLEAR_LINE_RANGE

_ansi_el_all:
    lda #0
    sta TEMP_LO
    lda #SCREEN_COLS
    sta TEMP_HI
    jmp ASCII_CLEAR_LINE_RANGE

ANSI_ERASE_DISPLAY:
    lda ANSI_PARAM0
    cmp #3
    beq ASCII_CLEAR_SCREEN_HOME
    cmp #2
    beq ASCII_CLEAR_SCREEN_HOME
    cmp #1
    beq ASCII_CLEAR_TO_START_SCREEN
    cmp #0
    beq ASCII_CLEAR_TO_END_SCREEN
    rts

ANSI_SGR:
    lda ANSI_PARAM0
    cmp #38
    beq _ansi_sgr_ext0
    cmp #48
    beq _ansi_sgr_ext0_bg
    jsr ANSI_APPLY_SGR
    lda ANSI_PARAM_INDEX
    cmp #2
    bcc _ansi_sgr_done
    lda ANSI_PARAM1
    cmp #38
    beq _ansi_sgr_ext1
    cmp #48
    beq _ansi_sgr_ext1_bg
    jsr ANSI_APPLY_SGR
    lda ANSI_PARAM_INDEX
    cmp #3
    bcc _ansi_sgr_done
    lda ANSI_PARAM2
    jsr ANSI_APPLY_SGR
    lda ANSI_PARAM_INDEX
    cmp #4
    bcc _ansi_sgr_done
    lda ANSI_PARAM3
    jsr ANSI_APPLY_SGR
    lda ANSI_PARAM_INDEX
    cmp #5
    bcc _ansi_sgr_done
    lda ANSI_PARAM4
    jsr ANSI_APPLY_SGR
    lda ANSI_PARAM_INDEX
    cmp #6
    bcc _ansi_sgr_done
    lda ANSI_PARAM5
    jsr ANSI_APPLY_SGR
    lda ANSI_PARAM_INDEX
    cmp #7
    bcc _ansi_sgr_done
    lda ANSI_PARAM6
    jsr ANSI_APPLY_SGR
    lda ANSI_PARAM_INDEX
    cmp #8
    bcc _ansi_sgr_done
    lda ANSI_PARAM7
    jsr ANSI_APPLY_SGR
_ansi_sgr_done:
    rts

_ansi_sgr_ext0:
    lda ANSI_PARAM_INDEX
    cmp #3
    bcc _ansi_sgr_done
    lda ANSI_PARAM1
    cmp #5
    beq _ansi_sgr_ext0_256_fg
    cmp #2
    bne _ansi_sgr_done
    lda ANSI_PARAM_INDEX
    cmp #5
    bcc _ansi_sgr_done
    lda ANSI_PARAM2
    sta ANSI_RGB_R
    lda ANSI_PARAM3
    sta ANSI_RGB_G
    lda ANSI_PARAM4
    sta ANSI_RGB_B
    jmp ANSI_MAP_RGB_FG
_ansi_sgr_ext0_256_fg:
    lda ANSI_PARAM2
    jmp ANSI_MAP_256_FG

_ansi_sgr_ext0_bg:
    lda ANSI_PARAM_INDEX
    cmp #3
    bcc _ansi_sgr_done
    lda ANSI_PARAM1
    cmp #5
    beq _ansi_sgr_ext0_256_bg
    cmp #2
    bne _ansi_sgr_done
    lda ANSI_PARAM_INDEX
    cmp #5
    bcc _ansi_sgr_done
    lda ANSI_PARAM2
    sta ANSI_RGB_R
    lda ANSI_PARAM3
    sta ANSI_RGB_G
    lda ANSI_PARAM4
    sta ANSI_RGB_B
    jmp ANSI_MAP_RGB_BG
_ansi_sgr_ext0_256_bg:
    lda ANSI_PARAM2
    jmp ANSI_MAP_256_BG

_ansi_sgr_ext1:
    lda ANSI_PARAM_INDEX
    cmp #4
    bcc _ansi_sgr_done
    lda ANSI_PARAM2
    cmp #5
    beq _ansi_sgr_ext1_256_fg
    cmp #2
    bne _ansi_sgr_done
    lda ANSI_PARAM_INDEX
    cmp #6
    bcc _ansi_sgr_done
    lda ANSI_PARAM3
    sta ANSI_RGB_R
    lda ANSI_PARAM4
    sta ANSI_RGB_G
    lda ANSI_PARAM5
    sta ANSI_RGB_B
    jmp ANSI_MAP_RGB_FG
_ansi_sgr_ext1_256_fg:
    lda ANSI_PARAM3
    jmp ANSI_MAP_256_FG

_ansi_sgr_ext1_bg:
    lda ANSI_PARAM_INDEX
    cmp #4
    bcc _ansi_sgr_done
    lda ANSI_PARAM2
    cmp #5
    beq _ansi_sgr_ext1_256_bg
    cmp #2
    bne _ansi_sgr_done
    lda ANSI_PARAM_INDEX
    cmp #6
    bcc _ansi_sgr_done
    lda ANSI_PARAM3
    sta ANSI_RGB_R
    lda ANSI_PARAM4
    sta ANSI_RGB_G
    lda ANSI_PARAM5
    sta ANSI_RGB_B
    jmp ANSI_MAP_RGB_BG
_ansi_sgr_ext1_256_bg:
    lda ANSI_PARAM3
    jmp ANSI_MAP_256_BG

ANSI_APPLY_SGR:
    cmp #0
    beq ANSI_RESET_ATTR
    cmp #1
    beq _ansi_bright_on
    cmp #4
    beq _ansi_sgr_ignore
    cmp #5
    beq _ansi_sgr_ignore
    cmp #7
    beq _ansi_inverse_on
    cmp #22
    beq _ansi_bright_off
    cmp #24
    beq _ansi_sgr_ignore
    cmp #25
    beq _ansi_sgr_ignore
    cmp #27
    beq _ansi_inverse_off
    cmp #39
    beq _ansi_default_fg
    cmp #49
    beq _ansi_default_bg
    cmp #30
    bcc _ansi_sgr_ignore
    cmp #38
    bcc _ansi_fg_normal
    cmp #40
    bcc _ansi_sgr_ignore
    cmp #48
    bcc _ansi_bg_normal
    cmp #90
    bcc _ansi_sgr_ignore
    cmp #98
    bcc _ansi_fg_bright
    cmp #100
    bcc _ansi_sgr_ignore
    cmp #108
    bcc _ansi_bg_bright
    rts

_ansi_bright_on:
    lda #1
    sta ANSI_BRIGHT
    jsr ANSI_BRIGHTEN_CURRENT_FG
    jmp ANSI_UPDATE_COLOR

_ansi_bright_off:
    lda #0
    sta ANSI_BRIGHT
    jsr ANSI_NORMALIZE_CURRENT_FG
    jmp ANSI_UPDATE_COLOR

_ansi_inverse_on:
    lda #1
    sta ANSI_INVERSE
    jmp ANSI_UPDATE_COLOR

_ansi_inverse_off:
    lda #0
    sta ANSI_INVERSE
    jmp ANSI_UPDATE_COLOR

_ansi_default_fg:
    lda #ASCII_DEFAULT_COLOR
    sta ASCII_FG_COLOR
    jmp ANSI_UPDATE_COLOR

_ansi_default_bg:
    lda #COLOR_BLACK
    sta ASCII_BG_COLOR
    jmp ANSI_UPDATE_COLOR

_ansi_fg_normal:
    sec
    sbc #30
    tax
    lda ANSI_BRIGHT
    beq _ansi_load_normal
    lda ANSI_COLOR_BRIGHT,x
    sta ASCII_FG_COLOR
    jmp ANSI_UPDATE_COLOR
_ansi_load_normal:
    lda ANSI_COLOR_NORMAL,x
    sta ASCII_FG_COLOR
    jmp ANSI_UPDATE_COLOR

_ansi_fg_bright:
    sec
    sbc #90
    tax
    lda ANSI_COLOR_BRIGHT,x
    sta ASCII_FG_COLOR
    jmp ANSI_UPDATE_COLOR

_ansi_bg_normal:
    sec
    sbc #40
    tax
    lda ANSI_COLOR_NORMAL,x
    sta ASCII_BG_COLOR
    jmp ANSI_UPDATE_COLOR

_ansi_bg_bright:
    sec
    sbc #100
    tax
    lda ANSI_COLOR_BRIGHT,x
    sta ASCII_BG_COLOR
    jmp ANSI_UPDATE_COLOR

_ansi_sgr_ignore:
    rts

ANSI_BRIGHTEN_CURRENT_FG:
    ldx #0
_ansi_brighten_loop:
    lda ASCII_FG_COLOR
    cmp ANSI_COLOR_NORMAL,x
    beq _ansi_brighten_match
    inx
    cpx #8
    bcc _ansi_brighten_loop
    rts
_ansi_brighten_match:
    lda ANSI_COLOR_BRIGHT,x
    sta ASCII_FG_COLOR
    rts

ANSI_NORMALIZE_CURRENT_FG:
    ldx #0
_ansi_normalize_loop:
    lda ASCII_FG_COLOR
    cmp ANSI_COLOR_BRIGHT,x
    beq _ansi_normalize_match
    inx
    cpx #8
    bcc _ansi_normalize_loop
    rts
_ansi_normalize_match:
    lda ANSI_COLOR_NORMAL,x
    sta ASCII_FG_COLOR
    rts

ANSI_RESET_ATTR:
    lda #ASCII_DEFAULT_COLOR
    sta ASCII_FG_COLOR
    lda #COLOR_BLACK
    sta ASCII_BG_COLOR
    lda #0
    sta ANSI_BRIGHT
    sta ANSI_INVERSE
    jmp ANSI_UPDATE_COLOR

ANSI_UPDATE_COLOR:
    lda ANSI_INVERSE
    bne _ansi_color_inverse
    lda ASCII_BG_COLOR
    jsr ANSI_COLOR_TO_BG_NIBBLE
    sta TEMP_A
    lda ASCII_FG_COLOR
    and #$0f
    ora TEMP_A
    sta ASCII_COLOR
    rts
_ansi_color_inverse:
    lda ASCII_FG_COLOR
    jsr ANSI_COLOR_TO_BG_NIBBLE
    sta TEMP_A
    lda ASCII_BG_COLOR
    and #$0f
    ora TEMP_A
    sta ASCII_COLOR
    rts

ANSI_COLOR_TO_BG_NIBBLE:
    and #$0f
    asl a
    asl a
    asl a
    asl a
    rts

ANSI_MAP_256_FG:
    jsr ANSI_256_TO_COLOR
    sta ASCII_FG_COLOR
    jmp ANSI_UPDATE_COLOR

ANSI_MAP_16_FG:
    cmp #8
    bcc _ansi_map_16_normal
    sec
    sbc #8
    tax
    lda ANSI_COLOR_BRIGHT,x
    sta ASCII_FG_COLOR
    jmp ANSI_UPDATE_COLOR
_ansi_map_16_normal:
    tax
    lda ANSI_COLOR_NORMAL,x
    sta ASCII_FG_COLOR
    jmp ANSI_UPDATE_COLOR

ANSI_MAP_256_BG:
    jsr ANSI_256_TO_COLOR
    sta ASCII_BG_COLOR
    jmp ANSI_UPDATE_COLOR

ANSI_MAP_16_BG:
    cmp #8
    bcc _ansi_map_16_bg_normal
    sec
    sbc #8
    tax
    lda ANSI_COLOR_BRIGHT,x
    sta ASCII_BG_COLOR
    jmp ANSI_UPDATE_COLOR
_ansi_map_16_bg_normal:
    tax
    lda ANSI_COLOR_NORMAL,x
    sta ASCII_BG_COLOR
    jmp ANSI_UPDATE_COLOR

ANSI_MAP_RGB_FG:
    jsr ANSI_RGB_TO_COLOR
    sta ASCII_FG_COLOR
    jmp ANSI_UPDATE_COLOR

ANSI_MAP_RGB_BG:
    jsr ANSI_RGB_TO_COLOR
    sta ASCII_BG_COLOR
    jmp ANSI_UPDATE_COLOR

ANSI_256_TO_COLOR:
    sta ANSI_COLOR_INDEX
    cmp #16
    bcc _ansi_256_low16
    cmp #232
    bcs _ansi_256_gray

    sec
    sbc #16
    sta ANSI_COLOR_WORK
    lda #0
    sta ANSI_RGB_R
_ansi_256_r_loop:
    lda ANSI_COLOR_WORK
    cmp #36
    bcc _ansi_256_r_done
    sec
    sbc #36
    sta ANSI_COLOR_WORK
    inc ANSI_RGB_R
    bra _ansi_256_r_loop
_ansi_256_r_done:
    lda #0
    sta ANSI_RGB_G
_ansi_256_g_loop:
    lda ANSI_COLOR_WORK
    cmp #6
    bcc _ansi_256_g_done
    sec
    sbc #6
    sta ANSI_COLOR_WORK
    inc ANSI_RGB_G
    bra _ansi_256_g_loop
_ansi_256_g_done:
    lda ANSI_COLOR_WORK
    sta ANSI_RGB_B

    lda #0
    sta ANSI_COLOR_BITS
    lda ANSI_RGB_R
    cmp #3
    bcc _ansi_256_no_r
    lda ANSI_COLOR_BITS
    ora #1
    sta ANSI_COLOR_BITS
_ansi_256_no_r:
    lda ANSI_RGB_G
    cmp #3
    bcc _ansi_256_no_g
    lda ANSI_COLOR_BITS
    ora #2
    sta ANSI_COLOR_BITS
_ansi_256_no_g:
    lda ANSI_RGB_B
    cmp #3
    bcc _ansi_256_no_b
    lda ANSI_COLOR_BITS
    ora #4
    sta ANSI_COLOR_BITS
_ansi_256_no_b:
    lda ANSI_COLOR_BITS
    bne _ansi_256_have_bits
    lda ANSI_RGB_R
    cmp #2
    bcs _ansi_256_dim_gray
    lda ANSI_RGB_G
    cmp #2
    bcs _ansi_256_dim_gray
    lda ANSI_RGB_B
    cmp #2
    bcs _ansi_256_dim_gray
_ansi_256_have_bits:
    ldx ANSI_COLOR_BITS
    lda ANSI_RGB_R
    cmp #5
    bcs _ansi_256_bright
    lda ANSI_RGB_G
    cmp #5
    bcs _ansi_256_bright
    lda ANSI_RGB_B
    cmp #5
    bcs _ansi_256_bright
    lda ANSI_COLOR_NORMAL,x
    rts
_ansi_256_bright:
    lda ANSI_COLOR_BRIGHT,x
    rts
_ansi_256_dim_gray:
    lda #COLOR_DARK_GREY
    rts

_ansi_256_low16:
    tax
    cpx #8
    bcc _ansi_256_low_normal
    txa
    sec
    sbc #8
    tax
    lda ANSI_COLOR_BRIGHT,x
    rts
_ansi_256_low_normal:
    lda ANSI_COLOR_NORMAL,x
    rts

_ansi_256_gray:
    cmp #244
    bcc _ansi_256_return_darkgrey
    cmp #252
    bcc _ansi_256_return_grey
    lda #COLOR_WHITE
    rts
_ansi_256_return_darkgrey:
    lda #COLOR_DARK_GREY
    rts
_ansi_256_return_grey:
    lda #COLOR_GREY
    rts

ANSI_RGB_TO_COLOR:
    lda #0
    sta ANSI_COLOR_BITS
    lda ANSI_RGB_R
    cmp #128
    bcc _ansi_rgb_no_r
    lda ANSI_COLOR_BITS
    ora #1
    sta ANSI_COLOR_BITS
_ansi_rgb_no_r:
    lda ANSI_RGB_G
    cmp #128
    bcc _ansi_rgb_no_g
    lda ANSI_COLOR_BITS
    ora #2
    sta ANSI_COLOR_BITS
_ansi_rgb_no_g:
    lda ANSI_RGB_B
    cmp #128
    bcc _ansi_rgb_no_b
    lda ANSI_COLOR_BITS
    ora #4
    sta ANSI_COLOR_BITS
_ansi_rgb_no_b:
    lda ANSI_COLOR_BITS
    bne _ansi_rgb_have_bits
    lda ANSI_RGB_R
    cmp #64
    bcs _ansi_rgb_dim_gray
    lda ANSI_RGB_G
    cmp #64
    bcs _ansi_rgb_dim_gray
    lda ANSI_RGB_B
    cmp #64
    bcs _ansi_rgb_dim_gray
_ansi_rgb_have_bits:
    ldx ANSI_COLOR_BITS
    lda ANSI_RGB_R
    cmp #192
    bcs _ansi_rgb_bright
    lda ANSI_RGB_G
    cmp #192
    bcs _ansi_rgb_bright
    lda ANSI_RGB_B
    cmp #192
    bcs _ansi_rgb_bright
    lda ANSI_COLOR_NORMAL,x
    rts
_ansi_rgb_bright:
    lda ANSI_COLOR_BRIGHT,x
    rts
_ansi_rgb_dim_gray:
    lda #COLOR_DARK_GREY
    rts

ANSI_DSR:
    rts

ANSI_DEVICE_ATTRIBUTES:
    rts

ANSI_MODE_SET:
    lda ANSI_PARAM0
    cmp #1
    bne _ansi_mode_set_not_cursor_app
    lda ANSI_PRIVATE
    beq _ansi_mode_set_not_cursor_app
    lda #1
    sta ANSI_CURSOR_APP_MODE
    rts
_ansi_mode_set_not_cursor_app:
    lda ANSI_PARAM0
    cmp #25
    beq CURSOR_SPRITE_SHOW
    cmp #7
    beq _ansi_set_wrap
    cmp #6
    bne _ansi_mode_set_done
    lda #1
    sta ANSI_ORIGIN_MODE
    lda ASCII_SCROLL_TOP
    sta ASCII_ROW
    lda #0
    sta ASCII_COL
    jmp ASCII_RECALC_PTR
_ansi_set_wrap:
    lda #1
    sta ASCII_WRAP_MODE
_ansi_mode_set_done:
    rts

ANSI_MODE_RESET:
    lda ANSI_PARAM0
    cmp #1
    bne _ansi_mode_reset_not_cursor_app
    lda ANSI_PRIVATE
    beq _ansi_mode_reset_not_cursor_app
    lda #0
    sta ANSI_CURSOR_APP_MODE
    rts
_ansi_mode_reset_not_cursor_app:
    lda ANSI_PARAM0
    cmp #25
    beq CURSOR_SPRITE_DISABLE
    cmp #7
    beq _ansi_reset_wrap
    cmp #6
    bne _ansi_mode_reset_done
    lda #0
    sta ANSI_ORIGIN_MODE
    sta ASCII_ROW
    sta ASCII_COL
    jmp ASCII_RECALC_PTR
_ansi_reset_wrap:
    lda #0
    sta ASCII_WRAP_MODE
_ansi_mode_reset_done:
    rts

ANSI_SET_SCROLL_REGION:
    lda ANSI_PARAM0
    bne _ansi_region_top_given
    lda #1
_ansi_region_top_given:
    sec
    sbc #1
    sta TEMP_LO

    lda ANSI_PARAM1
    bne _ansi_region_bottom_given
    lda #SCREEN_ROWS
_ansi_region_bottom_given:
    sec
    sbc #1
    sta TEMP_HI

    lda TEMP_LO
    cmp #SCREEN_ROWS
    bcs _ansi_region_reset
    lda TEMP_HI
    cmp #SCREEN_ROWS
    bcs _ansi_region_reset
    lda TEMP_LO
    cmp TEMP_HI
    bcs _ansi_region_reset
    lda TEMP_LO
    sta ASCII_SCROLL_TOP
    lda TEMP_HI
    sta ASCII_SCROLL_BOTTOM
    bra _ansi_region_home

_ansi_region_reset:
    lda #0
    sta ASCII_SCROLL_TOP
    lda #SCREEN_ROWS-1
    sta ASCII_SCROLL_BOTTOM

_ansi_region_home:
    lda #0
    sta ASCII_COL
    lda ANSI_ORIGIN_MODE
    beq _ansi_region_home_screen
    lda ASCII_SCROLL_TOP
    bra _ansi_region_home_store
_ansi_region_home_screen:
    lda #0
_ansi_region_home_store:
    sta ASCII_ROW
    jmp ASCII_RECALC_PTR

ANSI_FULL_RESET:
    jsr ANSI_SOFT_RESET_STATE
    jmp ASCII_CLEAR_SCREEN_HOME

ANSI_SOFT_RESET:
    lda ANSI_INTERMEDIATE
    cmp #'!'
    bne _ansi_soft_reset_done
    jsr ANSI_SOFT_RESET_STATE
_ansi_soft_reset_done:
    rts

ANSI_TAB_CLEAR:
    rts

ANSI_SOFT_RESET_STATE:
    jsr ANSI_RESET_ATTR
    lda #1
    sta ASCII_WRAP_MODE
    lda #0
    sta ASCII_SCROLL_TOP
    sta ANSI_ORIGIN_MODE
    sta ANSI_G0_GRAPHICS
    sta ANSI_G1_GRAPHICS
    sta ANSI_USE_G1
    sta ANSI_CURSOR_APP_MODE
    lda #SCREEN_ROWS-1
    sta ASCII_SCROLL_BOTTOM
    jsr CURSOR_SPRITE_SHOW
    rts

ANSI_SAVE_CURSOR:
    lda ASCII_ROW
    sta ASCII_SAVED_ROW
    lda ASCII_COL
    sta ASCII_SAVED_COL
    lda ASCII_FG_COLOR
    sta ASCII_SAVED_FG_COLOR
    lda ASCII_BG_COLOR
    sta ASCII_SAVED_BG_COLOR
    lda ANSI_BRIGHT
    sta ANSI_SAVED_BRIGHT
    lda ANSI_INVERSE
    sta ANSI_SAVED_INVERSE
    lda ANSI_G0_GRAPHICS
    sta ANSI_SAVED_G0_GRAPHICS
    lda ANSI_G1_GRAPHICS
    sta ANSI_SAVED_G1_GRAPHICS
    lda ANSI_USE_G1
    sta ANSI_SAVED_USE_G1
    rts

ANSI_RESTORE_CURSOR:
    lda ASCII_SAVED_ROW
    sta ASCII_ROW
    lda ASCII_SAVED_COL
    sta ASCII_COL
    lda ASCII_SAVED_FG_COLOR
    sta ASCII_FG_COLOR
    lda ASCII_SAVED_BG_COLOR
    sta ASCII_BG_COLOR
    lda ANSI_SAVED_BRIGHT
    sta ANSI_BRIGHT
    lda ANSI_SAVED_INVERSE
    sta ANSI_INVERSE
    lda ANSI_SAVED_G0_GRAPHICS
    sta ANSI_G0_GRAPHICS
    lda ANSI_SAVED_G1_GRAPHICS
    sta ANSI_G1_GRAPHICS
    lda ANSI_SAVED_USE_G1
    sta ANSI_USE_G1
    jsr ANSI_UPDATE_COLOR
    jmp ASCII_RECALC_PTR

ASCII_PUT_BYTE:
    cmp #CR
    beq ASCII_CR
    cmp #LF
    beq ASCII_LF
    cmp #$09
    beq ASCII_TAB
    cmp #$08
    beq ASCII_BACKSPACE
    cmp #$7f
    beq ASCII_BACKSPACE
    cmp #$20
    bcc _ascii_put_done
    jsr ASCII_WRITE_CHAR
    jsr ASCII_ADVANCE
_ascii_put_done:
    rts

ASCII_CR:
    lda #0
    sta ASCII_COL
    jmp ASCII_RECALC_PTR

ASCII_LF:
    jmp ASCII_NEWLINE

ASCII_TAB:
    lda ASCII_COL
    and #$f8
    clc
    adc #8
    cmp #SCREEN_COLS
    bcc _ascii_tab_set
    lda ASCII_WRAP_MODE
    bne ASCII_NEWLINE
    lda #SCREEN_COLS-1
_ascii_tab_set:
    sta ASCII_COL
    jmp ASCII_RECALC_PTR

ASCII_NEXT_LINE:
    lda #0
    sta ASCII_COL
    jmp ASCII_NEWLINE

ASCII_INDEX:
    lda ASCII_ROW
    cmp ASCII_SCROLL_BOTTOM
    beq _ascii_index_scroll
    cmp #SCREEN_ROWS-1
    bcs _ascii_index_done
    inc ASCII_ROW
_ascii_index_done:
    jmp ASCII_RECALC_PTR
_ascii_index_scroll:
    jsr ASCII_SCROLL_REGION_UP
    jmp ASCII_RECALC_PTR

ASCII_REVERSE_INDEX:
    lda ASCII_ROW
    cmp ASCII_SCROLL_TOP
    beq _ascii_ri_scroll
    lda ASCII_ROW
    beq _ascii_ri_done
    dec ASCII_ROW
_ascii_ri_done:
    jmp ASCII_RECALC_PTR
_ascii_ri_scroll:
    jsr ASCII_SCROLL_REGION_DOWN
    jmp ASCII_RECALC_PTR

ASCII_WRITE_CHAR:
    sta ASCII_CHAR
    jsr ANSI_MAP_DEC_GRAPHICS
    sta ASCII_CHAR
    lda ASCII_PTR_LO
    sta PTR_LO
    lda ASCII_PTR_HI
    sta PTR_HI
    ldy #0
    lda ASCII_CHAR
    sta (PTR_LO),y
    lda ASCII_COLOR_PTR_LO
    sta PTR_LO
    lda ASCII_COLOR_PTR_HI
    sta PTR_HI
    lda #COLOR_BANK
    sta PTR_BANK
    lda #0
    sta PTR_TOP
    ldz #0
    lda ASCII_COLOR
    sta [PTR_LO],z
    rts

ANSI_MAP_DEC_GRAPHICS:
    lda ANSI_USE_G1
    beq _ansi_map_g0
    lda ANSI_G1_GRAPHICS
    bra _ansi_map_check
_ansi_map_g0:
    lda ANSI_G0_GRAPHICS
_ansi_map_check:
    beq _ansi_map_plain
    lda ASCII_CHAR
    cmp #'j'
    beq _ansi_map_lr
    cmp #'k'
    beq _ansi_map_ur
    cmp #'l'
    beq _ansi_map_ul
    cmp #'m'
    beq _ansi_map_ll
    cmp #'n'
    beq _ansi_map_cross
    cmp #'q'
    beq _ansi_map_hline
    cmp #'t'
    beq _ansi_map_left_t
    cmp #'u'
    beq _ansi_map_right_t
    cmp #'v'
    beq _ansi_map_bottom_t
    cmp #'w'
    beq _ansi_map_top_t
    cmp #'x'
    beq _ansi_map_vline
    cmp #'a'
    beq _ansi_map_shade
    cmp #'f'
    beq _ansi_map_degree
    cmp #'g'
    beq _ansi_map_plusminus
    cmp #'~'
    beq _ansi_map_bullet
_ansi_map_plain:
    lda ASCII_CHAR
    rts
_ansi_map_lr:
    lda #$d9
    rts
_ansi_map_ur:
    lda #$bf
    rts
_ansi_map_ul:
    lda #$da
    rts
_ansi_map_ll:
    lda #$c0
    rts
_ansi_map_cross:
    lda #$c5
    rts
_ansi_map_hline:
    lda #$c4
    rts
_ansi_map_left_t:
    lda #$c3
    rts
_ansi_map_right_t:
    lda #$b4
    rts
_ansi_map_bottom_t:
    lda #$c1
    rts
_ansi_map_top_t:
    lda #$c2
    rts
_ansi_map_vline:
    lda #$b3
    rts
_ansi_map_shade:
    lda #$b1
    rts
_ansi_map_degree:
    lda #$f8
    rts
_ansi_map_plusminus:
    lda #$f1
    rts
_ansi_map_bullet:
    lda #$f9
    rts

ASCII_ADVANCE:
    inc ASCII_COL
    lda ASCII_COL
    cmp #SCREEN_COLS
    bcc _ascii_advance_ptr
    lda ASCII_WRAP_MODE
    bne _ascii_wrap_newline
    lda #SCREEN_COLS-1
    sta ASCII_COL
    jmp ASCII_RECALC_PTR
_ascii_wrap_newline:
    jmp ASCII_NEWLINE
_ascii_advance_ptr:
    inc ASCII_PTR_LO
    bne _ascii_advance_color
    inc ASCII_PTR_HI
_ascii_advance_color:
    inc ASCII_COLOR_PTR_LO
    bne _ascii_advance_done
    inc ASCII_COLOR_PTR_HI
_ascii_advance_done:
    rts

ASCII_NEWLINE:
    lda #0
    sta ASCII_COL
    lda ASCII_ROW
    cmp ASCII_SCROLL_BOTTOM
    beq _ascii_scroll_region
    cmp #SCREEN_ROWS-1
    bcs _ascii_newline_done
    inc ASCII_ROW
    jmp ASCII_RECALC_PTR
_ascii_scroll_region:
    jsr ASCII_SCROLL_REGION_UP
_ascii_newline_done:
    jmp ASCII_RECALC_PTR

ASCII_BACKSPACE:
    lda ASCII_COL
    beq _ascii_bs_done
    dec ASCII_COL
    jsr ASCII_RECALC_PTR
    lda #$20
    jsr ASCII_WRITE_CHAR
_ascii_bs_done:
    rts

ASCII_READ_SRC_CELL:
    ldx ASCII_SRC_ROW
    lda SCREEN_ROW_LO,x
    clc
    adc ASCII_WORK_COL
    sta PTR_LO
    lda SCREEN_ROW_HI,x
    adc #0
    sta PTR_HI
    ldy #0
    lda (PTR_LO),y
    sta ASCII_WORK_BYTE

    ldx ASCII_SRC_ROW
    lda SCREEN_ROW_LO,x
    clc
    adc ASCII_WORK_COL
    sta PTR_LO
    lda SCREEN_ROW_HI,x
    adc #$f0
    sta PTR_HI
    lda #COLOR_BANK
    sta PTR_BANK
    lda #0
    sta PTR_TOP
    ldz #0
    lda [PTR_LO],z
    sta ASCII_WORK_COLOR
    rts

ASCII_WRITE_DST_CELL:
    ldx ASCII_DST_ROW
    lda SCREEN_ROW_LO,x
    clc
    adc ASCII_WORK_COL
    sta PTR_LO
    lda SCREEN_ROW_HI,x
    adc #0
    sta PTR_HI
    ldy #0
    lda ASCII_WORK_BYTE
    sta (PTR_LO),y

    ldx ASCII_DST_ROW
    lda SCREEN_ROW_LO,x
    clc
    adc ASCII_WORK_COL
    sta PTR_LO
    lda SCREEN_ROW_HI,x
    adc #$f0
    sta PTR_HI
    lda #COLOR_BANK
    sta PTR_BANK
    lda #0
    sta PTR_TOP
    ldz #0
    lda ASCII_WORK_COLOR
    sta [PTR_LO],z
    rts

ASCII_COPY_SRC_TO_DST_ROW:
    lda #0
    sta ASCII_WORK_COL
_ascii_copy_row_loop:
    jsr ASCII_READ_SRC_CELL
    jsr ASCII_WRITE_DST_CELL
    inc ASCII_WORK_COL
    lda ASCII_WORK_COL
    cmp #SCREEN_COLS
    bne _ascii_copy_row_loop
    rts

ASCII_CLEAR_DST_ROW:
    lda ASCII_ROW
    pha
    lda ASCII_DST_ROW
    sta ASCII_ROW
    lda #0
    sta TEMP_LO
    lda #SCREEN_COLS
    sta TEMP_HI
    jsr ASCII_CLEAR_LINE_RANGE
    pla
    sta ASCII_ROW
    rts

ASCII_SCROLL_REGION_UP:
    lda ASCII_SCROLL_TOP
    sta ASCII_DST_ROW
_ascii_region_up_copy:
    lda ASCII_DST_ROW
    cmp ASCII_SCROLL_BOTTOM
    bcs _ascii_region_up_clear
    clc
    adc #1
    sta ASCII_SRC_ROW
    jsr ASCII_COPY_SRC_TO_DST_ROW
    inc ASCII_DST_ROW
    bra _ascii_region_up_copy
_ascii_region_up_clear:
    lda ASCII_SCROLL_BOTTOM
    sta ASCII_DST_ROW
    jmp ASCII_CLEAR_DST_ROW

ASCII_SCROLL_REGION_DOWN:
    lda ASCII_SCROLL_BOTTOM
    sta ASCII_DST_ROW
_ascii_region_down_copy:
    lda ASCII_DST_ROW
    cmp ASCII_SCROLL_TOP
    beq _ascii_region_down_clear
    sec
    sbc #1
    sta ASCII_SRC_ROW
    jsr ASCII_COPY_SRC_TO_DST_ROW
    dec ASCII_DST_ROW
    bra _ascii_region_down_copy
_ascii_region_down_clear:
    lda ASCII_SCROLL_TOP
    sta ASCII_DST_ROW
    jmp ASCII_CLEAR_DST_ROW

ASCII_CLEAR_LINE_RANGE:
    lda TEMP_HI
    beq _ascii_clr_line_done
    sta ASCII_WORK_COUNT
    lda TEMP_LO
    sta ASCII_WORK_START

    ldx ASCII_ROW
    lda SCREEN_ROW_LO,x
    clc
    adc ASCII_WORK_START
    sta PTR_LO
    lda SCREEN_ROW_HI,x
    adc #0
    sta PTR_HI
    lda ASCII_WORK_COUNT
    sta TEMP_HI
_ascii_clr_line_loop:
    ldy #0
    lda #$20
    sta (PTR_LO),y
    inc PTR_LO
    bne _ascii_clr_line_dec
    inc PTR_HI
_ascii_clr_line_dec:
    dec TEMP_HI
    bne _ascii_clr_line_loop

    ldx ASCII_ROW
    lda SCREEN_ROW_LO,x
    clc
    adc ASCII_WORK_START
    sta PTR_LO
    lda SCREEN_ROW_HI,x
    adc #$f0
    sta PTR_HI
    lda #COLOR_BANK
    sta PTR_BANK
    lda #0
    sta PTR_TOP
    lda ASCII_WORK_COUNT
    sta TEMP_HI
_ascii_clr_line_color_loop:
    ldz #0
    lda ASCII_COLOR
    sta [PTR_LO],z
    inc PTR_LO
    bne _ascii_clr_line_color_dec
    inc PTR_HI
_ascii_clr_line_color_dec:
    dec TEMP_HI
    bne _ascii_clr_line_color_loop
_ascii_clr_line_done:
    rts

ASCII_CLEAR_TO_END_SCREEN:
    jsr ANSI_ERASE_LINE
    lda ASCII_ROW
    clc
    adc #1
    sta TEMP_A
_ascii_cte_row_loop:
    lda TEMP_A
    cmp #SCREEN_ROWS
    bcs _ascii_cte_done
    lda ASCII_ROW
    pha
    lda TEMP_A
    sta ASCII_ROW
    lda #0
    sta TEMP_LO
    lda #SCREEN_COLS
    sta TEMP_HI
    jsr ASCII_CLEAR_LINE_RANGE
    pla
    sta ASCII_ROW
    inc TEMP_A
    bra _ascii_cte_row_loop
_ascii_cte_done:
    jmp ASCII_RECALC_PTR

CLEAR_NETWORK_STATUS_AREA:
    lda ASCII_COLOR
    pha
    lda #COLOR_WHITE
    sta ASCII_COLOR
    lda #MENU_STATUS_ROW
    sta TEMP_A
_clear_network_row_loop:
    lda TEMP_A
    cmp #SCREEN_ROWS
    bcs _clear_network_rows_done
    sta ASCII_DST_ROW
    jsr ASCII_CLEAR_DST_ROW
    inc TEMP_A
    bra _clear_network_row_loop
_clear_network_rows_done:
    pla
    sta ASCII_COLOR
    lda #PET_HOME
    jsr K_CHROUT
    lda #MENU_STATUS_ROW
    sta TEMP_A
_clear_network_cursor_loop:
    lda TEMP_A
    beq _clear_network_cursor_done
    lda #PET_DOWN
    jsr K_CHROUT
    dec TEMP_A
    bra _clear_network_cursor_loop
_clear_network_cursor_done:
    lda #PET_WHITE
    jmp K_CHROUT

ASCII_CLEAR_TO_START_SCREEN:
    lda ASCII_ROW
    sta ASCII_ERASE_ROW
    lda #0
    sta TEMP_A
_ascii_cts_row_loop:
    lda TEMP_A
    cmp ASCII_ERASE_ROW
    bcs _ascii_cts_current_row
    sta ASCII_ROW
    lda #0
    sta TEMP_LO
    lda #SCREEN_COLS
    sta TEMP_HI
    jsr ASCII_CLEAR_LINE_RANGE
    inc TEMP_A
    bra _ascii_cts_row_loop
_ascii_cts_current_row:
    lda ASCII_ERASE_ROW
    sta ASCII_ROW
    lda #0
    sta TEMP_LO
    lda ASCII_COL
    clc
    adc #1
    sta TEMP_HI
    jsr ASCII_CLEAR_LINE_RANGE
    lda ASCII_ERASE_ROW
    sta ASCII_ROW
    jmp ASCII_RECALC_PTR

ASCII_CLEAR_SCREEN_HOME:
    lda #<SCREEN_BASE
    sta PTR_LO
    lda #>SCREEN_BASE
    sta PTR_HI
    lda #<((SCREEN_ROWS)*SCREEN_COLS)
    sta TEMP_LO
    lda #>((SCREEN_ROWS)*SCREEN_COLS)
    sta TEMP_HI
_ascii_clear_screen_loop:
    ldy #0
    lda #$20
    sta (PTR_LO),y
    inc PTR_LO
    bne _ascii_clear_screen_dec
    inc PTR_HI
_ascii_clear_screen_dec:
    lda TEMP_LO
    bne _ascii_clear_screen_dec_lo
    dec TEMP_HI
_ascii_clear_screen_dec_lo:
    dec TEMP_LO
    lda TEMP_LO
    ora TEMP_HI
    bne _ascii_clear_screen_loop

    lda #<COLOR_BASE
    sta PTR_LO
    lda #>COLOR_BASE
    sta PTR_HI
    lda #COLOR_BANK
    sta PTR_BANK
    lda #0
    sta PTR_TOP
    lda #<((SCREEN_ROWS)*SCREEN_COLS)
    sta TEMP_LO
    lda #>((SCREEN_ROWS)*SCREEN_COLS)
    sta TEMP_HI
_ascii_clear_color_loop:
    ldz #0
    lda ASCII_COLOR
    sta [PTR_LO],z
    inc PTR_LO
    bne _ascii_clear_color_dec
    inc PTR_HI
_ascii_clear_color_dec:
    lda TEMP_LO
    bne _ascii_clear_color_dec_lo
    dec TEMP_HI
_ascii_clear_color_dec_lo:
    dec TEMP_LO
    lda TEMP_LO
    ora TEMP_HI
    bne _ascii_clear_color_loop

    lda #0
    sta ASCII_ROW
    sta ASCII_COL
    jmp ASCII_RECALC_PTR

ASCII_RECALC_PTR:
    ldx ASCII_ROW
    lda SCREEN_ROW_LO,x
    clc
    adc ASCII_COL
    sta ASCII_PTR_LO
    sta ASCII_COLOR_PTR_LO
    lda SCREEN_ROW_HI,x
    adc #0
    sta ASCII_PTR_HI
    clc
    adc #$f0
    sta ASCII_COLOR_PTR_HI
    rts

ASCII_SCROLL:
    lda #<(SCREEN_BASE+SCREEN_COLS)
    sta PTR_LO
    lda #>(SCREEN_BASE+SCREEN_COLS)
    sta PTR_HI
    lda #<SCREEN_BASE
    sta PTR_BANK
    lda #>SCREEN_BASE
    sta PTR_TOP
    lda #<((SCREEN_ROWS-1)*SCREEN_COLS)
    sta TEMP_LO
    lda #>((SCREEN_ROWS-1)*SCREEN_COLS)
    sta TEMP_HI
_ascii_scroll_copy:
    ldy #0
    lda (PTR_LO),y
    sta (PTR_BANK),y
    inc PTR_LO
    bne _ascii_scroll_dst
    inc PTR_HI
_ascii_scroll_dst:
    inc PTR_BANK
    bne _ascii_scroll_dec
    inc PTR_TOP
_ascii_scroll_dec:
    lda TEMP_LO
    bne _ascii_scroll_dec_lo
    dec TEMP_HI
_ascii_scroll_dec_lo:
    dec TEMP_LO
    lda TEMP_LO
    ora TEMP_HI
    bne _ascii_scroll_copy

    lda #<(SCREEN_BASE+((SCREEN_ROWS-1)*SCREEN_COLS))
    sta PTR_BANK
    lda #>(SCREEN_BASE+((SCREEN_ROWS-1)*SCREEN_COLS))
    sta PTR_TOP
    lda #SCREEN_COLS
    sta TEMP_LO
_ascii_scroll_clear:
    ldy #0
    lda #$20
    sta (PTR_BANK),y
    inc PTR_BANK
    bne _ascii_scroll_clear_dec
    inc PTR_TOP
_ascii_scroll_clear_dec:
    dec TEMP_LO
    bne _ascii_scroll_clear
    jmp ASCII_SCROLL_COLOR

ASCII_SCROLL_COLOR:
    lda #<(COLOR_BASE+SCREEN_COLS)
    sta ASCII_COLOR_SRC_LO
    lda #>(COLOR_BASE+SCREEN_COLS)
    sta ASCII_COLOR_SRC_HI
    lda #<COLOR_BASE
    sta ASCII_COLOR_DST_LO
    lda #>COLOR_BASE
    sta ASCII_COLOR_DST_HI
    lda #<((SCREEN_ROWS-1)*SCREEN_COLS)
    sta TEMP_LO
    lda #>((SCREEN_ROWS-1)*SCREEN_COLS)
    sta TEMP_HI
_ascii_scroll_color_copy:
    lda ASCII_COLOR_SRC_LO
    sta PTR_LO
    lda ASCII_COLOR_SRC_HI
    sta PTR_HI
    lda #COLOR_BANK
    sta PTR_BANK
    lda #0
    sta PTR_TOP
    ldz #0
    lda [PTR_LO],z
    sta ASCII_WORK_BYTE

    lda ASCII_COLOR_DST_LO
    sta PTR_LO
    lda ASCII_COLOR_DST_HI
    sta PTR_HI
    lda #COLOR_BANK
    sta PTR_BANK
    lda #0
    sta PTR_TOP
    ldz #0
    lda ASCII_WORK_BYTE
    sta [PTR_LO],z

    inc ASCII_COLOR_SRC_LO
    bne _ascii_scroll_color_dst_inc
    inc ASCII_COLOR_SRC_HI
_ascii_scroll_color_dst_inc:
    inc ASCII_COLOR_DST_LO
    bne _ascii_scroll_color_dec
    inc ASCII_COLOR_DST_HI
_ascii_scroll_color_dec:
    lda TEMP_LO
    bne _ascii_scroll_color_dec_lo
    dec TEMP_HI
_ascii_scroll_color_dec_lo:
    dec TEMP_LO
    lda TEMP_LO
    ora TEMP_HI
    bne _ascii_scroll_color_copy

    lda #<(COLOR_BASE+((SCREEN_ROWS-1)*SCREEN_COLS))
    sta PTR_LO
    lda #>(COLOR_BASE+((SCREEN_ROWS-1)*SCREEN_COLS))
    sta PTR_HI
    lda #COLOR_BANK
    sta PTR_BANK
    lda #0
    sta PTR_TOP
    lda #SCREEN_COLS
    sta TEMP_LO
_ascii_scroll_color_clear:
    ldz #0
    lda ASCII_COLOR
    sta [PTR_LO],z
    inc PTR_LO
    bne _ascii_scroll_color_clear_dec
    inc PTR_HI
_ascii_scroll_color_clear_dec:
    dec TEMP_LO
    bne _ascii_scroll_color_clear
    rts

PRINT_Z:
    sta PTR_LO
    stx PTR_HI
    ldy #0
_print_loop:
    lda (PTR_LO),y
    beq _print_done
    jsr ASCII_TO_PETSCII_TEXT
    jsr K_CHROUT
    iny
    bne _print_loop
    inc PTR_HI
    bra _print_loop
_print_done:
    rts

ASCII_TO_PETSCII_TEXT:
    cmp #'A'
    bcc _ascii_text_check_lower
    cmp #'Z'+1
    bcs _ascii_text_check_lower
    ora #$80
    rts
_ascii_text_check_lower:
    cmp #'a'
    bcc _ascii_text_done
    cmp #'z'+1
    bcs _ascii_text_done
    and #$df
_ascii_text_done:
    rts

PRINT_LINEBUF:
    ldx #0
_print_linebuf_loop:
    cpx LINE_LEN
    beq _print_linebuf_done
    lda LINEBUF,x
    jsr K_CHROUT
    inx
    bra _print_linebuf_loop
_print_linebuf_done:
    rts

PRINT_NETWORK_SETTINGS:
    lda #<MSG_SETTINGS_HDR
    ldx #>MSG_SETTINGS_HDR
    jsr PRINT_Z

    lda #<MSG_LOCAL_IP
    ldx #>MSG_LOCAL_IP
    jsr PRINT_Z
    lda #<MIP_GET_LOCAL_IP
    ldx #>MIP_GET_LOCAL_IP
    jsr GET_IPBUF_TARGET
    jsr PRINT_IPBUF_CR

    lda #<MSG_GATEWAY
    ldx #>MSG_GATEWAY
    jsr PRINT_Z
    lda #<MIP_GET_GATEWAY
    ldx #>MIP_GET_GATEWAY
    jsr GET_IPBUF_TARGET
    jsr PRINT_IPBUF_CR

    lda #<MSG_SUBNET
    ldx #>MSG_SUBNET
    jsr PRINT_Z
    lda #<MIP_GET_SUBNET
    ldx #>MIP_GET_SUBNET
    jsr GET_IPBUF_TARGET
    jsr PRINT_IPBUF_CR

    lda #<MSG_DNS
    ldx #>MSG_DNS
    jsr PRINT_Z
    lda #<MIP_GET_DNS
    ldx #>MIP_GET_DNS
    jsr GET_IPBUF_TARGET
    jsr PRINT_IPBUF_CR
    rts

PRINT_IPBUF_CR:
    jsr PRINT_IPBUF
    lda #CR
    jmp K_CHROUT

PRINT_IPBUF:
    lda #0
    sta IP_PRINT_INDEX
_print_ip_loop:
    ldx IP_PRINT_INDEX
    lda IPBUF,x
    jsr PRINT_BYTE_DEC
    inc IP_PRINT_INDEX
    lda IP_PRINT_INDEX
    cmp #4
    beq _print_ip_done
    lda #'.'
    jsr K_CHROUT
    bra _print_ip_loop
_print_ip_done:
    rts

SEND_DEC_A:
    sta DEC_VALUE
    lda #0
    sta DEC_PRINTED
    sta TEMP_HI
_send_dec_hundreds_loop:
    lda DEC_VALUE
    cmp #100
    bcc _send_dec_hundreds_done
    sec
    sbc #100
    sta DEC_VALUE
    inc TEMP_HI
    bra _send_dec_hundreds_loop
_send_dec_hundreds_done:
    lda TEMP_HI
    beq _send_dec_tens_init
    clc
    adc #'0'
    jsr SEND_BYTE_A
    lda #1
    sta DEC_PRINTED
_send_dec_tens_init:
    lda #0
    sta TEMP_HI
_send_dec_tens_loop:
    lda DEC_VALUE
    cmp #10
    bcc _send_dec_tens_done
    sec
    sbc #10
    sta DEC_VALUE
    inc TEMP_HI
    bra _send_dec_tens_loop
_send_dec_tens_done:
    lda TEMP_HI
    bne _send_dec_print_tens
    lda DEC_PRINTED
    beq _send_dec_ones
_send_dec_print_tens:
    lda TEMP_HI
    clc
    adc #'0'
    jsr SEND_BYTE_A
_send_dec_ones:
    lda DEC_VALUE
    clc
    adc #'0'
    jmp SEND_BYTE_A

PRINT_BYTE_DEC:
    sta DEC_VALUE
    lda #0
    sta DEC_PRINTED
    sta TEMP_HI
_dec_hundreds_loop:
    lda DEC_VALUE
    cmp #100
    bcc _dec_hundreds_done
    sec
    sbc #100
    sta DEC_VALUE
    inc TEMP_HI
    bra _dec_hundreds_loop
_dec_hundreds_done:
    lda TEMP_HI
    beq _dec_tens_init
    clc
    adc #'0'
    jsr K_CHROUT
    lda #1
    sta DEC_PRINTED
_dec_tens_init:
    lda #0
    sta TEMP_HI
_dec_tens_loop:
    lda DEC_VALUE
    cmp #10
    bcc _dec_tens_done
    sec
    sbc #10
    sta DEC_VALUE
    inc TEMP_HI
    bra _dec_tens_loop
_dec_tens_done:
    lda TEMP_HI
    bne _dec_print_tens
    lda DEC_PRINTED
    beq _dec_ones
_dec_print_tens:
    lda TEMP_HI
    clc
    adc #'0'
    jsr K_CHROUT
_dec_ones:
    lda DEC_VALUE
    clc
    adc #'0'
    jmp K_CHROUT

PRINT_HEX_A:
    pha
    lsr
    lsr
    lsr
    lsr
    jsr PRINT_HEX_NIBBLE
    pla
    and #$0f
    jmp PRINT_HEX_NIBBLE

PRINT_HEX_NIBBLE:
    and #$0f
    cmp #10
    bcc _hex_digit
    clc
    adc #'A'-10
    jmp K_CHROUT
_hex_digit:
    clc
    adc #'0'
    jmp K_CHROUT

CALL_DEBUG_TARGET:
    jsr FAR_CALL_NOARGS
    sta DBG_A
    stx DBG_X
    sty DBG_Y
    tza
    sta DBG_Z
    rts

PRINT_DBG_A:
    lda DBG_A
    jmp PRINT_HEX_A

PRINT_DBG_X:
    lda DBG_X
    jmp PRINT_HEX_A

PRINT_DBG_Y:
    lda DBG_Y
    jmp PRINT_HEX_A

PRINT_DBG_Z:
    lda DBG_Z
    jmp PRINT_HEX_A

PRINT_DNS_DEBUG:
    lda #<MSG_DNS_DEBUG1
    ldx #>MSG_DNS_DEBUG1
    jsr PRINT_Z
    lda #<MIP_DNS_DEBUG
    ldx #>MIP_DNS_DEBUG
    jsr CALL_DEBUG_TARGET
    jsr PRINT_DBG_A
    lda #<MSG_DBG_ST
    ldx #>MSG_DBG_ST
    jsr PRINT_Z
    jsr PRINT_DBG_X
    lda #<MSG_DBG_TX
    ldx #>MSG_DBG_TX
    jsr PRINT_Z
    jsr PRINT_DBG_Y
    lda #<MSG_DBG_TF
    ldx #>MSG_DBG_TF
    jsr PRINT_Z
    jsr PRINT_DBG_Z
    lda #CR
    jsr K_CHROUT

    lda #<MSG_DNS_DEBUG2
    ldx #>MSG_DNS_DEBUG2
    jsr PRINT_Z
    lda #<MIP_DNS_DEBUG2
    ldx #>MIP_DNS_DEBUG2
    jsr CALL_DEBUG_TARGET
    jsr PRINT_DBG_A
    lda #<MSG_DBG_ARP
    ldx #>MSG_DBG_ARP
    jsr PRINT_Z
    jsr PRINT_DBG_X
    lda #<MSG_DBG_PF
    ldx #>MSG_DBG_PF
    jsr PRINT_Z
    jsr PRINT_DBG_Y
    lda #<MSG_DBG_P
    ldx #>MSG_DBG_P
    jsr PRINT_Z
    jsr PRINT_DBG_Z
    lda #CR
    jsr K_CHROUT

    lda #<MSG_DNS_DEBUG3
    ldx #>MSG_DNS_DEBUG3
    jsr PRINT_Z
    lda #<MIP_DNS_DEBUG3
    ldx #>MIP_DNS_DEBUG3
    jsr CALL_DEBUG_TARGET
    jsr PRINT_DBG_A
    lda #<MSG_DBG_AN
    ldx #>MSG_DBG_AN
    jsr PRINT_Z
    jsr PRINT_DBG_X
    lda #<MSG_DBG_NS
    ldx #>MSG_DBG_NS
    jsr PRINT_Z
    jsr PRINT_DBG_Y
    lda #<MSG_DBG_BF
    ldx #>MSG_DBG_BF
    jsr PRINT_Z
    jsr PRINT_DBG_Z
    lda #CR
    jmp K_CHROUT

PRINT_CONNECT_DEBUG:
    lda #<MSG_REMOTE_STORED
    ldx #>MSG_REMOTE_STORED
    jsr PRINT_Z
    lda #<MIP_GET_REMOTE_IP
    ldx #>MIP_GET_REMOTE_IP
    jsr GET_IPBUF_TARGET
    jsr PRINT_IPBUF_CR

    lda #<MSG_CONN_DEBUG1
    ldx #>MSG_CONN_DEBUG1
    jsr PRINT_Z
    lda #<MIP_CONNECT_DEBUG
    ldx #>MIP_CONNECT_DEBUG
    jsr CALL_DEBUG_TARGET
    jsr PRINT_DBG_A
    lda #<MSG_DBG_RS
    ldx #>MSG_DBG_RS
    jsr PRINT_Z
    jsr PRINT_DBG_X
    lda #<MSG_DBG_SA
    ldx #>MSG_DBG_SA
    jsr PRINT_Z
    jsr PRINT_DBG_Y
    lda #<MSG_DBG_BA
    ldx #>MSG_DBG_BA
    jsr PRINT_Z
    jsr PRINT_DBG_Z
    lda #CR
    jsr K_CHROUT

    lda #<MSG_CONN_DEBUG2
    ldx #>MSG_CONN_DEBUG2
    jsr PRINT_Z
    lda #<MIP_CONNECT_DEBUG2
    ldx #>MIP_CONNECT_DEBUG2
    jsr CALL_DEBUG_TARGET
    jsr PRINT_DBG_A
    lda #<MSG_DBG_TF
    ldx #>MSG_DBG_TF
    jsr PRINT_Z
    jsr PRINT_DBG_X
    lda #<MSG_DBG_RAW
    ldx #>MSG_DBG_RAW
    jsr PRINT_Z
    jsr PRINT_DBG_Y
    lda #<MSG_DBG_TCP
    ldx #>MSG_DBG_TCP
    jsr PRINT_Z
    jsr PRINT_DBG_Z
    lda #CR
    jsr K_CHROUT

    lda #<MSG_CONN_DEBUG3
    ldx #>MSG_CONN_DEBUG3
    jsr PRINT_Z
    lda #<MIP_CONNECT_DEBUG3
    ldx #>MIP_CONNECT_DEBUG3
    jsr CALL_DEBUG_TARGET
    jsr PRINT_DBG_A
    lda #<MSG_DBG_EH
    ldx #>MSG_DBG_EH
    jsr PRINT_Z
    jsr PRINT_DBG_X
    lda #<MSG_DBG_EL
    ldx #>MSG_DBG_EL
    jsr PRINT_Z
    jsr PRINT_DBG_Y
    lda #<MSG_DBG_PR
    ldx #>MSG_DBG_PR
    jsr PRINT_Z
    jsr PRINT_DBG_Z
    lda #CR
    jsr K_CHROUT

    lda #<MSG_SYN_PORTS
    ldx #>MSG_SYN_PORTS
    jsr PRINT_Z
    lda #<MIP_SYN_DEBUG1
    ldx #>MIP_SYN_DEBUG1
    jsr CALL_DEBUG_TARGET
    jsr PRINT_DBG_A
    jsr PRINT_DBG_X
    lda #<MSG_DBG_SP
    ldx #>MSG_DBG_SP
    jsr PRINT_Z
    jsr PRINT_DBG_Y
    jsr PRINT_DBG_Z
    lda #CR
    jsr K_CHROUT

    lda #<MSG_SYN_DST
    ldx #>MSG_SYN_DST
    jsr PRINT_Z
    lda #<MIP_SYN_DEBUG2
    ldx #>MIP_SYN_DEBUG2
    jsr CALL_DEBUG_TARGET
    jsr PRINT_DBG_A
    lda #'.'
    jsr K_CHROUT
    jsr PRINT_DBG_X
    lda #'.'
    jsr K_CHROUT
    jsr PRINT_DBG_Y
    lda #'.'
    jsr K_CHROUT
    jsr PRINT_DBG_Z
    lda #CR
    jsr K_CHROUT

    lda #<MSG_SYN_SEQ
    ldx #>MSG_SYN_SEQ
    jsr PRINT_Z
    lda #<MIP_SYN_DEBUG3
    ldx #>MIP_SYN_DEBUG3
    jsr CALL_DEBUG_TARGET
    jsr PRINT_DBG_A
    jsr PRINT_DBG_X
    jsr PRINT_DBG_Y
    jsr PRINT_DBG_Z
    lda #CR
    jsr K_CHROUT

    lda #<MSG_SYNACK_SEQ
    ldx #>MSG_SYNACK_SEQ
    jsr PRINT_Z
    lda #<MIP_SYNACK_DEBUG1
    ldx #>MIP_SYNACK_DEBUG1
    jsr CALL_DEBUG_TARGET
    jsr PRINT_DBG_A
    jsr PRINT_DBG_X
    jsr PRINT_DBG_Y
    jsr PRINT_DBG_Z
    lda #CR
    jsr K_CHROUT

    lda #<MSG_SYNACK_ACK
    ldx #>MSG_SYNACK_ACK
    jsr PRINT_Z
    lda #<MIP_SYNACK_DEBUG2
    ldx #>MIP_SYNACK_DEBUG2
    jsr CALL_DEBUG_TARGET
    jsr PRINT_DBG_A
    jsr PRINT_DBG_X
    jsr PRINT_DBG_Y
    jsr PRINT_DBG_Z
    lda #CR
    jsr K_CHROUT

    lda #<MSG_SYNACK_EXPECT
    ldx #>MSG_SYNACK_EXPECT
    jsr PRINT_Z
    lda #<MIP_SYNACK_DEBUG3
    ldx #>MIP_SYNACK_DEBUG3
    jsr CALL_DEBUG_TARGET
    jsr PRINT_DBG_A
    jsr PRINT_DBG_X
    jsr PRINT_DBG_Y
    jsr PRINT_DBG_Z
    lda #CR
    jsr K_CHROUT

    lda #<MSG_RX_PORTS
    ldx #>MSG_RX_PORTS
    jsr PRINT_Z
    lda #<MIP_RX_DEBUG2
    ldx #>MIP_RX_DEBUG2
    jsr CALL_DEBUG_TARGET
    jsr PRINT_DBG_A
    jsr PRINT_DBG_X
    lda #<MSG_DBG_DP
    ldx #>MSG_DBG_DP
    jsr PRINT_Z
    jsr PRINT_DBG_Y
    jsr PRINT_DBG_Z
    lda #CR
    jsr K_CHROUT

    lda #<MSG_RX_SRC
    ldx #>MSG_RX_SRC
    jsr PRINT_Z
    lda #<MIP_RX_DEBUG3
    ldx #>MIP_RX_DEBUG3
    jsr CALL_DEBUG_TARGET
    jsr PRINT_DBG_A
    lda #'.'
    jsr K_CHROUT
    jsr PRINT_DBG_X
    lda #'.'
    jsr K_CHROUT
    jsr PRINT_DBG_Y
    lda #'.'
    jsr K_CHROUT
    jsr PRINT_DBG_Z
    lda #<MSG_RX_FLAGS
    ldx #>MSG_RX_FLAGS
    jsr PRINT_Z
    lda #<MIP_RX_DEBUG4
    ldx #>MIP_RX_DEBUG4
    jsr CALL_DEBUG_TARGET
    jsr PRINT_DBG_A
    lda #CR
    jmp K_CHROUT

PRINT_DHCP_STATE:
    lda TEMP_A
    cmp #1
    beq _dhcp_discover
    cmp #2
    beq _dhcp_offer
    cmp #3
    beq _dhcp_request
    cmp #4
    beq _dhcp_bound
    rts
_dhcp_discover:
    lda #<MSG_DHCP_DISCOVER
    ldx #>MSG_DHCP_DISCOVER
    jmp PRINT_Z
_dhcp_offer:
    lda #<MSG_DHCP_OFFER
    ldx #>MSG_DHCP_OFFER
    jmp PRINT_Z
_dhcp_request:
    lda #<MSG_DHCP_REQUEST
    ldx #>MSG_DHCP_REQUEST
    jmp PRINT_Z
_dhcp_bound:
    lda #<MSG_DHCP_BOUND
    ldx #>MSG_DHCP_BOUND
    jmp PRINT_Z

WAIT_FRAME:
    lda FRAMECOUNT
_wait_frame_loop:
    cmp FRAMECOUNT
    beq _wait_frame_loop
    rts

RESET_DHCP_TIMEOUT:
    lda #<DHCP_TIMEOUT_FRAMES
    sta TIMEOUT_LO
    lda #>DHCP_TIMEOUT_FRAMES
    sta TIMEOUT_HI
    bra RESET_TIMEOUT_FRAME

RESET_DNS_TIMEOUT:
    lda #<DNS_TIMEOUT_FRAMES
    sta TIMEOUT_LO
    lda #>DNS_TIMEOUT_FRAMES
    sta TIMEOUT_HI
    bra RESET_TIMEOUT_FRAME

RESET_CONNECT_TIMEOUT:
    lda #<CONNECT_TIMEOUT_FRAMES
    sta TIMEOUT_LO
    lda #>CONNECT_TIMEOUT_FRAMES
    sta TIMEOUT_HI

RESET_TIMEOUT_FRAME:
    lda FRAMECOUNT
    sta TIMEOUT_FRAME_LAST
    rts

DEC_TIMEOUT_FRAME:
    lda FRAMECOUNT
    cmp TIMEOUT_FRAME_LAST
    beq _timeout_frame_same
    sta TIMEOUT_FRAME_LAST
    bra DEC_TIMEOUT
_timeout_frame_same:
    clc
    rts

DEC_TIMEOUT:
    lda TIMEOUT_LO
    bne _dec_lo
    lda TIMEOUT_HI
    beq _timeout_done
    dec TIMEOUT_HI
_dec_lo:
    dec TIMEOUT_LO
    clc
    rts
_timeout_done:
    sec
    rts

;-----------------------------------------------------------------------------
; Storage
;-----------------------------------------------------------------------------
LINE_LEN:               .byte 0
LINEBUF:                .fill 80, 0
IPBUF:                  .byte 0,0,0,0
OCTET_INDEX:            .byte 0
CUR_VALUE:              .byte 0
DIGIT_VALUE:            .byte 0
DIGIT_SEEN:             .byte 0
PORT_LO:                .byte 0
PORT_HI:                .byte 0
IP_PRINT_INDEX:         .byte 0
DEC_VALUE:              .byte 0
DEC_PRINTED:            .byte 0
TEMP_A:                 .byte 0
TEMP_LO:                .byte 0
TEMP_HI:                .byte 0
DBG_A:                  .byte 0
DBG_X:                  .byte 0
DBG_Y:                  .byte 0
DBG_Z:                  .byte 0
TIMEOUT_LO:             .byte 0
TIMEOUT_HI:             .byte 0
TIMEOUT_FRAME_LAST:     .byte 0
LAST_DHCP_STATE:        .byte 0
TERM_MODE:              .byte 0
RX_PUMP_COUNT:          .byte 0
TERMINAL_EVENT:         .byte 0
RX_BLOCK_COUNT:         .byte 0
RX_BLOCK_INDEX:         .byte 0
ASCII_ROW:              .byte 0
ASCII_COL:              .byte 0
ASCII_PTR_LO:           .byte 0
ASCII_PTR_HI:           .byte 0
ASCII_COLOR_PTR_LO:     .byte 0
ASCII_COLOR_PTR_HI:     .byte 0
ASCII_COLOR:            .byte ASCII_DEFAULT_COLOR
ASCII_FG_COLOR:         .byte ASCII_DEFAULT_COLOR
ASCII_BG_COLOR:         .byte COLOR_BLACK
ASCII_STR_LO:           .byte 0
ASCII_STR_HI:           .byte 0
ASCII_CHAR:             .byte 0
ANSI_STATE:             .byte 0
ANSI_CHAR:              .byte 0
ANSI_FINAL:             .byte 0
ANSI_PARAM0:            .byte 0
ANSI_PARAM1:            .byte 0
ANSI_PARAM2:            .byte 0
ANSI_PARAM3:            .byte 0
ANSI_PARAM4:            .byte 0
ANSI_PARAM5:            .byte 0
ANSI_PARAM6:            .byte 0
ANSI_PARAM7:            .byte 0
ANSI_PARAM_CUR:         .byte 0
ANSI_PARAM_INDEX:       .byte 0
ANSI_SAW_DIGIT:         .byte 0
ANSI_BRIGHT:            .byte 0
ANSI_PRIVATE:           .byte 0
ANSI_INTERMEDIATE:      .byte 0
ANSI_INVERSE:           .byte 0
ANSI_ORIGIN_MODE:       .byte 0
ANSI_CHARSET_TARGET:    .byte 0
ANSI_G0_GRAPHICS:       .byte 0
ANSI_G1_GRAPHICS:       .byte 0
ANSI_USE_G1:            .byte 0
ANSI_CURSOR_APP_MODE:   .byte 0
ANSI_RGB_R:             .byte 0
ANSI_RGB_G:             .byte 0
ANSI_RGB_B:             .byte 0
ANSI_COLOR_BITS:        .byte 0
ANSI_COLOR_INDEX:       .byte 0
ANSI_COLOR_WORK:        .byte 0
ASCII_WRAP_MODE:        .byte 1
ASCII_SCROLL_TOP:       .byte 0
ASCII_SCROLL_BOTTOM:    .byte SCREEN_ROWS-1
ASCII_SAVED_ROW:        .byte 0
ASCII_SAVED_COL:        .byte 0
ASCII_SAVED_FG_COLOR:   .byte ASCII_DEFAULT_COLOR
ASCII_SAVED_BG_COLOR:   .byte COLOR_BLACK
ANSI_SAVED_BRIGHT:      .byte 0
ANSI_SAVED_INVERSE:     .byte 0
ANSI_SAVED_G0_GRAPHICS: .byte 0
ANSI_SAVED_G1_GRAPHICS: .byte 0
ANSI_SAVED_USE_G1:      .byte 0
ASCII_ERASE_ROW:        .byte 0
ASCII_WORK_START:       .byte 0
ASCII_WORK_COUNT:       .byte 0
ASCII_WORK_BYTE:        .byte 0
ASCII_WORK_COLOR:       .byte 0
ASCII_WORK_COL:         .byte 0
ASCII_WORK_DST_COL:     .byte 0
ASCII_SRC_ROW:          .byte 0
ASCII_DST_ROW:          .byte 0
ASCII_COLOR_SRC_LO:     .byte 0
ASCII_COLOR_SRC_HI:     .byte 0
ASCII_COLOR_DST_LO:     .byte 0
ASCII_COLOR_DST_HI:     .byte 0
CURSOR_SPRITE_X_HI:     .byte 0
FAR_TARGET_LO_VAR:      .byte 0
FAR_TARGET_HI_VAR:      .byte 0
ARG_A_VAR:              .byte 0
ARG_X_VAR:              .byte 0
ARG_Y_VAR:              .byte 0
STAGE_TARGET_LO_VAR:    .byte 0
STAGE_TARGET_HI_VAR:    .byte 0
STAGE_ARG_A_VAR:        .byte 0
STAGE_ARG_X_VAR:        .byte 0
STAGE_ARG_Y_VAR:        .byte 0
STAGE_ARG_Z_VAR:        .byte 0
PHONE_COUNT:            .byte 0
PHONE_PAGE:             .byte 0
PHONE_EOF_PENDING:      .byte 0
PHONE_INDEX:            .byte 0
PHONE_WORK_INDEX:       .byte 0
PHONE_LINE_INDEX:       .byte 0
PHONE_PICK_MODE:        .byte 0
PHONE_FIELD_OFFSET_VAR: .byte 0
PHONE_FIELD_MAX_VAR:    .byte 0
PHONEBOOK:              .fill PHONE_MAX*PHONE_ENTRY_SIZE, 0

SCREEN_ROW_LO:
    .byte $00,$50,$a0,$f0,$40,$90,$e0,$30,$80,$d0
    .byte $20,$70,$c0,$10,$60,$b0,$00,$50,$a0,$f0
    .byte $40,$90,$e0,$30,$80
SCREEN_ROW_HI:
    .byte $08,$08,$08,$08,$09,$09,$09,$0a,$0a,$0a
    .byte $0b,$0b,$0b,$0c,$0c,$0c,$0d,$0d,$0d,$0d
    .byte $0e,$0e,$0e,$0f,$0f

ANSI_COLOR_NORMAL:
    .byte COLOR_BLACK,COLOR_RED,COLOR_GREEN,COLOR_YELLOW
    .byte COLOR_BLUE,COLOR_PURPLE,COLOR_CYAN,COLOR_WHITE
ANSI_COLOR_BRIGHT:
    .byte COLOR_DARK_GREY,COLOR_LIGHT_RED,COLOR_LIGHT_GREEN,COLOR_YELLOW
    .byte COLOR_LIGHT_BLUE,COLOR_PURPLE,COLOR_CYAN,COLOR_WHITE

    .align 16
CURSOR_SPRITE_PTRS:
    .word 0
    .word 0,0,0,0,0,0,0

    .align 64
CURSOR_SPRITE_SHAPE:
    .byte %11110000,%00000000,%00000000
    .byte %11110000,%00000000,%00000000
    .byte %11110000,%00000000,%00000000
    .byte %11110000,%00000000,%00000000
    .byte %11110000,%00000000,%00000000
    .byte %11110000,%00000000,%00000000
    .byte %11110000,%00000000,%00000000
    .byte %11110000,%00000000,%00000000
    .byte %00000000,%00000000,%00000000
    .byte %00000000,%00000000,%00000000
    .byte %00000000,%00000000,%00000000
    .byte %00000000,%00000000,%00000000
    .byte %00000000,%00000000,%00000000
    .byte %00000000,%00000000,%00000000
    .byte %00000000,%00000000,%00000000
    .byte %00000000,%00000000,%00000000
    .byte %00000000,%00000000,%00000000
    .byte %00000000,%00000000,%00000000
    .byte %00000000,%00000000,%00000000
    .byte %00000000,%00000000,%00000000
    .byte %00000000,%00000000,%00000000
    .byte 0

RX_BLOCK_BUF:
    .fill RX_BLOCK_MAX, 0

MSG_TITLE:
    .byte CLR, PET_MIXED, CR
    .byte PET_CYAN
    .byte $20
    .fill 78, PET_HLINE
    .byte CR
    .byte PET_YELLOW
    .text "   Mega-IP ANSI-Term 1.0"
    .byte CR
    .byte PET_WHITE
    .text "   45GS02 Assembly Terminal for ANSI, ASCII, and PETSCII Systems"
    .byte CR
    .byte PET_CYAN
    .byte $20
    .fill 78, PET_HLINE
    .byte CR
    .byte PET_GREEN
    .text "   Ctrl-W disconnects        Cursor keys send ANSI sequences"
    .byte CR
    .byte PET_WHITE
    .text "   Built on the Mega-IP TCP/IP stack for the MEGA65"
    .byte CR, CR, 0
MSG_RESET:
    .text "Resetting Ethernet..."
    .byte CR, 0
MSG_CONFIG:
    .byte CR
    .text "[D]HCP or [M]anual network setup? "
    .byte 0
MSG_DHCP_START:
    .byte CR
    .text "STARTING DHCP..."
    .byte CR, 0
MSG_DHCP_DISCOVER:
    .text "..DISCOVER SENT"
    .byte CR, 0
MSG_DHCP_OFFER:
    .text "..OFFER SEEN"
    .byte CR, 0
MSG_DHCP_REQUEST:
    .text "..REQUEST SENT"
    .byte CR, 0
MSG_DHCP_BOUND:
    .text "..IP BOUND"
    .byte CR, 0
MSG_DHCP_FAIL:
    .text "DHCP FAILED OR TIMED OUT."
    .byte CR, 0
MSG_SETTINGS_HDR:
    .byte CR
    .text "NETWORK SETTINGS:"
    .byte CR, 0
MSG_LOCAL_IP:
    .text "LOCAL IP       : "
    .byte 0
MSG_GATEWAY:
    .text "DEFAULT GATEWAY: "
    .byte 0
MSG_SUBNET:
    .text "SUBNET MASK    : "
    .byte 0
MSG_DNS:
    .text "PRIMARY DNS    : "
    .byte 0
MSG_NETWORK_READY:
    .text "NETWORK READY."
    .byte CR, 0
MSG_TERM_MODE:
    .byte CR
    .text "TERM MODE [A]SCII OR [P]ETSCII? "
    .byte 0
MSG_CONNECT_BY:
    .byte CR
    .text "CONNECT BY [I]P ADDRESS, [H]OST NAME, OR [P]HONEBOOK? "
    .byte 0
MSG_REMOTE_IP:
    .text "REMOTE IP      : "
    .byte 0
MSG_REMOTE_HOST:
    .text "HOST NAME      : "
    .byte 0
MSG_REMOTE_PORT:
    .text "REMOTE PORT    : "
    .byte 0
MSG_BAD_HOST:
    .text "BAD HOST NAME."
    .byte CR, 0
MSG_RESOLVING:
    .byte CR
    .text "RESOLVING HOST '"
    .byte 0
MSG_QUOTE_CR:
    .text "'"
    .byte CR, 0
MSG_RESOLVED_TO:
    .text "RESOLVED TO "
    .byte 0
MSG_LOOKUP_FAIL:
    .text "HOST LOOKUP FAILED."
    .byte CR, 0
MSG_DNS_DEBUG1:
    .text "DNS DEBUG S="
    .byte 0
MSG_DNS_DEBUG2:
    .text "DNS DEBUG RX="
    .byte 0
MSG_DNS_DEBUG3:
    .text "DNS DEBUG QD="
    .byte 0
MSG_BAD_IP:
    .text "BAD IP ADDRESS."
    .byte CR, 0
MSG_BAD_PORT:
    .text "BAD PORT."
    .byte CR, 0
MSG_PHONE_TITLE:
    .byte CLR, PET_MIXED, PET_CYAN
    .byte $20
    .fill 78, PET_HLINE
    .byte CR
    .byte PET_YELLOW
    .text "   ANSI-Term Phonebook"
    .byte CR
    .byte PET_CYAN
    .byte $20
    .fill 78, PET_HLINE
    .byte CR, CR
    .byte PET_WHITE, 0
MSG_PHONE_EMPTY:
    .text "   No phonebook entries yet."
    .byte CR, 0
MSG_PHONE_PAGE:
    .text "   Page "
    .byte 0
MSG_PHONE_OF:
    .text " of "
    .byte 0
MSG_PHONE_HOST_LINE:
    .text "      Host: "
    .byte 0
MSG_PHONE_USER_LINE:
    .text "      User ID: "
    .byte 0
MSG_PHONE_COMMAND:
    .byte CR, PET_GREEN
    .text "   #=Dial  < >=Page  A=Add  E=Edit  D=Del  R=Reload  Q=Quit: "
    .byte PET_WHITE, 0
MSG_PHONE_ADD_TITLE:
    .byte PET_CYAN
    .byte $20
    .fill 78, PET_HLINE
    .byte CR
    .byte PET_YELLOW
    .text "   Add Phonebook Entry"
    .byte CR
    .byte PET_CYAN
    .byte $20
    .fill 78, PET_HLINE
    .byte CR, CR
    .byte PET_WHITE, 0
MSG_PHONE_EDIT_TITLE:
    .byte PET_CYAN
    .byte $20
    .fill 78, PET_HLINE
    .byte CR
    .byte PET_YELLOW
    .text "   Edit Phonebook Entry"
    .byte CR
    .byte PET_CYAN
    .byte $20
    .fill 78, PET_HLINE
    .byte CR, CR
    .byte PET_WHITE, 0
MSG_PHONE_NAME:
    .text "NAME    : "
    .byte 0
MSG_PHONE_HOST:
    .text "HOST/IP : "
    .byte 0
MSG_PHONE_PORT:
    .text "PORT    : "
    .byte 0
MSG_PHONE_TYPE:
    .text "TYPE [A/P]: "
    .byte 0
MSG_PHONE_USER:
    .text "USER ID : "
    .byte 0
MSG_PHONE_BLANK_KEEP:
    .text "LEAVE A FIELD BLANK TO KEEP ITS CURRENT VALUE."
    .byte CR, CR, 0
MSG_PHONE_FULL:
    .text "PHONEBOOK IS FULL."
    .byte CR, 0
MSG_PHONE_BAD_NAME:
    .text "BAD NAME."
    .byte CR, 0
MSG_PHONE_BAD_TYPE:
    .text "TYPE MUST BE A OR P."
    .byte CR, 0
MSG_PHONE_PICK:
    .byte CR, PET_GREEN
    .text "ENTRY NUMBER: "
    .byte PET_WHITE, 0
MSG_PHONE_BAD_ENTRY:
    .text "BAD ENTRY."
    .byte CR, 0
MSG_PHONE_DELETE_CONFIRM:
    .text "DELETE THIS ENTRY [Y/N]? "
    .byte 0
MSG_PHONE_SAVED:
    .text "PHONEBOOK SAVED."
    .byte CR, 0
MSG_PHONE_SAVE_FAIL:
    .text "PHONEBOOK SAVE FAILED."
    .byte CR, 0
MSG_PHONE_DIAL:
    .byte CR
    .text "DIALING "
    .byte 0
MSG_PRESS_KEY:
    .text "PRESS ANY KEY."
    .byte CR, 0
PHONE_READ_NAME:
    .text "ANSI-TERM.PB,S,R"
PHONE_READ_NAME_END:
PHONE_WRITE_NAME:
    .text "@0:ANSI-TERM.PB,S,W"
PHONE_WRITE_NAME_END:
MSG_CONNECTING:
    .byte CR
    .text "CONNECTING TO "
    .byte 0
MSG_DOTS_CR:
    .text "..."
    .byte CR, 0
MSG_CONNECT_FAIL:
    .text "CONNECT FAILED - PRESS ANY KEY."
    .byte CR, 0
MSG_REMOTE_STORED:
    .text "REMOTE STORED="
    .byte 0
MSG_CONN_DEBUG1:
    .text "CONNECT DEBUG EV="
    .byte 0
MSG_CONN_DEBUG2:
    .text "CONNECT DEBUG TX="
    .byte 0
MSG_CONN_DEBUG3:
    .text "CONNECT DEBUG DC="
    .byte 0
MSG_DBG_ST:
    .text " ST="
    .byte 0
MSG_DBG_TX:
    .text " TX="
    .byte 0
MSG_DBG_TF:
    .text " TF="
    .byte 0
MSG_DBG_ARP:
    .text " ARP="
    .byte 0
MSG_DBG_PF:
    .text " PF="
    .byte 0
MSG_DBG_P:
    .text " P="
    .byte 0
MSG_DBG_AN:
    .text " AN="
    .byte 0
MSG_DBG_NS:
    .text " NS="
    .byte 0
MSG_DBG_BF:
    .text " BF="
    .byte 0
MSG_DBG_RS:
    .text " RS="
    .byte 0
MSG_DBG_SA:
    .text " SA="
    .byte 0
MSG_DBG_BA:
    .text " BA="
    .byte 0
MSG_DBG_RAW:
    .text " RAW="
    .byte 0
MSG_DBG_TCP:
    .text " TCP="
    .byte 0
MSG_DBG_EH:
    .text " EH="
    .byte 0
MSG_DBG_EL:
    .text " EL="
    .byte 0
MSG_DBG_PR:
    .text " PR="
    .byte 0
MSG_DBG_SP:
    .text " SP="
    .byte 0
MSG_DBG_DP:
    .text " DP="
    .byte 0
MSG_SYN_PORTS:
    .text "SYN PORT DP="
    .byte 0
MSG_SYN_DST:
    .text "SYN DST="
    .byte 0
MSG_SYN_SEQ:
    .text "SYN SEQ="
    .byte 0
MSG_SYNACK_SEQ:
    .text "SYNACK SEQ="
    .byte 0
MSG_SYNACK_ACK:
    .text "SYNACK ACK="
    .byte 0
MSG_SYNACK_EXPECT:
    .text "EXP ACK="
    .byte 0
MSG_RX_PORTS:
    .text "RX PORT SP="
    .byte 0
MSG_RX_SRC:
    .text "RX SRC="
    .byte 0
MSG_RX_FLAGS:
    .text " FL="
    .byte 0
MSG_CONNECTED:
    .text "CONNECTED. CTRL-W OR F7 DISCONNECTS."
    .byte CR, CR, 0
MSG_TERMINATED:
    .byte CR
    .text "CONNECTION TERMINATED."
    .byte CR, 0
MSG_DISCONNECTING:
    .byte CR
    .text "DISCONNECTING."
    .byte CR, 0
