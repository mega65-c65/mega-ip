"""Build and parse the frames used in the mega-ip tests (Ethernet II, ARP,
IPv4, TCP, UDP), with real checksums."""

import struct

BROADCAST = b'\xff' * 6
ETH_ARP, ETH_IPV4 = 0x0806, 0x0800
PROTO_ICMP, PROTO_TCP, PROTO_UDP = 1, 6, 17
FIN, SYN, RST, PSH, ACK = 0x01, 0x02, 0x04, 0x08, 0x10


def ip_bytes(ip):
    return bytes(ip)


def checksum(data):
    if len(data) % 2:
        data += b'\x00'
    s = sum(struct.unpack('!%dH' % (len(data) // 2), data))
    while s >> 16:
        s = (s & 0xFFFF) + (s >> 16)
    return (~s) & 0xFFFF


def ethernet(dst, src, ethertype, payload):
    frame = bytes(dst) + bytes(src) + struct.pack('!H', ethertype) + payload
    return frame + bytes(max(0, 60 - len(frame)))


def arp(op, sha, spa, tha, tpa):
    return struct.pack('!HHBBH', 1, 0x0800, 6, 4, op) + bytes(sha) + bytes(spa) \
        + bytes(tha) + bytes(tpa)


def ipv4(src, dst, proto, payload, ident=0x1234, ttl=64, frag=0x4000):
    total = 20 + len(payload)
    hdr = struct.pack('!BBHHHBBH4s4s', 0x45, 0, total, ident, frag, ttl, proto, 0,
                      bytes(src), bytes(dst))
    hdr = hdr[:10] + struct.pack('!H', checksum(hdr)) + hdr[12:]
    return hdr + payload


def tcp(src_ip, dst_ip, sport, dport, seq, ack, flags, payload=b'', window=4096):
    hdr = struct.pack('!HHIIBBHHH', sport, dport, seq & 0xFFFFFFFF, ack & 0xFFFFFFFF,
                      5 << 4, flags, window, 0, 0)
    pseudo = bytes(src_ip) + bytes(dst_ip) + struct.pack('!BBH', 0, PROTO_TCP,
                                                         len(hdr) + len(payload))
    csum = checksum(pseudo + hdr + payload)
    return hdr[:16] + struct.pack('!H', csum) + hdr[18:] + payload


def udp(src_ip, dst_ip, sport, dport, payload):
    length = 8 + len(payload)
    hdr = struct.pack('!HHHH', sport, dport, length, 0)
    pseudo = bytes(src_ip) + bytes(dst_ip) + struct.pack('!BBH', 0, PROTO_UDP, length)
    csum = checksum(pseudo + hdr + payload) or 0xFFFF
    return hdr[:6] + struct.pack('!H', csum) + payload


DHCP_OFFER, DHCP_REQUEST, DHCP_ACK, DHCP_NAK, DHCP_DISCOVER = 2, 3, 5, 6, 1


def dhcp_reply(xid, chaddr, msg_type, yiaddr, server_id, mask=(255, 255, 255, 0),
               router=None, dns=None, lease=3600):
    """A BOOTREPLY from a DHCP server, as a complete broadcast frame."""
    bootp = struct.pack('!BBBB4sHH4s4s4s4s', 2, 1, 6, 0, bytes(xid), 0, 0x8000,
                        bytes(4), bytes(yiaddr), bytes(server_id), bytes(4))
    bootp += bytes(chaddr) + bytes(10) + bytes(64) + bytes(128)
    opts = bytes([99, 130, 83, 99, 53, 1, msg_type, 54, 4]) + bytes(server_id)
    opts += bytes([1, 4]) + bytes(mask)
    opts += bytes([3, 4]) + bytes(router or server_id)
    if dns:
        opts += bytes([6, 4]) + bytes(dns)
    opts += bytes([51, 4]) + struct.pack('!I', lease) + bytes([255])
    payload = bootp + opts
    u = udp(server_id, (255, 255, 255, 255), 67, 68, payload)
    ip = ipv4(server_id, (255, 255, 255, 255), PROTO_UDP, u)
    return ethernet(BROADCAST, b'\x02\x00\x00\x00\x00' + bytes([server_id[3]]), ETH_IPV4, ip)


def dhcp_fields(parsed):
    """(xid, message type, options dict) of a DHCP frame the stack sent."""
    p = parsed.udp['payload']
    xid = p[4:8]
    opts, i = {}, 240
    while i < len(p) and p[i] != 255:
        if p[i] == 0:
            i += 1
            continue
        code, ln = p[i], p[i + 1]
        opts[code] = p[i + 2:i + 2 + ln]
        i += 2 + ln
    return xid, opts.get(53, b'\x00')[0], opts


def refix_checksums(frame):
    """Recompute the IPv4 header and TCP/UDP checksums of an IPv4 frame after
    fields were changed, so a mutated frame gets past checksum checks."""
    f = bytearray(frame)
    if len(f) < 34 or f[12:14] != b'\x08\x00':
        return bytes(f)
    ihl = (f[14] & 0x0F) * 4
    if ihl < 20 or 14 + ihl > len(f):
        return bytes(f)
    f[24:26] = b'\x00\x00'
    f[24:26] = struct.pack('!H', checksum(bytes(f[14:14 + ihl])))
    total = struct.unpack('!H', f[16:18])[0]
    seg_start, seg_end = 14 + ihl, min(14 + total, len(f))
    seg = f[seg_start:seg_end]
    proto = f[23]
    pos = {PROTO_TCP: 16, PROTO_UDP: 6}.get(proto)
    if pos is not None and len(seg) >= pos + 2:
        seg[pos:pos + 2] = b'\x00\x00'
        pseudo = bytes(f[26:34]) + struct.pack('!BBH', 0, proto, len(seg))
        seg[pos:pos + 2] = struct.pack('!H', checksum(pseudo + bytes(seg)))
        f[seg_start:seg_end] = seg
    return bytes(f)


def dns_reply(query, answer_ip, server_mac, server_ip, client_mac, dst_ip=None):
    """An A-record answer to the stack's DNS `query` (a Parsed frame).

    `dst_ip` overrides the IP destination (normally the stack's address)."""
    q = query.udp['payload']
    question = q[12:]
    msg = q[0:2] + struct.pack('!HHHHH', 0x8180, 1, 1, 0, 0) + question
    msg += struct.pack('!HHHIH', 0xC00C, 1, 1, 60, 4) + bytes(answer_ip)
    dst = bytes(dst_ip) if dst_ip else bytes(query.ip['src'])
    u = udp(server_ip, dst, 53, query.udp['sport'], msg)
    return ethernet(client_mac, server_mac, ETH_IPV4, ipv4(server_ip, dst, PROTO_UDP, u))


class Parsed:
    """Fields of a transmitted frame; missing layers stay None."""

    def __init__(self, raw):
        self.raw = raw
        self.dst, self.src = raw[0:6], raw[6:12]
        self.ethertype = struct.unpack('!H', raw[12:14])[0]
        self.arp = self.ip = self.tcp = self.udp = None
        body = raw[14:]
        if self.ethertype == ETH_ARP:
            hw, pt, hl, pl, op = struct.unpack('!HHBBH', body[:8])
            self.arp = dict(op=op, sha=body[8:14], spa=body[14:18],
                            tha=body[18:24], tpa=body[24:28])
        elif self.ethertype == ETH_IPV4:
            ihl = (body[0] & 0x0F) * 4
            total = struct.unpack('!H', body[2:4])[0]
            self.ip = dict(proto=body[9], src=body[12:16], dst=body[16:20],
                           header_ok=checksum(body[:ihl]) == 0, total=total)
            seg = body[ihl:total]
            if body[9] == PROTO_TCP:
                sport, dport, seq, ack, off, flags, win = struct.unpack('!HHIIBBH', seg[:16])
                hlen = (off >> 4) * 4
                pseudo = body[12:20] + struct.pack('!BBH', 0, PROTO_TCP, len(seg))
                self.tcp = dict(sport=sport, dport=dport, seq=seq, ack=ack, flags=flags,
                                window=win, payload=seg[hlen:],
                                checksum_ok=checksum(pseudo + seg) == 0)
            elif body[9] == PROTO_UDP:
                sport, dport, length = struct.unpack('!HHH', seg[:6])
                self.udp = dict(sport=sport, dport=dport, payload=seg[8:length])

    def __repr__(self):
        if self.arp:
            return '<ARP op=%d %s -> %s>' % (self.arp['op'], list(self.arp['spa']),
                                             list(self.arp['tpa']))
        if self.tcp:
            t = self.tcp
            names = ''.join(n for n, f in (('F', FIN), ('S', SYN), ('R', RST), ('P', PSH),
                                           ('A', ACK)) if t['flags'] & f)
            return '<TCP %d->%d %s seq=%d ack=%d len=%d>' % (
                t['sport'], t['dport'], names, t['seq'], t['ack'], len(t['payload']))
        if self.udp:
            return '<UDP %d->%d len=%d>' % (self.udp['sport'], self.udp['dport'],
                                            len(self.udp['payload']))
        return '<frame type=%04x>' % self.ethertype
