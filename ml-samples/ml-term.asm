; ---------------------------------------------------------------------------
; ml-term - simple MegaIP terminal sample in 45GS02 assembly
;
; Build:
;   ..\64tass.exe --cbm-prg ml-term.asm -L ml-term.lst -o ml-term.prg
;
; Run from BASIC 65. ETH.BIN must be on the same disk; this program loads it.
;   LOAD "ML-TERM.PRG"
;   RUN
;
; The BASIC launcher line jumps into this machine-language program. The
; terminal sends typed bytes directly through MegaIP's ML-friendly send-byte
; entry point; it does not use BASIC A$ for terminal I/O.
; ---------------------------------------------------------------------------

.cpu "45gs02"

; ---------------------------------------------------------------------------
; User settings
; ---------------------------------------------------------------------------

LOCAL_PORT      = $c001

; ---------------------------------------------------------------------------
; MegaIP public jump table. eth.bin is loaded at P($42000), which maps to
; bank 4 offset $2000.
; ---------------------------------------------------------------------------

MEGAIP_BANK             = $04
PROGRAM_BANK            = $00
MIP_INIT                = $2000
MIP_SET_GATEWAY_IP      = $2003
MIP_SET_LOCAL_IP        = $2006
MIP_SET_LOCAL_PORT      = $2009
MIP_SET_REMOTE_IP       = $200c
MIP_SET_REMOTE_PORT     = $200f
MIP_SET_SUBNET_MASK     = $2012
MIP_SET_CHAR_XLATE      = $2015
MIP_RBUF_GET            = $201e
MIP_DISCONNECT          = $2021
MIP_STATUS_POLL         = $2024
MIP_CONNECT_START       = $2027
MIP_CONNECT_POLL        = $202a
MIP_DNS_RESULT_IP       = $2033
MIP_DNS_STATE           = $2036
MIP_DHCP_START          = $2042
MIP_DHCP_POLL           = $2045
MIP_SET_PRIMARY_DNS     = $204b
MIP_GET_LOCAL_IP        = $204e
MIP_GET_GATEWAY_IP      = $2051
MIP_GET_SUBNET_MASK     = $2054
MIP_GET_PRIMARY_DNS     = $2057
MIP_GET_REMOTE_IP       = $205a
MIP_TCP_FORCE_CLOSE     = $205d
MIP_GET_ABI_INFO        = $2060
MIP_SEND_BYTE           = $7000
MIP_DNS_LOOKUP_BUFFER   = $7003
MIP_INIT_ML_SAFE        = $7006
MIP_DHCP_DEBUG          = $7009
MIP_DHCP_DEBUG_TX       = $700c
MIP_DNS_START_BUFFER    = $700f
MIP_DNS_DEBUG           = $7012
MIP_DNS_DEBUG2          = $7015
MIP_DNS_START_BUFFER_YLEN = $7018
MIP_CALL_STAGED         = $701b
MIP_RBUF_GET_BYTE       = $701e
MIP_RBUF_GET_BLOCK      = $7021
MIP_STAGED_ARGS         = $71c0
MIP_CALL_BLOCK_LEN      = $06

CONN_CONNECTED          = %00000001
CONN_FAILED             = %00000010
DNS_STATE_DONE          = $02
DNS_STATE_FAIL          = $03
DNS_TIMEOUT_TICKS       = 600
DHCP_STATE_BOUND        = $04
DHCP_STATE_FAILED       = $7f
DHCP_TIMEOUT_TICKS      = 1200
RX_SLICE_BUDGET         = $10

; ---------------------------------------------------------------------------
; ROM and system locations
; ---------------------------------------------------------------------------

KERNAL_CHROUT           = $ffd2
KERNAL_GETIN            = $ffe4
KERNAL_SETLFS           = $ffba
KERNAL_SETNAM           = $ffbd
KERNAL_SETBNK           = $ff6b
KERNAL_LOAD             = $ffd5
KERNAL_JSRFAR           = $ff6e
VIC_RASTER              = $d012
VIC_CTRL1               = $d011
VIC_BORDER              = $d020
VIC_BACKGROUND          = $d021

KEY_CTRL_W              = $17
CHR_CR                  = $0d
CHR_LF                  = $0a
CHR_BACKSPACE           = $08
CHR_DELETE              = $14
CHR_LOWER               = $0e
CHR_CLEAR               = $93
LINE_INPUT_MAX          = 63

; ---------------------------------------------------------------------------
; Call a MegaIP routine through a staged bank-4 dispatcher. KERNAL JSRFAR is
; used only for the no-argument dispatcher call; entry registers are DMA-staged
; first because JSRFAR does not preserve them for the far target.
; ---------------------------------------------------------------------------

