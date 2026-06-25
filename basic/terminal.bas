  100 rem ===================================================================
  110 rem = mega-ip basic65 tcpip library demo
  120 rem = v.01
  130 rem = written by xlar54 and chatgpt :)
  140 rem ===================================================================
  150 rem startup should not write to the disk image
  160 bload"eth.bin",p($42000),r  : rem load library to bank 4
  170 gosub2490                   : rem install embedded cursor sprite
  180 background 0:border 0       : rem set screen colors
  190 key 1,chr$(133)             : rem redefine f1 to toggle xlate mode
  200 key 3,chr$(135)             : rem redefine f3 to toggle echo mode
  210 rem == constants ======================================================
  220 xx$="{red}{rvon} - Connection Terminated.{rvof}":m=0
  230 mo$(0)="C/G":mo$(1)="ASCII":ec=0
  240 gosub 250:gosub 290:goto 330
  250 rem == set up screen ==================================================
  260 print"{clr}"+chr$(14)+"{wht}";:sprite 0,0
  270 print "{rvon}{red}M{cyn}E{lgrn}G{lblu}A{lred}-{orng}I{yel}P{cyn} BASIC65 Demo Terminal                                                   {rvof}"
  280 return
  290 rem == reset ethernet controller ===================================
  300 if rn=0 then print "{down}{down}Resetting Ethernet Controller...":print
  310 if rn=0 then sys $42000:rn=1         : rem reset controlller
  320 return
  330 rem == config mode selection =======================================
  340 print:print" - [D]HCP Autoconfig or [M]anual Config":print
  350 getkey a$
  360 if a$="d" or a$="D" then begin
  370 :print " - Attempting DHCP autoconfig...":print
  380 :sys $42042                           : rem start dhcp request
  385 :a=-1
  390 :fort=1to20000
  400 ::sys $42024:sys $42045:rreg b        : rem poll for dhcp response
  410 ::if b<>a and b=1 then print"..DISCOVER sent":a=b
  420 ::if b<>a and b=2 then print"..OFFER seen":a=b
  430 ::if b<>a and b=3 then print"..REQUEST sent":a=b
  440 ::if b<>a and b=4 then print"..IP Bound":a=b
  450 ::if b=4 then 640
  520 ::if b=127 then 540
  530 :next
  540 :print:print"{red}..DHCP timeout.{wht}":sleep 2:gosub 250:goto 330
  550 bend
  560 if a$="m" or a$="M" then begin
  570 :input " - Local IP       :   192.168.1.76{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}";oc$:gosub2380:ifx=0 then 570:else sys $42006,oc(0),oc(1),oc(2),oc(3)
  580 :input " - Default Gateway:   192.168.1.1{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}";oc$:gosub2380:ifx=0 then 580:else sys $42003,oc(0),oc(1),oc(2),oc(3)
  590 :input " - Subnet Mask    :   255.255.255.0{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}";oc$:gosub2380:ifx=0 then 590:else sys $42012,oc(0),oc(1),oc(2),oc(3)
  600 :input " - Primary DNS    :   8.8.8.8{left}{left}{left}{left}{left}{left}{left}{left}{left}";oc$:gosub2380:ifx=0 then 600:else sys $4204b,oc(0),oc(1),oc(2),oc(3)
  610 :goto 640
  620 bend
  630 goto 350
  640 rem == use established settings ======================================
  645 sys $4205d                    : rem clear tcp/arp state, keep dhcp config
  650 gosub 250
  654 print"{wht}"
  655 print " {CBM-A}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{CBM-S}"
  660 print "   Local IP       : ";:sys $4204e:gosub1720:print x$
  670 print " {$a0} Default Gateway: ";:sys $42051:gosub1720:print x$
  680 print "   Subnet Mask    : ";:sys $42054:gosub1720:print x$
  690 print " {$a0} Primary DNS    : ";:sys $42057:gosub1720:print x$
  700 print " {CBM-Z}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{CBM-X}"
  710 rcursor px,py
  720 print chr$(27)+"@";
  730 rem === select xlate mode     =========================================
  740 print:print"{wht} - Text Translation : [A]SCII or [C]G Graphics"
  750 getkey x$
  760 if x$="a" or x$="A" then m=1:sys $42015,m:goto 790
  770 if x$="c" or x$="C" then m=0:sys $42015,m:goto 790
  780 goto 750
  790 rem === select ip or hostname =========================================
  800 print:print"{wht} - Connect By       : [I]P Address or [H]ost Name"
  810 getkey x$
  820 if x$="h" or x$="H" then 850
  830 if x$="i" or x$="I" then 1010
  840 goto 810
  850 rem == dns resolution =================================================
  860 print:input"{wht} - DNS Host Name    :",a$
  870 print:print"{wht} - Resolving host '"+a$+"'";:sys $42063:rreg a : rem dns start a$
  875 if a=0 then print:print"{lred} - Bad host name.{wht}":sleep 3:cursor px,py:goto640
  880 bt=ti
  890 sys $42024:sys $42036:rreg a       :rem poll and check for reply
  900 rem quiet dns wait
  905 if a=1 and ti-bt<600 then 890
  906 if a=1 then print:print"{lred} - Timed out.{wht}":sleep 3:cursor px,py:goto640
  907 if a=0 and ti-bt<600 then 890
  908 if a=0 then print:print"{lred} - Timed out.{wht}":sleep 3:cursor px,py:goto640
  910 if a=2 then begin
  920 :rem retrieve the ip address
  930 :sys $42033:rreg a,x,y,z:ip(0)=a:ip(1)=x:ip(2)=y:ip(3)=z
  940 :gosub1680:print". Resolved to ";ip$:goto1110
  950 bend
 960 if a=3 then begin
  970 :print:print"{lred} - Lookup failed.{wht}":sleep 3:cursor px,py:goto640
 1000 bend
 1010 rem == validate ip address ===========================================
 1020 ip$="":print:input"{wht} - Remote IP Address:",ip$:x=0
 1030 fort=1tolen(ip$)
 1040 :if mid$(ip$,t,1)="." then x=x+1
 1050 next
 1060 if x<>3 then x=0:goto1010
 1070 t$="":ct=0
 1080 fort=1tolen(ip$)
 1090 :if mid$(ip$,t,1)="." then ip(ct)=val(t$):ct=ct+1:t$="":else t$=t$+mid$(ip$,t,1)
 1100 nextt:ip(ct)=val(t$)
 1110 input " -{$a0}Remote Port:";po
 1120 if po<1 or po>65534 then 1110
 1130 ph=int(po/256):pl=mod(po,256)
 1140 gosub 1150:goto1220
 1150 rem == set up connection =================================================
 1160 sys $4200c, ip(0),ip(1),ip(2),ip(3)          : rem remote ip
 1170 sys $4200f, ph,pl                            : rem remote port
 1180 mh=$c0:ml=int(rnd(0)*255)                    : rem generate random local
 1190 sys $42009, mh,ml                            : rem random local port
 1200 return
 1210 rem
 1220 rem == connect to host ===================================================
 1230 rem
 1240 t=0:gosub1680:print:print" - Connecting to "+ip$+"..."
 1250 rem sys $42012:goto390
 1260 sys $42027                                  : rem connect start
 1270 t=t+1:sys $4202a:rreg a                     : rem poll for connection
 1280 :if (a and 1) then begin
 1290 :::print"{yel}{CTRL-G} - Connected!"
 1300 :::print" - [F1] Term Mode  [F3] Echo Toggle  [F7] Disconnect"
 1310 :::print:goto 1380
 1320 :bend
 1330 :if (a and 2) then print"{red}  - Connect failed.{wht}":sleep 3:goto640
 1340 if t < 20000 then 1270
 1350 print"{red} - Connect Timeout.{wht}":sleep 3:goto 640
 1360 rem
 1370 rem == tx/rx loop =======================================================
 1380 rem
 1390 sprite 0,1 : rem enable cursor sprite
 1400 rcursor cx,cy:movspr 0,24+(cx*4),50+(cy*8)
 1410 gosub 1630
 1420 get a$:if a$="" then 1470
 1430 if a$="{CTRL-W}" or a$="{f7}" then print:printxx$:sys $42021:sys $4205d:sleep 3:an=0:an$="":goto 640:rem disconnect
 1440 if a$="{f1}" then gosub 1590:goto1470
 1450 if a$="{f3}" or a$="{f5}" then gosub 1650:goto1470
 1460 sys$4201b:if ec=1 then printa$;:rcursor cx,cy:movspr 0,24+(cx*4),50+(cy*8)
 1470 sys $4201e:rreg a:if a=0 or a=10 then 1570  : rem get incoming byte
 1480 if a=27 then an=1:goto 1570
 1490 if a=91 and an=1 then an=2:goto 1570
 1500 if an=2 then begin
 1510 :an$=an$+chr$(a)
 1520 :if (a>64 and a<91) or (a>192 and a<219) then an=0:gosub1760
 1530 :goto1570
 1540 bend
 1550 print chr$(a);:rcursor cx,cy:movspr 0,24+(cx*4),50+(cy*8)
 1560 ifa=34thenprint chr$(27);chr$(27);
 1570 sys $42024:rreg a:if a=0 then 1580 : rem status poll
 1575 print:print xx$:sys $42024:sys $4205d:sleep 3:an=0:an$="":goto640
 1580 goto 1420
 1590 rem == switch terminal modes =========================================
 1600 if m=0 then m=1:goto 1620
 1610 if m=1 then m=0
 1620 sys $42015,m:print                             : rem set char xlate mode
 1630 print"{rvon}"+mo$(m)+" Activated.{rvof}":print
 1640 return
 1650 rem == switch echo mode  =========================================
 1660 if ec=0 then ec=1:print:print" - Echo ON":print:return
 1670 if ec=1 then ec=0:print:print" - Echo OFF":print:return
 1680 rem == reassemble the ip string =====================================
 1690 ip$=mid$(str$(ip(0)),2)+"."+mid$(str$(ip(1)),2)+"."
 1700 ip$=ip$+mid$(str$(ip(2)),2)+"."+mid$(str$(ip(3)),2)
 1710 return
 1720 rem == reassemble rreg ip      =====================================
 1730 rreg a,x,y,z:ip(0)=a:ip(1)=x:ip(2)=y:ip(3)=z
 1740 gosub1680:x$=ip$
 1750 return
 1760 rem == ansi code handling ===========================================
 1770 ap$=left$(an$,len(an$)-1):ac$=right$(an$,1):an$=""
 1780 pc=0:t$="":fort=1tolen(ap$)
 1790 :if mid$(ap$,t,1)=";" then ap(pc)=val(t$):t$="":pc=pc+1:goto1810
 1800 :t$=t$+mid$(ap$,t,1)
 1810 nextt
 1820 ap(pc)=val(t$):if pc=0 and ap(pc)=0 then ap(pc)=1
 1830 if ac$="m" then begin
 1840 :fort=0topc
 1850 :if ap(t)=30 or ap(t)=90 then print"{gry1}";:return
 1860 :if ap(t)=31 or ap(t)=91 then print"{red}";:return
 1870 :if ap(t)=32 or ap(t)=92 then print"{grn}";:return
 1880 :if ap(t)=33 or ap(t)=93 then print"{yel}";:return
 1890 :if ap(t)=34 or ap(t)=94 then print"{blu}";:return
 1900 :if ap(t)=35 or ap(t)=95 then print"{pur}";:return
 1910 :if ap(t)=36 or ap(t)=96 then print"{cyn}";:return
 1920 :if ap(t)=37 or ap(t)=97 then print"{gry3}";:return
 1930 :if ap(t)=38 or ap(t)=98 then print"{rvon}";:return
 1940 :if ap(t)=27 then print"{rvof}";:return
 1950 :if ap(t)=7 then print"{rvof}";:return
 1960 :return
 1970 bend
 1980 if ac$="f" or ac$="H" then begin
 1990 :cy=ap(0)-1:cx=ap(1)-1
 2000 :if cx<0 then cx=0
 2010 :if cy<0 then cy=0
 2020 :if cx>79 then cx=79
 2030 :if cy>24 then cy=24
 2040 :cursor cx,cy:gosub 2360:return
 2050 bend
 2060 if ac$="n" then begin
 2070 :a$=chr$(27)+"["+mid$(str$(cx+1),2)+";"+mid$(str$(cy+1),2)+"R"
 2080 :sys $4201b
 2090 bend
 2100 if ac$="A" then begin
 2110 :if ap(0)=0 then ap(0)=1
 2120 :forz=1toap(0):print"{up}";:next:gosub2360:return
 2130 bend
 2140 if ac$="B" then begin
 2150 :if ap(0)=0 then ap(0)=1
 2160 :forz=1toap(0):print"{down}";:next:gosub2360:return
 2170 bend
 2180 if ac$="C" then begin
 2190 :if ap(0)=0 then ap(0)=1
 2200 :forz=1toap(0):print"{rght}";:next:gosub2360:return
 2210 bend
 2220 if ac$="D" then begin
 2230 :if ap(0)=0 then ap(0)=1
 2240 :forz=1toap(0):print"{left}";:next:gosub2360:return
 2250 bend
 2260 if ac$="K" and val(ap$)=0 then print chr$(27)+"q";:gosub2360:return
 2270 if ac$="K" and val(ap$)=1 then print chr$(27)+"p";:gosub2360:return
 2280 if ac$="K" and val(ap$)=2 then print chr$(27)+"q"+chr$(27)+"p";:gosub2360:return
 2290 if ac$="J" and val(ap$)=0 then print chr$(27)+"j"+chr$(27)+"@";:gosub2360:return
 2300 if ac$="J" and val(ap$)=2 then print"{clr}";:gosub2360:return
 2310 if ac$="M" then printchr$(27)+"v";:gosub2360:return
 2320 if ac$="D" then printchr$(27)+"w";:gosub2360:return
 2325 if ac$="G" then printchr$(27)+"j";:gosub2360:return
 2330 if ac$="s" then px=cx:py=cy:return
 2340 if ac$="u" then cx=px:cy=py:cursor cx,cy:gosub2360:return
 2350 return
 2360 rem == move sprite ================
 2370 rcursor cx,cy:movspr 0,24+(cx*4),50+(cy*8):return
 2380 rem == octet str to array  ===========================================
 2390 x=0:oc(0)=0:oc(1)=0:oc(2)=0:oc(3)=0
 2400 fort=1tolen(oc$)
 2410 :if mid$(oc$,t,1)="." then x=x+1
 2420 next
 2430 if x<>3 then x=0:return
 2440 t$="":ct=0
 2450 fort=1tolen(oc$)
  2460 :if mid$(oc$,t,1)="." then oc(ct)=val(t$):ct=ct+1:t$="":else t$=t$+mid$(oc$,t,1)
  2470 nextt:oc(ct)=val(t$)
  2480 x=1:return
  2490 rem == install 4x8 block cursor sprite ===============================
  2500 restore 2600
  2510 for i=0 to 63:read b:poke $0600+i,b:next
  2520 return
  2600 data 240,0,0,240,0,0,240,0,0,240,0,0,240,0,0,240
  2610 data 0,0,240,0,0,240,0,0,0,0,0,0,0,0,0,0
  2620 data 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
  2630 data 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
