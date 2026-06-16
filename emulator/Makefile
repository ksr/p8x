# P8X emulator + microcode + assembler
CC=cc
CFLAGS=-O2 -Wall
# adjust UC if the microcode directory moves again
UC=../microcode

all: p8xemu ucode

p8xemu: p8xemu.c
	$(CC) $(CFLAGS) -o $@ $<

ucode:
	cd $(UC) && python3 genucode.py

test: p8xemu ucode
	cd test && cp ../$(UC)/u?.bin . && \
	python3 ../../assembler/p8xasm.py test1.asm -o t1.bin && ../p8xemu t1.bin && \
	python3 ../../assembler/p8xasm.py test2.asm -o t2.bin && ../p8xemu t2.bin && \
	python3 ../../assembler/p8xasm.py test3.asm -o t3.bin && ../p8xemu t3.bin
	$(MAKE) test-isa

# Per-instruction self-checking regression: halts with A=00 on success,
# or A=<test id> at the first failing check.
test-isa: p8xemu ucode
	cd test && cp ../$(UC)/u?.bin . && \
	python3 ../../assembler/p8xasm.py test_isa.asm -o tisa.bin && \
	../p8xemu tisa.bin 2>tisa.out; \
	grep -q ' A=00 ' tisa.out && echo "ISA TEST: PASS" || \
	  { echo "ISA TEST: FAIL —"; tail -1 tisa.out; exit 1; }

.PHONY: all ucode test test-isa
