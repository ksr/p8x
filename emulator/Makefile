# P8X emulator + microcode + assembler
CC=cc
CFLAGS=-O2 -Wall
# adjust UC if the microcode directory moves again
UC=../microcode

all: p8xemu ucode

p8xemu: p8xemu.c ../generators/glkwtab.h ../generators/trigtab.h
	$(CC) $(CFLAGS) -o $@ p8xemu.c

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
	$(MAKE) test-gfx

# p8cc C cross-compiler: compile -> assemble -> run -> check console output.
test-c: p8xemu ucode
	sh test/c_compile_test.sh
	sh test/c_libc_test.sh
	sh test/c_struct_test.sh
	sh test/c_global_test.sh
	sh test/c_selfhost_test.sh
	sh test/c_bios_test.sh
	sh test/c_libfile_test.sh
	sh test/c_dir_test.sh
	sh test/c_dir_recursive_test.sh
	sh test/c_dirglob_test.sh
	sh test/c_vi_relpath_test.sh
	sh test/c_redirect_test.sh
	sh test/c_stdin_test.sh
	sh test/c_cat_test.sh
	sh test/c_filters_test.sh
	sh test/c_fileops_test.sh
	sh test/c_pager_test.sh
	sh test/c_textutils_test.sh
	sh test/c_findiff_test.sh
	sh test/c_tree_test.sh
	sh test/c_disasm_test.sh
	sh test/c_pipe_test.sh

# Native assembler self-host: assemble its own source on-target == host build.
# Slow (37 KB through the emulated assembler twice); run on demand, not in `test`.
test-asm-selfhost: p8xemu ucode
	sh test/asm_selfhost_test.sh

# Native assembler assembles the FULL OS (p8xos.asm, ~872 symbols) on-target ==
# host build. Guards the symbol-table capacity (the `make os` self-host path).
# Slow (assembles the OS under emulation); run on demand, not in `test`.
test-asm-os: p8xemu ucode
	sh test/os_asmos_test.sh

# Build the heaviest /bin command (vi) through BOTH native toolchains on-target ==
# host: the asm twin via `asm`, the C command via `cc`+`asm`. Command-Makefile
# analog of test-asm-os. Slow (two native builds under emulation); on demand.
test-cmdbuild: p8xemu ucode
	sh test/os_cmdbuild_test.sh

# Full system build: build the whole ready-to-boot system the way run.sh does
# (OS + every /bin + /bina + /src + /man + /lib + dual-CF), boot it headless, and
# smoke-test boot / PATH / pipes / `make` rebuild / the /d1 mount. Slow; on demand.
test-sysbuild: p8xemu ucode
	sh test/os_sysbuild_test.sh

# The FULL system test: (1) `make test` assembles/compiles every source + runs the
# whole emulator suite; (2) the native-assembler self-host; (3) the full system
# build + headless boot + an on-emulator `make` rebuild. A COMPLETE on-emulator
# rebuild of all 42 commands is `cd /src/commands/c && make all` (and the asm dir)
# on the target itself (minutes of emulated time); os_sysbuild rebuilds one command
# as CI-tractable proof.
test-full: p8xemu ucode
	$(MAKE) test
	$(MAKE) test-asm-selfhost
	$(MAKE) test-asm-os
	$(MAKE) test-cmdbuild
	$(MAKE) test-sysbuild

# Per-instruction self-checking regression: halts with A=00 on success,
# or A=<test id> at the first failing check.
test-isa: p8xemu ucode
	cd test && cp ../$(UC)/u?.bin . && \
	python3 ../../assembler/p8xasm.py test_isa.asm -o tisa.bin && \
	../p8xemu tisa.bin 2>tisa.out; \
	grep -q ' A=00 ' tisa.out && echo "ISA TEST: PASS" || \
	  { echo "ISA TEST: FAIL —"; tail -1 tisa.out; exit 1; }
	sh test/isa_wordops_test.sh
	sh test/asm_include_test.sh

