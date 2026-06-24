@echo off
cls
del /q *.bin 2>nul
del /q *.lst 2>nul
del /q *.prg 2>nul
del /q megaip.d81 2>nul
del /q basic\term.prg 2>nul
del /q basic\webserver.prg 2>nul
del /q ml-samples\ml-term.prg 2>nul
del /q ml-samples\ml-term.lst 2>nul

.\64tass.exe .\src\eth.asm --nostart -L eth.lst -o eth.bin

.\64tass.exe --cbm-prg .\ml-samples\ml-term.asm -L ml-samples\ml-term.lst -o ml-samples\ml-term.prg

.\c1541.exe -format megaip,wr d81 megaip.d81

.\petcat.exe -w65 -o basic\webserver.prg -- basic\webserver.bas
.\petcat.exe -w65 -o basic\term.prg -- basic\term.bas

.\c1541.exe megaip.d81 -write basic\term.prg term.prg
.\c1541.exe megaip.d81 -write basic\cursor.bin cursor
.\c1541.exe megaip.d81 -write basic\webserver.prg webserver.prg
.\c1541.exe megaip.d81 -write ml-samples\ml-term.prg ml-term.prg
.\c1541.exe megaip.d81 -write eth.bin

