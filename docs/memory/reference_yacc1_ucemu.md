---
name: reference-yacc1-ucemu
description: "YACC1 microcode-level emulator (software/ucemu/y1ucemu, 2026-09-22): what it models, how to run it, what it found (H-1/H-2 real and fixed, compiler BSS bugs), RAM fills with $FF, BRDEV branches so console = UART model"
metadata:
  type: reference
---

`software/ucemu/y1ucemu` (YACC1-D) steps test.hex through a model of every card (like p8xemu). Run:
`y1ucemu -x -m -f prog.img` (monitor ROM + program), `-t`/`-T` traces, `-w` bus fights, `-F and|src` fight policy,
`-u other.hex`. `tests/ucemu/run.py` = compiler suite on it (14/14); `tests/ucemu/isa.asm` = differential test of every
instruction vs the interpreter (byte streams identical except BRDEV, which BRANCHES in microcode).
Lessons: RAM is filled with $FF (unprogrammed) -> found y1cc never zeroed globals and padded partial initialisers with
DS (fixed: main clears bss_start..bss_end; padding = real zeros). Stand-alone images MUST start with a BR to an
A15-high address (FORCE-ROM remap) - the compiler's --boot stub and brur.asm do. Port reads are sampled once per
-IO-RD assertion (a multi-step strobe would otherwise consume several input bytes).
Findings: H-2 (BRZ/BRNZ ALU drives bus during PC load -> taken BRZ lands on offset $00) and H-1 (PUSHR corrupts the
pushed word: $ABCD -> $21CC) reproduced and FIXED in branch.c; test.hex regenerated (14 records differ from the
sequencer EEPROM: BRUR + H-1 + H-2). EEPROM RELOADED 2026-09-22 (evening) with `tools/ucode_send.py --all`, card verified RAM == EEPROM == test.hex; bench checks (tests/assembler/brur ABC0123, tests/ucemu/isa.asm) still to run on the machine.
Not modelled: interrupts with a source, CF card, video. Under the microcode, the monitor boots from real reset.

2026-09-22 evening: y1ucemu also has -i 0|1 (input-switch line for BRINH/BRINL), -I N (flip it every N steps), -L (print LED/TIL311/ON-OFF writes), -R 1|2 (register cards fitted; -R 1 = R4..R7 absent, reads $FF). Bench lesson: the bring-up machine ran with ONE index card until 2026-09-22, so ROM test programs must use only R1/R3/TMP (never R2); the first romcount used R6/R7 and lit every LED. tests/assembler/romcount + romdiag (switch-paced instruction check) are the ROM-toolchain tests.
