;=============================================================================
; Public BASIC-facing jump table
;=============================================================================

*=$2000

    ; Jump table for various functions
    jmp ETH_INIT
    jmp ETH_SET_GATEWAY_IP
    jmp ETH_SET_LOCAL_IP
    jmp ETH_SET_LOCAL_PORT
    jmp ETH_SET_REMOTE_IP
    jmp ETH_SET_REMOTE_PORT
    jmp ETH_SET_SUBNET_MASK
    jmp ETH_SET_CHAR_XLATE

    jmp ETH_TCP_SEND
    jmp ETH_TCP_SEND_STRING
    jmp RBUF_GET
    jmp ETH_TCP_DISCONNECT
    jmp ETH_STATUS_POLL

    jmp ETH_TCP_CONNECT_START
    jmp ETH_CONNECT_POLL
    jmp ETH_CONNECT_CANCEL

    jmp ETH_DNS_LOOKUP
    jmp ETH_GET_DNS_RESULT_IP
    jmp ETH_GET_DNS_STATE

    jmp ETH_TCP_LISTEN_START
    jmp ETH_TCP_LISTEN_STOP
    jmp ETH_ACCEPT_POLL

    jmp ETH_DHCP_START
    jmp ETH_DHCP_POLL
    jmp ETH_GET_DHCP_STATE

    jmp ETH_SET_PRIMARY_DNS
    jmp ETH_GET_LOCAL_IP
    jmp ETH_GET_GATEWAY_IP
    jmp ETH_GET_SUBNET_MASK
    jmp ETH_GET_PRIMARY_DNS
    jmp ETH_GET_REMOTE_IP
    jmp ETH_TCP_FORCE_CLOSE
    jmp ETH_GET_ABI_INFO
    jmp ETH_DNS_START_ASTR
    jmp ETH_TCP_TX_IDLE