MIP_CALL .macro target
    sta mip_arg_a
    lda #<\target
    sta mip_call_target_lo
    lda #>\target
    sta mip_call_target_hi
    lda #$00
    tab
    stx mip_arg_x
    sty mip_arg_y
    tza
    sta mip_arg_z

    lda $02
    sta mip_save_02
    lda $03
    sta mip_save_03
    lda $04
    sta mip_save_04
    lda $05
    sta mip_save_05

    lda #$00
    sta $d707
    .byte $80
    .byte $00
    .byte $81
    .byte $00
    .byte $00
    .byte $00
    .byte <MIP_CALL_BLOCK_LEN, >MIP_CALL_BLOCK_LEN
    .byte <mip_call_target_lo, >mip_call_target_lo, PROGRAM_BANK
    .byte <MIP_STAGED_ARGS, >MIP_STAGED_ARGS, MEGAIP_BANK
    .byte $00
    .word $0000

    lda #MEGAIP_BANK
    sta $02
    lda #>MIP_CALL_STAGED
    sta $03
    lda #<MIP_CALL_STAGED
    sta $04
    lda #$04
    sta $05

    jsr KERNAL_JSRFAR

    php
    sta mip_ret_a
    stx mip_ret_x
    sty mip_ret_y
    tza
    sta mip_ret_z

    lda #$00
    tab

    lda mip_save_02
    sta $02
    lda mip_save_03
    sta $03
    lda mip_save_04
    sta $04
    lda mip_save_05
    sta $05

    lda mip_ret_z
    taz
    ldy mip_ret_y
    ldx mip_ret_x
    lda mip_ret_a
    plp
.endm

MIP_CALL_DIRECT .macro target
    lda $02
    sta mip_save_02
    lda $03
    sta mip_save_03
    lda $04
    sta mip_save_04
    lda $05
    sta mip_save_05

    lda #MEGAIP_BANK
    sta $02
    lda #>\target
    sta $03
    lda #<\target
    sta $04
    lda #$04
    sta $05

    jsr KERNAL_JSRFAR

    php
    sta mip_ret_a
    stx mip_ret_x
    sty mip_ret_y
    tza
    sta mip_ret_z

    lda #$00
    tab

    lda mip_save_02
    sta $02
    lda mip_save_03
    sta $03
    lda mip_save_04
    sta $04
    lda mip_save_05
    sta $05

    lda mip_ret_z
    taz
    ldy mip_ret_y
    ldx mip_ret_x
    lda mip_ret_a
    plp
.endm

; ---------------------------------------------------------------------------
; BASIC launcher: 10 SYS 8448
; ---------------------------------------------------------------------------

* = $2001

    .word basic_end
    .word 10
    .byte $9e, $20
    .text "8448"
    .byte $00
basic_end:
    .word $0000

* = $2100

start:
    lda #$00
    sta VIC_BORDER
    sta VIC_BACKGROUND
    lda #CHR_LOWER
    jsr KERNAL_CHROUT
    jsr clear_screen
    lda #<msg_banner
    ldx #>msg_banner
    jsr print_string

    lda #<msg_loading
    ldx #>msg_loading
    jsr print_string
    jsr load_megaip_library
    bcc library_loaded

    lda #<msg_load_failed
    ldx #>msg_load_failed
    jsr print_string
    rts

library_loaded:
    lda #<msg_init
    ldx #>msg_init
    jsr print_string
    MIP_CALL_DIRECT MIP_INIT

    lda #$01
    MIP_CALL MIP_SET_CHAR_XLATE

    jsr configure_network

configured:
    MIP_CALL_DIRECT MIP_TCP_FORCE_CLOSE
    jsr configure_remote

    lda #<msg_connecting
    ldx #>msg_connecting
    jsr print_string
    jsr connect_remote
    bcc connected

    lda #<msg_connect_failed
    ldx #>msg_connect_failed
    jsr print_string
    jmp configured

connected:
    lda #<msg_connected
    ldx #>msg_connected
    jsr print_string
    jsr terminal_loop
    jmp configured

load_megaip_library:
    lda #$00
    tab

    lda #MEGAIP_BANK
    ldx #$00
    jsr KERNAL_SETBNK

    lda #$00
    ldx #$08
    ldy #$00
    jsr KERNAL_SETLFS

    lda #eth_bin_name_end - eth_bin_name
    ldx #<eth_bin_name
    ldy #>eth_bin_name
    jsr KERNAL_SETNAM

    lda #$40
    ldx #<MIP_INIT
    ldy #>MIP_INIT
    jsr KERNAL_LOAD
    bcs load_megaip_failed

    lda #$00
    tax
    jsr KERNAL_SETBNK
    clc
    rts

load_megaip_failed:
    sta load_error
    lda #$00
    tax
    jsr KERNAL_SETBNK
    lda load_error
    sec
    rts

configure_network:
    lda #<msg_config_mode
    ldx #>msg_config_mode
    jsr print_string

config_key:
    jsr wait_key
    cmp #'D'
    beq config_dhcp
    cmp #'d'
    beq config_dhcp
    cmp #'M'
    beq config_manual
    cmp #'m'
    beq config_manual
    jmp config_key

