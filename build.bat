cls
del *.bin
del *.lst
del *.prg
64tass ./src/eth.asm --nostart -L eth.lst -o eth.bin
64tass ./src/irq.asm -L irq.lst -o irq.bin.prg
