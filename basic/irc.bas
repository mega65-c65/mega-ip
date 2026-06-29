100 rem ==================================================================
110 rem = mega-ip irc chat client for basic65
120 rem = demo of the eth.bin tcp/ip library
130 rem ==================================================================
140 vs$="1.0":nl=4095:dim nm$(nl):nc=0 : rem nick list
150 bload"eth.bin",p($42000),r       : rem load library to bank 4
160 print chr$(14);                   : rem lowercase / ascii display
170 key 1,chr$(133):key 3,chr$(135):key on
180 sprite 0,0
190 background 0:border 0
200 sv$="":ch$="":tp$="":pj$="":ob$="":ld=0:nt=0:nr=0:nw$="":lc=-1:pd=0:gosub 800
210 window 0,2,67,22:cursor 0,0
220 cr$=chr$(13)+chr$(10)             : rem irc line terminator
230 rem == reset ethernet controller ==
240 print"Resetting Ethernet...":print
250 sys $42000
260 gosub 3470                       : rem dhcp or manual network setup
270 rem == network is configured ==
280 rem == irc is ascii, turn on translation ==
290 sys $42015,1
300 rem == gather connection settings ==
310 print:pp$=" - Server: ":df$="irc.libera.chat":gosub 3890:sv$=an$
320 pp$=" - Port: ":df$="6667":gosub 3890:po$=an$
330 pp$=" - Channel (Optional): ":df$="#mega65":gosub 3890:ch$=an$
340 pp$=" - Nick: ":df$="":gosub 3890:nk$=an$:if nk$="" then 340
350 pp$=" - NickServ Pwd (Optional) : ":df$="":mk=1:gosub 3890:pw$=an$:mk=0
360 rem == resolve the server name ==
370 print:print"resolving ";sv$;" ";
380 a$=sv$:sys $42063:rreg a
390 if a=0 then print"{lred}bad name.{wht}":end
400 tt=ti
410 sys $42024:sys $42036:rreg a
420 if a=2 then 450
430 if a=3 then print"{lred}lookup failed.{wht}":end
440 if ti-tt<600 then 410:else print"{lred}timed out.{wht}":end
450 sys $42033:rreg a,x,y,z
460 ad$=mid$(str$(a),2)+"."+mid$(str$(x),2)+"."+mid$(str$(y),2)+"."+mid$(str$(z),2)
470 sys $4200c,a,x,y,z              : rem set remote ip
480 print"-> ";ad$
490 po=val(po$):if po<1 or po>65535 then print"{lred}bad port.{wht}":goto 320
500 ph=int(po/256):pl=po-ph*256
510 sys $4200f,ph,pl                : rem set remote port
520 sys $42009,$c0,int(rnd(1)*255)  : rem random ephemeral local port
530 rem == connect ==
540 print:print"connecting...";
550 sys $42027
560 tt=ti
570 sys $4202a:rreg a
580 if (a and 1) then 610
590 if (a and 2) then print"{lred} failed.{wht}":end
600 if ti-tt<2000 then 570:else print"{lred} timed out.{wht}":end
610 li=0:jn=0:rl$="":ob$="":tp$="":pj$="":ld=0:rd=0:nt=0:nr=0:nw$="":lc=-1:pd=0:iw=0:ij=0:jp=0 : rem ld=names loading
620 gosub 800:gosub 1530             : rem ui, register
630 rem ====================== main loop =========================
640 if jp=1 and ti-jt>600 then gosub 4100
650 if iw=1 and ti-it>600 then iw=0:pr$="{yel}* NickServ authorization timed out.":gosub 1050:gosub 1120
660 get k$:if k$<>"" then gosub 1800 : rem keyboard gets first chance
670 bc=0
680 sys $4201e:rreg a               : rem read one incoming byte
690 if a=0 then 780                 : rem 0 = ring empty
700 if a=10 then 770                : rem ignore lf
710 if nr=1 then gosub 3270:goto 770
720 if a=13 and rd=1 then rd=0:rl$="":goto 780
730 if a=13 then gosub 1220:gosub 1120:goto 780 : rem process line, refresh input
740 if rd=1 then 770
750 if len(rl$)<250 then rl$=rl$+chr$(a):gosub 3340:goto 770
760 rd=1:rl$="":goto 780
770 bc=bc+1:if bc<96 then 680
780 sys $42024:rreg a:if a<>0 then 2110
790 goto 650
800 rem ================== build screen ==========================
810 cursor off:cc=0:cr=0
820 window 0,0,79,24:print"{wht}{clr}";
830 window 0,2,67,22,1             : rem chat scroll region (cleared)
840 rem -- draw header on row 0 (full screen) --
850 window 0,0,79,24:print chr$(19);chr$(19);:cursor 0,0
860 for zj=0 to 79:t@&(zj,0)=160:c@&(zj,0)=1:t@&(zj,1)=160:c@&(zj,1)=3:next
870 hd$="Mega-IP IRC Chat v"+vs$:if sv$<>"" then hd$="Mega-IP IRC Chat : "+sv$
880 if len(hd$)>64 then hd$=left$(hd$,64)
890 h2$=hd$:if len(hd$)>64 then h2$=left$(hd$,64)
900 if len(h2$)>64 then h2$=left$(h2$,64)
910 print"{rvon}{wht}";h2$;
920 cursor 65,0:print"{rvon}{lgrn}/help for menu";
930 cursor 0,1:print"{rvof}";
940 tb$="":if ch$<>"" then tb$="Channel: "+ch$:if ch$<>"" and tp$<>"" then tb$=tb$+" - "+tp$
950 if len(tb$)>79 then tb$=left$(tb$,79)
960 t2$=tb$:if len(tb$)>79 then t2$=left$(tb$,79)
970 if len(t2$)>79 then t2$=left$(t2$,79)
980 print"{rvon}{cyn}";t2$;
990 cursor 0,2:print"{rvof}";
1000 gosub 1060                      : rem fixed frame
1010 gosub 2540                      : rem fill names panel
1020 gosub 1120                      : rem draw empty input line
1030 return
1040 rem -- print one line into the chat window --
1050 window 0,2,67,22:cursor cc,cr:print:print pr$;chr$(27);chr$(79);:rcursor cc,cr:return
1060 rem -- redraw fixed divider and input separator --
1070 window 0,0,79,24
1080 for zj=2 to 22:t@&(68,zj)=93:c@&(68,zj)=3:next
1090 for zj=0 to 79:t@&(zj,23)=64:c@&(zj,23)=3:next
1100 t@&(68,23)=113:c@&(68,23)=3
1110 window 0,2,67,22:return
1120 rem -- redraw the input line on row 24 --
1130 window 0,0,79,24:print chr$(19);chr$(19);:cursor 0,24
1140 if pd=1 then lm$="Leaving channel...":print"{yel}";lm$;:zk=77-len(lm$):if zk>0 then for zj=1 to zk:print" ";:next:window 0,2,67,22:return
1150 if iw=1 then lm$="Authorizing your credentials...":print"{yel}";lm$;:zk=77-len(lm$):if zk>0 then for zj=1 to zk:print" ";:next:window 0,2,67,22:return
1160 if jp=1 and ob$="" then lm$="Joining "+ch$+"...":print"{yel}";lm$;:zk=77-len(lm$):if zk>0 then for zj=1 to zk:print" ";:next:window 0,2,67,22:return
1170 if ld=1 and ob$="" then gosub 3400:return
1180 if len(ob$)>77 then id$=right$(ob$,77):else id$=ob$
1190 print"{wht}";id$;chr$(27);chr$(79);chr$(18);" ";chr$(146);  : rem esc-o cancels quote mode
1200 zk=77-len(id$):if zk>0 then for zj=1 to zk:print" ";:next
1210 window 0,2,67,22:return
1220 rem ================== process incoming line =================
1230 if rl$="" then return
1240 if left$(rl$,4)="PING" then a$="PONG"+mid$(rl$,5)+cr$:sys $4201b:rl$="":return
1250 gosub 1530                      : rem register on first line
1260 cm$="":cp=instr(rl$," "):if left$(rl$,1)=":" and cp>0 then cm$=mid$(rl$,cp+1,3)
1270 if cm$="432" or cm$="433" then gosub 4130:rl$="":return       : rem nick invalid/in use
1280 if ch$<>"" and cm$="332" then gosub 2930:rl$="":return        : rem topic reply
1290 if ch$<>"" and cm$="331" then tp$="":gosub 3080:rl$="":return  : rem no topic
1300 if ch$<>"" and cm$="333" then rl$="":return                   : rem topic metadata
1310 if ch$<>"" and (cm$="353" or instr(rl$," 353 ")>0) then jp=0:ij=1:gosub 2380:rl$="":return  : rem names reply
1320 if ch$<>"" and (cm$="366" or instr(rl$," 366 ")>0) then jp=0:ij=1:ld=0:nr=0:nw$="":gosub 2540:rl$="":return  : rem end of names
1330 if jn=0 and instr(rl$," 001")>0 then jn=1:gosub 1560
1340 if pd=1 and cm$="442" then ch$="":tp$="":pj$="":pd=0:ij=0:jp=0:ld=0:nr=0:nw$="":nc=0:nt=0:gosub 800:gosub 2690:rl$="":return
1350 if pd=1 and instr(rl$," PART ")=0 then rl$="":return
1360 if cm$="470" then gosub 4030:rl$="":return
1370 if ch$<>"" and instr("403 405 471 473 474 475 476 477 489",cm$)>0 then gosub 3170:rl$="":return
1380 if left$(rl$,1)<>":" then pr$=rl$:gosub 1050:rl$="":return
1390 ns=instr(rl$,"!"):if ns=0 then ns=instr(rl$," ")
1400 if ns<3 then pr$=rl$:gosub 1050:rl$="":return
1410 sn$=mid$(rl$,2,ns-2)
1420 if instr(rl$," NOTICE ")>0 then gosub 1770:rl$="":return
1430 if instr(rl$," PRIVMSG ")>0 then gosub 1590:rl$="":return
1440 if ch$<>"" and instr(rl$," JOIN ")>0 then gosub 2490:rl$="":return
1450 if ch$<>"" and instr(rl$," PART ")>0 then gosub 2810:rl$="":return
1460 if ch$<>"" and instr(rl$," QUIT ")>0 then gosub 2780:rl$="":return
1470 if ch$<>"" and instr(rl$," TOPIC ")>0 then gosub 2930:rl$="":return
1480 if ch$<>"" and instr(rl$," MODE "+ch$+" ")>0 then gosub 4380:rl$="":return
1490 if ch$<>"" and instr(rl$," NICK ")>0 then gosub 1730:rl$="":return
1500 if pd=1 then rl$="":return
1510 mp=instr(rl$," :"):if mp=0 then pr$=rl$:else pr$=mid$(rl$,mp+2)
1520 gosub 1050:rl$="":return
1530 if li=1 then return
1540 li=1:a$="nick "+nk$+cr$:sys $4201b
1550 a$="user "+nk$+" 0 * :"+nk$+cr$:sys $4201b:return
1560 rem -- after welcome, identify first if requested, then join --
1570 if pw$<>"" then a$="privmsg NickServ :IDENTIFY "+pw$+cr$:sys $4201b:iw=1:it=ti:pr$="{wht}* identifying with NickServ...":gosub 1050:return
1580 gosub 2270:return
1590 mp=instr(rl$," :"):if mp=0 then return
1600 pv=instr(rl$," PRIVMSG "):if pv=0 then return
1610 tg$=mid$(rl$,pv+9):sp=instr(tg$," "):if sp=0 then return
1620 tg$=left$(tg$,sp-1):mb$=mid$(rl$,mp+2):if left$(mb$,1)=chr$(1) then 1670
1630 sx$=mb$:gosub 4290:mb$=sy$
1640 if tg$=ch$ then pr$="{cyn}<{lgrn}"+sn$+"{cyn}> {wht}"+mb$:gosub 1050:return
1650 zn$=tg$:gosub 2740:tc$=zz$:zn$=nk$:gosub 2740:if tc$<>zz$ then return
1660 pr$="{lred}*PM* {cyn}<"+sn$+">{wht} "+mb$:gosub 1050:return
1670 ap=instr(mb$,"ACTION "):if ap>0 then mb$=mid$(mb$,ap+7)
1680 if right$(mb$,1)=chr$(1) then mb$=left$(mb$,len(mb$)-1)
1690 sx$=mb$:gosub 4290:mb$=sy$
1700 if tg$=ch$ then pr$="{yel} * "+sn$+" "+mb$:gosub 1050:return
1710 zn$=tg$:gosub 2740:tc$=zz$:zn$=nk$:gosub 2740:if tc$<>zz$ then return
1720 pr$="{lred}*PM* {yel}* "+sn$+" "+mb$:gosub 1050:return
1730 np=instr(rl$," NICK "):nn$=mid$(rl$,np+6):if left$(nn$,1)=":" then nn$=mid$(nn$,2)
1740 zn$=sn$:gosub 2740:os$=zz$
1750 for zi=0 to nc-1:zn$=nm$(zi):gosub 2740:if zz$=os$ then nm$(zi)=nn$
1760 next:pr$="{yel} * "+sn$+" is now "+nn$:gosub 1050:gosub 2540:return
1770 mp=instr(rl$," :"):if mp=0 then return
1780 mb$=mid$(rl$,mp+2):sx$=mb$:gosub 4290:mb$=sy$:gosub 4190
1790 pr$="{yel}-"+sn$+"- {wht}"+mb$:gosub 1050:return
1800 rem ====================== keyboard ==========================
1810 if iw=1 then ob$="":gosub 1120:return
1820 if pd=1 then ob$="":gosub 1120:return
1830 if k$=chr$(147) or k$=chr$(19) then return
1840 if k$=chr$(133) then gosub 3000:return
1850 if k$=chr$(135) then gosub 3040:return
1860 if k$=chr$(13) then gosub 1900:gosub 1120:return
1870 if k$=chr$(20) then if len(ob$)>0 then ob$=left$(ob$,len(ob$)-1)
1880 if k$<>chr$(13) and k$<>chr$(20) and len(ob$)<200 then ob$=ob$+k$
1890 gosub 1120:return
1900 rem -- a line was entered --
1910 if ob$="" then return
1920 if left$(ob$,1)="/" then gosub 1980:ob$="":return
1930 if ch$="" or ij=0 then pr$="{lred}* not in a channel.":gosub 1050:ob$="":return
1940 if pd=1 then pr$="{lred}* leaving channel, standby.":gosub 1050:ob$="":return
1950 mx=235-len(ch$)-12:if len(ob$)>mx then pr$="{lred}* line too long.":gosub 1050:ob$="":return
1960 a$="privmsg "+ch$+" :"+ob$+cr$:sys $4201b
1970 pr$="{cyn}<{lred}"+nk$+"{cyn}> {lred}"+ob$:gosub 1050:ob$="":return
1980 rem -- slash command --
1990 if left$(ob$,5)="/msg " then gosub 2870:return
2000 if left$(ob$,6)="/join " then nj$=mid$(ob$,7):if ij=1 then pj$=nj$:a$="part "+ch$+cr$:sys $4201b:pd=1:ld=0:nr=0:nw$="":gosub 1120:return
2010 if left$(ob$,6)="/join " then ch$=nj$:tp$="":pj$="":iw=0:pd=0:ij=0:gosub 800:gosub 2270:return
2020 if ob$="/part" and ch$="" then pr$="{lred}* not in a channel.":gosub 1050:return
2030 if ob$="/part" and ij=0 then ch$="":tp$="":pj$="":iw=0:jp=0:pd=0:ld=0:nr=0:nw$="":nc=0:nt=0:gosub 800:gosub 2690:return
2040 if ob$="/part" then pj$="":a$="part "+ch$+cr$:sys $4201b:pd=1:ld=0:nr=0:nw$="":gosub 1120:return
2050 if left$(ob$,6)="/nick " then nk$=mid$(ob$,7):a$="nick "+nk$+cr$:sys $4201b:pr$="{wht}* nick is now "+nk$:gosub 1050:return
2060 if ob$="/names" and ch$<>"" then nc=0:nt=0:ld=1:nr=0:nw$="":lc=-1:gosub 2540:gosub 3400:a$="names "+ch$+cr$:sys $4201b:return
2070 if left$(ob$,4)="/me " then gosub 2960:return
2080 if ob$="/quit" then a$="quit :bye"+cr$:sys $4201b:sys $42021:print chr$(19);chr$(19);"{clr}{wht}disconnected.":end
2090 if ob$="/help" then gosub 2130:return
2100 pr$="{lred}* unknown command.":gosub 1050:return
2110 rem -- disconnected --
2120 sys $4205d:print chr$(19);chr$(19);"{clr}{lred}* connection closed.{wht}":end
2130 rem -- help --
2140 pr$="":gosub 1050
2150 pr$="{lgrn}MegaIP Help:":gosub 1050
2160 pr$="{lgrn}/join #channel      - join a channel":gosub 1050
2170 pr$="{lgrn}/part               - leave channel":gosub 1050
2180 pr$="{lgrn}/nick name          - change nick":gosub 1050
2190 pr$="{lgrn}/names              - refresh names":gosub 1050
2200 pr$="{lgrn}/msg <nick> message - send private message":gosub 1050
2210 pr$="{lgrn}/me action          - send an action":gosub 1050
2220 pr$="{lgrn}/quit               - disconnect":gosub 1050:return
2230 rem -- rreg ip into ad$ --
2240 rreg a,x,y,z
2250 ad$=mid$(str$(a),2)+"."+mid$(str$(x),2)+"."+mid$(str$(y),2)+"."+mid$(str$(z),2)
2260 return
2270 rem -- join the configured channel --
2280 if ch$="" then gosub 2690:return
2290 ij=0:jp=1:jt=ti:a$="join "+ch$+cr$:sys $4201b:nc=0:nt=0:ld=1:nr=0:nw$="":lc=-1:tp$="":return
2300 rem -- add zn$ to nick list if not already present --
2310 dn$=zn$:gosub 2740:os$=zz$:fd=0:for zi=0 to nc-1:zn$=nm$(zi):gosub 2740:if zz$=os$ then fd=1
2320 next:if fd=0 and nc<nl then nm$(nc)=dn$:nc=nc+1
2330 return
2340 rem -- remove zn$ from nick list --
2350 gosub 2740:os$=zz$:fp=-1:for zi=0 to nc-1:zn$=nm$(zi):gosub 2740:if zz$=os$ then fp=zi
2360 next:if fp<0 then return
2370 for zj=fp to nc-2:nm$(zj)=nm$(zj+1):next:nc=nc-1:return
2380 rem -- parse a 353 names reply into the array --
2390 mp=instr(rl$," :"):if mp=0 then return
2400 tn$=mid$(rl$,mp+2)
2410 sp=instr(tn$," "):if sp=0 then zn$=tn$:gosub 2430:return
2420 zn$=left$(tn$,sp-1):gosub 2430:tn$=mid$(tn$,sp+1):goto 2410
2430 rem -- add zn$ to list (keep leading @/+/etc prefix) --
2440 if zn$="" then return
2450 if ld=1 then gosub 2470:return
2460 gosub 2300:return
2470 if nc<nl then nm$(nc)=zn$:nc=nc+1:gosub 3400
2480 return
2490 rem -- a JOIN line --
2500 if pd=1 then return
2510 zn$=sn$:gosub 2740:os$=zz$:zn$=nk$:gosub 2740
2520 if os$=zz$ then jp=0:ij=1:ld=1:lc=-1:gosub 2540:gosub 3400:return
2530 zn$=sn$:gosub 2300:pr$="{yel} * "+sn$+" joined.":gosub 1050:gosub 2540:return
2540 rem -- fill names panel with absolute cursors; avoids narrow-window scroll --
2550 window 0,0,79,24
2560 mx=nc-20:if mx<0 then mx=0
2570 if nt<0 then nt=0
2580 if nt>mx then nt=mx
2590 for zy=2 to 22:cursor 69,zy:print"          ";:next
2600 if nc=0 and ld=1 then cursor 69,2:print"{yel}loading";:goto 2650
2610 if nc=0 then goto 2650
2620 ze=nt+20:if ze>nc then ze=nc
2630 for zi=nt to ze-1:cursor 69,2+(zi-nt):print"{wht}";left$(nm$(zi),10);:next
2640 gosub 3210
2650 gosub 1060:window 0,2,67,22:return
2660 rem -- part notice: self already handled by /part; others -> "left" --
2670 if sn$=nk$ then return
2680 pr$="{yel} * "+sn$+" left.":gosub 1050:return
2690 window 0,2,67,22,1:cc=0:cr=0:gosub 1060          : rem clear chat, home to top
2700 pr$="{wht}You are not in a channel.":gosub 1050
2710 pr$="":gosub 1050
2720 pr$="/join #channel - join a channel":gosub 1050
2730 pr$="/quit - disconnect (end)":gosub 1050:return
2740 rem -- normalize nick into zz$ by dropping irc mode prefix --
2750 zz$=zn$:if zz$="" then return
2760 if instr("@+%&~",left$(zz$,1))>0 then zz$=mid$(zz$,2):goto 2760
2770 return
2780 rem -- a QUIT line --
2790 zn$=sn$:gosub 2340:if pd=1 then gosub 2540:return
2800 pr$="{yel} * "+sn$+" quit irc.":gosub 1050:gosub 2540:return
2810 rem -- a PART line --
2820 zn$=sn$:gosub 2740:os$=zz$:zn$=nk$:gosub 2740
2830 if os$<>zz$ then zn$=sn$:gosub 2340:if pd=1 then gosub 2540:return
2840 if os$<>zz$ then gosub 2660:gosub 2540:return
2850 if pj$<>"" then ch$=pj$:pj$="":tp$="":nc=0:nt=0:ld=1:nr=0:nw$="":lc=-1:pd=0:ij=0:gosub 800:gosub 2270:return
2860 ch$="":tp$="":nc=0:nt=0:ld=0:nr=0:nw$="":lc=-1:pd=0:ij=0:jp=0:gosub 800:gosub 2690:return
2870 rem -- private message command: /msg nick text --
2880 pm$=mid$(ob$,6):sp=instr(pm$," "):if sp=0 then pr$="{lred}* usage: /msg nick text":gosub 1050:return
2890 tn$=left$(pm$,sp-1):mb$=mid$(pm$,sp+1):if mb$="" then return
2900 dn$=tn$:zn$=tn$:gosub 2740:tn$=zz$
2910 mx=235-len(tn$)-12:if len(mb$)>mx then pr$="{lred}* message too long.":gosub 1050:return
2920 a$="privmsg "+tn$+" :"+mb$+cr$:sys $4201b:pr$="{cyn}->{lgrn}"+dn$+"{cyn} {lred}"+mb$:gosub 1050:return
2930 rem -- channel topic / announcement bar --
2940 mp=instr(rl$," :"):if mp=0 then tp$="":gosub 3080:return
2950 sx$=mid$(rl$,mp+2):gosub 4290:tp$=sy$:gosub 3080:return
2960 rem -- channel action command --
2970 if ch$="" then pr$="{lred}* not in a channel.":gosub 1050:return
2980 ac$=mid$(ob$,5):mx=235-len(ch$)-21:if len(ac$)>mx then pr$="{lred}* action too long.":gosub 1050:return
2990 a$="privmsg "+ch$+" :"+chr$(1)+"action "+ac$+chr$(1)+cr$:sys $4201b:pr$="{yel} * "+nk$+" "+ac$:gosub 1050:return
3000 rem -- keyboard names pager: f1 previous, f3 next --
3010 if nc<=20 then return
3020 if nt>0 then nt=nt-20:gosub 2540:gosub 1120
3030 return
3040 if nc<=20 then return
3050 mm=nc-20:if mm<0 then mm=0
3060 if nt<mm then nt=nt+20:gosub 2540:gosub 1120
3070 return
3080 rem -- redraw channel/topic bar only --
3090 window 0,0,79,24:for zj=0 to 79:t@&(zj,1)=160:c@&(zj,1)=3:next:cursor 0,1
3100 tb$="":if ch$<>"" then tb$="Channel: "+ch$:if ch$<>"" and tp$<>"" then tb$=tb$+" - "+tp$
3110 if len(tb$)>79 then tb$=left$(tb$,79)
3120 t2$=tb$:if len(tb$)>79 then t2$=left$(tb$,79)
3130 if len(t2$)>79 then t2$=left$(t2$,79)
3140 print"{rvon}{cyn}";t2$;
3150 cursor 0,2:print"{rvof}";
3160 window 0,2,67,22:return
3170 rem -- join failed or was redirected/denied --
3180 jc$=ch$:er$=rl$:mp=instr(rl$," :"):if mp>0 then er$=mid$(rl$,mp+2)
3190 ch$="":tp$="":pj$="":ld=0:nr=0:nw$="":lc=-1:nc=0:nt=0:pd=0:iw=0:ij=0:jp=0
3200 gosub 800:pr$="{lred}* "+jc$+": "+er$:gosub 1050:return
3210 rem -- draw nick panel pager row --
3220 if nc<=20 then return
3230 for zx=69 to 78:t@&(zx,22)=160:c@&(zx,22)=1:next
3240 if nt>0 then cursor 69,22:print"{rvon}{wht}<=F1";
3250 if nt<mx then cursor 75,22:print"{rvon}{wht}F3=";:t@&(78,22)=190:c@&(78,22)=1
3260 print"{rvof}";:return
3270 rem -- consume one byte of a streamed 353 names list --
3280 if a=13 then if nw$<>"" then zn$=nw$:gosub 2430
3290 if a=13 then nr=0:nw$="":return
3300 if a=32 then if nw$<>"" then zn$=nw$:gosub 2430:nw$=""
3310 if a=32 then return
3320 if len(nw$)<40 then nw$=nw$+chr$(a)
3330 return
3340 rem -- switch long 353 names lines to streaming parse --
3350 if ld<>1 or nr=1 then return
3360 if instr(rl$," 353 ")=0 then return
3370 mp=instr(rl$," :"):if mp=0 then return
3380 tn$=mid$(rl$,mp+2):rl$="":nr=1:nw$="":rd=0
3390 for zp=1 to len(tn$):a=asc(mid$(tn$,zp,1)):gosub 3270:next:return
3400 rem -- loading names status line --
3410 if ld<>1 or ob$<>"" then return
3420 if lc=nc then return
3430 lc=nc:lm$="Loading names, standby... "+mid$(str$(nc),2)
3440 window 0,0,79,24:print chr$(19);chr$(19);:cursor 0,24
3450 print"{yel}";lm$;:zk=77-len(lm$):if zk>0 then for zj=1 to zk:print" ";:next
3460 window 0,2,67,22:return
3470 rem -- configure network like terminal.bas --
3480 print:print" - [D]HCP Autoconfig or [M]anual Config":print
3490 getkey cf$
3500 if cf$="d" or cf$="D" then 3530
3510 if cf$="m" or cf$="M" then 3650
3520 goto 3490
3530 print" - Attempting DHCP autoconfig...":print
3540 sys $42042:a=-1
3550 for t=1 to 20000
3560 sys $42024:sys $42045:rreg b
3570 if b<>a and b=1 then print"..DISCOVER sent":a=b
3580 if b<>a and b=2 then print"..OFFER seen":a=b
3590 if b<>a and b=3 then print"..REQUEST sent":a=b
3600 if b<>a and b=4 then print"..IP Bound":a=b
3610 if b=4 then 3690
3620 if b=127 then 3640
3630 next:print"{lred}..DHCP timeout.{wht}":sleep 2:goto 3480
3640 print"{lred}..DHCP failed.{wht}":sleep 2:goto 3480
3650 input " - Local IP       :   192.168.1.76{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}";oc$:gosub 3770:if x=0 then 3650:else sys $42006,oc(0),oc(1),oc(2),oc(3)
3660 input " - Default Gateway:   192.168.1.1{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}";oc$:gosub 3770:if x=0 then 3660:else sys $42003,oc(0),oc(1),oc(2),oc(3)
3670 input " - Subnet Mask    :   255.255.255.0{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}";oc$:gosub 3770:if x=0 then 3670:else sys $42012,oc(0),oc(1),oc(2),oc(3)
3680 input " - Primary DNS    :   8.8.8.8{left}{left}{left}{left}{left}{left}{left}{left}{left}";oc$:gosub 3770:if x=0 then 3680:else sys $4204b,oc(0),oc(1),oc(2),oc(3)
3690 sys $4205d
3700 window 0,2,67,22,1:cc=0:cr=0:gosub 1060
3710 print"{wht}Network Settings:"
3720 print" Local IP       : ";:sys $4204e:gosub 2230:print ad$
3730 print" Default Gateway: ";:sys $42051:gosub 2230:print ad$
3740 print" Subnet Mask    : ";:sys $42054:gosub 2230:print ad$
3750 print" Primary DNS    : ";:sys $42057:gosub 2230:print ad$:print
3760 return
3770 rem -- octet string to oc() --
3780 x=0:oc(0)=0:oc(1)=0:oc(2)=0:oc(3)=0
3790 for t=1 to len(oc$)
3800 if mid$(oc$,t,1)="." then x=x+1
3810 next
3820 if x<>3 then x=0:return
3830 t$="":ct=0
3840 for t=1 to len(oc$)
3850 if mid$(oc$,t,1)="." then oc(ct)=val(t$):ct=ct+1:t$="":else t$=t$+mid$(oc$,t,1)
3860 next t:oc(ct)=val(t$)
3870 for t=0 to 3:if oc(t)<0 or oc(t)>255 then x=0:return
3880 next:x=1:return
3890 rem -- chat-pane prompt: pp$ + editable default df$ -> an$ --
3900 an$=df$:dd=1:print pp$;:if mk=1 and len(an$)>0 then for z=1 to len(an$):print"*";:next
3910 if mk<>1 then print an$;
3920 gosub 4530
3930 getkey k$:gosub 4540
3940 if k$=chr$(147) or k$=chr$(19) then gosub 4530:goto 3930
3950 if k$=chr$(13) then print:return
3960 if k$=chr$(20) then dd=0:if len(an$)>0 then an$=left$(an$,len(an$)-1):print chr$(20);" ";chr$(20);
3970 if k$=chr$(20) then gosub 4530:goto 3930
3980 if len(k$)<>1 then gosub 4530:goto 3930
3990 if asc(k$)<32 then gosub 4530:goto 3930
4000 if dd=1 and df$<>"" then for z=1 to len(an$):print chr$(20);" ";chr$(20);:next:an$="":dd=0
4010 if len(an$)<60 then an$=an$+k$:if mk=1 then print"*";:else print k$;
4020 gosub 4530:goto 3930
4030 rem -- channel forward numeric 470: old channel -> new channel --
4040 fw$=rl$:for zx=1 to 4:p=instr(fw$," "):if p=0 then return
4050 fw$=mid$(fw$,p+1):next
4060 p=instr(fw$," "):if p>0 then fw$=left$(fw$,p-1)
4070 if fw$="" then return
4080 ch$=fw$:tp$="":nc=0:nt=0:ld=1:nr=0:nw$="":lc=-1:pd=0:ij=0:jp=1:jt=ti
4090 gosub 800:return
4100 rem -- join timed out without success, redirect, or failure --
4110 jc$=ch$:ch$="":tp$="":pj$="":ld=0:nr=0:nw$="":lc=-1:nc=0:nt=0:pd=0:iw=0:ij=0:jp=0
4120 gosub 800:gosub 2690:pr$="{lred}* join timed out: "+jc$:gosub 1050:return
4130 rem -- nickname invalid or already in use; pick a fallback and retry --
4140 rn=int(rnd(1)*9000)+1000
4150 if cm$="432" then nk$="mega"+mid$(str$(rn),2):goto 4180
4160 if len(nk$)>12 then nk$=left$(nk$,12)
4170 nk$=nk$+mid$(str$(rn),2)
4180 a$="nick "+nk$+cr$:sys $4201b:pr$="{yel}* trying nick "+nk$:gosub 1050:return
4190 rem -- NickServ identify notice watcher --
4200 if iw<>1 then return
4210 if instr(mb$,"You are now identified")>0 or instr(mb$,"You are now logged in")>0 then 4280
4220 if instr(mb$,"Password accepted")>0 or instr(mb$,"Authentication successful")>0 then 4280
4230 if instr(mb$,"Invalid password")>0 or instr(mb$,"Password incorrect")>0 then 4260
4240 if instr(mb$,"not registered")>0 or instr(mb$,"not recognized")>0 or instr(mb$,"No such nick")>0 then 4260
4250 return
4260 iw=0:jp=0:ij=0:ld=0:nr=0:nw$="":ch$="":tp$="":gosub 3080:gosub 2540
4270 pr$="{lred}* NickServ identify failed.":gosub 1050:return
4280 iw=0:pr$="{wht}* NickServ identified.":gosub 1050:gosub 2270:return
4290 rem -- strip irc color/control codes from sx$ into sy$ --
4300 sy$="":for qx=1 to len(sx$)
4310 qc=asc(mid$(sx$,qx,1)):if qc=3 then gosub 4350:goto 4340
4320 if qc<32 then 4340
4330 sy$=sy$+mid$(sx$,qx,1)
4340 next:return
4350 if qx<len(sx$) then qc=asc(mid$(sx$,qx+1,1)):if qc>=48 and qc<=57 then qx=qx+1:goto 4350
4360 if qx<len(sx$) and mid$(sx$,qx+1,1)="," then qx=qx+1:goto 4350
4370 return
4380 rem -- simple channel mode prefix update for +o/-o/+v/-v --
4390 mp=instr(rl$," MODE "+ch$+" "):if mp=0 then return
4400 md$=mid$(rl$,mp+len(ch$)+7):sp=instr(md$," "):if sp=0 then return
4410 mo$=left$(md$,sp-1):tn$=mid$(md$,sp+1):sp=instr(tn$," "):if sp>0 then tn$=left$(tn$,sp-1)
4420 if tn$="" then return
4430 px$="":if instr(mo$,"+o")>0 then px$="@"
4440 if px$="" and instr(mo$,"+v")>0 then px$="+"
4450 zn$=tn$:gosub 2740:os$=zz$:fp=-1:for zi=0 to nc-1:zn$=nm$(zi):gosub 2740:if zz$=os$ then fp=zi
4460 next:if fp<0 then return
4470 zn$=nm$(fp):gosub 2740:bn$=zz$
4480 if instr(mo$,"-o")>0 and left$(nm$(fp),1)="@" then nm$(fp)=bn$:gosub 2540:return
4490 if instr(mo$,"-v")>0 and left$(nm$(fp),1)="+" then nm$(fp)=bn$:gosub 2540:return
4500 if px$="+" and left$(nm$(fp),1)="@" then return
4510 if px$<>"" then nm$(fp)=px$+bn$:gosub 2540:return
4520 return
4530 print chr$(18);" ";chr$(146);:return
4540 print chr$(20);" ";chr$(20);:return
