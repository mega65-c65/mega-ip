Ethernet TCPIP Library for BASIC on the MEGA65

*Pull requests are very very welcome.

See the included d81 file for usage.  Refer to the BASIC code on how to set connection settings.  A sample terminal program is included.

*Note: Find the latest public build on filehost for the MEGA65:

https://files.mega65.org?id=f5c206da-9fef-4a07-a54d-6149d8105a44

Usage:

1) Load the ML library
In your BASIC65 program, load the code to bank 4 at the start of your program:

10 BLOAD"eth.bin",P($42000),R

In order to respect BASIC's MAP settings, it must be loaded 2k over the start of the bank, hence $42000.

2) Initialize the library and reset the NIC
The library takes advantage of BASIC65's SYS and RREG commands to avoid PEEKing and POKEing.  But you still need to know the memory locations for the SYS calls.

20 SYS $42000

3) Set local and remote endpoints and settings

For any TCPIP connection, you need to provide:

30 SYS $42003,192,168,1,1      <--- Gateway IP Address (most often your home router)
40 SYS $42006,192,168,1,76     <--- The MEGA65's IP address (pick an unused address on your network)
45 SYS $42009,$c0,$01          <--- Your local port (Hi,Lo). 16 bit value, typically randomly generated
50 SYS $4200c,207,32,1,18      <--- The REMOTE IP (the machine you want to connect to)
55 SYS $4200f,0,23             <--- The REMOTE PORT (also a 16bit value hi,low. In this case, telnet port 23)
60 SYS $42012,$ff,$ff,$ff,$00  <--- The subnet mask (determines if the remote machine is on same local network)
                                    Usually 255.255.255.0 for most people

4) Start a connection

65 SYS $42027                  <--- Initiate a connection attempt given the values above

5) You now must POLL the network adapter for the connection

70 FOR T=1 TO 10000
75 :SYS $42024                 <--- Network "pump".  You must call this regularly
80 :SYS $4202a:RREG A          <--- Check connection status
85 :IF A....  THEN 100         <--- Test for valid connection
90 NEXT T                      <--- Keep waiting
95 PRINT"TIMED OUT":END        <--- Give up

6) Connection is now established, you can transmit and recieve data

The library automatically uses the A$ variable for sending strings:

100 GET A$: IF A$<> "" THEN SYS $4201b    <--- Send whatever is in A$ to the remote machine
105 SYS $42024                            <--- Dont forget to call the network pump
110 SYS $4201e:RREG A                     <--- Attempt to read a byte from the remote machine
120 IF A<>0 THEN PRINT CHR$(A);           <--- If there is a byte to read, print it
125 GOTO 100                              <--- Loop endlessly

7) To disconnect, simply:

SYS $42021

TODO: document statuses, DNS lookup, and Listener mode


