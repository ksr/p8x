# P8X — 8-bit TTL homebrew CPU

Hand-built 8-bit CPU, ~130 chips of 74HCT logic, microcoded, on a 10-slot
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
- Memory map (rev E): $0000-1FFF ROM (8K), $2000-FEFF RAM (56K, 2x 62256),
  $FF00-FFFF I/O (switches $FF00, LEDs $FF02, ACIA $FF04/05, CF-IDE $FF10-17).
  The OS loads at $2000. P8XFS is v2-only (hierarchical).
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
   (NEXT / IDEAS / VERIFY / WONT-DO sections — live work only). Completed items
   move OUT to BACKLOG-DONE.md; don't let finished work pile up in BACKLOG.md.
   Read WONT-DO / SUPERSEDED before starting anything that looks obviously
   missing — several entries there are decisions NOT to do something, and one of
   them (signed compares in p8cc) shipped a buffer overflow when acted on.

8. **`emulator/test/` and `fpga/tang-nano-20k/sim/` are .gitignore ALLOW-LISTS**
   — everything is ignored, the hand-written sources are named. The tests write
   scratch files (images, .bin/.asm twins, traces) next to their sources, and a
   deny-list could not keep up: it reached ~200 lines and still leaked, letting
   generated .asm twins get tracked and go stale, which silently made the
   os_cmdbuild byte-compare check an out-of-date build.
   So: **adding a new hand-written test source needs a `!` line in .gitignore**
   (or a name matching the existing convention — `*.sh`, `test*.asm`). If `git
   add` appears to do nothing, that is why. Never "fix" it by deleting the
   `emulator/test/*` line; add the exception.

## Build & test
- `cd emulator && make`         — build the emulator
- `make ucode`                  — regenerate u0-u3.bin (UC var = microcode dir)
- `make test`                   — assemble the smoke test and run it
  (expects "P8X lives! same ucode as the EPROMs" then HALT)
- After ANY microcode change: regenerate images and re-run both tests
  (message print; JSR/RTS round trip in emulator/test/).

FPGA (needs `iverilog`; the board flow needs oss-cad-suite):
- `fpga/sim/run.sh 20000`                        — co-sim vs the emulator
- `fpga/sim/run.sh 60000 isa_test.asm`           — all 88 opcodes
- `fpga/sim/run.sh 200000 "" console_in.txt`     — driven monitor + console diff
- `fpga/sim/console.sh "" os/run-disk.img`       — interactive console on the RTL
- `fpga/tang-nano-20k/build.sh cpu load`         — build + program the board
- After ANY change to fpga/rtl/ or the microcode: re-run all three co-sims. The
  emulator is the golden model; a divergence names the exact microcycle.

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
- fpga/         — the standalone FPGA P8X (parallel track to the TTL build, not a
  replacement). fpga/rtl/ is the board-independent core (p8x_cpu.v, p8x_soc.v);
  fpga/sim/ is the co-simulation harness that diffs the RTL against the emulator
  cycle-for-cycle; fpga/tang-nano-20k/ is the Sipeed Tang Nano 20K board build
  (p8xasm.py and gen_progguide.py locate genucode.py automatically; the
   emulator Makefile's UC variable points at the microcode directory)

## Near-term roadmap (see BACKLOG.md)
(The original three items — assembler sharing the opcode table, CF-IDE emulation,
the decoupling-cap generator pass — are all long done; see BACKLOG-DONE.md.)
1. TTL build: the IRQ-controller card wiring, then hardware bring-up (Fusion DRC,
   footprint confirmation, order the backplane first).
2. FPGA build: Milestone 5 — clock up (currently 9 MHz against a ~50 MHz Fmax,
   three fabric phases per microcycle) and wire IRQ through.
3. OS: multi-stage pipes (`a | b | c`); a `path` command.
