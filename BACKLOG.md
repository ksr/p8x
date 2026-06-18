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
  DONE (Phase 1 complete — monitor assembles & boots in the emulator):
    - adopted CONVENTIONAL active-high carry (rev B): C=1 = carry / A>=B
    - CLC/SEC (SETC/CLRC bits), JC/JNC, ROL/ROR + carry-coupled shifter
      (SHL/SHR latch shifted-out bit -> C; SHCIN shifts C in for rotates)
    - assembler: char literals may contain space/+/- (tokenizer fix)
    - firmware/p8xmon.asm converted to p8xasm dialect (EQU->=, DB->.byte/
      .ascii, ORG->.org); assembles to 101 symbols; banner, ?, D dump all work
- **Monitor port — Phase 2 (hardware): DONE.** All rev-B microcode-word
  changes are realized in the CAD generators:
    - backplane bus allocation (rev C3); control-card pipeline-latch remap;
      reg-bank 3-bit PSEL decode + PT pointer.
    - ALU flag-register redesign: C split onto a 7474 (U26) with SETC/CLRC
      async preset/clear; Z/N source-muxed on LDZN (U22) with a 74260 bus
      zero-detect (U27); carry-coupled shifter (U28/U29 mux shift-out F7/F0 vs
      inverted Cn+4; U30 muxes the shift-in CIN vs C on SHCIN); U31 gates the
      C and Z/N/V clocks (CLK&LDF, CLK&(LDF|LDZN)).
    - NB: pin/pad-validated only, not DRC'd; the rev-B *behaviour* is proven in
      the emulator (make test-isa). A full Eagle DRC + airwire check before fab
      remains on the VERIFY list.
- **P8XFS v2 hierarchy (IN PROGRESS)**: host side, OS navigation, MKDIR/RMDIR,
  and TREE are done (see DONE). Remaining:
    - **v2-aware PACK**: currently flat-only (guarded). A v2 PACK must walk the
      tree and, when moving a directory extent, repoint the parent's entry AND
      that dir's own `.` plus every child's `..`. Re-verify with v2 fsck.
    - **on-target FORMAT** (optional): monitor F still writes v1; either teach it
      v2 or add an OS FORMAT so a card can be made bootable without the host.
      (Monitor B is unchanged — it only reads sig+OSCNT.)
    - **watch the OS code size**: the image is ~4.1 KB at $8000; OS variables
      were moved to $9600 to clear it (RUN'd programs still load at the $A000
      TPA). If code approaches $9600, bump the var base again.
- **P8XFS v2 hierarchy**: upgrade the flat directory to subdirectories
  (directory-is-a-file, `.`/`..`, path resolve) per p8xfs-v2-hierarchical.md —
  CD/MKDIR/RMDIR/TREE. Monitor ROM unchanged (B only reads sig+OSCNT); move
  FORMAT policy onto the OS. p8xfs.py grows mkdir/tree/fsck.
- **CFREAD ABI is 1-byte LBA**: the BIOS CFREAD/CFWRITE only set LBA0 (LBA1-3
  zeroed in the monitor's CFSETL), capping addressable sectors at 256. Fine for
  small images today; widen to a multi-byte LBA in CFSETL + the BIOS contract
  before volumes exceed 128 KB.

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

- [ ] **Housekeeping (from 2026-06 consistency audit; not yet decided):**
    - Tracked generated binaries: `microcode/u0-u3.bin` are committed but
      regenerate byte-identically from genucode.py. Consider gitignoring them
      and letting `make` build them. (Lean keep — project frames them as the
      canonical EPROM images, burned *and* interpreted.)
    - `busnet()` is duplicated in gen_eagle.py and gen_bus_pdf.py (kept in sync
      by hand; drift risk). De-dup is awkward because gen_bus_pdf is meant to be
      standalone — importing gen_eagle regenerates all boards as a side effect.
      A clean fix would guard gen_eagle's board-writing under `if __name__ ==
      "__main__"` so it's importable without side effects.
    - Smoke tests test1-3.asm overlap test_isa.asm (per-opcode). They give
      higher-level scenario coverage (banner, JSR/RTS, countdown); keep as
      complementary unless trimming.
- [ ] Assembler for P8X syntax (Python, shares opcode table with microcode
      generator — single source of truth for the ISA)
- [ ] Microcode generator → EPROM images (same shared table)
- [ ] Mac-side p8xfs tool (put/get/ls/mkdir/tree/fsck via USB CF reader)
- [ ] **C-based P8X CPU emulator** — cycle-accurate against the microcode
      (ideally interprets the same EPROM images the hardware will burn, so
      microcode bugs surface in software first); memory map, ACIA-to-stdio,
      CF image file backing; test bed for monitor/OS/BASIC before hardware
- [ ] **Simple text editor** — a P8X/OS program (TPA at $A000) for editing text
      files: load a file via the BIOS into a RAM buffer, line-oriented edit
      (insert/delete/list/replace by line, like the BASIC editor), save back
      with the OS SAVE path. Serial-console friendly (no cursor addressing
      needed); a screen/visual mode is a later stretch. Pairs naturally with
      RUN — write source, save, assemble off-target for now. Could share the
      line-buffer/rebuild approach already proven in p8xbasic.asm.
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
