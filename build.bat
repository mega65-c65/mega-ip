@echo off
cls

if not exist target mkdir target

del /q target\*.bin 2>nul
del /q target\*.lst 2>nul
del /q target\*.prg 2>nul
del /q target\*.d81 2>nul

rem Remove legacy build outputs from before target\ was used.
del /q eth.bin 2>nul
del /q eth.lst 2>nul
del /q *.prg 2>nul
del /q megaip.d81 2>nul
del /q basic\term.prg 2>nul
del /q basic\terminal.prg 2>nul
del /q basic\webserver.prg 2>nul
del /q basic\a-term.prg 2>nul
del /q basic\ansi-term.prg 2>nul

.\64tass.exe -D DEBUG=0 .\src\eth.asm --nostart -L target\eth.lst -o target\eth.bin
.\64tass.exe --cbm-prg .\basic\ansi-term.asm -L target\ansi-term.lst -o target\ansi-term.prg
.\64tass.exe --nostart .\basic\cp437_font.asm -o target\cp437.bin

.\c1541.exe -format megaip,wr d81 target\megaip.d81

.\petcat.exe -w65 -o target\webserver.prg -- basic\webserver.bas
.\petcat.exe -w65 -o target\terminal.prg -- basic\terminal.bas
.\petcat.exe -w65 -o target\irc.prg -- basic\irc.bas

.\c1541.exe target\megaip.d81 -write target\terminal.prg terminal
.\c1541.exe target\megaip.d81 -write target\webserver.prg webserver
.\c1541.exe target\megaip.d81 -write target\irc.prg irc
.\c1541.exe target\megaip.d81 -write target\ansi-term.prg ansi-term
.\c1541.exe target\megaip.d81 -write target\eth.bin eth.bin
.\c1541.exe target\megaip.d81 -write target\cp437.bin cp437.bin
.\c1541.exe target\megaip.d81 -write basic\index.html index.html,s
.\c1541.exe target\megaip.d81 -write basic\about.html about.html,s
