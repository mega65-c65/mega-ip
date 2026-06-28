  100 rem ===================================================================
  110 rem = mega-ip basic65 tcpip library demo
  120 rem = v.01
  130 rem = written by xlar54 and chatgpt :)
  140 rem ===================================================================
  150 rem startup should not write to the disk image
  160 bload"eth.bin",p($42000),r  : rem load library to bank 4
  170 background 0:border 0       : rem set screen colors
  180 gosub 250:gosub 290:goto 330
  250 rem == set up screen ==================================================
  260 print"{clr}"+chr$(14)+"{wht}";
  270 print "{rvon}{red}M{cyn}E{lgrn}G{lblu}A{lred}-{orng}I{yel}P{cyn} BASIC Web Server Demo                                                   {rvof}"
  280 return
  290 rem == reset ethernet controller ======================================
  300 if rn=0 then print "{down}{down}Resetting Ethernet Controller...":print
  310 if rn=0 then sys $42000:rn=1         : rem reset controller
  320 return
  330 rem == config mode selection ==========================================
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
  570 :input " - Local IP       :   192.168.1.76{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}";oc$:gosub1400:ifx=0 then 570:else sys $42006,oc(0),oc(1),oc(2),oc(3)
  580 :input " - Default Gateway:   192.168.1.1{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}";oc$:gosub1400:ifx=0 then 580:else sys $42003,oc(0),oc(1),oc(2),oc(3)
  590 :input " - Subnet Mask    :   255.255.255.0{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}";oc$:gosub1400:ifx=0 then 590:else sys $42012,oc(0),oc(1),oc(2),oc(3)
  600 :input " - Primary DNS    :   8.8.8.8{left}{left}{left}{left}{left}{left}{left}{left}{left}";oc$:gosub1400:ifx=0 then 600:else sys $4204b,oc(0),oc(1),oc(2),oc(3)
  610 :goto 640
  620 bend
  630 goto 350
  640 rem == use established settings ======================================
  645 sys $4205d                    : rem clear tcp/arp state, keep dhcp config
  650 gosub 250
  654 print"{wht}"
  655 print " {CBM-A}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{CBM-S}"
  660 print "   Local IP       : ";:sys $4204e:gosub1300:print x$
  670 print " {$a0} Default Gateway: ";:sys $42051:gosub1300:print x$
  680 print "   Subnet Mask    : ";:sys $42054:gosub1300:print x$
  690 print " {$a0} Primary DNS    : ";:sys $42057:gosub1300:print x$
  700 print " {CBM-Z}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{CBM-X}"
  730 rem === set up listener ===============================================
  740 sys $42015,1:rem send ascii to browser
  750 if ls=0 then gosub 1800
  760 sys$42039,0,80                           : rem start listener
  770 sys $42024:sys$4202a:sys $4203f:rreg a:  : rem poll listener state
  780 if(aand1)<>0 then 860                   : rem connected
  790 if(aand2)<>0 then print" - Failed":sleep2:goto730: rem failed/busy
  800 goto 770
  860 rem == send a webpage ================================================
  870 vc=vc+1:cr$=chr$(13)+chr$(10):gosub 1200:gosub 1510:gosub 1700
  880 rem selected file is in f$
  885 if fv=1 then 940
  886 if nf=1 then 980
  887 print"..";ts$;" - client request - ";f$
  890 sys $42015,1:a$="HTTP/1.0 200 OK"+cr$+"Content-Type: text/html"+cr$:gosub 1000
  895 a$="Cache-Control: no-store, no-cache, must-revalidate"+cr$+"Pragma: no-cache"+cr$+"Expires: 0"+cr$+"Connection: close"+cr$+cr$:gosub 1000
  900 sys $42015,0:gosub 1100:sys $42015,1
  910 gosub 1030:sys $42021:gosub 1030:sleep1:rem close connection
  920 sys $4205d:rem force tcp state closed
  930 goto 730
  940 sys $42015,1:a$="HTTP/1.0 204 No Content"+cr$+"Content-Length: 0"+cr$:gosub 1000
  950 a$="Cache-Control: no-store, no-cache, must-revalidate"+cr$+"Pragma: no-cache"+cr$+"Expires: 0"+cr$+"Connection: close"+cr$+cr$:gosub 1000
  960 gosub 1030:sys $42021:gosub 1030:sleep1
  970 sys $4205d:goto 730
  980 sys $42015,1:a$="HTTP/1.0 404 Not Found"+cr$+"Content-Length: 0"+cr$:gosub 1000
  990 a$="Cache-Control: no-store, no-cache, must-revalidate"+cr$+"Pragma: no-cache"+cr$+"Expires: 0"+cr$+"Connection: close"+cr$+cr$:gosub 1000
  995 gosub 1030:sys $42021:gosub 1030:sleep1:sys $4205d:goto 730
 1000 sys $4201b
 1010 for wt=1 to 3000:sys $42024:sys $42066:rreg a:if a=1 then return
 1020 next wt:return
 1030 for wt=1 to 6000:sys $42024:sys $42066:rreg a:if a=1 then return
 1040 next wt:return
 1100 rem == stream html file in max tcp-sized chunks =======================
 1110 open 2,8,2,f$+",s,r"
 1120 a$=""
 1130 for i=1 to 235
 1140 get#2,b$:if st<>0 then 1180
 1150 a$=a$+b$
 1160 next i
 1170 gosub 1000:goto 1120
 1180 if len(a$)>0 then gosub 1000
 1190 close 2:return
 1200 rem == read first http request line ==================================
 1205 sys $42015,0
 1210 rq$="":ab=0:fv=0:ix=0:nf=0:sp=0:pl=0:ro=0:am=0:fm=0:im=0
 1220 for rt=1 to 20000
 1230 sys $42024:sys $4201e:rreg a
 1240 if a=0 then 1280
 1245 gosub 1900:rt=1
 1250 if a=13 or a=10 then 1290
 1260 if len(rq$)<120 then rq$=rq$+chr$(a)
 1280 next rt
 1290 return
 1300 rem == reassemble rreg ip ============================================
 1310 rreg a,x,y,z:ip(0)=a:ip(1)=x:ip(2)=y:ip(3)=z
 1320 ip$=mid$(str$(ip(0)),2)+"."+mid$(str$(ip(1)),2)+"."
 1330 ip$=ip$+mid$(str$(ip(2)),2)+"."+mid$(str$(ip(3)),2)
 1340 x$=ip$:return
 1400 rem == octet str to array ============================================
 1410 x=0:oc(0)=0:oc(1)=0:oc(2)=0:oc(3)=0
 1420 fort=1tolen(oc$)
 1430 :if mid$(oc$,t,1)="." then x=x+1
 1440 next
 1450 if x<>3 then x=0:return
 1460 t$="":ct=0
 1470 fort=1tolen(oc$)
 1480 :if mid$(oc$,t,1)="." then oc(ct)=val(t$):ct=ct+1:t$="":else t$=t$+mid$(oc$,t,1)
 1490 nextt:oc(ct)=val(t$)
 1500 x=1:return
 1510 rem == choose file from http request ================================
 1520 f$=""
 1530 if fv=1 then f$="favicon.ico":return
 1540 if ab=1 then f$="about.html":return
 1550 if ix=1 or ro=1 then f$="index.html":return
 1560 nf=1:f$="notfound":return
 1700 rem == timestamp =====================================================
 1710 ts$=dt$+" @ "+ti$
 1720 return
 1800 rem == set up log window =============================================
 1810 print:print" - Listening for connections on port 80"
 1820 print:print"Log:"
 1830 print "{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}"
 1840 print:window 0,14,79,24,1:ls=1:return
 1900 rem == detect special paths in request bytes =========================
 1910 b=a:if b>96 and b<123 then b=b-32
 1920 if b>192 and b<219 then b=b-128
 1930 if b=32 then sp=sp+1:return
 1940 if sp<>1 then return
 1950 if b=63 then sp=2:return
 1960 if pl<>0 then 2000
 1970 pl=1:if b=47 then ro=1:am=1:fm=1:im=1:return
 1980 return
 2000 pl=pl+1:if ro=1 then ro=0
 2010 gosub 2200:gosub 2300:gosub 2400:return
 2200 rem == match /about ==================================================
 2210 if am=0 then return
 2220 if am=1 and b=65 then am=2:return
 2230 if am=2 and b=66 then am=3:return
 2240 if am=3 and b=79 then am=4:return
 2250 if am=4 and b=85 then am=5:return
 2260 if am=5 and b=84 then ab=1:am=6:return
 2270 am=0:return
 2300 rem == match /favicon ===============================================
 2310 if fm=0 then return
 2320 if fm=1 and b=70 then fm=2:return
 2330 if fm=2 and b=65 then fm=3:return
 2340 if fm=3 and b=86 then fm=4:return
 2350 if fm=4 and b=73 then fm=5:return
 2360 if fm=5 and b=67 then fm=6:return
 2370 if fm=6 and b=79 then fm=7:return
 2380 if fm=7 and b=78 then fv=1:fm=8:return
 2390 fm=0:return
 2400 rem == match /index ==================================================
 2410 if im=0 then return
 2420 if im=1 and b=73 then im=2:return
 2430 if im=2 and b=78 then im=3:return
 2440 if im=3 and b=68 then im=4:return
 2450 if im=4 and b=69 then im=5:return
 2460 if im=5 and b=88 then ix=1:im=6:return
 2470 im=0:return
