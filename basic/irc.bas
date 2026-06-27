100 rem ==================================================================
105 rem = mega-ip irc chat client for basic65
110 rem = demo of the eth.bin tcp/ip library
120 rem ==================================================================
125 vs$="1.0"
130 bload"eth.bin",p($42000),r       : rem load library to bank 4
135 print chr$(14);                   : rem lowercase / ascii display
140 background 0:border 0
145 print"{clr}{wht}";
150 print"{rvon} mega-ip irc chat   v"+vs$+" {rvof}":print
155 cr$=chr$(13)+chr$(10)             : rem irc line terminator
160 rem == reset ethernet controller ==
165 print"resetting ethernet...":print
170 sys $42000
175 rem == dhcp autoconfig ==
180 print"requesting dhcp address...":print
185 sys $42042
190 tt=ti
195 sys $42024:sys $42045:rreg b
200 if b=4 then 230
205 if b=127 then print"{lred}dhcp failed.{wht}":end
210 if ti-tt<1200 then 195
215 print"{lred}dhcp timed out.{wht}":end
230 print"ip address: ";:sys $4204e:gosub 900:print ad$:print
240 rem == irc is ascii, turn on translation ==
245 sys $42015,1
250 rem == gather connection settings ==
255 print"server  (irc.libera.chat) :":input sv$:if sv$="" then sv$="irc.libera.chat"
260 print"port    (6667) :":input po$:if po$="" then po$="6667"
265 print"channel (#mega65) :":input ch$:if ch$="" then ch$="#c64friends"
270 print"nick :":input nk$:if nk$="" then 270
300 rem == resolve the server name ==
305 print:print"resolving ";sv$;" ";
310 a$=sv$:sys $42063:rreg a
315 if a=0 then print"{lred}bad name.{wht}":end
320 tt=ti
325 sys $42024:sys $42036:rreg a
330 if a=2 then 345
335 if a=3 then print"{lred}lookup failed.{wht}":end
340 if ti-tt<600 then 325:else print"{lred}timed out.{wht}":end
345 sys $42033:rreg a,x,y,z
347 ad$=mid$(str$(a),2)+"."+mid$(str$(x),2)+"."+mid$(str$(y),2)+"."+mid$(str$(z),2)
350 sys $4200c,a,x,y,z              : rem set remote ip
355 print"-> ";ad$
360 po=val(po$):ph=int(po/256):pl=po-ph*256
365 sys $4200f,ph,pl                : rem set remote port
370 sys $42009,$c0,int(rnd(1)*255)  : rem random ephemeral local port
375 rem == connect ==
380 print:print"connecting...";
385 sys $42027
390 tt=ti
395 sys $4202a:rreg a
400 if (a and 1) then 420
405 if (a and 2) then print"{lred} failed.{wht}":end
410 if ti-tt<2000 then 395:else print"{lred} timed out.{wht}":end
420 li=0:jn=0:rl$="":ob$=""
425 gosub 600                       : rem build the split-screen ui
500 rem ====================== main loop =========================
505 sys $4201e:rreg a               : rem read one incoming byte
510 if a=0 then 525                 : rem 0 = ring empty
515 if a=10 then 505                : rem ignore lf
520 if a=13 then gosub 700:goto 525 : rem cr = end of irc line
522 if len(rl$)<250 then rl$=rl$+chr$(a)
524 goto 505
525 get k$:if k$<>"" then gosub 800 : rem one keystroke per pass
530 sys $42024:rreg a:if a<>0 then 870
535 goto 505
600 rem ================== build screen ==========================
605 cursor off:cc=0:cr=0
610 print"{wht}{clr}";
615 window 0,1,79,22,1             : rem chat scroll region (cleared)
620 rem -- draw header on row 0 (full screen) --
625 print chr$(19);chr$(19);:cursor 0,0
630 hd$="mega-ip irc "+ch$:if len(hd$)>79 then hd$=left$(hd$,79)
635 print"{rvon}{wht}";hd$;:zk=79-len(hd$):for zj=1 to zk:print" ";:next:print"{rvof}";
640 rem -- separator on row 23 --
645 cursor 0,23:print"{cyn}";:for zj=0 to 78:print chr$(192);:next
650 gosub 680                      : rem draw empty input line
655 return
660 rem -- print one line into the chat window --
665 window 0,1,79,22:cursor cc,cr:print:print pr$;:rcursor cc,cr:return
680 rem -- redraw the input line on row 24 --
685 print chr$(19);chr$(19);:cursor 0,24
690 if len(ob$)>77 then id$=right$(ob$,77):else id$=ob$
692 print"{wht}";id$;chr$(18);" ";chr$(146);
694 zk=77-len(id$):if zk>0 then for zj=1 to zk:print" ";:next
696 return
700 rem ================== process incoming line =================
705 if rl$="" then return
710 if left$(rl$,4)="PING" then a$="PONG"+mid$(rl$,5)+cr$:sys $4201b:rl$="":return
715 gosub 760                      : rem register on first line
720 if jn=0 and instr(rl$," 001")>0 then jn=1:a$="join "+ch$+cr$:sys $4201b
725 if left$(rl$,1)<>":" then pr$=rl$:gosub 665:rl$="":return
730 ns=instr(rl$,"!"):if ns=0 then ns=instr(rl$," ")
735 sn$=mid$(rl$,2,ns-2)
740 if instr(rl$," PRIVMSG ")>0 then gosub 770:rl$="":return
742 if instr(rl$," JOIN ")>0 then pr$="{yel} * "+sn$+" joined.":gosub 665:rl$="":return
744 if instr(rl$," PART ")>0 then pr$="{yel} * "+sn$+" left.":gosub 665:rl$="":return
746 if instr(rl$," QUIT ")>0 then pr$="{yel} * "+sn$+" quit irc.":gosub 665:rl$="":return
748 if instr(rl$," NICK ")>0 then gosub 790:rl$="":return
750 mp=instr(rl$," :"):if mp=0 then pr$=rl$:else pr$=mid$(rl$,mp+2)
752 gosub 665:rl$="":return
760 if li=1 then return
762 li=1:a$="nick "+nk$+cr$:sys $4201b
764 a$="user "+nk$+" 0 * :"+nk$+cr$:sys $4201b:return
770 mp=instr(rl$," :"):if mp=0 then return
772 mb$=mid$(rl$,mp+2):if left$(mb$,1)=chr$(1) then 780
774 pr$="{cyn}<{lgrn}"+sn$+"{cyn}> {wht}"+mb$:gosub 665:return
780 ap=instr(mb$,"ACTION "):if ap>0 then mb$=mid$(mb$,ap+7)
782 if right$(mb$,1)=chr$(1) then mb$=left$(mb$,len(mb$)-1)
784 pr$="{yel} * "+sn$+" "+mb$:gosub 665:return
790 np=instr(rl$," NICK "):nn$=mid$(rl$,np+6):if left$(nn$,1)=":" then nn$=mid$(nn$,2)
792 pr$="{yel} * "+sn$+" is now "+nn$:gosub 665:return
800 rem ====================== keyboard ==========================
805 if k$=chr$(13) then gosub 820:gosub 680:return
810 if k$=chr$(20) then if len(ob$)>0 then ob$=left$(ob$,len(ob$)-1)
815 if k$<>chr$(13) and k$<>chr$(20) and len(ob$)<200 then ob$=ob$+k$
818 gosub 680:return
820 rem -- a line was entered --
825 if ob$="" then return
830 if left$(ob$,1)="/" then gosub 850:ob$="":return
835 if ch$="" then pr$="{lred}* not in a channel.":gosub 665:ob$="":return
840 a$="privmsg "+ch$+" :"+ob$+cr$:sys $4201b
845 pr$="{cyn}<{lred}"+nk$+"{cyn}> {lred}"+ob$:gosub 665:ob$="":return
850 rem -- slash command --
852 if left$(ob$,6)="/join " then ch$=mid$(ob$,7):a$="join "+ch$+cr$:sys $4201b:gosub 620:pr$="{wht}* joined "+ch$:gosub 665:return
854 if ob$="/part" then a$="part "+ch$+cr$:sys $4201b:pr$="{wht}* left "+ch$:gosub 665:ch$="":gosub 620:return
856 if left$(ob$,6)="/nick " then nk$=mid$(ob$,7):a$="nick "+nk$+cr$:sys $4201b:pr$="{wht}* nick is now "+nk$:gosub 665:return
858 if left$(ob$,4)="/me " then ac$=mid$(ob$,5):a$="privmsg "+ch$+" :"+chr$(1)+"action "+ac$+chr$(1)+cr$:sys $4201b:pr$="{yel} * "+nk$+" "+ac$:gosub 665:return
860 if ob$="/quit" then a$="quit :bye"+cr$:sys $4201b:sys $42021:print chr$(19);chr$(19);"{clr}{wht}disconnected.":end
862 if ob$="/help" then gosub 880:return
864 pr$="{lred}* unknown command.":gosub 665:return
870 rem -- disconnected --
872 sys $4205d:print chr$(19);chr$(19);"{clr}{lred}* connection closed.{wht}":end
880 rem -- help --
882 pr$="{wht}commands:":gosub 665
884 pr$="/join #chan  join a channel":gosub 665
886 pr$="/part        leave channel":gosub 665
888 pr$="/nick name   change nick":gosub 665
890 pr$="/me action   send an action":gosub 665
892 pr$="/quit        disconnect":gosub 665:return
900 rem -- rreg ip into ad$ --
905 rreg a,x,y,z
910 ad$=mid$(str$(a),2)+"."+mid$(str$(x),2)+"."+mid$(str$(y),2)+"."+mid$(str$(z),2)
915 return
