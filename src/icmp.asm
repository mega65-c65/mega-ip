
ICMP_BUILD_REQUEST:

    ; ETH_TYPE = $0800
    lda #$08
    sta ETH_TX_TYPE
    lda #$06
    sta ETH_TX_TYPE + 1