# Filesystem round-trip: monitor F (format) + B (boot) against the CF model.
test-cf: p8xemu ucode
	sh test/cf_test.sh
	sh test/cf_hilba_test.sh
	sh test/cf2_test.sh
	sh test/fs_bios_test.sh
	sh test/fdelete_test.sh
	sh test/fdelete_hilba_test.sh
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
	sh test/os_bigdir_test.sh
	sh test/os_bigpack_test.sh
	sh test/os_append_test.sh
	sh test/os_bigfile_test.sh
	sh test/os_format_test.sh
	sh test/os_argv_test.sh
	sh test/os_path_test.sh
	sh test/os_pathcmd_test.sh
	sh test/os_cdnorm_test.sh
	sh test/os_lineedit_test.sh
	sh test/os_edit_test.sh
	sh test/os_asm_test.sh
	sh test/os_asm_use_test.sh
	sh test/os_asm_inc_test.sh
	sh test/os_sh_test.sh
	sh test/os_hist_test.sh
	sh test/os_complete_test.sh
	sh test/os_examine_test.sh
	sh test/os_awk_test.sh
	sh test/os_cmp_test.sh
	sh test/os_mk_test.sh
	sh test/os_bootload_test.sh
	sh test/os_dualvol_test.sh
	sh test/os_cprecursive_test.sh
	sh test/os_mountcmd_test.sh
	sh test/os_vi_test.sh
	sh test/os_man_test.sh
	sh test/os_depdump_test.sh
	sh test/os_cc_test.sh
	sh test/os_cc_bigcmd_test.sh
	sh test/os_mount_test.sh

# Monitor smoke test (D/?, no card), plus disk BASIC (boot via B) and SAVE/LOAD.
# (ROM BASIC was removed — BASIC now ships as the disk program /BIN/BASIC.BIN.)
test-basic: p8xemu ucode
	sh test/mon_test.sh
	sh test/basic_disk_test.sh
	sh test/basic_syntax_test.sh
	sh test/basic_step_test.sh
	sh test/basic_string_test.sh
	sh test/basic_fileio_test.sh
	sh test/basic_strval_test.sh
	sh test/basic_savepath_test.sh
	sh test/basic_gfx_test.sh
	sh test/basic_cwd_test.sh
	sh test/basic_saveload_test.sh
	sh test/os_basic_test.sh
	sh test/basic_gl_test.sh

# I/O card model: switch input (-s) -> $FF00 and LED writes ($FF02, -L).
test-io: p8xemu ucode
	sh test/io_test.sh

# Graphics: everything through the GL port ($FF50) since the device door
# closed -- the C library, the image twins, the GL language suites, and
# the demo fleet (size-vs-CSTACKTOP + frame smoke).
test-gfx: p8xemu ucode
	sh test/c_g3d_test.sh
	sh test/c_demo_test.sh
	sh test/c_paint_test.sh
	sh test/c_desk_test.sh
	sh test/wm_reside_test.sh
	sh test/wm_kernel_test.sh
	sh test/wm_events_test.sh
	sh test/wm_mouse_test.sh
	sh test/wm_launch_test.sh
	sh test/c_image_test.sh
	sh test/c_gl_test.sh
	sh test/c_gl_mat_test.sh
	sh test/c_gl_list_test.sh
	sh test/c_gl_ascii_test.sh
# (c_gl_rtl_test.sh — the emulator-vs-RTL frame compare — needs iverilog;
#  run it by hand or from the fpga flow, not from make test.)

# rev E memory map: $2000-$FEFF is RAM (OS at $2000). Write+readback -> 'Y'.
test-mem: p8xemu ucode
	cd test && cp ../$(UC)/u?.bin . && \
	python3 ../../assembler/p8xasm.py test_ram48.asm -o tmem.bin && \
	../p8xemu -l 200000 tmem.bin 2>/dev/null | tr -d '\0' | grep -q Y && \
	  echo "MEM48 TEST: PASS" || { echo "MEM48 TEST: FAIL"; exit 1; }

.PHONY: all ucode rom test test-isa test-cf test-os test-basic test-io test-mem test-c test-asm-selfhost test-asm-os test-cmdbuild test-sysbuild test-full
