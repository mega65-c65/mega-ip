# Ethernet TCPIP Library for BASIC on the MEGA65

*Pull requests are very very welcome.

See the included d81 file for usage.  Refer to the BASIC code on how to set connection settings.  A sample terminal program is included.

*Note: Find the latest public build on filehost for the MEGA65:

https://files.mega65.org?id=f5c206da-9fef-4a07-a54d-6149d8105a44

The public SYS jump table is the supported interface. Internal data addresses
are not part of the API; use the getters below instead of PEEK/POKE.

## Tools and credits
* "petcat" and "c1541" are part of the VICE emulation package
* 64TASS is available from sourceforge and is included here for build simplicity

## Usage:

1) Load the ML library
In your BASIC65 program, load the code to bank 4 at the start of your program:

```10 BLOAD"eth.bin",P($42000),R```

In order to respect BASIC's MAP settings, it must be loaded 2k over the start of the bank, hence $42000.

2) Initialize the library and reset the NIC
The library takes advantage of BASIC65's SYS and RREG commands to avoid PEEKing and POKEing.  But you still need to know the memory locations for the SYS calls.

```20 SYS $42000```

3) Set local and remote endpoints and settings

For any TCPIP connection, you need to provide:

```
30 SYS $42003,192,168,1,1      <--- Gateway IP Address (most often your home router)
40 SYS $42006,192,168,1,76     <--- The MEGA65's IP address (pick an unused address on your network)
45 SYS $42009,$c0,$01          <--- Your local port (Hi,Lo). 16 bit value, typically randomly generated
50 SYS $4200c,207,32,1,18      <--- The REMOTE IP (the machine you want to connect to)
55 SYS $4200f,0,23             <--- The REMOTE PORT (also a 16bit value hi,low. In this case, telnet port 23)
60 SYS $42012,$ff,$ff,$ff,$00  <--- The subnet mask (determines if the remote machine is on same local network)
                                    Usually 255.255.255.0 for most people
```

4) Start a connection

```
65 SYS $42027                  <--- Initiate a connection attempt given the values above
```

5) You now must POLL the network adapter for the connection

```
70 FOR T=1 TO 10000
75 :SYS $42024                 <--- Network "pump".  You must call this regularly
80 :SYS $4202a:RREG A          <--- Check connection status
85 :IF A....  THEN 100         <--- Test for valid connection
90 NEXT T                      <--- Keep waiting
95 PRINT"TIMED OUT":END        <--- Give up
```

6) Connection is now established, you can transmit and recieve data

The library automatically uses the A$ variable for sending strings:

```
100 GET A$: IF A$<> "" THEN SYS $4201b    <--- Send whatever is in A$ to the remote machine
105 SYS $42024                            <--- Dont forget to call the network pump
110 SYS $4201e:RREG A                     <--- Attempt to read a byte from the remote machine
120 IF A<>0 THEN PRINT CHR$(A);           <--- If there is a byte to read, print it
125 GOTO 100                              <--- Loop endlessly
```

7) To disconnect, simply:

```SYS $42021```

TODO: document statuses, DNS lookup, and Listener mode

## Public jump table

These calls are made after loading `eth.bin` at `P($42000)`. The address shown
is the BASIC `SYS` address.

| Address | Routine | Notes |
| --- | --- | --- |
| `$42000` | Initialize/reset Ethernet | Full controller reset |
| `$42003` | Set gateway IP | `SYS addr,a,b,c,d` |
| `$42006` | Set local IP | `SYS addr,a,b,c,d` |
| `$42009` | Set local port | `SYS addr,hi,lo` |
| `$4200c` | Set remote IP | `SYS addr,a,b,c,d` |
| `$4200f` | Set remote port | `SYS addr,hi,lo` |
| `$42012` | Set subnet mask | `SYS addr,a,b,c,d` |
| `$42015` | Set character translation | `0` C/G, `1` ASCII |
| `$4201b` | Send BASIC `A$` | BASIC string send path |
| `$4201e` | Receive one byte | `RREG A`; carry set means empty for ML callers |
| `$42021` | TCP disconnect | Graceful close when established |
| `$42024` | Status poll/network pump | Call regularly |
| `$42027` | Connect start | Non-blocking |
| `$4202a` | Connect poll | `RREG A` status bits |
| `$4202d` | Connect cancel | Abort in-flight connect |
| `$42030` | DNS lookup from `A$` | BASIC compatibility wrapper |
| `$42033` | Get DNS result IP | `RREG A,X,Y,Z` |
| `$42036` | Get DNS state | `RREG A` |
| `$42039` | Listen start | `SYS addr,port_hi,port_lo` |
| `$4203c` | Listen stop | |
| `$4203f` | Accept poll | `RREG A` status bits |
| `$42042` | DHCP start | Non-blocking |
| `$42045` | DHCP poll | `RREG A` state |
| `$42048` | Get DHCP state | `RREG A` |
| `$4204b` | Set primary DNS | `SYS addr,a,b,c,d` |
| `$4204e` | Get local IP | `RREG A,X,Y,Z` |
| `$42051` | Get gateway IP | `RREG A,X,Y,Z` |
| `$42054` | Get subnet mask | `RREG A,X,Y,Z` |
| `$42057` | Get primary DNS | `RREG A,X,Y,Z` |
| `$4205a` | Get remote IP | `RREG A,X,Y,Z` |
| `$4205d` | Force TCP closed | Clears transient session state, keeps DHCP config |
| `$42060` | Get ABI info | `A/X=major/minor`, feature bits in `Y/Z` |
| `$42063` | DNS start from `A$` | Non-blocking; `RREG A`, 1 means started |
| `$42066` | TCP TX idle | `RREG A`, 1 means queue empty and no unacked data |

`$42024` is also the TCP transmit pump. It retires ACKed outbound data,
retransmits unacknowledged data on a frame-paced timeout, and returns non-zero
for TCP events or closed state. Current event bits are: `$01` reset/closed,
`$02` peer FIN, `$04` local close complete, `$08` TIME_WAIT done, `$10` connect
fail, `$20` TX timeout.

The receive path also answers ordinary IPv4 ICMP echo requests, so another
machine on the network can `ping` the MEGA65 while the stack is being polled.

ML-only helper entries live at `$47000+` in bank 4. They do not replace the
BASIC-facing calls; they add buffer and byte-oriented entry points for assembly
programs.

| Address | Purpose | Notes |
| --- | --- | --- |
| `$47000` | TCP send byte | `A=byte` |
| `$47003` | DNS lookup buffer | Blocking compatibility wrapper |
| `$47006` | ML-safe init | Lightweight init/reset helper |
| `$47009` | DHCP debug | `A/X/Y/Z = RX, UDP68, stage, msg` |
| `$4700c` | DHCP TX debug | `A/X/Y/Z = discover ok/fail, request ok/fail` |
| `$4700f` | DNS start buffer | Legacy `A/X=ptr, Y=bank, Z=len` |
| `$47012` | DNS debug | `A/X/Y/Z = state, stage, tx ok, tx fail` |
| `$47015` | DNS debug 2 | `A/X/Y/Z = rx, arp waits, parse fails, port hi` |
| `$47018` | DNS start buffer, bank-1 workspace | `A/X=ptr, Y=len` when called locally or through `$4701b`; source must stay in physical `$12000-$1f7ff` |
| `$4701b` | ML staged dispatcher | Argument-bearing far calls; args staged at bank-4 `$71c0` |
| `$4701e` | ML receive byte | `X=1, A=byte` when data is available; `X=0` when empty |
