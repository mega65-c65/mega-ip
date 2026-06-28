100 rem ==================================================================
105 rem = mega-ip irc chat client for basic65
110 rem = demo of the eth.bin tcp/ip library
120 rem ==================================================================
125 vs$="1.0":nl=4095:dim nm$(nl):nc=0 : rem nick list
130 bload"eth.bin",p($42000),r       : rem load library to bank 4
135 print chr$(14);                   : rem lowercase / ascii display
136 key 1,chr$(133):key 3,chr$(135):key on
137 sprite 0,0
140 background 0:border 0
145 sv$="":ch$="":tp$="":pj$="":ob$="":ld=0:nt=0:nr=0:nw$="":lc=-1:pd=0:gosub 600
150 window 0,2,67,22:cursor 0,0
155 cr$=chr$(13)+chr$(10)             : rem irc line terminator
160 rem == reset ethernet controller ==
165 print"Resetting Ethernet...":print
170 sys $42000
175 gosub 1100                       : rem dhcp or manual network setup
230 rem == network is configured ==
240 rem == irc is ascii, turn on translation ==
245 sys $42015,1
250 rem == gather connection settings ==
255 print:pp$=" - Server: ":df$="irc.libera.chat":gosub 1360:sv$=an$
260 pp$=" - Port: ":df$="6667":gosub 1360:po$=an$
265 pp$=" - Channel (Optional): ":df$="":gosub 1360:ch$=an$
270 pp$=" - Nick: ":df$="":gosub 1360:nk$=an$:if nk$="" then 270
275 pp$=" - NickServ Pwd (Optional) : ":df$="":mk=1:gosub 1360:pw$=an$:mk=0
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
360 po=val(po$):if po<1 or po>65535 then print"{lred}bad port.{wht}":goto 260
362 ph=int(po/256):pl=po-ph*256
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
420 li=0:jn=0:rl$="":ob$="":tp$="":pj$="":ld=0:rd=0:nt=0:nr=0:nw$="":lc=-1:pd=0:iw=0:ij=0:jp=0 : rem ld=names loading
425 gosub 600:gosub 760             : rem ui, register
500 rem ====================== main loop =========================
504 if jp=1 and ti-jt>600 then gosub 1390
505 if iw=1 and ti-it>600 then iw=0:pr$="{yel}* NickServ authorization timed out.":gosub 665:gosub 680
506 get k$:if k$<>"" then gosub 800 : rem keyboard gets first chance
507 bc=0
508 sys $4201e:rreg a               : rem read one incoming byte
510 if a=0 then 530                 : rem 0 = ring empty
515 if a=10 then 528                : rem ignore lf
516 if nr=1 then gosub 1070:goto 528
520 if a=13 and rd=1 then rd=0:rl$="":goto 530
521 if a=13 then gosub 700:gosub 680:goto 530 : rem process line, refresh input
522 if rd=1 then 528
523 if len(rl$)<250 then rl$=rl$+chr$(a):gosub 1080:goto 528
524 rd=1:rl$="":goto 530
528 bc=bc+1:if bc<96 then 508
530 sys $42024:rreg a:if a<>0 then 870
535 goto 505
600 rem ================== build screen ==========================
605 cursor off:cc=0:cr=0
610 window 0,0,79,24:print"{wht}{clr}";
615 window 0,2,67,22,1             : rem chat scroll region (cleared)
620 rem -- draw header on row 0 (full screen) --
625 window 0,0,79,24:print chr$(19);chr$(19);:cursor 0,0
626 for zj=0 to 79:t@&(zj,0)=160:c@&(zj,0)=1:t@&(zj,1)=160:c@&(zj,1)=3:next
630 hd$="Mega-IP IRC Chat v"+vs$:if sv$<>"" then hd$="Mega-IP IRC Chat : "+sv$
632 if len(hd$)>64 then hd$=left$(hd$,64)
633 h2$=hd$:if len(hd$)>64 then h2$=left$(hd$,64)
634 if len(h2$)>64 then h2$=left$(h2$,64)
635 print"{rvon}{wht}";h2$;
636 cursor 65,0:print"{rvon}{lgrn}/help for menu";
637 cursor 0,1:print"{rvof}";
638 tb$="":if ch$<>"" then tb$="Channel: "+ch$:if ch$<>"" and tp$<>"" then tb$=tb$+" - "+tp$
639 if len(tb$)>79 then tb$=left$(tb$,79)
640 t2$=tb$:if len(tb$)>79 then t2$=left$(tb$,79)
641 if len(t2$)>79 then t2$=left$(t2$,79)
642 print"{rvon}{cyn}";t2$;
643 cursor 0,2:print"{rvof}";
644 gosub 670                      : rem fixed frame
647 gosub 950                      : rem fill names panel
650 gosub 680                      : rem draw empty input line
655 return
660 rem -- print one line into the chat window --
665 window 0,2,67,22:cursor cc,cr:print:print pr$;chr$(27);chr$(79);:rcursor cc,cr:return
670 rem -- redraw fixed divider and input separator --
671 window 0,0,79,24
672 for zj=2 to 22:t@&(68,zj)=93:c@&(68,zj)=3:next
673 for zj=0 to 79:t@&(zj,23)=64:c@&(zj,23)=3:next
674 t@&(68,23)=113:c@&(68,23)=3
675 window 0,2,67,22:return
680 rem -- redraw the input line on row 24 --
685 window 0,0,79,24:print chr$(19);chr$(19);:cursor 0,24
686 if pd=1 then lm$="Leaving channel...":print"{yel}";lm$;:zk=77-len(lm$):if zk>0 then for zj=1 to zk:print" ";:next:window 0,2,67,22:return
687 if iw=1 then lm$="Authorizing your credentials...":print"{yel}";lm$;:zk=77-len(lm$):if zk>0 then for zj=1 to zk:print" ";:next:window 0,2,67,22:return
688 if jp=1 and ob$="" then lm$="Joining "+ch$+"...":print"{yel}";lm$;:zk=77-len(lm$):if zk>0 then for zj=1 to zk:print" ";:next:window 0,2,67,22:return
689 if ld=1 and ob$="" then gosub 1090:return
690 if len(ob$)>77 then id$=right$(ob$,77):else id$=ob$
692 print"{wht}";id$;chr$(27);chr$(79);chr$(18);" ";chr$(146);  : rem esc-o cancels quote mode
694 zk=77-len(id$):if zk>0 then for zj=1 to zk:print" ";:next
696 window 0,2,67,22:return
700 rem ================== process incoming line =================
705 if rl$="" then return
710 if left$(rl$,4)="PING" then a$="PONG"+mid$(rl$,5)+cr$:sys $4201b:rl$="":return
715 gosub 760                      : rem register on first line
716 cm$="":cp=instr(rl$," "):if left$(rl$,1)=":" and cp>0 then cm$=mid$(rl$,cp+1,3)
717 if cm$="432" or cm$="433" then gosub 1400:rl$="":return       : rem nick invalid/in use
718 if ch$<>"" and cm$="332" then gosub 1010:rl$="":return        : rem topic reply
719 if ch$<>"" and cm$="331" then tp$="":gosub 1040:rl$="":return  : rem no topic
720 if ch$<>"" and cm$="333" then rl$="":return                   : rem topic metadata
721 if ch$<>"" and (cm$="353" or instr(rl$," 353 ")>0) then jp=0:ij=1:gosub 930:rl$="":return  : rem names reply
722 if ch$<>"" and (cm$="366" or instr(rl$," 366 ")>0) then jp=0:ij=1:ld=0:nr=0:nw$="":gosub 950:rl$="":return  : rem end of names
723 if jn=0 and instr(rl$," 001")>0 then jn=1:gosub 765
724 if pd=1 and cm$="442" then ch$="":tp$="":pj$="":pd=0:ij=0:jp=0:ld=0:nr=0:nw$="":nc=0:nt=0:gosub 600:gosub 970:rl$="":return
725 if pd=1 and instr(rl$," PART ")=0 then rl$="":return
726 if cm$="470" then gosub 1375:rl$="":return
727 if ch$<>"" and instr("403 405 471 473 474 475 476 477 489",cm$)>0 then gosub 1050:rl$="":return
728 if left$(rl$,1)<>":" then pr$=rl$:gosub 665:rl$="":return
730 ns=instr(rl$,"!"):if ns=0 then ns=instr(rl$," ")
734 if ns<3 then pr$=rl$:gosub 665:rl$="":return
735 sn$=mid$(rl$,2,ns-2)
740 if instr(rl$," NOTICE ")>0 then gosub 795:rl$="":return
741 if instr(rl$," PRIVMSG ")>0 then gosub 770:rl$="":return
742 if ch$<>"" and instr(rl$," JOIN ")>0 then gosub 945:rl$="":return
744 if ch$<>"" and instr(rl$," PART ")>0 then gosub 990:rl$="":return
746 if ch$<>"" and instr(rl$," QUIT ")>0 then gosub 985:rl$="":return
747 if ch$<>"" and instr(rl$," TOPIC ")>0 then gosub 1010:rl$="":return
748 if ch$<>"" and instr(rl$," MODE "+ch$+" ")>0 then gosub 1440:rl$="":return
749 if ch$<>"" and instr(rl$," NICK ")>0 then gosub 790:rl$="":return
750 if pd=1 then rl$="":return
751 mp=instr(rl$," :"):if mp=0 then pr$=rl$:else pr$=mid$(rl$,mp+2)
752 gosub 665:rl$="":return
760 if li=1 then return
762 li=1:a$="nick "+nk$+cr$:sys $4201b
764 a$="user "+nk$+" 0 * :"+nk$+cr$:sys $4201b:return
765 rem -- after welcome, identify first if requested, then join --
766 if pw$<>"" then a$="privmsg NickServ :IDENTIFY "+pw$+cr$:sys $4201b:iw=1:it=ti:pr$="{wht}* identifying with NickServ...":gosub 665:return
767 gosub 916:return
770 mp=instr(rl$," :"):if mp=0 then return
772 mb$=mid$(rl$,mp+2):if left$(mb$,1)=chr$(1) then 780
773 sx$=mb$:gosub 1420:mb$=sy$
774 if ch$<>"" and instr(rl$," PRIVMSG "+ch$+" ")>0 then pr$="{cyn}<{lgrn}"+sn$+"{cyn}> {wht}"+mb$:gosub 665:return
776 pr$="{lred}*PM* {cyn}<"+sn$+">{wht} "+mb$:gosub 665:return
780 ap=instr(mb$,"ACTION "):if ap>0 then mb$=mid$(mb$,ap+7)
782 if right$(mb$,1)=chr$(1) then mb$=left$(mb$,len(mb$)-1)
783 sx$=mb$:gosub 1420:mb$=sy$
784 if ch$<>"" and instr(rl$," PRIVMSG "+ch$+" ")>0 then pr$="{yel} * "+sn$+" "+mb$:gosub 665:return
786 pr$="{lred}*PM* {yel}* "+sn$+" "+mb$:gosub 665:return
790 np=instr(rl$," NICK "):nn$=mid$(rl$,np+6):if left$(nn$,1)=":" then nn$=mid$(nn$,2)
791 zn$=sn$:gosub 980:os$=zz$
792 for zi=0 to nc-1:zn$=nm$(zi):gosub 980:if zz$=os$ then nm$(zi)=nn$
793 next:pr$="{yel} * "+sn$+" is now "+nn$:gosub 665:gosub 950:return
795 mp=instr(rl$," :"):if mp=0 then return
796 mb$=mid$(rl$,mp+2):sx$=mb$:gosub 1420:mb$=sy$:gosub 1410
797 pr$="{yel}-"+sn$+"- {wht}"+mb$:gosub 665:return
800 rem ====================== keyboard ==========================
801 if iw=1 then ob$="":gosub 680:return
802 if pd=1 then ob$="":gosub 680:return
803 if k$=chr$(133) then gosub 1030:return
804 if k$=chr$(135) then gosub 1035:return
805 if k$=chr$(13) then gosub 820:gosub 680:return
810 if k$=chr$(20) then if len(ob$)>0 then ob$=left$(ob$,len(ob$)-1)
815 if k$<>chr$(13) and k$<>chr$(20) and len(ob$)<200 then ob$=ob$+k$
818 gosub 680:return
820 rem -- a line was entered --
825 if ob$="" then return
830 if left$(ob$,1)="/" then gosub 850:ob$="":return
835 if ch$="" or ij=0 then pr$="{lred}* not in a channel.":gosub 665:ob$="":return
836 if pd=1 then pr$="{lred}* leaving channel, standby.":gosub 665:ob$="":return
837 mx=235-len(ch$)-12:if len(ob$)>mx then pr$="{lred}* line too long.":gosub 665:ob$="":return
840 a$="privmsg "+ch$+" :"+ob$+cr$:sys $4201b
845 pr$="{cyn}<{lred}"+nk$+"{cyn}> {lred}"+ob$:gosub 665:ob$="":return
850 rem -- slash command --
851 if left$(ob$,5)="/msg " then gosub 1000:return
852 if left$(ob$,6)="/join " then nj$=mid$(ob$,7):if ij=1 then pj$=nj$:a$="part "+ch$+cr$:sys $4201b:pd=1:ld=0:nr=0:nw$="":gosub 680:return
853 if left$(ob$,6)="/join " then ch$=nj$:tp$="":pj$="":iw=0:pd=0:ij=0:gosub 600:gosub 916:return
854 if ob$="/part" and ch$="" then pr$="{lred}* not in a channel.":gosub 665:return
855 if ob$="/part" and ij=0 then ch$="":tp$="":pj$="":iw=0:jp=0:pd=0:ld=0:nr=0:nw$="":nc=0:nt=0:gosub 600:gosub 970:return
856 if ob$="/part" then pj$="":a$="part "+ch$+cr$:sys $4201b:pd=1:ld=0:nr=0:nw$="":gosub 680:return
857 if left$(ob$,6)="/nick " then nk$=mid$(ob$,7):a$="nick "+nk$+cr$:sys $4201b:pr$="{wht}* nick is now "+nk$:gosub 665:return
858 if ob$="/names" and ch$<>"" then nc=0:nt=0:ld=1:nr=0:nw$="":lc=-1:gosub 950:gosub 1090:a$="names "+ch$+cr$:sys $4201b:return
859 if left$(ob$,4)="/me " then gosub 1020:return
862 if ob$="/quit" then a$="quit :bye"+cr$:sys $4201b:sys $42021:print chr$(19);chr$(19);"{clr}{wht}disconnected.":end
863 if ob$="/help" then gosub 880:return
864 pr$="{lred}* unknown command.":gosub 665:return
870 rem -- disconnected --
872 sys $4205d:print chr$(19);chr$(19);"{clr}{lred}* connection closed.{wht}":end
880 rem -- help --
882 pr$="":gosub 665
883 pr$="{lgrn}MegaIP Help:":gosub 665
884 pr$="{lgrn}/join #channel      - join a channel":gosub 665
886 pr$="{lgrn}/part               - leave channel":gosub 665
888 pr$="{lgrn}/nick name          - change nick":gosub 665
889 pr$="{lgrn}/names              - refresh names":gosub 665
891 pr$="{lgrn}/msg <nick> message - send private message":gosub 665
892 pr$="{lgrn}/me action          - send an action":gosub 665
893 pr$="{lgrn}/quit               - disconnect":gosub 665:return
900 rem -- rreg ip into ad$ --
905 rreg a,x,y,z
910 ad$=mid$(str$(a),2)+"."+mid$(str$(x),2)+"."+mid$(str$(y),2)+"."+mid$(str$(z),2)
915 return
916 rem -- join the configured channel --
917 if ch$="" then gosub 970:return
918 ij=0:jp=1:jt=ti:a$="join "+ch$+cr$:sys $4201b:nc=0:nt=0:ld=1:nr=0:nw$="":lc=-1:tp$="":return
920 rem -- add zn$ to nick list if not already present --
921 dn$=zn$:gosub 980:os$=zz$:fd=0:for zi=0 to nc-1:zn$=nm$(zi):gosub 980:if zz$=os$ then fd=1
922 next:if fd=0 and nc<nl then nm$(nc)=dn$:nc=nc+1
923 return
925 rem -- remove zn$ from nick list --
926 gosub 980:os$=zz$:fp=-1:for zi=0 to nc-1:zn$=nm$(zi):gosub 980:if zz$=os$ then fp=zi
927 next:if fp<0 then return
928 for zj=fp to nc-2:nm$(zj)=nm$(zj+1):next:nc=nc-1:return
930 rem -- parse a 353 names reply into the array --
931 mp=instr(rl$," :"):if mp=0 then return
932 tn$=mid$(rl$,mp+2)
933 sp=instr(tn$," "):if sp=0 then zn$=tn$:gosub 936:return
934 zn$=left$(tn$,sp-1):gosub 936:tn$=mid$(tn$,sp+1):goto 933
936 rem -- add zn$ to list (keep leading @/+/etc prefix) --
937 if zn$="" then return
938 if ld=1 then gosub 940:return
939 gosub 920:return
940 if nc<nl then nm$(nc)=zn$:nc=nc+1:gosub 1090
941 return
945 rem -- a JOIN line --
946 if pd=1 then return
947 zn$=sn$:gosub 980:os$=zz$:zn$=nk$:gosub 980
948 if os$=zz$ then jp=0:ij=1:ld=1:lc=-1:gosub 950:gosub 1090:return
949 zn$=sn$:gosub 920:pr$="{yel} * "+sn$+" joined.":gosub 665:gosub 950:return
950 rem -- fill names panel with absolute cursors; avoids narrow-window scroll --
951 window 0,0,79,24
952 mx=nc-20:if mx<0 then mx=0
953 if nt<0 then nt=0
954 if nt>mx then nt=mx
955 for zy=2 to 22:cursor 69,zy:print"          ";:next
957 if nc=0 and ld=1 then cursor 69,2:print"{yel}loading";:goto 962
958 if nc=0 then goto 962
959 ze=nt+20:if ze>nc then ze=nc
960 for zi=nt to ze-1:cursor 69,2+(zi-nt):print"{wht}";left$(nm$(zi),10);:next
961 gosub 1060
962 gosub 670:window 0,2,67,22:return
965 rem -- part notice: self already handled by /part; others -> "left" --
966 if sn$=nk$ then return
967 pr$="{yel} * "+sn$+" left.":gosub 665:return
970 window 0,2,67,22,1:cc=0:cr=0:gosub 670          : rem clear chat, home to top
971 pr$="{wht}You are not in a channel.":gosub 665
972 pr$="":gosub 665
973 pr$="/join #channel - join a channel":gosub 665
974 pr$="/quit - disconnect (end)":gosub 665:return
980 rem -- normalize nick into zz$ by dropping irc mode prefix --
981 zz$=zn$:if zz$="" then return
982 if instr("@+%&~",left$(zz$,1))>0 then zz$=mid$(zz$,2):goto 982
983 return
985 rem -- a QUIT line --
986 zn$=sn$:gosub 925:if pd=1 then gosub 950:return
987 pr$="{yel} * "+sn$+" quit irc.":gosub 665:gosub 950:return
990 rem -- a PART line --
991 zn$=sn$:gosub 980:os$=zz$:zn$=nk$:gosub 980
992 if os$<>zz$ then zn$=sn$:gosub 925:if pd=1 then gosub 950:return
993 if os$<>zz$ then gosub 965:gosub 950:return
994 if pj$<>"" then ch$=pj$:pj$="":tp$="":nc=0:nt=0:ld=1:nr=0:nw$="":lc=-1:pd=0:ij=0:gosub 600:gosub 916:return
995 ch$="":tp$="":nc=0:nt=0:ld=0:nr=0:nw$="":lc=-1:pd=0:ij=0:jp=0:gosub 600:gosub 970:return
1000 rem -- private message command: /msg nick text --
1001 pm$=mid$(ob$,6):sp=instr(pm$," "):if sp=0 then pr$="{lred}* usage: /msg nick text":gosub 665:return
1002 tn$=left$(pm$,sp-1):mb$=mid$(pm$,sp+1):if mb$="" then return
1003 dn$=tn$:zn$=tn$:gosub 980:tn$=zz$
1004 mx=235-len(tn$)-12:if len(mb$)>mx then pr$="{lred}* message too long.":gosub 665:return
1006 a$="privmsg "+tn$+" :"+mb$+cr$:sys $4201b:pr$="{cyn}->{lgrn}"+dn$+"{cyn} {lred}"+mb$:gosub 665:return
1010 rem -- channel topic / announcement bar --
1011 mp=instr(rl$," :"):if mp=0 then tp$="":gosub 1040:return
1012 sx$=mid$(rl$,mp+2):gosub 1420:tp$=sy$:gosub 1040:return
1020 rem -- channel action command --
1021 if ch$="" then pr$="{lred}* not in a channel.":gosub 665:return
1022 ac$=mid$(ob$,5):mx=235-len(ch$)-21:if len(ac$)>mx then pr$="{lred}* action too long.":gosub 665:return
1024 a$="privmsg "+ch$+" :"+chr$(1)+"action "+ac$+chr$(1)+cr$:sys $4201b:pr$="{yel} * "+nk$+" "+ac$:gosub 665:return
1030 rem -- keyboard names pager: f1 previous, f3 next --
1031 if nc<=20 then return
1032 if nt>0 then nt=nt-20:gosub 950:gosub 680
1033 return
1035 if nc<=20 then return
1036 mm=nc-20:if mm<0 then mm=0
1037 if nt<mm then nt=nt+20:gosub 950:gosub 680
1038 return
1040 rem -- redraw channel/topic bar only --
1041 window 0,0,79,24:for zj=0 to 79:t@&(zj,1)=160:c@&(zj,1)=3:next:cursor 0,1
1042 tb$="":if ch$<>"" then tb$="Channel: "+ch$:if ch$<>"" and tp$<>"" then tb$=tb$+" - "+tp$
1043 if len(tb$)>79 then tb$=left$(tb$,79)
1044 t2$=tb$:if len(tb$)>79 then t2$=left$(tb$,79)
1045 if len(t2$)>79 then t2$=left$(t2$,79)
1046 print"{rvon}{cyn}";t2$;
1047 cursor 0,2:print"{rvof}";
1048 window 0,2,67,22:return
1050 rem -- join failed or was redirected/denied --
1051 jc$=ch$:er$=rl$:mp=instr(rl$," :"):if mp>0 then er$=mid$(rl$,mp+2)
1052 ch$="":tp$="":pj$="":ld=0:nr=0:nw$="":lc=-1:nc=0:nt=0:pd=0:iw=0:ij=0:jp=0
1053 gosub 600:pr$="{lred}* "+jc$+": "+er$:gosub 665:return
1060 rem -- draw nick panel pager row --
1061 if nc<=20 then return
1062 for zx=69 to 78:t@&(zx,22)=160:c@&(zx,22)=1:next
1063 if nt>0 then cursor 69,22:print"{rvon}{wht}<=F1";
1064 if nt<mx then cursor 75,22:print"{rvon}{wht}F3=";:t@&(78,22)=190:c@&(78,22)=1
1065 print"{rvof}";:return
1070 rem -- consume one byte of a streamed 353 names list --
1071 if a=13 then if nw$<>"" then zn$=nw$:gosub 936
1072 if a=13 then nr=0:nw$="":return
1073 if a=32 then if nw$<>"" then zn$=nw$:gosub 936:nw$=""
1074 if a=32 then return
1075 if len(nw$)<40 then nw$=nw$+chr$(a)
1076 return
1080 rem -- switch long 353 names lines to streaming parse --
1081 if ld<>1 or nr=1 then return
1082 if instr(rl$," 353 ")=0 then return
1083 mp=instr(rl$," :"):if mp=0 then return
1084 tn$=mid$(rl$,mp+2):rl$="":nr=1:nw$="":rd=0
1085 for zp=1 to len(tn$):a=asc(mid$(tn$,zp,1)):gosub 1070:next:return
1090 rem -- loading names status line --
1091 if ld<>1 or ob$<>"" then return
1092 if lc=nc then return
1093 lc=nc:lm$="Loading names, standby... "+mid$(str$(nc),2)
1094 window 0,0,79,24:print chr$(19);chr$(19);:cursor 0,24
1095 print"{yel}";lm$;:zk=77-len(lm$):if zk>0 then for zj=1 to zk:print" ";:next
1096 window 0,2,67,22:return
1100 rem -- configure network like terminal.bas --
1105 print:print" - [D]HCP Autoconfig or [M]anual Config":print
1110 getkey cf$
1115 if cf$="d" or cf$="D" then 1130
1120 if cf$="m" or cf$="M" then 1190
1125 goto 1110
1130 print" - Attempting DHCP autoconfig...":print
1135 sys $42042:a=-1
1140 for t=1 to 20000
1145 sys $42024:sys $42045:rreg b
1150 if b<>a and b=1 then print"..DISCOVER sent":a=b
1155 if b<>a and b=2 then print"..OFFER seen":a=b
1160 if b<>a and b=3 then print"..REQUEST sent":a=b
1165 if b<>a and b=4 then print"..IP Bound":a=b
1170 if b=4 then 1260
1175 if b=127 then 1185
1180 next:print"{lred}..DHCP timeout.{wht}":sleep 2:goto 1105
1185 print"{lred}..DHCP failed.{wht}":sleep 2:goto 1105
1190 input " - Local IP       :   192.168.1.76{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}";oc$:gosub 1300:if x=0 then 1190:else sys $42006,oc(0),oc(1),oc(2),oc(3)
1200 input " - Default Gateway:   192.168.1.1{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}";oc$:gosub 1300:if x=0 then 1200:else sys $42003,oc(0),oc(1),oc(2),oc(3)
1210 input " - Subnet Mask    :   255.255.255.0{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}{left}";oc$:gosub 1300:if x=0 then 1210:else sys $42012,oc(0),oc(1),oc(2),oc(3)
1220 input " - Primary DNS    :   8.8.8.8{left}{left}{left}{left}{left}{left}{left}{left}{left}";oc$:gosub 1300:if x=0 then 1220:else sys $4204b,oc(0),oc(1),oc(2),oc(3)
1260 sys $4205d
1262 window 0,2,67,22,1:cc=0:cr=0:gosub 670
1265 print"{wht}Network Settings:"
1270 print" Local IP       : ";:sys $4204e:gosub 900:print ad$
1275 print" Default Gateway: ";:sys $42051:gosub 900:print ad$
1280 print" Subnet Mask    : ";:sys $42054:gosub 900:print ad$
1285 print" Primary DNS    : ";:sys $42057:gosub 900:print ad$:print
1290 return
1300 rem -- octet string to oc() --
1305 x=0:oc(0)=0:oc(1)=0:oc(2)=0:oc(3)=0
1310 for t=1 to len(oc$)
1315 if mid$(oc$,t,1)="." then x=x+1
1320 next
1325 if x<>3 then x=0:return
1330 t$="":ct=0
1335 for t=1 to len(oc$)
1340 if mid$(oc$,t,1)="." then oc(ct)=val(t$):ct=ct+1:t$="":else t$=t$+mid$(oc$,t,1)
1345 next t:oc(ct)=val(t$)
1350 for t=0 to 3:if oc(t)<0 or oc(t)>255 then x=0:return
1355 next:x=1:return
1360 rem -- chat-pane prompt: pp$ + editable default df$ -> an$ --
1361 an$=df$:dd=1:print pp$;:if mk=1 and len(an$)>0 then for z=1 to len(an$):print"*";:next
1362 if mk<>1 then print an$;
1363 gosub 1460
1364 getkey k$:gosub 1461
1365 if k$=chr$(13) then print:return
1366 if k$=chr$(20) then dd=0:if len(an$)>0 then an$=left$(an$,len(an$)-1):print chr$(20);" ";chr$(20);
1367 if k$=chr$(20) then gosub 1460:goto 1364
1368 if len(k$)<>1 then gosub 1460:goto 1364
1369 if asc(k$)<32 then gosub 1460:goto 1364
1370 if dd=1 and df$<>"" then for z=1 to len(an$):print chr$(20);" ";chr$(20);:next:an$="":dd=0
1371 if len(an$)<60 then an$=an$+k$:if mk=1 then print"*";:else print k$;
1372 gosub 1460:goto 1364
1373 rem
1375 rem -- channel forward numeric 470: old channel -> new channel --
1376 fw$=rl$:for zx=1 to 4:p=instr(fw$," "):if p=0 then return
1377 fw$=mid$(fw$,p+1):next
1378 p=instr(fw$," "):if p>0 then fw$=left$(fw$,p-1)
1379 if fw$="" then return
1380 ch$=fw$:tp$="":nc=0:nt=0:ld=1:nr=0:nw$="":lc=-1:pd=0:ij=0:jp=1:jt=ti
1381 gosub 600:return
1390 rem -- join timed out without success, redirect, or failure --
1391 jc$=ch$:ch$="":tp$="":pj$="":ld=0:nr=0:nw$="":lc=-1:nc=0:nt=0:pd=0:iw=0:ij=0:jp=0
1392 gosub 600:gosub 970:pr$="{lred}* join timed out: "+jc$:gosub 665:return
1400 rem -- nickname invalid or already in use; pick a fallback and retry --
1401 rn=int(rnd(1)*9000)+1000
1402 if cm$="432" then nk$="mega"+mid$(str$(rn),2):goto 1405
1403 if len(nk$)>12 then nk$=left$(nk$,12)
1404 nk$=nk$+mid$(str$(rn),2)
1405 a$="nick "+nk$+cr$:sys $4201b:pr$="{yel}* trying nick "+nk$:gosub 665:return
1410 rem -- NickServ identify notice watcher --
1411 if iw<>1 then return
1412 if instr(mb$,"You are now identified")>0 or instr(mb$,"You are now logged in")>0 then 1419
1413 if instr(mb$,"Password accepted")>0 or instr(mb$,"Authentication successful")>0 then 1419
1414 if instr(mb$,"Invalid password")>0 or instr(mb$,"Password incorrect")>0 then 1417
1415 if instr(mb$,"not registered")>0 or instr(mb$,"not recognized")>0 or instr(mb$,"No such nick")>0 then 1417
1416 return
1417 iw=0:jp=0:ij=0:ld=0:nr=0:nw$="":ch$="":tp$="":gosub 1040:gosub 950
1418 pr$="{lred}* NickServ identify failed.":gosub 665:return
1419 iw=0:pr$="{wht}* NickServ identified.":gosub 665:gosub 916:return
1420 rem -- strip irc color/control codes from sx$ into sy$ --
1421 sy$="":for qx=1 to len(sx$)
1422 qc=asc(mid$(sx$,qx,1)):if qc=3 then gosub 1430:goto 1426
1423 if qc<32 then 1426
1424 sy$=sy$+mid$(sx$,qx,1)
1426 next:return
1430 if qx<len(sx$) then qc=asc(mid$(sx$,qx+1,1)):if qc>=48 and qc<=57 then qx=qx+1:goto 1430
1431 if qx<len(sx$) and mid$(sx$,qx+1,1)="," then qx=qx+1:goto 1430
1432 return
1440 rem -- simple channel mode prefix update for +o/-o/+v/-v --
1441 mp=instr(rl$," MODE "+ch$+" "):if mp=0 then return
1442 md$=mid$(rl$,mp+len(ch$)+7):sp=instr(md$," "):if sp=0 then return
1443 mo$=left$(md$,sp-1):tn$=mid$(md$,sp+1):sp=instr(tn$," "):if sp>0 then tn$=left$(tn$,sp-1)
1444 if tn$="" then return
1445 px$="":if instr(mo$,"+o")>0 then px$="@"
1446 if px$="" and instr(mo$,"+v")>0 then px$="+"
1447 zn$=tn$:gosub 980:os$=zz$:fp=-1:for zi=0 to nc-1:zn$=nm$(zi):gosub 980:if zz$=os$ then fp=zi
1448 next:if fp<0 then return
1449 zn$=nm$(fp):gosub 980:bn$=zz$
1450 if instr(mo$,"-o")>0 and left$(nm$(fp),1)="@" then nm$(fp)=bn$:gosub 950:return
1451 if instr(mo$,"-v")>0 and left$(nm$(fp),1)="+" then nm$(fp)=bn$:gosub 950:return
1452 if px$="+" and left$(nm$(fp),1)="@" then return
1453 if px$<>"" then nm$(fp)=px$+bn$:gosub 950:return
1454 return
1460 print chr$(18);" ";chr$(146);:return
1461 print chr$(20);" ";chr$(20);:return
