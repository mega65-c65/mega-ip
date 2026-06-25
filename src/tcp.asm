;=============================================================================
; Routine to handle incoming TCP packet
;=============================================================================
; Keep this private TCP block in the low runtime image but clear of the fixed
; BASIC data block and the $7000/$7200 public helper tables.
* = $6a00
INCOMING_TCP_PACKET:
    inc CONNECT_TCP_RX_DBG

    ; Only handle IPv4 TCP; drop others (e.g., mDNS/UDP)
    lda ETH_RX_FRAME_PAYLOAD+0
    and #$F0
    cmp #$40
    bne _drop

    ; TCP protocol?
    lda ETH_RX_FRAME_PAYLOAD+9
    cmp #$06
    bne _drop

    ; ---- ip_len_bytes = IHL * 4 (keep in X, do NOT store in TCP_DATA_OFFSET) ----
    lda ETH_RX_FRAME_PAYLOAD+0
    and #$0F
    asl
    asl
    cmp #20
    bcc _drop
    cmp #61
    bcs _drop
    tax                               ; X = ip header length in bytes

    ; ------ IP address checks ------
    ; dst IP must be LOCAL_IP
    ldy #0
_chk_dip:
    lda ETH_RX_FRAME_PAYLOAD+16,y    ; IPv4 dst at +16..+19 (fixed in IPv4)
    cmp LOCAL_IP,y
    bne _drop
    iny
    cpy #4
    bne _chk_dip

    ; ---- TCP flags at ip_len + 13 ----
    lda ETH_RX_FRAME_PAYLOAD+13,x
    sta ETH_RX_TCP_FLAGS

    ; If LISTENING, begin the handshake
    ; X already holds IHL offset here in your code.

_passive_try:
    ; Only if we are CLOSED and explicitly listening
    lda TCP_STATE
    cmp #TCP_STATE_CLOSED
    bne _passive_done
    lda TCP_LISTEN_ENABLED
    beq _passive_done               ; not listening

    ; match TCP dst port to listen port
    lda ETH_RX_FRAME_PAYLOAD+2,x    ; dst port hi
    cmp TCP_LISTEN_PORT
    bne _passive_done
    lda ETH_RX_FRAME_PAYLOAD+3,x    ; dst port lo
    cmp TCP_LISTEN_PORT+1
    bne _passive_done

    ; Must be a bare SYN (no RST/FIN; ACK ignored for SYN here)
    lda ETH_RX_TCP_FLAGS
    and #(TCP_FLAG_SYN | TCP_FLAG_RST | TCP_FLAG_FIN)
    cmp #TCP_FLAG_SYN
    bne _passive_done               ; not a pure SYN → let normal path drop it

    ; Source MAC must be an individual address, not multicast/broadcast.
    lda ETH_RX_FRAME_SRC_MAC
    and #$01
    bne _drop

    ; ----- Capture peer tuple -----
    ; Peer IP = IPv4 src at +12..+15 from IP header base (not +x)
    ldy #12
    lda ETH_RX_FRAME_PAYLOAD+0,y
    sta REMOTE_IP+0
    lda ETH_RX_FRAME_PAYLOAD+1,y
    sta REMOTE_IP+1
    lda ETH_RX_FRAME_PAYLOAD+2,y
    sta REMOTE_IP+2
    lda ETH_RX_FRAME_PAYLOAD+3,y
    sta REMOTE_IP+3

    ; Peer TCP src port
    lda ETH_RX_FRAME_PAYLOAD+0,x
    sta REMOTE_PORT
    lda ETH_RX_FRAME_PAYLOAD+1,x
    sta REMOTE_PORT+1

    ; Local port for the connection becomes the listen port
    lda TCP_LISTEN_PORT
    sta LOCAL_PORT
    lda TCP_LISTEN_PORT+1
    sta LOCAL_PORT+1

    ; ----- IRS := SEG.SEQ ; RCV.NXT := IRS+1 -----
    ; (SEG.SEQ was already latched into SEG_SEQ0..3 earlier in your code.)
    ;lda #$01
    ;sta REMOTE_ISN_BUMP             ; bump by 1 for SYN
    ;jsr CALC_REMOTE_ISN             ; REMOTE_ISN := SEG_SEQ + payload_len + bump
                                    ; (for bare SYN, payload_len=0 → IRS+1)

    ; ----- REMOTE_ISN := SEG.SEQ + 1 (consume their SYN) -----
    lda ETH_RX_FRAME_PAYLOAD+4,x
    sta REMOTE_ISN+0
    lda ETH_RX_FRAME_PAYLOAD+5,x
    sta REMOTE_ISN+1
    lda ETH_RX_FRAME_PAYLOAD+6,x
    sta REMOTE_ISN+2
    lda ETH_RX_FRAME_PAYLOAD+7,x
    sta REMOTE_ISN+3
    inc REMOTE_ISN+3
    bne +
    inc REMOTE_ISN+2
    bne +
    inc REMOTE_ISN+1
    bne +
    inc REMOTE_ISN+0
