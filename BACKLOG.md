# P8X Project Backlog

Add ideas as they come; move items between sections as they progress.
Last updated: 2026-06-19

## How to use
- **NEXT** — committed, in rough priority order
- **IDEAS** — captured, not yet committed
- **VERIFY** — open questions / checks before trusting something
- **DONE** — kept for the project log

---

## NEXT

- **P8XFS v2 — remaining loose ends** (the hierarchy itself is DONE; see DONE):
    - **on-target FORMAT** (optional): monitor F still writes v1; either teach it
      v2 or add an OS FORMAT so a card can be made bootable without the host.
      (Monitor B is unchanged — it only reads sig+OSCNT.)
    - **OS code size**: ~6.4 KB at $8000. The TPA was moved to $B000 and the OS
      var block relocated to $A000 (above the BIOS-pinned LBA $9D47 / SBUF
      $9E00), so code can now grow to ~$9D00 (~1.1 KB headroom) and vars have
      ~3.5 KB at $A000. To go beyond ~$9D00, code would need a second segment
      above SBUF ($A200+, below the $B000 TPA), since LBA/SBUF are fixed.
- **CFREAD ABI is 1-byte LBA**: the BIOS CFREAD/CFWRITE only set LBA0 (LBA1-3
  zeroed in the monitor's CFSETL), capping addressable sectors at 256. Fine for
  small images today; widen to a multi-byte LBA in CFSETL + the BIOS contract
  before volumes exceed 128 KB.


- [ ] Fusion import acceptance test: open backplane .sch/.brd pair, pour planes,
      run DRC, confirm zero airwires
- [ ] Verify DIN 41612 footprints against physical connectors in stock
      (row A/C orientation when mated, mounting holes, press-fit vs solder)
- [ ] Add mounting holes to backplane board (6× M3, clear of planes or
      stitched to GND)
- [ ] Add DIN connector mounting/flange holes at every backplane slot per
      connector datasheet (mechanical retention against card insertion force)
- [ ] Route memory card signals in Fusion (planes already done)
- [ ] Order backplane PCB first as the cheap validation article

## IDEAS

- [ ] **Optimize monitor/OS/BASIC hot paths with the rev-C T-operand ALU ops**
      (`LDT`/`ADDT`/`SUBT`/`CMPT`/etc.): these let you compute `A := A ⟨op⟩ T`
      without first shuffling the operand through B, so spots that currently do
      "save B, load operand into B, ALU, restore B" can collapse. Purely an
      optimization — the firmware is already correct as-is (the new ops are
      additive; existing code is byte-identical). **Do this only after the ALU
      card is built and the B-mux is verified in hardware** — code using the
      T-operand ops won't run on bare metal until the 74157 mux (U32/U33) is
      actually populated, so until then it would only work in the emulator.

- [ ] **Unix-like pipes in the OS shell** (`|`): output-to-file `>` redirection
      is DONE (see DONE — OUTCH sink + shell `>name` capture). The remaining,
      harder piece is `|`: with no multitasking, run sequentially — capture
      cmd1's output into the RBUF buffer (already built), then run cmd2 with its
      *input* sourced from that buffer. Needs a matching input indirection (an
      INCH the consumer reads) and, to be useful, filter commands that actually
      read a stream (MORE/WC/GREP-style) — none exist yet. RBUF is RAM-bound
      (~the TPA, $B000..). Scope: add INCH + one filter (e.g. MORE) -> `|`.
- [ ] **Man-page-style OS command reference in os/README.md.** The OS README
      currently has a one-line-per-command table. Expand it into per-command
      "man" entries — NAME / SYNOPSIS / DESCRIPTION / EXAMPLES, plus notes on
      paths, hex args, redirection, and error messages (`?EXISTS`, `?NO FILE`,
      `?NO DIR`, `FSCK: PROBLEMS=n`, etc.). Keep the quick table at the top as a
      summary and put the detailed entries below. Source of truth stays the
      on-target `HELP` text + the assembly; the README is the long-form companion.
      (Doc-only — no code change.)
- [ ] **Housekeeping (from 2026-06 consistency audit; not yet decided):**
    - Tracked generated binaries: `microcode/u0-u3.bin` are committed but
      regenerate byte-identically from genucode.py. Consider gitignoring them
      and letting `make` build them. (Lean keep — project frames them as the
      canonical EPROM images, burned *and* interpreted.) NB the `.hex` question
      is RESOLVED: the burnable Intel HEX now lives only in `rom/` (see DONE),
      and `microcode/u?.hex` were untracked + gitignored — `microcode/` holds
      just the `.bin` the emulator/tests load.
    - `busnet()` is duplicated in gen_eagle.py and gen_bus_pdf.py (kept in sync
      by hand; drift risk). De-dup is awkward because gen_bus_pdf is meant to be
      standalone — importing gen_eagle regenerates all boards as a side effect.
      A clean fix would guard gen_eagle's board-writing under `if __name__ ==
      "__main__"` so it's importable without side effects.
    - Smoke tests test1-3.asm overlap test_isa.asm (per-opcode). They give
      higher-level scenario coverage (banner, JSR/RTS, countdown); keep as
      complementary unless trimming.
- [ ] **C compiler (cross, then native)** — a big, long-horizon goal. Start
      with a **cross-compiler** on the host: a small-C subset (int/char/pointers,
      functions, if/while/for, basic expressions — no float, limited structs)
      emitting P8X assembly that feeds p8xasm.py. The 8-bit/16-bit-pointer ISA
      and the pointer bank shape the codegen (P0-P3 as frame/stack/scratch; a
      software call stack via P3). A **native** compiler on P8X/OS is the
      stretch goal once there's an on-target assembler + editor and enough RAM
      — likely an even smaller subset, possibly multi-pass through temp files.
      Depends on: a stable calling convention/ABI, the on-target assembler, and
      a C runtime (startup, multiply/divide/shift helpers, minimal libc over
      the BIOS). Sequence after Forth/assembler land; reference small-C / SubC
      style compilers for the subset and codegen approach.
- [ ] **On-target assembler** (a P8X/OS program or built-in) — makes the
      machine self-hosting for machine code: edit a `.asm` text file with EDIT,
      assemble it on-target to a runnable file, then RUN it. Two-pass like
      p8xasm.py (labels, the LDPn pseudo, .byte/.word/.org), reading source
      from a file and writing a binary file via the OS. The opcode table is the
      catch: it can't import genucode.py, so generate a compact on-target
      mnemonic->opcode table from the same ISA source (a genucode.py emitter)
      so the host and target assemblers can't drift. Scope: integer-only,
      modest program sizes; pairs with EDIT + RUN to close the write/assemble/
      run loop entirely on the P8X. (Host p8xasm.py stays the primary tool.)
- [ ] **Simple text editor** for editing text files: load a file into a RAM
      buffer, line-oriented edit (insert/delete/list/replace by line, like the
      BASIC editor), save back. Serial-console friendly (no cursor addressing);
      a screen/visual mode is a later stretch. Pairs naturally with RUN — write
      source, save, assemble off-target for now. Could share the line-buffer/
      rebuild approach already proven in p8xbasic.asm. Two ways to ship it:
        - **Built into the OS** as an EDIT command (preferred) — directly uses
          the resolved path + the existing LOAD/SAVE machinery and the OS's
          line buffer; no separate image to install. Watch the OS code size
          (OS ~6.4 KB; code can grow to ~$9D00 now that vars moved to $A000 — see
          the OS-code-size note in NEXT).
        - Or a standalone P8X/OS program (TPA at $B000) launched by RUN, using
          the BIOS vectors — keeps the kernel small but needs installing on
          each disk.
- [ ] **BASIC variable limits are tunable** — names are significant to 6 chars
      (`NAMLEN`) and capped at 32 variables (`NVARS`, 8-byte entries in the
      256-byte `VARTAB` at `$x100`). Both are constants in p8xbasic.asm; bump
      them if programs need longer names or more variables (grows the symbol
      table and may require nudging `VARTAB`/`PROG` placement). Also: names
      longer than 6 chars silently alias on their first 6 — could warn/error
      instead.
- [ ] **BASIC string-valued variables** (e.g. `A$ = "HELLO"`): add a string
      type alongside integers — string literals, `$`-suffixed variables,
      `PRINT`/`INPUT` of strings, and concatenation. Needs string storage
      (fixed per-variable buffers are simplest on this machine; a heap +
      compaction is the general but heavier route) and type tracking in the
      expression evaluator. Orthogonal to (and larger than) multi-character
      variable names — best layered on after those land.
- [ ] Tiny BASIC port (after Forth? Forth kernel is smaller and self-hosting)
- [ ] Forth kernel — pointer bank makes NEXT 4 cycles; arguably the native
      language of this machine
- [ ] FAT16 read-only support in P8X/OS (v3; Mac-side tool covers interchange
      until then)
- [ ] RESIZE for growable directories (P8XFS v3)
- [ ] FAT-style cluster allocation to eliminate PACK (P8XFS v3, entry format
      already compatible)
- [ ] DS1302 RTC on I/O card → file timestamps. Footprints provisioned (see
      DONE): DS1302 (U16) + 32.768kHz crystal (X3) + coin cell (BT1) + a 3-wire
      breakout header (J3), all DNP. Remaining: connect the 3-wire to a CPU port
      (reserved $FF08 / PORT DEC U2 Y3) — jumper J3 to spare port bits or add a
      small latch/buffer — write the bit-banged DS1302 driver, and VERIFY the
      crystal + coin-cell land patterns against the real parts (placeholder THT
      footprints used).
- [ ] Interrupt support — HARDWARE CONTROLLER WIRING (architecture done +
      footprints provisioned DNP, see DONE). The microcode/emulator/ISA side is
      implemented and tested (EI/DI/RTI, $08 IRQ entry, vector $0808, $FF06
      raises IRQ in the emulator). The control card now carries DNP footprints
      U20 (74244 forcing buffer) + U21 (7474 IE/pending FF) and B29 = IRQ is a
      reserved bus line; the safe connections are wired (buffer inputs = $08,
      outputs forced high-Z, IRQ -> FF). What remains is the BUS-CRITICAL wiring,
      to design with DRC/breadboard before populating:
        - connect U20 outputs (Y1-8) onto the data bus (currently unwired)
        - opcode decode for EI/DI/RTI (drives the IE FF) + a fetch/step-0 detector
        - service sequencer so the buffer enable (!G) asserts at the injected
          fetch AND during the two PTR-load steps (DOE=idle) -> P0=$0808, and is
          off otherwise (currently !G is tied high = permanently disabled)
        - SUPPRESS the memory read during the injected fetch (cross-card: gate
          the memory card's -RD/-OE with the IRQ-service signal) so the buffer
          isn't fighting the EEPROM on the bus
      RISK: it drives the shared data bus; a wiring error = bus contention = dead
      machine, and there's no DRC backstop in the generator. Recommend designing
      it deliberately (breadboard/DRC, or a small daughtercard). Monitor needs an
      ORG $0808 stub (JMP to a handler / RAM trampoline) once the hardware exists.
- [ ] p8x.pretty KiCad footprint lib if ever returning to KiCad round-trip
- [ ] Front-panel bus-monitor LED card (passive, address + data, great demo)
- [ ] Faster clock experiments once stable: 74F/74AHCT in critical paths,
      measure where it breaks

## VERIFY

- **Register bank: address bus floats for PSEL = 5, 6, 7** (2026-06 review). U33
  (74138) is always enabled and decodes only PSEL 0-4 (P0-P3 + PT); the address
  drivers U25/U26 are always on. For PSEL 5-7 no pointer drives the internal
  pointer bus, so an undefined value reaches A0-15. Safe ONLY if microcode never
  emits PSEL > 4 (PT = 4 is the max). Confirm the microcode constraint, or add a
  default-select / pull so the bus can't float.
- **System-wide data-bus arbitration is one-hot** (2026-06 review). Bus drivers
  are distributed: ALU U20 decodes DOE 1-6 (reg/ALU/flags); at DOE = 7 exactly one
  of memory/IO/CF should drive based on address decode. No check enforces "no
  DOE/address combination enables two drivers" across cards. In particular confirm
  the memory card is fully silent in the $FF00-$FFFF I/O page (via -IOPG) so it
  can't fight the I/O / CF cards on a read. (Backplane RN1 10k pull-ups hold the
  bus at $FF when nothing drives, so a no-driver case is defined.)
- Control card single-step circuit (7474 one-pulse + self-clear NAND): verify
  one-clock-per-press behaviour at bring-up; refine debounce RC if needed.
- I/O card SEL LED is source-driven from a gate output (deviation from the
  sink-drive standard) - noted on schematic; confirm brightness acceptable.

- [ ] Final pinout confirmation against *physical* datasheets before fab. A
      knowledge-based audit was done (see DONE) and fixed the 74260; still
      worth eyeballing the actual datasheets for the parts you'll buy — at
      minimum the 74260 (odd input/output split) and the wide DIPs (74181,
      28C64, 62256, 6850) — since manufacturer/variant pinouts can differ.
- [x] Opcodes the monitor needed: `JSR (P1)` is in the ISA (0x41) and the
      assembler exists. `JMP (P1)` turned out unnecessary — the monitor uses
      absolute JMP/JSR and never emits it (comment-only); not implemented.
- [ ] CF card 8-bit mode support — buy 2–3 candidates (SanDisk/industrial),
      test SET FEATURES $EF/$01 early. Fallback latch footprint provisioned DNP
      (see DONE): U9 (74374) with the CF high data byte D8-15 wired to its inputs,
      output high-Z and clock grounded. Only populate if a card refuses 8-bit
      mode; then wire the Q outputs onto D0-7 + a decoded read/latch-clock (design
      with DRC — it drives the data bus).
- [ ] Clock-channel verticals on backplane: ~0.6 mm clearance to slot-10 pad
      columns — confirm against house DRC rules
- [ ] Backplane CLK at far slot on scope after bring-up → decide whether to
      populate RC terminators (RT1/CT1, RT2/CT2 shipped DNP)
- [x] Backplane PWR LED: kept bottom-left, beside the +5V terminal block. Card
      standard §9 (PWR LED top-right) is *card*-specific; the backplane's
      top-right is occupied by the clock terminators (RT1/RT2/CT1/CT2/RN1), and
      placing the LED by the power entry is sensible. No move.
- [ ] PSU sizing — measure actual draw at bring-up vs the 4–5 A budget. ESTIMATE
      (~130 HCT chips + ~52 LEDs): HCT dynamic draw at a few MHz is a handful of
      mA/chip → ~1 A logic; LEDs (bus-monitor arrays via 330R + status LEDs via
      1K) ~0.3–0.4 A; memory/ACIA ~0.1 A ⇒ **~1.5 A typical, ~2 A worst case** —
      comfortable margin under 4–5 A. Confirm with a meter at bring-up.

## DONE

> Convention: substantial features get a **bold-title** prose entry (what was
> done + why + caveats). The original foundation milestones are a terse tick
> list under *Early milestones* at the end of this section.

- **C flag polarity — RESOLVED (rev B).** Chose conventional active-high carry
  (C=1 = carry / A≥B for SUB/CMP). The raw active-low 74181 Cn+4 is inverted by
  a spare U25 NAND on the ALU card before the C-flag mux, and the microcode,
  emulator, and monitor all use the conventional sense (BCP/JNC, CLC/SEC). The
  old "add an inverter or adopt a borrow convention" was a rev-A open question.

- **Monitor port (rev B ISA expansion) — DONE.** The monitor assumed a
  conventional accumulator ISA; reconciled by expanding the ISA. Phase 1
  (software/emulator): 3-bit PSEL + PT hidden scratch pointer; absolute
  addressing via PT (LDA/LDB/STA/JSR `a`); loads set Z/N (LDZN); LDA (Pn),
  INP/DEP, TAP/TPA, PHA/PLA, JZ/JNZ; CONVENTIONAL active-high carry (C=1 =
  carry / A>=B); CLC/SEC, JC/JNC, ROL/ROR + carry-coupled shifter; assembler
  char-literal tokenizer fix; firmware/p8xmon.asm converted to the p8xasm
  dialect — assembles and boots in the emulator (banner, `?`, `D` dump work).

- **Monitor port — Phase 2 (hardware) — DONE.** All rev-B microcode-word
  changes realized in the CAD generators: backplane bus allocation (rev C3);
  control-card pipeline-latch remap; reg-bank 3-bit PSEL decode + PT pointer;
  ALU flag-register redesign — C split onto a 7474 (U26) with SETC/CLRC async
  preset/clear; Z/N source-muxed on LDZN (U22) with a 74260 bus zero-detect
  (U27); carry-coupled shifter (U28/U29/U30); U31 gates the C and Z/N/V clocks.
  NB: pin/pad-validated only, not DRC'd; the rev-B *behaviour* is proven in the
  emulator (make test-isa). A full Eagle DRC + airwire check stays on VERIFY.

- **Connect IC power pins on the card()-built boards (schematic-review fix).**
  The 2026-06 review found that the generator's `card()` helper wired the
  connector and decoupling-cap pins to VCC/GND but never added each IC's own
  VCC/GND supply pin — so on control, regbank, ALU, I/O, and CF the chips' power
  pads weren't members of the power pours and wouldn't have been powered. (The
  hand-built memory card already did this; the backplane has no ICs.) `validate()`
  couldn't catch it — it checks pin-name legality, not connectivity. Fixed by a
  loop in `card()` that appends `(ref,"VCC")`/`(ref,"GND")` for every IC, skipping
  any pin already wired by hand (idempotent, so the few pre-existing ones don't
  duplicate). Regenerated all 7 boards (0 validation errors); a board-level audit
  confirms every IC on every card now has both VCC and GND on the power signals.

- **OS FSCK — read-only on-target consistency check.** Mirrors the host
  `p8xfs.py fsck`: verifies the `P8` boot signature, that every live extent
  starts in the data area and ends at/below the boot-block free pointer, and
  (v2) that every directory's `..` points at its true parent — via the same
  read-only tree walk `TREE`/`PACK` use (shared sector buffer + explicit RAM
  stack). Prints counts (dirs/files/deleted, free ptr, used sectors) and an
  `FSCK OK` / `FSCK: PROBLEMS=n` verdict; output is redirectable (`FSCK >LOG`).
  Read-only by design — no repair. Exhaustive cross-extent overlap and
  volume-end checks stay in the host tool (8-bit on-target LBAs and the single
  sector buffer make full overlap detection impractical on-target). On-target
  verdict matches the host on the same image; os_test (v1) and os_v2_test assert
  `FSCK OK` on a clean volume, and os_v2_test also corrupts the free pointer and
  asserts FSCK flags it. OS grew to ~$9BFD (still under the ~$9D00 ceiling).

- **I/O card in the emulator — switches + LEDs.** The emulator used to stub the
  I/O card ($FF00 always read 0; $FF02 writes went to an unseen var), so the
  switches/LEDs couldn't be exercised. Now `-s NN` sets the byte the switches
  present at $FF00 (so BASIC `PEEK(65280)` and monitor/OS reads see it), and
  `-L` traces every $FF02 LED write to stderr as it changes (`$NN  *.*..*.*`,
  `*` = lit); the final LED byte is also in the halt status line. New regression
  `make test-io` copies switches->LEDs and asserts both the value path and the
  trace. A runtime switch hotkey is still possible later (raw-mode stdin already
  feeds the ACIA, so it needs care) — the CLI flag covers the need for now.

- **Burnable images persist in rom/ + Intel HEX (build).** `genucode.py` and
  `tools/build_basic_rom.py` emit Intel HEX for an EEPROM programmer, and
  `tools/build_rom.sh` (`make rom`) builds the whole burn set into `rom/`:
  `p8x-ucode0..3.{bin,hex}` (the four 28C64 control-store EPROMs) and
  `p8x-prog-rom.{bin,hex}` (the 28C256 monitor + ROM BASIC). `rom/` is the single
  grab-and-burn folder and the sole home for the `.hex`; `microcode/` keeps the
  `u?.bin` the emulator/tests load. Round-trip verified for every image.

- **Reject duplicate names + errors bypass redirection (OS).** Two filesystem
  polish fixes: (1) **no duplicate names** — SAVE and `>FILE` redirection now
  run a `FINDENT` check on the parent directory before creating, and fail with
  `?EXISTS` if the leaf name is already present (MKDIR already did this). In
  SAVE the check is placed *before* the length calc because FINDENT clobbers
  `LENLO/HI` (and P2, which is saved/restored). (2) **errors go to the console,
  not the file** — the 12 OS error messages (`?...`) now print via the BIOS
  `PUTS` (always console) instead of the redirectable `OPUTS` sink, so e.g.
  `CAT missing >F` leaves the error on screen; and an empty capture creates no
  file at all (was a degenerate 0-length entry that failed fsck). os_test
  covers both. All 6 suites pass.

- **OS output redirection to a file (`cmd >FILE`).** All command output now
  flows through an OS sink (`OUTCH`, plus `OPUTS`/`OPHEX8` replacing the BIOS
  `PUTS`/`PHEX8` that called ROM `CONOUT` directly — 46 call sites rerouted).
  The shell (`REDSCAN`) splits a trailing `>name` off the command line, arms
  capture (`REDIRF`, buffer at the TPA `$B000`), runs the command with its
  output captured, then at the next prompt (`FLUSHRED`) writes the buffer to a
  new file via `SAVECORE`. So `DIR >L`, `CAT a >b`, `TREE >t`, etc. all work and
  the file has the exact captured length. Test: os_test does `DIR >DLIST` and
  verifies (host-side) DLIST holds the listing. Pipes (`|`) remain — see NEXT.

- **Monitor D paging + OS EXIT-to-monitor.** Two software-only quality-of-life
  items: (1) the monitor `D` (dump) command now pages — after each 256-byte
  block it waits for a key, CR/Enter dumps the next block (P1 keeps walking
  forward), `.` returns to the prompt (mirrors the `E` command's convention).
  (2) The OS shell gained `EXIT`/`MON`, which cold-restarts into the ROM monitor
  via `JMP $0000`, mirroring BASIC's `BYE` — so the monitor can now launch the
  OS (`B`), launch ROM BASIC (`X`), and both can get back. Tested: BASIC-ROM
  test exercises D paging (rows 00F0 then 0100); OS test confirms the monitor
  banner reappears after EXIT. The OS `DUMP` command pages the same way (CR=next
  block, `.`=exit; DODUMP — separate code from CMD_D); OS test pages to row B100.

- **RTC + CF-fallback footprints provisioned (rev C, DNP).** The last two
  pre-fab board items, both as Do-Not-Populate so the options exist post-fab
  without a respin:
  - I/O card: DS1302 RTC (U16) + 32.768kHz crystal (X3) + backup coin cell (BT1)
    + a 3-wire breakout header (J3). Fully isolated peripheral — crystal across
    X1/X2, VCC1 from +5, VCC2 from the cell, CE/SCLK/IO to J3. No bus contention
    possible. Reserved I/O address $FF08 (PORT DEC U2 Y3). VERIFY the crystal +
    coin-cell land patterns against real parts before fab (placeholder THT pkgs).
  - CF card: 8-bit-mode fallback latch (U9, 74374). The CF high data byte
    (D8-15) is wired to its inputs; output forced high-Z and clock grounded, so
    it's inert. Populate + wire the bus output + decode only if a CF card refuses
    8-bit mode (see NEXT). New device defs: DS1302/XTAL32/COIN + a DIP8 package.
    All 7 boards regenerate with 0 validation errors.

- **Interrupt ARCHITECTURE (rev C) — microcode/emulator/ISA (hardware pending).**
  Implemented and tested the whole interrupt model end to end in emulation;
  only the physical control-card circuit remains (see NEXT, and the risk note
  there). Design: a maskable IRQ with an interrupt-enable latch (IE), reset off.
  - Instructions: `EI`/`DI` (set/clear IE), `RTI` (pop flags+PC, re-enable IE),
    and `IRQ`/$08 (push PC+flags, vector to $0808) — $08 is also the opcode the
    hardware forcing buffer injects on a real IRQ, so it doubles as a software
    interrupt.
  - Vector: fixed ROM $0808. The forcing buffer's hardwired byte ($08) is BOTH
    the injected opcode AND both vector bytes — high $08, low $08 -> $0808 — so
    one pattern, one buffer, no separate zero-source. $0808 is just past the
    monitor code.
  - PC handling: the injected fetch still does P0++, so the $08 micro-routine
    starts with DEP0 to recover the true return address before pushing it.
  - Emulator: IE + irq_pending state; writing $FF06 raises an IRQ (models a
    device); injection at fetch when IE & pending (acknowledged: pending clear,
    IE masked); forcing buffer drives $08 while $08 runs with DOE=idle.
  - Test: ISA case 40 enables interrupts, raises one, confirms the $0808 handler
    ran and the preempted instruction completed after RTI. All 6 suites pass.

- **V flag + signed comparison (rev C).** Implemented the overflow flag and
  signed-compare branches end to end. NOTE: the old "one 7486 from carry-into
  vs carry-out-of bit 7" plan was **not feasible** — a 74181 handles a 4-bit
  group and doesn't expose carry-into-bit-7. Used the **sign-bit method**
  instead: `V = (A7 ^ F7) & (A7 ^ B7 ^ ~ALUS2)` (B7 = muxed B operand, F7 = raw
  ALU result sign; isADD = ~S2 since add-like ops have S2=0, sub-like S2=1).
  Ungated by M, so V is *valid after ADD/SUB/CMP* (documented convention).
  - ALU card: U34 (74HCT86) XORs + U35 (74HCT08) AND derive V into the flag
    register (was tied low). No bus change — FV is already bused.
  - Control card: U19 (74HCT86) computes N^V -> cond-mux D6; a spare U6 OR gate
    does (N^V)|Z -> D7 (D6/D7 were grounded). FCOND 6/7 select them.
  - Microcode: `BLT/BGE/BLE/BGT` (0x44-0x47) via FC LT=6 (N^V), LE=7 ((N^V)|Z).
    C still gives unsigned ordering (BCP/JNC); these give signed.
  - Emulator computes V by the identical Boolean; new ISA tests cover the
    sign-boundary cases where unsigned C would mislead (e.g. -128 < 1). All 6
    suites pass; all 7 boards regenerate with 0 validation errors.
  - Bring-up: confirm V/sign-compare on real silicon; the XOR/AND chain adds a
    little delay off the flag path (not the ALU critical path).

- **EEPROM ROM write-protect jumper (rev C).** Added a 3-pin select header
  `JWP` (HDR3) on the memory card in the 28C256 `!WE` path: jumper 1-2 routes
  `!WE` to the live `-WE` net (writable, the default), 2-3 ties it to VCC
  (write-protected, immune to runaway-code writes). The 62256 RAM stays on
  `-WE` unconditionally, so write-protecting the ROM doesn't touch RAM. Memory
  card regenerates with 0 validation errors. Assembly note: a jumper must be
  installed (1-2 by default) — leaving the header open floats the ROM `!WE`.

- **Second ALU-input mux (rev C) — B-side can take T.** Added a 2:1 mux on the
  ALU card B-operand path (U32/U33, 74157 ×2): B register when `BSEL=0`, T
  register when `BSEL=1`. `BSEL` is microcode-word bit 31 (was the lone spare),
  latched in control-card pipe U17.Q8 and carried to the ALU card on backplane
  B28 (was SPARE9). New opcodes `ADDT/SUBT/ANDT/ORT/XORT/CMPT` (0x80-0x85) run
  the usual ALU ops with T as the second operand — so e.g. `A := A + T` in one
  step, **B preserved**. Also added `LDT #imm`/`LDT a` (0x86/0x87) since T was
  otherwise microcode-scratch-only and had no programmer-visible load. Modelled
  in the emulator (bit 31 selects the B operand), covered by new ISA tests
  (ADDT/SUBT/CMPT/ANDT/ORT/XORT/LDT, all green), and documented in the
  programmer's guide. All 7 boards regenerate with 0 validation errors. The mux
  delay stacks ahead of the 74181/74182 carry path — confirm timing margin when
  bringing up the ALU card.

- **Datasheet pinout audit of the generator's device library.** Cross-checked
  all ~25 devices (74161/169/374/377/151/74/02/10/139/157/175/244/257/260/181/
  182, 7430, 7474, 74138, 28C64, 62256/28C256, 6850, MAX232, OSC can, IDE40,
  resistor/LED arrays) against standard datasheet pinouts. **Found + fixed one
  real error: the 74260** (dual 5-input NOR, the ALU bus zero-detect U27) had a
  scrambled pin map — gate-1 `C1` on pin 3 (should be 11) and the `Y1`/`Y2`
  outputs swapped (6↔8), among others. Corrected to the datasheet
  (1=1A 2=1B 3=2A 4=2B 5=2C 6=2Y 7=GND 8=1Y 9=2D 10=2E 11=1C 12=1D 13=1E
  14=VCC); the netlist uses logical pin names so it didn't change. All others
  matched. NB the 74244 uses flat A1-A8/Y1-Y8 labels (not 1A1..2A4) but the
  pins + An<->Yn pairing + the two `!G` enables are electrically correct.
- **Decoupling caps on every card.** gen_eagle's `card()` now drops one 100nF
  cap (`CDn`, C_DISC footprint) per IC, placed beside it and wired VCC<->GND;
  the memory card's separate build does the same for U1-U9. Counts: control 18,
  regbank 44, alu 31, io 15, cf 8, memory 9 (backplane already had its 10 +
  bulk). All 7 boards regenerate with 0 validation errors; schematic PDFs
  refreshed. (Placement is approximate pending Fusion routing.)
- **P8X/OS v1.0 — v2-aware PACK (filesystem complete).** Compacts hierarchical
  volumes in two phases. PHASE 1: a tree-walk min-find repeatedly picks the
  live file/dir extent with the smallest start LBA >= the running free pointer
  and copies it down, updating only the one parent directory entry that points
  to it (the walk reaches each extent via that entry, so the location is in
  hand; re-walking each pass reflects prior moves, and a moved directory
  carries its child *listing* verbatim so child pointers stay valid). PHASE 2:
  re-walk the compacted tree and rewrite every directory's '.' (=self) and '..'
  (=parent) from final positions, so CD/.. and fsck stay correct. Verified the
  hard case — a freed low extent forces A and its subdir SUB to move; after
  PACK, CD .. walks SUB->A->root correctly, CAT of the moved file is intact,
  and fsck reports 0 reclaimable. Also bumped the OS var base to $9A00 for code
  headroom. os_v2_test now PACKs and asserts a fully-compacted, navigable tree.
- **P8X/OS v0.8 — TREE.** Depth-first indented listing of the whole tree from
  root, iterative with an explicit RAM stack of (dir start, dir sectors, next
  entry index) frames (depth 8) — the single shared sector buffer rules out
  recursion, so on return from a child the parent's sector is re-read and the
  scan resumes. v2 only (a v1 root's 32-sector entry count overflows a byte,
  and flat volumes have no tree). Output matches the host `p8xfs tree`;
  os_v2_test asserts the indented hierarchy.
- **P8X/OS v0.7 — MKDIR / RMDIR on-target.** MKDIR resolves the parent, checks
  the name is free, allocates a SUBSECS (4) extent at the free pointer, writes
  its '.'/'..' (MKEXT), and adds a F_DIR entry to the parent (FINDSLOT+WRENT,
  now stamping a parameterized EFLAG). RMDIR resolves the dir, confirms it's a
  directory and empty (DIREMPTY: nothing past '.'/'..'), then tombstones the
  parent entry. Verified end to end (create / save-into / refuse-non-empty /
  delete / remove) with a fsck-clean result; os_v2_test exercises it. Also
  fixed a real collision the growth exposed: the OS image had reached ~4.1 KB
  ($8000-$9009) and overran its own variables at LINEBUF=$9000 (typed lines
  clobbered the tail of KW_MKDIR) — moved the OS variable block to $9600.
- **P8X/OS v0.6 — directory navigation (reads v1 + v2).** Generalized directory
  scanning from the fixed LBA 33-64 region to a (start LBA, sector count) pair,
  so the current directory and any resolved path share one code path (FINDENT,
  DIR, FINDSLOT). Cold start reads the boot-block version byte and sets the
  layout (v1: root 33/32 sectors, data @65; v2: root 33/4, data @37) + CWD =
  root. Added a RESOLVE routine (walks path components via the on-disk `.`/`..`
  entries; absolute `/...` vs relative), `CD` (with a best-effort CWD-path
  prompt), `DIR [path]`, and made LOAD/RUN/SAVE/DEL accept a path. PACK guarded
  to flat (v1) volumes. Fixed a P2-clobber bug (FINDENT walks SBUF with P2, so
  DESCEND now saves/restores the caller's path cursor). New regression
  os_v2_test.sh: host-builds a v2 disk with a subdir + program, boots, and
  checks CD/DIR/RUN (cwd + absolute path) + a rejected bad CD; v1 os_test still
  green.
- **P8XFS v2 host support (p8xfs.py).** `create --v2` lays a hierarchical
  volume (version 2, 4-sector root directory at LBA 33, data from LBA 37); a
  directory is a file whose extent holds entries with `.` (entry 0) and `..`
  (entry 1). Added path resolution, `mkdir` (allocates a 4-sector extent, writes
  `.`/`..`), path-based `put`/`get`/`ls [path]`, `tree`, and a version-aware
  `fsck` that walks the tree and verifies every `..` points at its true parent
  (negative-tested: a corrupted `..` is flagged). v1 (flat) volumes still work
  and remain the default, so the v1 OS + emulator tests are unaffected. This is
  the host reference + disk-builder for the on-target v2 work to come.
- **P8X/OS v0.5 — PACK + host fsck.** PACK compacts the data area: each pass
  scans the directory for the live file with the smallest start LBA >= the
  running free pointer, copies its extent down to the free pointer (low-to-high
  sector copy via SBUF — safe because dst <= src and extents are processed in
  ascending start order), rewrites that entry's start LBA, and advances the
  free pointer; finally the boot-block free pointer is lowered. Handles the
  tricky case where a SAVE reused an early directory slot so directory order
  != start-LBA order (min-find, not directory order). tools/p8xfs.py fsck
  verifies a volume (signature, every extent in-bounds, no overlaps, free
  pointer past the last extent) and reports reclaimable sectors. Verified:
  create/DEL/PACK leaves fsck-clean volumes with data intact across the moves;
  test-os runs PACK and fsck-checks the result.
- **P8X/OS v0.4 — DUMP + DEP.** DUMP addr shows 256 bytes (16 x "AAAA: 16 hex
  bytes  ASCII"); DEP addr b b ... deposits a series of hex byte values from
  addr (reusing the SAVE hex parser + the BIOS PHEX8). Makes the OS
  self-sufficient for inspecting/poking memory, and closes a self-hosting loop:
  DEP machine code -> SAVE it -> RUN it (verified end to end — a DEP'd 6-byte
  program saved and run prints its char). test-os now exercises DEP+DUMP.
- **BASIC — three build targets from one source.** Parameterized the
  interpreter on BASORG (code origin) + BASRAM (data base); PBUF fixed at
  $C000. Standalone (default $0000/$8000) is byte-identical to before.
  Disk build ($8000/$A000) installs as a bootable P8XFS image and runs via the
  monitor's B; ROM build ($2000/$A000) is overlaid into the monitor EEPROM by
  tools/build_basic_rom.py and launched by a new monitor X command; BASIC's
  BYE command jumps to the reset vector to return to the monitor. Needed a new
  assembler `-D NAME=VALUE` (CLI defines that win
  over source `=` defaults). Regression: `make test-basic` (X launches ROM
  BASIC; B boots disk BASIC; a program runs in each). BASIC code is ~4 KB so
  it clears the $A000 data region in both relocated builds.
- **P8X/OS v0.3 — SAVE (on-target file create).** SAVE name start end: parse
  two hex addresses (GETHEX/HEXVAL; 16-bit accumulate via SHL/ROL), 16-bit
  length = end - start (SUB + borrow into the high byte), sector count, then
  allocate at the boot-block free pointer, copy memory -> SBUF -> CFWRITE per
  sector, write a directory entry into the first free/$FF slot (FINDSLOT +
  WRENT, load=exec=start), and bump the free pointer. Verified: files persist
  across reboot, consecutive SAVEs allocate consecutive LBAs, and a SAVE'd
  range round-trips byte-identical through `p8xfs.py get`. test-os now also
  SAVEs and checks the bytes.
- **P8X/OS v0.2 — shell with file commands.** Added LOAD (read a file into its
  stored load address; sector count = ceil(len/512)), RUN (LOAD + JSR exec
  address, program RTS returns to the shell), and DEL (mark the entry $FF and
  write the directory sector back via CFWRITE — verified by re-reading DIR).
  Whole-word command matching + a filename parser (upcase, space-pad to 12,
  peek/INP2 so the line terminator isn't over-consumed); FINDENT walks the
  directory and captures a pointer to the matched entry's flag byte. Regression
  `make test-os` now boots, runs a program, deletes a file, and re-lists.
- **P8X/OS v0.1 — boots from CF, runs a shell.** RAM-resident OS
  (os/p8xos.asm) assembled with the new `--base 0x8000` mode, installed at
  LBA 1 by p8xfs.py and booted via the monitor's `B`. Calls the monitor's
  BIOS jump table at $0100 (CONIN/CONOUT/CONST/CFINIT/CFREAD/CFWRITE/PUTS/
  PHEX8 — a stable ABI; monitor body relocated to $0130). Shell: HELP and
  DIR (walks the flat P8XFS v1 directory LBA 33-64, prints name + hex size).
  Regression: `make test-os`.
- **Host tool p8xfs.py** (tools/): create/format a P8XFS v1 image, `boot`
  (install an OS image + set OSCNT), `put`/`get`/`ls`. Matches the monitor's
  on-disk layout (dir 33-64, data 65+).
- **Assembler --base**: emit a RAM-resident blob (labels resolved to the run
  address, only base..hi bytes written) for OS/program images that live above
  $8000. No --base = unchanged 32K ROM image.

- **Emulator: CF-IDE model** ($FF10-17). 8-bit True IDE task file backed by a
  flat sector-image file, attached with `p8xemu -c <img>` (auto-created +
  zero-filled to 256 sectors if absent). Models SET FEATURES/IDENTIFY/READ
  SECTORS/WRITE SECTORS with the BSY/DRQ handshake the monitor's driver spins
  on; IDENTIFY returns a byte-swapped model string. The monitor's filesystem
  hooks now run emulated end to end — `I` (init), `F` (format P8XFS boot block
  + directory), `B` (boot OS from LBA 1 to $8000). Regression: `make test-cf`
  (formats a card, plants a tiny OS at LBA 1, boots it). Surfaced + fixed a
  latent monitor bug: `CMD_F` compared `A` to `'Y'` *after* `CRLF` clobbered
  it, so format always aborted; reload the key from GETC's `TMP` copy.

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

### Early milestones (original checklist)

The foundational tick list from the project's first phase — kept as-is for the
record. Newer work is logged as bold-title entries above.

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
