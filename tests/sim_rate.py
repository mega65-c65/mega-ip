"""Rough throughput of a stack over a link with a round-trip delay, on m65sim.

python tests/sim_rate.py [rtt_ms]        (MEGAIP_ROOT picks the source to measure)

Polls 5 times a frame (as MegaNet does). Frames each way are held for half
the RTT. Upload: the program keeps the send queue full. Download: the peer
sends what the stack's window and MSS allow; the program drains the ring at
every poll. Prints KB/s at 50 frames a second.
"""
import sys
from collections import deque

from stack import ACK, PSH, SYN, Peer, Stack

RTT_MS = int(sys.argv[1]) if len(sys.argv) > 1 else 60
POLLS_PER_FRAME = 5
FRAMES = 250                                   # 5 s
DELAY = max(1, RTT_MS * POLLS_PER_FRAME // 20 // 2)   # polls each way


def tick(s):
    s.m.time_offset += s.m.instructions_per_line * s.m.lines_per_frame // POLLS_PER_FRAME
    s.poll()


def mss_of(syn_raw):
    off = (syn_raw[14 + 20 + 12] >> 4) * 4
    opts = syn_raw[14 + 40:14 + 20 + off]
    i = 0
    while i < len(opts):
        if opts[i] == 2:
            return int.from_bytes(opts[i + 2:i + 4], 'big')
        i += 1 if opts[i] in (0, 1) else opts[i + 1]
    return 536


def connect():
    s = Stack.ready()
    p = Peer(s)
    s.call('ETH_SET_REMOTE_IP', *p.ip)
    s.call('ETH_SET_REMOTE_PORT', 0, p.port)
    s.call('ETH_TCP_CONNECT_START')
    mss = 536
    for _ in range(50):
        s.call('ETH_CONNECT_POLL')
        for f in s.sent():
            if f.arp and f.arp['op'] == 1:
                s.deliver(p.arp_reply_to(f))
            elif f.tcp and f.tcp['flags'] & SYN:
                mss = mss_of(f.raw)
                p.local_port, p.ack = f.tcp['sport'], f.tcp['seq'] + 1
                s.deliver(p.segment(SYN | ACK, window=65535))
                p.seq += 1
        if s.state == 'ESTABLISHED':
            break
    s.sent()
    return s, p, mss


def upload():
    s, p, _ = connect()
    to_peer = deque()                          # (due poll, frame)
    to_stack = deque()
    got = 0
    start = p.ack
    for n in range(FRAMES * POLLS_PER_FRAME):
        while s.send_data(b'u' * 200) == 0:
            pass
        while to_stack and to_stack[0][0] <= n:
            s.deliver(to_stack.popleft()[1])
        tick(s)
        for f in s.sent():
            if f.tcp and f.tcp['payload']:
                to_peer.append((n + DELAY, f))
        while to_peer and to_peer[0][0] <= n:
            f = to_peer.popleft()[1]
            if f.tcp['seq'] == p.ack:
                p.ack += len(f.tcp['payload'])
                to_stack.append((n + DELAY, p.segment(ACK, window=65535)))
    got = p.ack - start
    return got / (FRAMES / 50) / 1024


def download():
    s, p, mss = connect()
    to_peer = deque()
    to_stack = deque()
    acked, window = p.seq, 0
    sent_to = p.seq
    got = 0
    for n in range(FRAMES * POLLS_PER_FRAME):
        while to_peer and to_peer[0][0] <= n:
            f = to_peer.popleft()[1]
            if f.tcp['ack'] - acked >= 0:
                acked, window = f.tcp['ack'], f.tcp['window']
        if n == 0:
            window = 1024
        while sent_to - acked < window:        # the peer sends what the window allows
            size = min(mss, window - (sent_to - acked))
            to_stack.append((n + DELAY, p.segment(PSH | ACK, b'd' * size, seq=sent_to)))
            sent_to += size
        while to_stack and to_stack[0][0] <= n:
            s.deliver(to_stack.popleft()[1])
        tick(s)
        got += len(s.read_received())
        for f in s.sent():
            if f.tcp:
                to_peer.append((n + DELAY, f))
        if s.eth.dropped:
            sent_to = acked                    # a drop: the peer resends (go-back)
            s.eth.dropped = 0
    return got / (FRAMES / 50) / 1024, mss


if __name__ == '__main__':
    up = upload()
    down, mss = download()
    print('RTT %d ms: upload %.1f KB/s, download %.1f KB/s (MSS %d)' % (RTT_MS, up, down, mss))
