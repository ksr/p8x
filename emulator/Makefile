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
	$(MAKE) test-c
	$(MAKE) test-asm-selfhost
	$(MAKE) test-io
	$(MAKE) test-mem

# p8cc C cross-compiler: compile -> assemble -> run -> check console output.
test-c: p8xemu ucode
	sh test/c_compile_test.sh
	sh test/c_libc_test.sh
	sh test/c_struct_test.sh
	sh test/c_global_test.sh
	sh test/c_selfhost_test.sh

# Native assembler self-host: assemble its own source on-target == host build.
# Slow (37 KB through the emulated assembler twice); run on demand, not in `test`.
test-asm-selfhost: p8xemu ucode
	sh test/asm_selfhost_test.sh

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
	sh test/cf_hilba_test.sh
	sh test/fs_bios_test.sh
	sh test/fdelete_test.sh
	sh test/fopen_test.sh
	sh test/fwrite_test.sh
	sh test/fresolve_test.sh
	sh test/fwrdir_test.sh
	sh test/fnorm_test.sh
	sh test/fnext_test.sh

# P8X/OS boot: build a P8XFS image with the OS + files, boot it, run DIR.
test-os: p8xemu ucode
	sh test/os_test.sh
	sh test/os_v2_test.sh
	sh test/os_format_test.sh
	sh test/os_argv_test.sh
	sh test/os_edit_test.sh
	sh test/os_asm_test.sh

# BASIC: launch ROM BASIC from the monitor (X), and boot disk BASIC (B).
test-basic: p8xemu ucode
	sh test/basic_rom_test.sh
	sh test/basic_disk_test.sh
	sh test/basic_saveload_test.sh
	sh test/os_basic_test.sh

# I/O card model: switch input (-s) -> $FF00 and LED writes ($FF02, -L).
test-io: p8xemu ucode
	sh test/io_test.sh

# rev D memory map: $4000-$7FFF is now RAM (was ROM). Write+readback -> 'Y'.
test-mem: p8xemu ucode
	cd test && cp ../$(UC)/u?.bin . && \
	python3 ../../assembler/p8xasm.py test_ram48.asm -o tmem.bin && \
	../p8xemu -l 200000 tmem.bin 2>/dev/null | tr -d '\0' | grep -q Y && \
	  echo "MEM48 TEST: PASS" || { echo "MEM48 TEST: FAIL"; exit 1; }

.PHONY: all ucode rom test test-isa test-cf test-os test-basic test-io test-mem test-c test-asm-selfhost
