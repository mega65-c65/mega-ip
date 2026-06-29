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
  887 if mg=1 then 4000
  888 if dl=1 then 5000
  889 if de=1 then 5200
  890 if rm=1 then 5400
  891 if up=1 then 5600
  892 print"..";ts$;" - client request - ";f$
  900 sys $42015,1:a$="HTTP/1.0 200 OK"+cr$+"Content-Type: text/html"+cr$:gosub 1000
  910 a$="Cache-Control: no-store, no-cache, must-revalidate"+cr$+"Pragma: no-cache"+cr$+"Expires: 0"+cr$+"Connection: close"+cr$+cr$:gosub 1000
  920 sys $42015,0:gosub 1100:sys $42015,1
  930 gosub 1030:sys $42021:gosub 1030:sleep1:sys $4205d:goto 730
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
 1210 rq$=""
 1220 for rt=1 to 20000
 1230 sys $42024:sys $4201e:rreg a
 1240 if a=0 then 1280
 1245 rt=1
 1250 if a=13 then 1280
 1255 if a=10 then 1290
 1260 if len(rq$)<120 then rq$=rq$+chr$(a)
 1280 next rt
 1290 gosub 1900:return
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
 1550 if mg=1 then f$="files.html":return
 1560 if dl=1 then f$=fl$:return
 1570 if de=1 then f$="delete":return
 1580 if rm=1 then f$="rename":return
 1590 if up=1 then f$="upload":return
 1600 if ix=1 or ro=1 then f$="index.html":return
 1610 nf=1:f$="notfound":return
 1700 rem == timestamp =====================================================
 1710 ts$=dt$+" @ "+ti$
 1720 return
 1800 rem == set up log window =============================================
 1810 print:print" - Listening for connections on port 80"
 1820 print:print"Log:"
 1830 print "{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}{SHIFT-*}"
 1840 print:window 0,14,79,24,1:ls=1:return
 1900 rem == parse request line ============================================
 1910 ab=0:fv=0:ix=0:nf=0:mg=0:dl=0:de=0:rm=0:up=0:ro=0
 1920 fl$="":nn$="":ft$="s":cl=0:pt$="":ps=0:pe=0:qs=0
 1930 for p=1 to len(rq$)
 1940 :b=asc(mid$(rq$,p,1))
 1950 :if ps=0 and b=32 then ps=p+1:goto 1990
 1960 :if ps<>0 and b=63 and qs=0 then pe=p-1:qs=p+1:goto 1990
 1970 :if ps<>0 and b=32 then if pe=0 then pe=p-1
 1980 :if ps<>0 and b=32 then p=len(rq$)
 1990 next p
 2000 if ps=0 then nf=1:return
 2010 if pe=0 then pe=len(rq$)
 2020 for p=ps to pe:b=asc(mid$(rq$,p,1)):if b>96 and b<123 then b=b-32
 2030 :pt$=pt$+chr$(b):next p
 2040 r0$=chr$(47):ra$=r0$+chr$(65)+chr$(66)+chr$(79)+chr$(85)+chr$(84)
 2050 rf$=r0$+chr$(70)+chr$(65)+chr$(86)+chr$(73)+chr$(67)+chr$(79)+chr$(78)
 2060 ri$=r0$+chr$(73)+chr$(78)+chr$(68)+chr$(69)+chr$(88)
 2070 rg$=r0$+chr$(70)+chr$(73)+chr$(76)+chr$(69)+chr$(83)
 2080 rd$=r0$+chr$(68)+chr$(79)+chr$(87)+chr$(78)+chr$(76)+chr$(79)+chr$(65)+chr$(68)
 2090 rs$=r0$+chr$(68)+chr$(69)+chr$(76)+chr$(69)+chr$(84)+chr$(69)
 2100 rr$=r0$+chr$(82)+chr$(69)+chr$(78)+chr$(65)+chr$(77)+chr$(69)
 2110 ru$=r0$+chr$(85)+chr$(80)+chr$(76)+chr$(79)+chr$(65)+chr$(68)
 2120 if pt$=r0$ then ro=1
 2130 if left$(pt$,len(ra$))=ra$ then ab=1
 2140 if left$(pt$,len(rf$))=rf$ then fv=1
 2150 if left$(pt$,len(ri$))=ri$ then ix=1
 2160 if left$(pt$,len(rg$))=rg$ then mg=1
 2170 if left$(pt$,len(rd$))=rd$ then dl=1
 2180 if left$(pt$,len(rs$))=rs$ then de=1
 2190 if left$(pt$,len(rr$))=rr$ then rm=1
 2200 if left$(pt$,len(ru$))=ru$ then up=1
 2210 if qs>0 then gosub 2700
 2220 return
 2700 rem == parse query string ============================================
 2710 ky=0:rd=0:pc=0:hx=0
 2720 for p=qs to len(rq$)
 2730 :b=asc(mid$(rq$,p,1))
 2740 :if b=32 then p=len(rq$):goto 2860
 2750 :if b=38 then ky=0:rd=0:pc=0:goto 2860
 2760 :if b=61 and rd=0 then rd=1:goto 2860
 2770 :if rd=0 then gosub 2900:goto 2860
 2780 :gosub 3000
 2860 next p:return
 2900 rem == query key ======================================================
 2910 if ky<>0 then return
 2920 if b>96 and b<123 then b=b-32
 2930 if b=70 then ky=1:return
 2940 if b=84 then ky=2:return
 2950 if b=78 then ky=3:return
 2960 if b=76 then ky=4:return
 2970 return
 3000 rem == query value byte ==============================================
 3010 if b=43 then b=32
 3020 if pc=1 then gosub 3200:hx=h:pc=2:return
 3030 if pc=2 then gosub 3200:b=hx*16+h:pc=0:goto 3060
 3040 if b=37 then pc=1:return
 3060 if ky=1 then gosub 3300:return
 3070 if ky=3 then gosub 3400:return
 3080 if ky=2 then if b=80 or b=112 then ft$="p"
 3090 if ky=2 then if b=83 or b=115 then ft$="s"
 3100 if ky=4 and b>47 and b<58 then cl=cl*10+b-48
 3110 return
 3200 rem == hex nybble =====================================================
 3210 h=0:if b>47 and b<58 then h=b-48:return
 3220 if b>64 and b<71 then h=b-55:return
 3230 if b>96 and b<103 then h=b-87:return
 3240 return
 3300 rem == append safe filename char =====================================
 3310 c=-1:if b>96 and b<123 then c=b-32
 3320 if b>64 and b<91 then c=b
 3330 if b>47 and b<58 then c=b
 3340 if b=46 or b=45 or b=95 or b=32 then c=b
 3350 if c<>-1 and len(fl$)<32 then fl$=fl$+chr$(c)
 3360 return
 3400 rem == append safe rename char =======================================
 3410 c=-1:if b>96 and b<123 then c=b-32
 3420 if b>64 and b<91 then c=b
 3430 if b>47 and b<58 then c=b
 3440 if b=46 or b=45 or b=95 or b=32 then c=b
 3450 if c<>-1 and len(nn$)<32 then nn$=nn$+chr$(c)
 3460 return
 3500 rem == petscii dir byte to ascii char ================================
 3510 c$="":if b>64 and b<91 then c$=chr$(b+32):return
 3520 if b>192 and b<219 then c$=chr$(b-128):return
 3530 if b>31 and b<127 then c$=chr$(b):return
 3540 return
 3600 rem == append safe dir filename char =================================
 3610 gosub 3500:if c$="" then return
 3620 cb=asc(c$):ok=0
 3630 if cb>64 and cb<91 then ok=1
 3640 if cb>96 and cb<123 then ok=1
 3650 if cb>47 and cb<58 then ok=1
 3660 if cb=46 or cb=45 or cb=95 or cb=32 then ok=1
 3670 if ok=1 and len(nm$)<32 then nm$=nm$+c$
 3680 return
 3800 rem == url encode nm$ to ue$ =========================================
 3810 ue$="":for q=1 to len(nm$)
 3820 :cb=asc(mid$(nm$,q,1)):ok=0
 3830 :if cb>64 and cb<91 then ok=1
 3840 :if cb>96 and cb<123 then ok=1
 3850 :if cb>47 and cb<58 then ok=1
 3860 :if cb=46 or cb=45 or cb=95 then ok=1
 3870 :if ok=1 then ue$=ue$+chr$(cb):goto 3890
 3880 :if cb=32 then ue$=ue$+"%20"
 3890 next q:return
 4000 rem == dynamic file manager page =====================================
 4010 print"..";ts$;" - client request - files.html"
 4020 sys $42015,1:a$="HTTP/1.0 200 OK"+cr$+"Content-Type: text/html"+cr$:gosub 1000
 4030 a$="Cache-Control: no-store, no-cache, must-revalidate"+cr$+"Pragma: no-cache"+cr$+"Expires: 0"+cr$+"Connection: close"+cr$+cr$:gosub 1000
 4040 lb$=chr$(123):rb$=chr$(125)
 4050 a$="<!doctype html><html><head><meta charset='utf-8'><title>drive 8 files</title></head><body>":gosub 1000
 4060 a$="<h1>drive 8 files</h1><p><a href='/'>home</a> | <a href='/about.html'>about</a></p>":gosub 1000
 4070 a$="<h2>upload</h2><input id='file' type='file'><select id='type'>":gosub 1000
 4072 a$="<option value='p'>PRG/binary</option><option value='s'>SEQ/text</option></select>":gosub 1000
 4074 a$="<button type='button' onclick='up()'>upload</button>":gosub 1000
 4076 a$="<p id='upmsg' hidden>Uploading. Please wait...</p>":gosub 1000
 4080 a$="<h2>directory</h2><table id='dir' border='1' cellpadding='6' cellspacing='0'><tr><th>Filename</th><th>Type</th><th>Size</th><th colspan='2'>Actions</th></tr>":gosub 1000:gosub 4300
 4090 a$="</table><script>async function up()"+lb$+"let f=document.getElementById('file').files[0];if(!f)return;let t=document.getElementById('type').value;document.getElementById('upmsg').hidden=false;":gosub 1000
 4100 a$="document.getElementById('dir').style.display='none';for(let e of document.querySelectorAll('button,input,select'))e.disabled=true;":gosub 1000
 4110 a$="await fetch('/upload?f='+encodeURIComponent(f.name)+'&t='+t+'&l='+f.size,"+lb$+"method:'POST',body:f"+rb$+");location='/files.html';"+rb$+"</script></body></html>":gosub 1000
 4120 gosub 1030:sys $42021:gosub 1030:sleep1:sys $4205d:goto 730
 4300 rem == stream directory listing ======================================
 4310 close 2:df=1:open 2,8,0,"$"
 4320 get#2,b$:get#2,b$
 4330 get#2,b$:if st<>0 then 4490
 4340 ll=asc(b$+chr$(0)):get#2,b$:lh=asc(b$+chr$(0)):if ll=0 and lh=0 then 4490
 4350 get#2,b$:bl=asc(b$+chr$(0)):get#2,b$:bh=asc(b$+chr$(0)):bk=bl+bh*256
 4360 nm$="":ln$="":qt=0
 4370 get#2,b$:if st<>0 then 4490
 4380 b=asc(b$+chr$(0)):if b=0 then 4430
 4390 gosub 3500:if c$<>"" then ln$=ln$+c$
 4400 if b=34 then qt=1-qt:goto 4370
 4410 if qt=1 then gosub 3600
 4420 goto 4370
 4430 if df=1 then df=0:goto 4330
 4435 if nm$="" then 4330
 4440 gosub 3800:tp$="s":pr$=chr$(80)+chr$(82)+chr$(71):pl$=chr$(112)+chr$(114)+chr$(103)
 4450 if instr(ln$,pr$)>0 or instr(ln$,pl$)>0 then tp$="p"
 4455 td$="SEQ":if tp$="p" then td$="PRG"
 4460 a$="<tr><td><a href='/download?f="+ue$+"&t="+tp$+"'>"+nm$+"</a></td><td>"+td$+"</td><td align='right'>"+mid$(str$(bk),2)+" blocks</td>":gosub 1000
 4465 a$="<td><form action='/rename'><input type='hidden' name='f' value='"+nm$+"'><input name='n' size='12'><button>Rename</button></form></td>":gosub 1000
 4470 a$="<td><form action='/delete'><input type='hidden' name='f' value='"+nm$+"'><button>Delete</button></form></td></tr>":gosub 1000
 4480 goto 4330
 4490 close 2:return
 5000 rem == download file ==================================================
 5010 if fl$="" then nf=1:goto 980
 5020 print"..";ts$;" - download - ";fl$
 5030 sys $42015,1:a$="HTTP/1.0 200 OK"+cr$:gosub 1000
 5040 if ft$="p" then a$="Content-Type: application/octet-stream"+cr$:else a$="Content-Type: text/plain"+cr$
 5050 gosub 1000:a$="Content-Disposition: attachment; filename="+chr$(34)+fl$+chr$(34)+cr$+"Connection: close"+cr$+cr$:gosub 1000
 5060 sys $42015,0:gosub 5150:sys $42015,1
 5070 gosub 1030:sys $42021:gosub 1030:sleep1:sys $4205d:goto 730
 5150 close 2:open 2,8,2,fl$+","+ft$+",r"
 5160 a$="":for i=1 to 235
 5170 get#2,b$:if st<>0 then 5190
 5180 a$=a$+b$:next i:gosub 1000:goto 5160
 5190 if len(a$)>0 then gosub 1000
 5195 close 2:return
 5200 rem == delete file ====================================================
 5210 if fl$<>"" then open 15,8,15:print#15,"s:"+fl$:close 15
 5220 print"..";ts$;" - delete - ";fl$:goto 5800
 5400 rem == rename file ====================================================
 5410 if fl$<>"" and nn$<>"" then open 15,8,15:print#15,"r0:"+nn$+"="+fl$:close 15
 5420 print"..";ts$;" - rename - ";fl$:goto 5800
 5600 rem == upload file ====================================================
 5610 print"..";ts$;" - upload - ";fl$
 5620 gosub 6200
 5630 if fl$="" then goto 5800
 5640 open 15,8,15:print#15,"s:"+fl$:close 15
 5650 close 2:open 2,8,2,fl$+","+ft$+",w"
 5660 gosub 6300:close 2:goto 5800
 5800 rem == redirect to file manager ======================================
 5810 sys $42015,1:a$="HTTP/1.0 303 See Other"+cr$+"Location: /files.html"+cr$:gosub 1000
 5820 a$="Content-Length: 0"+cr$+"Connection: close"+cr$+cr$:gosub 1000
 5830 gosub 1030:sys $42021:gosub 1030:sleep1:sys $4205d:goto 730
 6200 rem == discard http headers ==========================================
 6210 hl=0
 6220 sys $42024:sys $4201e:rreg a
 6230 if a=0 then 6220
 6240 if a=13 then 6220
 6250 if a=10 then if hl=0 then return
 6260 if a=10 then hl=0:goto 6220
 6270 hl=hl+1:goto 6220
 6300 rem == receive upload body ===========================================
 6310 ub=0:bs$="":sys $42015,0
 6320 if ub>=cl then 6380
 6330 sys $42024:sys $4701e:rreg a,x
 6340 if x=0 then 6330
 6350 bs$=bs$+chr$(a):ub=ub+1
 6360 if len(bs$)<128 then 6320
 6370 print#2,bs$;:bs$="":goto 6320
 6380 if len(bs$)>0 then print#2,bs$;
 6390 return
