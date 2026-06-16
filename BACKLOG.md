# P8X Project Backlog

Add ideas as they come; move items between sections as they progress.
Last updated: 2026-06-11

## How to use
- **NEXT** — committed, in rough priority order
- **IDEAS** — captured, not yet committed
- **VERIFY** — open questions / checks before trusting something
- **DONE** — kept for the project log

---

## NEXT

- **Monitor port (rev B ISA expansion — IN PROGRESS)**: the monitor assumes a
  conventional accumulator ISA. Reconciling it is being done by expanding the
  ISA (option 1). Done so far (software/emulator, Phase 1):
    - microcode word widened to 3-bit PSEL + PT hidden scratch pointer (PSEL=4)
    - absolute addressing via PT: LDA/LDB/STA/JSR `a`
    - loads set Z/N (LDZN control bit, bit 27)
    - new opcodes: LDA (Pn) non-inc, INP1-3/DEP1-3, TAP/TPA n L/H, PHA/PLA,
      JZ/JNZ (aliases of BZ/BNZ)
  Remaining (gated on the carry-polarity decision):
    - CLC/SEC, JC/JNC, carry-coupled shifter (SHL captures bit7->C, ROL shifts
      C in) — all depend on whether we adopt conventional active-high carry
      (rev B) vs the deliberate rev-A active-low Cn+4 quirk
    - then assemble p8xmon.asm and boot it in the emulator over the ACIA
- **Monitor port — Phase 2 (hardware, after sim works)**: realize the rev B
  microcode-word changes in the CAD generators —
    - control card: pipeline-latch remap for the new PSEL2 bit + LDZN
    - reg-bank card: add the 5th (PT) pointer + widen PSEL decode (74139->74138)
    - backplane: route PSEL2 on a SPARE line; update bus-definition
    - ALU card: carry-coupled shifter path (C flag <-> shifter shift in/out)
  regenerate all CAD + PDFs; the microcode word format currently leads the
  hardware design.
- **Emulator: CF-IDE model** ($FF10-17, sector buffer against a P8XFS disk
  image file) so the OS/filesystem work can run emulated end to end.

- **Decoupling caps**: no card netlist includes per-IC 100nF decoupling yet
  (standards sec.5 requires them). Add a generator pass that drops one cap per
  IC into every card's netlist + board before any fab order.
- **Datasheet pinout verification**: ~25 device definitions were added to the
  generator for the five new cards (74161/169/374/377/151/74/02/10/139/157/
  175/244/257/260/181/182, 28C64, 6850, MAX232, osc cans, IDE40, arrays).
  Pin numbers came from memory; verify every one against datasheets before fab.

- [ ] Fusion import acceptance test: open backplane .sch/.brd pair, pour planes,
      run DRC, confirm zero airwires
- [ ] Verify DIN 41612 footprints against physical connectors in stock
      (row A/C orientation when mated, mounting holes, press-fit vs solder)
- [ ] Add mounting holes to backplane board (6× M3, clear of planes or
      stitched to GND)
- [ ] Add DIN connector mounting/flange holes at every backplane slot per
      connector datasheet (mechanical retention against card insertion force)
- [ ] Route memory card signals in Fusion (planes already done)
- [ ] Generate remaining five card schematics/boards from the generator:
      register bank, ALU, control/microcode, I/O, CF-IDE
- [ ] Order backplane PCB first as the cheap validation article

## IDEAS

- [ ] Assembler for P8X syntax (Python, shares opcode table with microcode
      generator — single source of truth for the ISA)
- [ ] Microcode generator → EPROM images (same shared table)
- [ ] Mac-side p8xfs tool (put/get/ls/mkdir/tree/fsck via USB CF reader)
- [ ] **C-based P8X CPU emulator** — cycle-accurate against the microcode
      (ideally interprets the same EPROM images the hardware will burn, so
      microcode bugs surface in software first); memory map, ACIA-to-stdio,
      CF image file backing; test bed for monitor/OS/BASIC before hardware
- [ ] Tiny BASIC port (after Forth? Forth kernel is smaller and self-hosting)
- [ ] Forth kernel — pointer bank makes NEXT 4 cycles; arguably the native
      language of this machine
- [ ] FAT16 read-only support in P8X/OS (v3; Mac-side tool covers interchange
      until then)
- [ ] RESIZE for growable directories (P8XFS v3)
- [ ] FAT-style cluster allocation to eliminate PACK (P8XFS v3, entry format
      already compatible)
- [ ] DS1302 RTC on I/O card → file timestamps
- [ ] Interrupt support: latch IRQ, force opcode $FF at fetch, microcode pushes
      PC + vectors (one 74244 forcing the bus)
