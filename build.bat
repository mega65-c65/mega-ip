cls
del *.bin
del *.lst
del *.prg
del megaip.d81
del basic/term.prg
del basic/webserver.prg

64tass ./src/eth.asm --nostart -L eth.lst -o eth.bin

c1541 -format megaip,wr d81 megaip.d81

petcat -w65 -o basic/webserver.prg -- basic/webserver.bas
petcat -w65 -o basic/term.prg -- basic/term.bas

c1541 megaip.d81 -write basic/term.prg term.prg
c1541 megaip.d81 -write basic/cursor.bin cursor
c1541 megaip.d81 -write basic/webserver.prg webserver.prg
c1541 megaip.d81 -write eth.bin

