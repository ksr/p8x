---
name: project-p8x
description: "p8x is the user's hand-built 8-bit TTL homebrew CPU project — key facts, conventions, and current work"
metadata: 
  node_type: memory
  type: project
  originSessionId: df90e3f3-8668-416d-bc7b-83f2952ba723
---

P8X is a hand-built 8-bit microcoded CPU using ~130 74HCT chips (per generators/gen_bom.py — the old "~75" estimate was low; the register bank alone is 44 ICs) on a 10-slot DIN41612 backplane. Project lives at ~/Documents/Projects/p8x.

**Why:** Personal homebrew CPU project, hardware is being fabricated.

**How to apply:** Always work from ~/Documents/Projects/p8x. Follow the hard rules in CLAUDE.md — generators are canon, never hand-edit Eagle files or ROM binaries. Check BACKLOG.md before/after work.

## Key architecture facts
- 8-bit data, 16-bit address; address bus driven by 4×16-bit pointer registers (P0=PC, P1/P2=general, P3=SP)
- Registers: A, B, T, T2, FLAGS (C, Z, N, V); plus PT, a hidden microcode-only 5th pointer (PSEL=4) for absolute addressing
- C flag: as of 2026-06-16 adopted CONVENTIONAL active-high carry (rev B): C=1 = carry-out / A>=B. (The old rev-A "raw active-low Cn+4, do NOT fix" quirk was deliberately replaced — user approved — to run the monitor.)
- Microcode word is now 32 bits with 3-bit PSEL; added LDZN (loads set Z/N), SHCIN (rotate), SETC/CLRC (CLC/SEC). Microcode word format now LEADS the hardware CAD (Phase 2 pending).
- V flag hardwired 0 in rev A. Memory map: $0000-7FFF EEPROM, $8000-FEFF RAM, $FF00-FFFF I/O

## Current NEXT items (as of 2026-06-16)
1. Monitor port: Phase 1 DONE — ISA expanded (PT/abs addressing, load-flags, PHA/PLA, INP/DEP, TAP/TPA, ROL/CLC/SEC/JC/JNC, conventional carry); p8xmon.asm assembles & boots in emulator. Phase 2 = realize rev-B microcode-word changes in CAD (control card PSEL2/LDZN, reg-bank 5th pointer, backplane PSEL2 line, ALU carry-coupled shifter).
2. Emulator: CF-IDE model ($FF10-17) against a P8XFS disk image
3. Decoupling caps generator pass
4. Datasheet pinout verification before fab
5. Various hardware/PCB checks (DIN footprints, mounting holes, routing)

## What's done
- Assembler (p8xasm.py): two-pass, shares opcode table with genucode.py
- Emulator v1 (p8xemu.c): interprets same ROM images as hardware, 35 opcodes, ACIA on stdin/stdout
- Microcode toolchain: genucode.py → u0-u3.bin
- Eagle schematics/boards generated for all 6 cards + backplane