config_dhcp:
    jsr KERNAL_CHROUT
    jsr print_cr
    jsr configure_dhcp
    bcc config_done

    lda #<msg_dhcp_failed_manual
    ldx #>msg_dhcp_failed_manual
    jsr print_string
    jsr configure_manual
    jmp config_done

config_manual:
    jsr KERNAL_CHROUT
    jsr print_cr
    jsr configure_manual

config_done:
    clc
    rts

configure_dhcp:
    lda #<msg_dhcp
    ldx #>msg_dhcp
    jsr print_string

    MIP_CALL_DIRECT MIP_DHCP_START

    lda #<DHCP_TIMEOUT_TICKS
    sta timeout_lo
    lda #>DHCP_TIMEOUT_TICKS
    sta timeout_hi
    lda #$00
    sta dot_counter
    lda #$ff
    sta dhcp_last_state
    jsr print_dhcp_debug

dhcp_loop:
    MIP_CALL_DIRECT MIP_DHCP_POLL
    sta dhcp_state
    jsr print_dhcp_state
    lda dhcp_state
    cmp #DHCP_STATE_BOUND
    beq dhcp_ok
    cmp #DHCP_STATE_FAILED
    beq dhcp_fail

    inc dot_counter
    lda dot_counter
    and #$07
    bne dhcp_skip_dot
    lda #'.'
    jsr KERNAL_CHROUT
dhcp_skip_dot:
    lda dot_counter
    and #$3f
    bne dhcp_skip_debug
    jsr print_dhcp_debug
dhcp_skip_debug:
    jsr wait_frame
    jsr dec_timeout
    bcc dhcp_loop

dhcp_timeout:
    lda #<msg_dhcp_timeout
    ldx #>msg_dhcp_timeout
    jsr print_string
    jsr print_dhcp_debug
    sec
    rts

dhcp_fail:
    lda #<msg_dhcp_nak
    ldx #>msg_dhcp_nak
    jsr print_string
    jsr print_dhcp_debug
    sec
    rts

dhcp_ok:
    jsr print_cr
    clc
    rts

print_dhcp_state:
    cmp dhcp_last_state
    beq print_dhcp_done
    sta dhcp_last_state
    cmp #$01
    beq print_dhcp_discover
    cmp #$02
    beq print_dhcp_offer
    cmp #$03
    beq print_dhcp_request
    cmp #$04
    beq print_dhcp_bound
    cmp #DHCP_STATE_FAILED
    beq print_dhcp_failed_state
print_dhcp_done:
    rts

print_dhcp_discover:
    lda #<msg_dhcp_discover
    ldx #>msg_dhcp_discover
    jmp print_string

print_dhcp_offer:
    lda #<msg_dhcp_offer
    ldx #>msg_dhcp_offer
    jmp print_string

print_dhcp_request:
    lda #<msg_dhcp_request
    ldx #>msg_dhcp_request
    jmp print_string

print_dhcp_bound:
    lda #<msg_dhcp_bound
    ldx #>msg_dhcp_bound
    jmp print_string

print_dhcp_failed_state:
    lda #<msg_dhcp_failed_state
    ldx #>msg_dhcp_failed_state
    jmp print_string

print_dhcp_debug:
    MIP_CALL_DIRECT MIP_DHCP_DEBUG
    sta dhcp_debug_rx
    stx dhcp_debug_udp
    sty dhcp_debug_stage
    tza
    sta dhcp_debug_msg

    MIP_CALL_DIRECT MIP_DHCP_DEBUG_TX
    sta dhcp_debug_disc_ok
    stx dhcp_debug_disc_fail
    sty dhcp_debug_req_ok
    tza
    sta dhcp_debug_req_fail

    lda #<msg_dhcp_debug_rx
    ldx #>msg_dhcp_debug_rx
    jsr print_string
    lda dhcp_debug_rx
    jsr print_hex_byte

    lda #<msg_dhcp_debug_udp
    ldx #>msg_dhcp_debug_udp
    jsr print_string
    lda dhcp_debug_udp
    jsr print_hex_byte

    lda #<msg_dhcp_debug_stage
    ldx #>msg_dhcp_debug_stage
    jsr print_string
    lda dhcp_debug_stage
    jsr print_hex_byte

    lda #<msg_dhcp_debug_msg
    ldx #>msg_dhcp_debug_msg
    jsr print_string
    lda dhcp_debug_msg
    jsr print_hex_byte

    lda #<msg_dhcp_debug_disc_ok
    ldx #>msg_dhcp_debug_disc_ok
    jsr print_string
    lda dhcp_debug_disc_ok
    jsr print_hex_byte

    lda #<msg_dhcp_debug_disc_fail
    ldx #>msg_dhcp_debug_disc_fail
    jsr print_string
    lda dhcp_debug_disc_fail
    jsr print_hex_byte

    lda #<msg_dhcp_debug_req_ok
    ldx #>msg_dhcp_debug_req_ok
    jsr print_string
    lda dhcp_debug_req_ok
    jsr print_hex_byte

    lda #<msg_dhcp_debug_req_fail
    ldx #>msg_dhcp_debug_req_fail
    jsr print_string
    lda dhcp_debug_req_fail
    jsr print_hex_byte
    jmp print_cr

