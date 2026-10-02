---
name: reference-yacc1-compiler
description: "YACC1 ISA/toolchain facts the y1cc C compiler depends on: BRVR is indirect, R2 is the hardware IR, carry rules, assembler quirks (case fold, 29-char labels, no negatives, DS flush), emulator -x mode"
metadata:
  type: reference
---

Hardware/toolchain facts established 2026-09-22 while building `software/compiler/y1cc.py` (YACC1-D):
- **BRVR Rn = indirect jump**: microcode reads [Rn],[Rn+1] into the branch register, Rn += 2, PC <- it
  (docs/isa/steps.txt). The monitor's `G AAAA` is `BRVR R7`, so it jumps THROUGH the word at AAAA and pushes no
  return address. The monitor's G was therefore broken on the hardware (never ran the code AT the address). FIXED IN THE TREE
  2026-09-22: monitor.asm G = `JSRUR R7 + BR cmdloop`; firmware/rom/shipped/rom = the rebuild TO BURN (chip still
  = 2021 build, captured file). y1cc default: main first, RET returns to the prompt; `--vector` = old-chip layout
  (DW start / JSR f_main / BR $F000). Emulator BRVR/JSRUR were wrong and are patched to match the microcode.
  BRUR Rn IMPLEMENTED 2026-09-22 at $AD (2 bytes, register in operand byte like JSRUR): generator branch.c, opcodes.h,
  yacc1.def, emulator, test.hex regenerated (only record $AD changed). Emulator-proven (tests/assembler/brur ABC0123);
  sequencer EEPROM reloaded 2026-09-22 evening (tools/ucode_send.py); bench check of BRUR on the machine pending.
- **R2 is the hidden operand-address register** on the hardware for LDA/STA/LDT/STT/LDR/STR (emulator uses a 9th
  register): never keep a value in R2 across those. Compiler never touches R2.
- **Carry**: hardware loads the carry FF on SUB and on every shift; emulator does not. Only rely on carry inside
  ADDT/ADDTC (ADDI/ADDIC) pairs with register moves between (monitor do_add16 idiom) and CSHL/CSHR after `LDAI 0 / CSHL`.
- **Words are big-endian** (LDR/STR/DW/MVIW: high byte first). MOVRR src,dst.
- **No microcode**: LDTVR/STTVR/OUTVR/BR16Z/BR16NZ/BRNC (emulator runs LDTVR/STTVR anyway).
- **RC/asm quirks**: source lines upper-cased (labels case-insensitive, `DB "text"` shouted -> emit numbers), labels
  max 29 chars (30+ crashes), `-1` silently assembles as 01, `(label+4).0/.1` byte selectors work (`label+4.0` no),
  `\B` operand > 255 errors, `DS` now flushes the hex record (was a real bug: bytes after DS landed at the wrong address).
- **Emulator**: `-x` = scripted (quiet, HALT exits, `HALT at aaaa after N instructions, R3=xxxx` on stderr); console =
  port 2 (`OUTA P2` prints, `OUTI P2` does NOT; `INP P2` reads stdin, 0 at EOF, and a literal 'q' ends input);
  BRDEV never branches on the emulator, always on hardware (runtime selects BIOS path with it).
- Monitor command syntax on the emulator: single command char, `G3000` (no space: getaddress reads the next 4 chars).
- **RAM map to respect**: $0100-$02FF BASIC vars, $0C00-$0EFF stack, $0F00-$0FFF monitor vars, $1000-$1FFF BASIC token
  buffer (cleared at every monitor boot/restart!), $2000.. monitor T-test scratch. y1cc default ORG = $3000.
- y1cc `switch` (2026-09-22): compare chain vs BRUR jump table by size; `--no-brur` flag for the machine until the
  microcode EEPROM is reloaded; per-test flags in tests/compiler via `// y1cc: ...`.
- Size vs P8X (bench/sizecmp.sh, 2026-09-22): same C source -> YACC1 binary 15-27% SMALLER than p8cc's (fixed-address
  LDR/STR/MVIW 3 bytes vs P8X frame/memory-word ops), but ~10x the clock cycles. Literals > 65535 = compile error.