+
    ; ----- Send SYN|ACK back (build without the ARP gate) -----
    lda #$08
    sta ETH_TX_TYPE
    lda #$00
    sta ETH_TX_TYPE+1

    lda #$00
    sta TCP_DATA_PAYLOAD_SIZE
    sta TCP_DATA_PAYLOAD_SIZE+1
    lda #20
    sta TCP_HEADER_SIZE          ; ensure checksum code uses 20-byte TCP hdr

    lda #$06
    jsr BUILD_IPV4_HEADER              ; uses LOCAL_IP/REMOTE_IP

    lda #(TCP_FLAG_SYN|TCP_FLAG_ACK)
    jsr BUILD_TCP_HEADER               ; uses LOCAL_ISN / REMOTE_ISN

    ; Fast-path MAC: reply to sender, avoid ARP wait
    ldy #5
_copy_mac:
    lda ETH_RX_FRAME_SRC_MAC,y
    sta ETH_TX_FRAME_DEST_MAC,y
    dey
    bpl _copy_mac
    jsr TCP_SAVE_PEER_MAC

    ; total length = 14 (Eth) + 20 (IP) + 20 (TCP) = 54 bytes (60 pad)
    lda #60
    sta ETH_TX_LEN_LSB
    lda #$00
    sta ETH_TX_LEN_MSB

    jsr ETH_PACKET_SEND
    bcs _drop

    ; ----- Choose / bump our ISS (LOCAL_ISN) -----
    ; Reuse your simple monotonic bump (no RNG needed here)
    inc LOCAL_ISN+3
    bne +
    inc LOCAL_ISN+2
    bne +
    inc LOCAL_ISN+1
    bne +
    inc LOCAL_ISN+0
+
    ; Enter SYN-RCVD so final ACK will complete the handshake
    lda #TCP_STATE_SYN_RECEIVED
    sta TCP_STATE
    rts                              ; fully handled this segment

_passive_done:
    ; ===== end passive-open demux =====

    ; src IP must be REMOTE_IP (once we are trying to talk to a peer)
    ; (do this unconditionally; if you prefer, you can skip while CLOSED)
    ldy #0
_chk_sip:
    lda ETH_RX_FRAME_PAYLOAD+12,y    ; IPv4 src at +12..+15
    cmp REMOTE_IP,y
    bne _drop
    iny
    cpy #4
    bne _chk_sip

    ; verify this is our socket (dst port at ip_len+2) ----
    lda ETH_RX_FRAME_PAYLOAD+2,x      ; dst port hi
    cmp LOCAL_PORT+0
    bne _drop
    lda ETH_RX_FRAME_PAYLOAD+3,x      ; dst port lo
    cmp LOCAL_PORT+1
    bne _drop

    ; verify peer source port too
    lda ETH_RX_FRAME_PAYLOAD+0,x      ; src port hi
    cmp REMOTE_PORT+0
    bne _drop
    lda ETH_RX_FRAME_PAYLOAD+1,x      ; src port lo
    cmp REMOTE_PORT+1
    bne _drop

    ; ---- TCP flags at ip_len + 13 ----
    lda ETH_RX_FRAME_PAYLOAD+13,x
    sta ETH_RX_TCP_FLAGS

    ; SEG.SEQ → SEG_SEQ[0..3] (big endian)
    lda ETH_RX_FRAME_PAYLOAD+4,x
    sta SEG_SEQ+0
    lda ETH_RX_FRAME_PAYLOAD+5,x
    sta SEG_SEQ+1
    lda ETH_RX_FRAME_PAYLOAD+6,x
    sta SEG_SEQ+2
    lda ETH_RX_FRAME_PAYLOAD+7,x
    sta SEG_SEQ+3

    ; SEG.ACK -> SEG_ACK[0..3] (big endian)
    lda ETH_RX_FRAME_PAYLOAD+8,x
    sta SEG_ACK+0
    lda ETH_RX_FRAME_PAYLOAD+9,x
    sta SEG_ACK+1
    lda ETH_RX_FRAME_PAYLOAD+10,x
    sta SEG_ACK+2
    lda ETH_RX_FRAME_PAYLOAD+11,x
    sta SEG_ACK+3

    ; ---- compute payload size and TCP_DATA_OFFSET (payload start) ----
    jsr CALC_RX_TCP_BYTE_COUNT

    ; hand off to the state machine (still in IRQ context)
    jmp TCP_STATE_HANDLER

_drop:
    rts