print_dns_debug:
    MIP_CALL_DIRECT MIP_DNS_DEBUG
    sta dns_debug_state
    stx dns_debug_stage
    sty dns_debug_tx_ok
    tza
    sta dns_debug_tx_fail

    MIP_CALL_DIRECT MIP_DNS_DEBUG2
    sta dns_debug_rx
    stx dns_debug_arp
    sty dns_debug_parse_fail
    tza
    sta dns_debug_port_hi

    lda #<msg_dns_debug_state
    ldx #>msg_dns_debug_state
    jsr print_string
    lda dns_debug_state
    jsr print_hex_byte

    lda #<msg_dns_debug_stage
    ldx #>msg_dns_debug_stage
    jsr print_string
    lda dns_debug_stage
    jsr print_hex_byte

    lda #<msg_dns_debug_tx_ok
    ldx #>msg_dns_debug_tx_ok
    jsr print_string
    lda dns_debug_tx_ok
    jsr print_hex_byte

    lda #<msg_dns_debug_tx_fail
    ldx #>msg_dns_debug_tx_fail
    jsr print_string
    lda dns_debug_tx_fail
    jsr print_hex_byte

    lda #<msg_dns_debug_rx
    ldx #>msg_dns_debug_rx
    jsr print_string
    lda dns_debug_rx
    jsr print_hex_byte

    lda #<msg_dns_debug_arp
    ldx #>msg_dns_debug_arp
    jsr print_string
    lda dns_debug_arp
    jsr print_hex_byte

    lda #<msg_dns_debug_parse_fail
    ldx #>msg_dns_debug_parse_fail
    jsr print_string
    lda dns_debug_parse_fail
    jsr print_hex_byte

    lda #<msg_dns_debug_port_hi
    ldx #>msg_dns_debug_port_hi
    jsr print_string
    lda dns_debug_port_hi
    jsr print_hex_byte
    jmp print_cr

configure_manual:
    lda #<msg_manual_header
    ldx #>msg_manual_header
    jsr print_string

    lda #<msg_prompt_local_ip
    ldx #>msg_prompt_local_ip
    jsr read_ip_prompt
    lda parsed_ip+0
    ldx parsed_ip+1
    ldy parsed_ip+2
    ldz parsed_ip+3
    MIP_CALL MIP_SET_LOCAL_IP

    lda #<msg_prompt_gateway
    ldx #>msg_prompt_gateway
    jsr read_ip_prompt
    lda parsed_ip+0
    ldx parsed_ip+1
    ldy parsed_ip+2
    ldz parsed_ip+3
    MIP_CALL MIP_SET_GATEWAY_IP

    lda #<msg_prompt_subnet
    ldx #>msg_prompt_subnet
    jsr read_ip_prompt
    lda parsed_ip+0
    ldx parsed_ip+1
    ldy parsed_ip+2
    ldz parsed_ip+3
    MIP_CALL MIP_SET_SUBNET_MASK

    lda #<msg_prompt_dns
    ldx #>msg_prompt_dns
    jsr read_ip_prompt
    lda parsed_ip+0
    ldx parsed_ip+1
    ldy parsed_ip+2
    ldz parsed_ip+3
    MIP_CALL MIP_SET_PRIMARY_DNS
    rts

configure_remote:
    lda #<msg_remote_mode
    ldx #>msg_remote_mode
    jsr print_string

remote_mode_key:
    jsr wait_key
    cmp #'I'
    beq remote_ip
    cmp #'i'
    beq remote_ip
    cmp #'H'
    beq remote_host
    cmp #'h'
    beq remote_host
    jmp remote_mode_key

remote_ip:
    jsr KERNAL_CHROUT
    jsr print_cr
    lda #<msg_prompt_remote_ip
    ldx #>msg_prompt_remote_ip
    jsr read_ip_prompt
    lda parsed_ip+0
    ldx parsed_ip+1
    ldy parsed_ip+2
    ldz parsed_ip+3
    MIP_CALL MIP_SET_REMOTE_IP
    jmp configure_remote_port

remote_host:
    jsr KERNAL_CHROUT
    jsr print_cr
remote_host_prompt:
    jsr read_hostname_prompt
    bcs remote_host_prompt

configure_remote_port:
    jsr read_port_prompt
    lda parsed_port_hi
    ldx parsed_port_lo
    MIP_CALL MIP_SET_REMOTE_PORT

    jsr set_dynamic_local_port
    rts

set_dynamic_local_port:
    lda local_port_seed
    clc
    adc VIC_RASTER
    adc parsed_port_lo
    bne +
    lda #$40