**2026-09-24 plan (Ken):** a C-based C compiler, Mac first, native eventually. Ken chose to TEACH y1cc RECURSION (only functions in a recursive cycle change; everything else must stay byte-identical) over a recursion-free compiler. Then software/compiler/c/y1cc.c = C twin, byte-identical asm to y1cc.py over the whole corpus, written in the y1cc subset (no #ifdef/long/function pointers; host I/O behind a small interface file) so it can self-compile later; native path = multi-pass split (won't fit 32K TPA) + on-target assembler (wave 3). Keep y1cc.py as reference/bootstrap.
**DONE 2026-09-24:** recursion b35398f (callee frame save/restore around in-cycle calls; rules: main not recursive, no &local into a re-entering call); C twin bbc56c4 software/compiler/c/y1cc.c 3,122 lines, 117/121 identical + 4 same errors, y1cc16 16-bit check build, twinfuzz 1,400 programs; self-compiled image 82,345 B = 2.5x the 32K TPA (codegen 56K) -> needs pass split; assembler label table 1,000 max (y1cc.c has 3,817, it CRASHES); 768-byte stack too small for native.
**2026-09-24:** pass split DONE (bf56baa/b99426b): cc1..cc9 + y1ccp, chain byte-identical to y1cc.py, every pass fits 32K (cc9 244 B free, cc7 546); open: per-pass stack (--stack vs OS), Y1/OS >64K files, include depth, exit, exec chaining. Assembler label table 8,191 + whitespace-hang fix (449be7e). ISA extension under way (Ken approved): LDZ/STZ variable page, SHL16, ADDIW behind opt-in --xisa until EEPROM reload + machine bench; measured passes 119,083 code bytes, LDR/STR = 34%.
XISA DONE on emulators (a43330f/6f9367d/c250183): $80+n LDZ, $88+n STZ (R6.hi page), $C0+n ADDIW, $C8+n SHL16; opt-in --xisa; passes -17.7%, /BIN -12.9%. PENDING Ken at machine: ucode_send.py --all + bench (isa + xisa), then make --xisa default.
2026-09-25: native asm DONE (os/commands/asm.c, 61541ca..55963a6): 283/297 byte-identical to host asm, runs on both emulators, 32,299 B, ~1,360 symbols; host asm crashes on >=100 chars after label (quirk 12). Native-C stage under way: y1cc --stack ADDR (Ken's pick via recommendation), Y1/OS 32-bit file positions, SYSTAB enlarge (22 full), exit + EXEC chaining, then compile natively on the emulators.
**2026-09-25 NATIVE C WORKS on both emulators** (698c4bd..b4d0845): /BIN/CC chains /LIB/CC/CC1..CC9 via EXEC, /BIN/ASM assembles, 27/27 byte-identical to host incl. pass 4 compiling itself. --stack ADDR (passes 0xCFFF), 24-bit file positions, SYSTAB2 32 entries at $4FC0 (old $0F14 copy of 0..21), EXIT/EXEC/SEEK syscalls. Passes + C OS REQUIRE --xisa (else 3 passes over 32K) -> machine needs xisa EEPROM reload. Speed ~32 clocks/instr: hello 3.7 min, cat.c ~1 h at 1 MHz; cc9+lexer byte-at-a-time syscalls = 60% -> sector I/O next. y1cc bug: block comment starting on a #define line spanning lines not skipped.
**2026-09-25 SELF-HOSTS** (d9098ef): under Y1/OS on the emulators the 9 passes + asm + cc rebuild themselves byte-identical to the host builds, then again with the native builds = fixed point; tests/native/selfhost.py (make selfhost, in make check, ~30 s). One full native rebuild = 2.37G instructions, measured 22 h at 1 MHz on the microcode emulator; stage writes ~4.7 MB of disk (needs a real CF card, not 1 MB). Nothing needed fixing.
2026-09-26: /BIN/ASM = hand-written os/commands-asm/asm.asm (b61e44a/e405b70/9536749): 9,239 B, ~1,660 labels, ~5x fewer instructions than asm.c (now /BIN/ASMC, still the spec - keep both in step; tests/asm checks agreement); uses ADDIW/SHL16 (needs xisa microcode). Native compile 27 programs 6h11->4h39; self-host stage ~15h52 at 1 MHz. READN 'stale data' = the asm READN variant's own misuse (kept GL_SKIP after SEEK); REAL bug found+fixed 771a856: y1os.asm fs_getc boundary compare missing ANDI 0F0H (since 6a42b9f) -> stale sector when a file is longer in sectors than its start LBA; C kernel was right; never hit by tests (os/disk.img files start >LBA 1100); tests/os rdn + rdnlow (FRESH volume).
