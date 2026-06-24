  100 rem ===================================================================
  110 rem = mega-ip basic65 tcpip library demo
  120 rem = v.01
  130 rem = written by xlar54 and chatgpt :)
  140 rem ===================================================================
  150 dsave"@web server"          : rem save any changes
  160 bload"eth.bin",p($42000),r  : rem load library to bank 4
  170 background 0:border 0       : rem set screen colors
  180 rem == set up screen ==================================================
  190 print"{clr}"+chr$(14)+"{wht}";
  200 print "{rvon}{red}M{cyn}E{lgrn}G{lblu}A{lred}-{orng}I{yel}P{cyn} BASIC Web Server Demo"                                                  "
  210 print:print "{lgrn}See BASIC code to set local IP, netmask, gateway, etc.":print
  220 print " - Default Local IP   : 192.168.1.76"
  230 print " - Default Gateway    : 192.168.1.1"
  240 print " - Default Subnet Mask: 255.255.255.0"
  250 print " =========================================================="
  260 if rn=0 then print "{down}{down}Resetting Ethernet Controller...":print
  270 if rn=0 then sys $42000:rn=1         : rem reset controlller
  280 sys $42003, 192,168,1,1              : rem gateway ip
  290 sys $42006, 192,168,1,76             : rem local ip
  300 sys $42012, 255,255,255,0            : rem subnet mask
  310 rem === set up listener ===============================================
  320 rem  poke $443a8,$4c:poke $443a9,$cc:poke $443aa,$43: rem bypass filters
  321 rem jmp $43cc
  322 rem  stop
  323 rem poke $4470e,$4c:poke $4470f,$20:poke $44710,$47: rem bypass filters
  340 print:print" - Listening for connections on port 80"
  350 sys$42039,0,80                           : rem start listener
  360 sys $42024:sys$4202a:sys $4203f:rreg a:  : rem poll listener state
  370 if(aand1)<>0 then 460                   : rem connected
  380 if(aand2)<>0 then print" - Failed":sleep2:goto180: rem failed/busy
  390 goto 360
  400 rem == set up connection =================================================
  410 sys $4200c, ip(0),ip(1),ip(2),ip(3)          : rem remote ip
  420 sys $4200f, ph,pl                            : rem remote port
  430 mh=$c0:ml=int(rnd(0)*255)                    : rem generate random local
  440 sys $42009, mh,ml                            : rem random local port
  450 return
  460 rem == send a webpage =============================================
  470 vc=vc+1:print"..client"
  480 a$="<html>":sys $4201b
  490 a$="<body>":sys $4201b
  500 a$="<h1>a mega65 webserver running from basic!</h1>":sys $4201b
  510 a$="<p>this is a demo of a simple web server running ":sys $4201b
  520 a$="on a mega65 personal computer.  The server is ":sys $4201b
  530 a$="written in basic65, with a machine language networking":sys $4201b
  540 a$=" library.</p>":sys $4201b
  550 a$="<p>you are visitor #"+str$(vc)+" to the page.</p>":sys $4201b
  560 a$="</body>":sys $4201b
  570 a$="</html>":sys $4201b
  580 sys $42021:sleep1:rem close connection
  590 sys $4205d:rem force tcp state closed
  620 goto 350