+
    sta local_port_seed
    lda #>LOCAL_PORT
    ldx local_port_seed
    MIP_CALL MIP_SET_LOCAL_PORT
    rts

connect_remote:
    MIP_CALL_DIRECT MIP_CONNECT_START

    lda #<$0258
    sta timeout_lo
    lda #>$0258
    sta timeout_hi
    lda #$00
    sta dot_counter

connect_loop:
    MIP_CALL_DIRECT MIP_CONNECT_POLL
    sta connect_status
    and #CONN_CONNECTED
    bne connect_ok

    lda connect_status
    and #CONN_FAILED
    bne connect_fail

    inc dot_counter
    lda dot_counter
    and #$1f
    bne +
    lda #'.'
    jsr KERNAL_CHROUT
+
    jsr wait_frame
    jsr dec_timeout
    bcc connect_loop

connect_fail:
    sec
    rts

connect_ok:
    jsr print_cr
    clc
    rts

terminal_loop:
    jsr KERNAL_GETIN
    beq terminal_poll
    cmp #KEY_CTRL_W
    beq disconnect
    sta typed_key
    lda typed_key
    jsr send_char

terminal_poll:
    MIP_CALL_DIRECT MIP_STATUS_POLL
    bne disconnect
    jsr receive_pending
    jmp terminal_loop

disconnect:
    MIP_CALL_DIRECT MIP_DISCONNECT
    lda #<msg_disconnected
    ldx #>msg_disconnected
    jsr print_string
    rts

receive_pending:
    lda #<rx_buffer
    ldx #>rx_buffer
    ldy #PROGRAM_BANK
    ldz #RX_SLICE_BUDGET
    MIP_CALL MIP_RBUF_GET_BLOCK
    sta rx_count
    beq receive_done
    lda #$00
    sta rx_index

receive_next:
    ldx rx_index
    lda rx_buffer,x
    cmp #CHR_LF
    beq receive_count
    jsr KERNAL_CHROUT
receive_count:
    inc rx_index
    lda rx_index
    cmp rx_count
    bcc receive_next

receive_done:
    rts

send_char:
    jsr key_to_wire
    bcs send_done
    cmp #CHR_CR
    bne send_wire_byte

    lda #CHR_CR
    jsr send_wire_byte
    lda #CHR_LF
    jmp send_wire_byte

send_wire_byte:
    MIP_CALL MIP_SEND_BYTE
    bne send_done
    lda #<msg_tx_failed
    ldx #>msg_tx_failed
    jsr print_string
send_done:
    rts

key_to_wire:
    cmp #CHR_DELETE
    bne +
    lda #$7f
    clc
    rts
+
    cmp #CHR_BACKSPACE
    beq _key_ok
    cmp #CHR_CR
    beq _key_ok

    cmp #$80
    bcc _key_ascii_candidate
    and #$7f

_key_ascii_candidate:
    cmp #$20
    bcc _key_drop
    cmp #$7f
    bcs _key_drop

_key_ok:
    clc
    rts

_key_drop:
    sec
    rts

read_hostname_prompt:
    lda #<msg_prompt_remote_host
    ldx #>msg_prompt_remote_host
    jsr print_string
    jsr read_line
    lda line_len
    beq read_hostname_bad

    lda #<msg_resolving
    ldx #>msg_resolving
    jsr print_string
    lda #<input_buffer
    ldx #>input_buffer
    ldy #PROGRAM_BANK
    ldz line_len
    MIP_CALL MIP_DNS_START_BUFFER
    bne dns_start_ok

    jsr print_dns_debug
    jmp read_hostname_bad

dns_start_ok:

    lda #<DNS_TIMEOUT_TICKS
    sta timeout_lo
    lda #>DNS_TIMEOUT_TICKS
    sta timeout_hi
    lda #$00
    sta dot_counter
    jsr print_dns_debug

dns_loop:
    MIP_CALL_DIRECT MIP_STATUS_POLL
    MIP_CALL_DIRECT MIP_DNS_STATE
    sta dns_state
    cmp #DNS_STATE_DONE
    beq read_hostname_resolved
    cmp #DNS_STATE_FAIL
    beq read_hostname_fail_debug

    inc dot_counter
    lda dot_counter
    and #$1f
    bne dns_skip_dot
    lda #'.'
    jsr KERNAL_CHROUT
dns_skip_dot:
    lda dot_counter
    and #$7f
    bne dns_skip_debug
    jsr print_dns_debug
dns_skip_debug:
    jsr wait_frame
    jsr dec_timeout
    bcc dns_loop

read_hostname_fail_debug:
    jsr print_dns_debug
    jmp read_hostname_bad

read_hostname_resolved:
    MIP_CALL_DIRECT MIP_DNS_RESULT_IP
    sta parsed_ip+0
    stx parsed_ip+1
    sty parsed_ip+2
    tza
    sta parsed_ip+3

    lda parsed_ip+0
    ldx parsed_ip+1
    ldy parsed_ip+2
    ldz parsed_ip+3
    MIP_CALL MIP_SET_REMOTE_IP

    jsr print_cr
    clc
    rts