- [ ] Second ALU-input mux so ALU B-side can take X/T → cleaner indexed math
- [ ] p8x.pretty KiCad footprint lib if ever returning to KiCad round-trip
- [ ] Front-panel bus-monitor LED card (passive, address + data, great demo)
- [ ] Faster clock experiments once stable: 74F/74AHCT in critical paths,
      measure where it breaks

## VERIFY

- **C flag polarity**: the flag register latches the RAW 74181 Cn+4 pin,
  which is active-LOW carry (1 = no carry). Emulator matches hardware.
  Decide: add an inverter on the ALU card (rev B) or adopt the convention
  in the assembler/monitor (6502-style borrow flavour).

- Control card single-step circuit (7474 one-pulse + self-clear NAND): verify
  one-clock-per-press behaviour at bring-up; refine debounce RC if needed.
- ALU card V flag is unimplemented in rev A (FV driven low). Rev B: derive
  V from carry-into vs carry-out-of bit 7 (one 7486 XOR).
- I/O card SEL LED is source-driven from a gate output (deviation from the
  sink-drive standard) - noted on schematic; confirm brightness acceptable.

- [ ] Two new opcodes required by monitor: JMP (P1), JSR (P1) — fold into the
      official ISA table when the assembler exists
- [ ] CF card 8-bit mode support — buy 2–3 candidates (SanDisk/industrial),
      test SET FEATURES $EF/$01 early; latch fallback adds 2 chips if needed
- [ ] Clock-channel verticals on backplane: ~0.6 mm clearance to slot-10 pad
      columns — confirm against house DRC rules
- [ ] Backplane CLK at far slot on scope after bring-up → decide whether to
      populate RC terminators (RT1/CT1, RT2/CT2 shipped DNP)
- [ ] Backplane PWR LED: already in design (RL1 + LED1, currently bottom-left)
      — confirm placement or move top-right to match card standard §9
- [ ] EEPROM write protection: decide if WE̅ to 28C256 should be jumpered off
      after monitor is stable (protects ROM from runaway code)
- [ ] PSU sizing: ~75 LS/HCT chips, measure actual draw at bring-up vs 4–5 A
      budget

## DONE

- **Assembler (p8xasm.py)**: two-pass, imports the opcode table from
  genucode.py (single source of truth). Labels, expressions with <lo/>hi,
  .org/.byte/.word/.ascii(z)/.fill/equates, LDPn #imm16 pseudo-op,
  listing output. mktest.py retired; tests are now .asm files
  (message print / JSR-RTS / CMP-BZ countdown), all passing via make test.

- **Emulator v1 + microcode toolchain**: genucode.py emits the four 28C64
  images; p8xemu.c interprets the same images cycle-by-cycle (74181
  active-high tables, shifter stages, pipeline FCOND timing, ACIA on
  stdin/stdout). 35 opcodes defined. Verified: message print via ACIA
  (580 cycles) and JSR (P1)/RTS push-pop round trip (30 cycles).

- Bus rev C2: SPARE0-3 reallocated as flag lines FC/FZ/FN/FV (A27-A30,
  ALU card to control card). SPARE8-11 opened on B27-B30 (guard now B3-B26);
  eight official spares total (4-11). Backplane routes the B-row spares.
- Eagle sch+brd generated and validated for all five remaining cards
  (control, register bank, ALU, I/O, CF-IDE) + netlist-style PDF each.

- [x] Architecture: P8X — 8-bit, microcoded, 4×16-bit pointer bank (74169s),
      PC/SP/MAR unified into pointers
- [x] Rev C bus pinout: 96-pin DIN, 6×+5V top / 6×GND bottom, row B guard
- [x] Card set defined: control, register bank, ALU, memory, I/O, CF-IDE
- [x] Memory card schematic (Eagle + KiCad, rev C), placed board
- [x] 10-slot backplane: schematic + fully routed 4-layer board, 1" pitch,
      compact <250 mm variant
- [x] Termination analysis: AC termination provisioned on clocks only, DNP;
      Thevenin rejected (HCT mid-rail bias); data-bus pull-ups instead
- [x] ROM monitor written (p8xmon.asm): E/D/I/F/B/G commands
- [x] P8X/OS designed: BIOS jump table, boot-from-CF, shell
- [x] P8XFS v2 spec: hierarchical, directories-as-files, PACK algorithm
- [x] CF-IDE interface design: 8-bit mode, 5 chips, memory-mapped $FF10
- [x] Card design standards document (p8x-card-standards.md)
