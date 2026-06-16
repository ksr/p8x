# P8X — 8-bit TTL homebrew CPU

Hand-built 8-bit CPU, ~75 chips of 74HCT logic, microcoded, on a 10-slot
DIN41612 backplane. Six cards: control/microcode, register bank, ALU,
memory, I/O, CF-IDE.

## Architecture quick reference
- 8-bit data, 16-bit address. Address bus is ALWAYS driven by one of four
  16-bit pointer registers (74169 counters): P0=PC, P1/P2=general, P3=SP
  (empty-descending; push = write-then-decrement).
- Registers A, B (ALU operands), hidden temps T/T2, FLAGS (C,Z,N,V).
- Bus discipline: 4-bit encoded DOE (data output enable) and DLD (data
  load) fields, decoded per card. DOE: 0 idle, 1 A, 2 B, 3 T, 4 T2,
  5 ALU, 6 FLAGS, 7 MEM, 8 PTRL, 9 PTRH. DLD: 1-5 A/B/T/T2/FLAGS-restore,
  6 IR, 7 MEMW, 8/9 PTRL/PTRH.
- Memory map: $0000-7FFF EEPROM, $8000-FEFF RAM, $FF00-FFFF I/O
  (switches $FF00, LEDs $FF02, ACIA $FF04/05, CF-IDE $FF10-17).
- Microcode: ROM address = IR | step<<8 | cond<<12. Step 0 of every opcode
  is the fetch cycle. The FCOND field of the executing word selects the
  flag driving A12 for the NEXT lookup (pipeline timing).

## Hard rules
1. **Generators are canon.** Never hand-edit Eagle .sch/.brd files or ROM
   binaries — they are build artifacts of generators/ and
   firmware/microcode/genucode.py. Edit the generator, regenerate.
2. **The emulator interprets the same ROM images burned to the EPROMs**
   (firmware/microcode/u0-u3.bin). Never give the emulator private opcode
   knowledge; all instruction semantics live in the microcode.
3. **The assembler (when built) must share genucode.py's opcode table** —
   one source of truth for mnemonics/encodings.
4. Active-low signals use a leading dash: -RES, -RD, -MEMW.
5. **C flag quirk (deliberate, matches hardware):** the flag register
   latches the RAW 74181 Cn+4 pin, which is active-LOW carry
   (C=1 means NO carry out). Do not "fix" this in the emulator; it is a
   VERIFY item in BACKLOG.md (invert in rev B vs adopt as convention).
6. V flag is hardwired 0 in rev A (matches the ALU card).
7. Check BACKLOG.md before and after working; keep it current
   (NEXT / IDEAS / VERIFY / DONE sections).

## Build & test
- `cd emulator && make`         — build the emulator
- `make ucode`                  — regenerate u0-u3.bin (UC var = microcode dir)
- `make test`                   — assemble the smoke test and run it
  (expects "P8X lives! same ucode as the EPROMs" then HALT)
- After ANY microcode change: regenerate images and re-run both tests
  (message print; JSR/RTS round trip in emulator/test/).

## Layout
- hardware/<board>/ — everything for one board in one place: generated CAD
  (.sch/.brd, artifacts; see rule 1) + schematic PDF + README + design docs.
  One dir per board: backplane, memory-card, control-card, regbank-card,
  alu-card, io-card, cf-card
- docs/         — cross-cutting docs only: p8x-system-design.md,
  p8x-card-standards.md, p8x-programmers-guide.pdf
- generators/   — Python generators for CAD + schematic PDF renderers (run from hardware/)
- microcode/    — genucode.py + u0-u3.bin images + gen_progguide.py
- assembler/    — p8xasm.py (two-pass assembler)
- firmware/     — p8xmon.asm (ROM monitor source)
- basic/        — p8xbasic.asm (BASIC interpreter; skeleton REPL so far)
- emulator/     — p8xemu.c, Makefile, test/
  (p8xasm.py and gen_progguide.py locate genucode.py automatically; the
   emulator Makefile's UC variable points at the microcode directory)

## Near-term roadmap (see BACKLOG.md)
1. Assembler sharing the opcode table; assemble p8xmon.asm; boot the
   monitor in the emulator (needs more opcodes in microcode: JMP (P1),
   JSR abs, compare/branch variants the monitor uses).
2. CF-IDE emulation against a P8XFS disk image file.
3. Decoupling-cap generator pass + datasheet pinout verification before fab.