read_hostname_bad:
    lda #<msg_bad_host
    ldx #>msg_bad_host
    jsr print_string
    sec
    rts

read_ip_prompt:
    sta prompt_ptr_lo
    stx prompt_ptr_hi

read_ip_again:
    lda prompt_ptr_lo
    ldx prompt_ptr_hi
    jsr print_string
    jsr read_line
    jsr parse_ip
    bcc read_ip_ok

    lda #<msg_bad_ip
    ldx #>msg_bad_ip
    jsr print_string
    jmp read_ip_again

read_ip_ok:
    rts

read_port_prompt:
    lda #<msg_remote_port
    ldx #>msg_remote_port
    jsr print_string
    jsr read_line
    jsr parse_port
    bcc read_port_ok

    lda #<msg_bad_port
    ldx #>msg_bad_port
    jsr print_string
    jmp read_port_prompt

read_port_ok:
    rts

read_line:
    lda #$00
    sta line_len

read_line_next:
    jsr wait_key
    cmp #CHR_CR
    beq read_line_done
    cmp #CHR_DELETE
    beq read_line_backspace
    cmp #CHR_BACKSPACE
    beq read_line_backspace

    ldx line_len
    cpx #LINE_INPUT_MAX
    bcs read_line_next
    sta input_buffer,x
    inc line_len
    jsr KERNAL_CHROUT
    jmp read_line_next

read_line_backspace:
    ldx line_len
    beq read_line_next
    dec line_len
    lda #CHR_DELETE
    jsr KERNAL_CHROUT
    lda #' '
    jsr KERNAL_CHROUT
    lda #CHR_DELETE
    jsr KERNAL_CHROUT
    jmp read_line_next

read_line_done:
    ldx line_len
    lda #$00
    sta input_buffer,x
    jsr print_cr
    rts

wait_key:
    jsr KERNAL_GETIN
    beq wait_key
    rts

parse_ip:
    lda #$00
    sta input_index
    sta octet_index
    sta octet_value
    sta digit_count

parse_next:
    ldx input_index
    lda input_buffer,x
    beq parse_end
    cmp #'.'
    beq parse_dot
    cmp #'0'
    bcc parse_fail
    cmp #':'
    bcs parse_fail

    sec
    sbc #'0'
    sta digit_value
    lda digit_count
    cmp #$03
    bcs parse_fail
    inc digit_count
    jsr append_digit_to_octet
    bcs parse_fail
    inc input_index
    jmp parse_next

parse_dot:
    lda digit_count
    beq parse_fail
    jsr store_octet
    bcs parse_fail
    inc input_index
    lda #$00
    sta octet_value
    sta digit_count
    jmp parse_next

parse_end:
    lda digit_count
    beq parse_fail
    jsr store_octet
    bcs parse_fail
    lda octet_index
    cmp #$04
    bne parse_fail
    clc
    rts

parse_fail:
    sec
    rts

parse_port:
    lda #$00
    sta input_index
    sta digit_count
    sta parsed_port_lo
    sta parsed_port_hi

parse_port_next:
    ldx input_index
    lda input_buffer,x
    beq parse_port_end
    cmp #'0'
    bcc parse_port_fail
    cmp #':'
    bcs parse_port_fail

    sec
    sbc #'0'
    sta digit_value
    lda digit_count
    cmp #$05
    bcs parse_port_fail
    inc digit_count
    jsr append_digit_to_port
    bcs parse_port_fail
    inc input_index
    jmp parse_port_next

parse_port_end:
    lda digit_count
    beq parse_port_fail
    lda parsed_port_lo
    ora parsed_port_hi
    beq parse_port_fail
    clc
    rts

parse_port_fail:
    sec
    rts

store_octet:
    lda octet_index
    cmp #$04
    bcs store_octet_fail
    tax
    lda octet_value
    sta parsed_ip,x
    inc octet_index
    clc
    rts

store_octet_fail:
    sec
    rts

append_digit_to_octet:
    lda octet_value
    sta math_lo
    lda #$00
    sta math_hi

    asl math_lo
    rol math_hi
    lda math_lo
    sta math2_lo
    lda math_hi
    sta math2_hi

    asl math_lo
    rol math_hi
    asl math_lo
    rol math_hi

    lda math_lo
    clc
    adc math2_lo
    sta math_lo
    lda math_hi
    adc math2_hi
    sta math_hi

    lda math_lo
    clc
    adc digit_value
    sta math_lo
    lda math_hi
    adc #$00
    sta math_hi
    bne append_digit_overflow

    lda math_lo
    sta octet_value
    clc
    rts

append_digit_overflow:
    sec
    rts

