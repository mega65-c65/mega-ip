100 rem ==================================================================
110 rem = mega65 hardware rng test
120 rem = temporary test for $d7fe bit 7 and $d7ef random byte
130 rem ==================================================================
140 rs=55294:rv=55279:ct=64
150 print chr$(147);chr$(14);"{wht}"
160 print "mega65 hardware rng test":print
170 print "$d7fe bit 7 = 1 means rng not ready"
180 print "$d7ef read returns a random byte and starts the next one":print
190 print "press any key for ";ct;" samples, q to quit."
200 getkey k$:if k$="q" or k$="Q" then end
210 print chr$(147);chr$(14);"{wht}"
220 print "rng bytes from $d7ef":print
230 mn=999999:mx=0:tw=0:nr=0
240 for i=1 to ct
250 w=0
260 if (peek(rs) and 128)<>0 then w=w+1:if w<60000 then 260
270 if w>=60000 then print:print "{lred}timeout waiting for ready bit{wht}":goto 370
280 v=peek(rv)
290 if w>0 then nr=nr+1
300 tw=tw+w:if w<mn then mn=w
310 if w>mx then mx=w
320 print right$("  "+mid$(str$(v),2),3);
330 if (i and 15)=0 then print
340 next i
350 print:print "samples        :";ct
360 print "not-ready hits :";nr;"  wait min/max/total:";mn;mx;tw
370 print:print "press any key to sample again, q to quit."
380 goto 200
