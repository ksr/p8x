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

# Build the persistent burnable image set (control-store EPROMs + program ROM)
# into microcode/ and rom/ — see rom/README.md for the chip map.
rom:
	sh ../tools/build_rom.sh

test: p8xemu ucode
	cd test && cp ../$(UC)/u?.bin . && \
	python3 ../../assembler/p8xasm.py test1.asm -o t1.bin && ../p8xemu t1.bin && \
	python3 ../../assembler/p8xasm.py test2.asm -o t2.bin && ../p8xemu t2.bin && \
	python3 ../../assembler/p8xasm.py test3.asm -o t3.bin && ../p8xemu t3.bin
	$(MAKE) test-isa
	$(MAKE) test-cf
	$(MAKE) test-os
	$(MAKE) test-basic
	$(MAKE) test-io

# Per-instruction self-checking regression: halts with A=00 on success,
# or A=<test id> at the first failing check.
test-isa: p8xemu ucode
	cd test && cp ../$(UC)/u?.bin . && \
	python3 ../../assembler/p8xasm.py test_isa.asm -o tisa.bin && \
	../p8xemu tisa.bin 2>tisa.out; \
	grep -q ' A=00 ' tisa.out && echo "ISA TEST: PASS" || \
	  { echo "ISA TEST: FAIL —"; tail -1 tisa.out; exit 1; }

# Filesystem round-trip: monitor F (format) + B (boot) against the CF model.
test-cf: p8xemu ucode
	sh test/cf_test.sh

# P8X/OS boot: build a P8XFS image with the OS + files, boot it, run DIR.
test-os: p8xemu ucode
	sh test/os_test.sh
	sh test/os_v2_test.sh

# BASIC: launch ROM BASIC from the monitor (X), and boot disk BASIC (B).
test-basic: p8xemu ucode
	sh test/basic_rom_test.sh
	sh test/basic_disk_test.sh

# I/O card model: switch input (-s) -> $FF00 and LED writes ($FF02, -L).
test-io: p8xemu ucode
	sh test/io_test.sh

.PHONY: all ucode rom test test-isa test-cf test-os test-basic test-io