append_digit_to_port:
    lda parsed_port_lo
    sta math_lo
    lda parsed_port_hi
    sta math_hi

    asl math_lo
    rol math_hi
    bcs append_port_overflow
    lda math_lo
    sta math2_lo
    lda math_hi
    sta math2_hi

    asl math_lo
    rol math_hi
    bcs append_port_overflow
    asl math_lo
    rol math_hi
    bcs append_port_overflow

    lda math_lo
    clc
    adc math2_lo
    sta math_lo
    lda math_hi
    adc math2_hi
    sta math_hi
    bcs append_port_overflow

    lda math_lo
    clc
    adc digit_value
    sta parsed_port_lo
    lda math_hi
    adc #$00
    sta parsed_port_hi
    bcs append_port_overflow

    clc
    rts

append_port_overflow:
    sec
    rts

dec_timeout:
    lda timeout_lo
    bne dec_timeout_lo
    lda timeout_hi
    beq timeout_expired
    dec timeout_hi
    lda #$ff
    sta timeout_lo
    clc
    rts

dec_timeout_lo:
    dec timeout_lo
    clc
    rts

timeout_expired:
    sec
    rts

wait_frame:
    lda VIC_RASTER
    sta wait_last_lo
    lda VIC_CTRL1
    and #$80
    sta wait_last_hi

wait_frame_loop:
    lda VIC_RASTER
    sta wait_cur_lo
    lda VIC_CTRL1
    and #$80
    sta wait_cur_hi

    lda wait_cur_hi
    cmp wait_last_hi
    bcc wait_frame_done
    bne wait_frame_update

    lda wait_cur_lo
    cmp wait_last_lo
    bcc wait_frame_done

wait_frame_update:
    lda wait_cur_lo
    sta wait_last_lo
    lda wait_cur_hi
    sta wait_last_hi
    jmp wait_frame_loop

wait_frame_done:
    rts

clear_screen:
    lda #CHR_CLEAR
    jsr KERNAL_CHROUT
    rts

print_cr:
    lda #CHR_CR
    jsr KERNAL_CHROUT
    rts

print_string:
    sta print_load+1
    stx print_load+2
    ldy #$00
print_next:
print_load:
    lda $ffff,y
    beq print_done
    jsr KERNAL_CHROUT
    iny
    bne print_next
    inc print_load+2
    bne print_next
print_done:
    rts

print_hex_byte:
    sta hex_temp
    lsr
    lsr
    lsr
    lsr
    jsr print_hex_nibble
    lda hex_temp
    and #$0f

print_hex_nibble:
    cmp #$0a
    bcc print_hex_digit
    clc
    adc #'A' - 10
    jmp KERNAL_CHROUT

print_hex_digit:
    clc
    adc #'0'
    jmp KERNAL_CHROUT

mip_call_target_lo:.byte $00
mip_call_target_hi:.byte $00
mip_arg_a:      .byte $00
mip_arg_x:      .byte $00
mip_arg_y:      .byte $00
mip_arg_z:      .byte $00
mip_ret_a:      .byte $00
mip_ret_x:      .byte $00
mip_ret_y:      .byte $00
mip_ret_z:      .byte $00
mip_save_02:    .byte $00
mip_save_03:    .byte $00
mip_save_04:    .byte $00
mip_save_05:    .byte $00
timeout_lo:     .byte $00
timeout_hi:     .byte $00
dot_counter:    .byte $00
connect_status: .byte $00
dhcp_state:     .byte $00
dhcp_last_state:.byte $00
dns_state:      .byte $00
dhcp_debug_rx:  .byte $00
dhcp_debug_udp: .byte $00
dhcp_debug_stage:.byte $00
dhcp_debug_msg: .byte $00
dhcp_debug_disc_ok:.byte $00
dhcp_debug_disc_fail:.byte $00
dhcp_debug_req_ok:.byte $00
dhcp_debug_req_fail:.byte $00
dns_debug_state:.byte $00
dns_debug_stage:.byte $00
dns_debug_tx_ok:.byte $00
dns_debug_tx_fail:.byte $00
dns_debug_rx:   .byte $00
dns_debug_arp:  .byte $00
dns_debug_parse_fail:.byte $00
dns_debug_port_hi:.byte $00
typed_key:      .byte $00
rx_count:       .byte $00
rx_index:       .byte $00
hex_temp:       .byte $00
wait_last_lo:   .byte $00
wait_last_hi:   .byte $00
wait_cur_lo:    .byte $00
wait_cur_hi:    .byte $00
prompt_ptr_lo:  .byte $00
prompt_ptr_hi:  .byte $00
line_len:       .byte $00
input_index:    .byte $00
octet_index:    .byte $00
octet_value:    .byte $00
digit_count:    .byte $00
digit_value:    .byte $00
math_lo:        .byte $00
math_hi:        .byte $00
math2_lo:       .byte $00
math2_hi:       .byte $00
parsed_ip:      .byte $00, $00, $00, $00
parsed_port_lo: .byte $00
parsed_port_hi: .byte $00
local_port_seed:.byte $37
load_error:     .byte $00
input_buffer:   .fill LINE_INPUT_MAX + 1, $00
rx_buffer:      .fill RX_SLICE_BUDGET, $00

eth_bin_name:
    .text "ETH.BIN"
eth_bin_name_end:

msg_banner:
    .text "MEGA-IP ML-TERM"
    .byte CHR_CR
    .text "CTRL-W DISCONNECTS."
    .byte CHR_CR, CHR_CR, $00
msg_loading:
    .text "LOADING ETH.BIN..."
    .byte CHR_CR, $00
msg_load_failed:
    .text "FAILED TO LOAD ETH.BIN."
    .byte CHR_CR, $00
msg_init:
    .text "RESETTING ETHERNET..."
    .byte CHR_CR, $00
msg_config_mode:
    .text "[D]HCP OR [M]ANUAL SETUP? "
    .byte $00
msg_dhcp:
    .text "DHCP"
    .byte CHR_CR, $00
msg_dhcp_discover:
    .text "..DISCOVER SENT"
    .byte CHR_CR, $00
msg_dhcp_offer:
    .text "..OFFER SEEN"
    .byte CHR_CR, $00
msg_dhcp_request:
    .text "..REQUEST SENT"
    .byte CHR_CR, $00
msg_dhcp_bound:
    .text "..IP BOUND"
    .byte CHR_CR, $00
msg_dhcp_failed_state:
    .text "..DHCP FAILED STATE"
    .byte CHR_CR, $00
msg_dhcp_timeout:
    .text "..DHCP TIMEOUT"
    .byte CHR_CR, $00
msg_dhcp_nak:
    .text "..DHCP NAK"
    .byte CHR_CR, $00
msg_dhcp_debug_rx:
    .text "DHCP DEBUG RX="
    .byte $00
msg_dhcp_debug_udp:
    .text " UDP68="
    .byte $00
msg_dhcp_debug_stage:
    .text " STAGE="
    .byte $00
msg_dhcp_debug_msg:
    .text " MSG="
    .byte $00
msg_dhcp_debug_disc_ok:
    .text " DO="
    .byte $00
msg_dhcp_debug_disc_fail:
    .text " DF="
    .byte $00
msg_dhcp_debug_req_ok:
    .text " RO="
    .byte $00
msg_dhcp_debug_req_fail:
    .text " RF="
    .byte $00
msg_dns_debug_state:
    .text "DNS DEBUG S="
    .byte $00
msg_dns_debug_stage:
    .text " ST="
    .byte $00
msg_dns_debug_tx_ok:
    .text " TX="
    .byte $00
msg_dns_debug_tx_fail:
    .text " TF="
    .byte $00
msg_dns_debug_rx:
    .text " RX="
    .byte $00
msg_dns_debug_arp:
    .text " ARP="
    .byte $00
msg_dns_debug_parse_fail:
    .text " PF="
    .byte $00
msg_dns_debug_port_hi:
    .text " P="
    .byte $00
msg_dhcp_failed_manual:
    .byte CHR_CR
    .text "DHCP FAILED; ENTER MANUAL SETTINGS."
    .byte CHR_CR, $00
msg_manual_header:
    .text "MANUAL NETWORK SETUP"
    .byte CHR_CR, $00
msg_prompt_local_ip:
    .text "LOCAL IP       : "
    .byte $00
msg_prompt_gateway:
    .text "DEFAULT GATEWAY: "
    .byte $00
msg_prompt_subnet:
    .text "SUBNET MASK    : "
    .byte $00
msg_prompt_dns:
    .text "PRIMARY DNS    : "
    .byte $00
msg_bad_ip:
    .text "BAD IP ADDRESS. USE N.N.N.N WITH 0-255 OCTETS."
    .byte CHR_CR, $00
msg_remote_mode:
    .text "[I]P ADDRESS OR [H]OST NAME? "
    .byte $00
msg_prompt_remote_ip:
    .text "REMOTE IP      : "
    .byte $00
msg_prompt_remote_host:
    .text "REMOTE HOST    : "
    .byte $00
msg_bad_host:
    .text "HOST LOOKUP FAILED."
    .byte CHR_CR, $00
msg_resolving:
    .text "RESOLVING..."
    .byte $00
msg_remote_port:
    .text "REMOTE PORT    : "
    .byte $00
msg_bad_port:
    .text "BAD PORT. USE 1-65535."
    .byte CHR_CR, $00
msg_connecting:
    .text "CONNECTING"
    .byte $00
msg_connect_failed:
    .byte CHR_CR
    .text "CONNECT FAILED."
    .byte CHR_CR, $00
msg_connected:
    .text "CONNECTED."
    .byte CHR_CR, $00
msg_tx_failed:
    .text "TX!"
    .byte $00
msg_disconnected:
    .byte CHR_CR
    .text "DISCONNECTED."
    .byte CHR_CR, $00
