# P8X Project Backlog

Add ideas as they come; move items between sections as they progress.
Last updated: 2026-06-24

## How to use
- **NEXT** — committed, in rough priority order
- **IDEAS** — captured, not yet committed
- **VERIFY** — open questions / checks before trusting something
- **DONE** — kept for the project log

---

## NEXT

- [ ] **Second CF as a removable master / transfer drive.** Goal (2026-06-25):
      keep a "master" CF holding core files (e.g. `/BIN` binaries) and, in the
      field with no host, provision a fresh card by copying from it — `FORMAT`,
      insert master, `IMPORT 1:/BIN`, done. Scope is deliberately **read-from-
      drive-1 only**, NOT full dual-volume: the working/boot volume stays drive 0
      with the normal CWD; drive 1 is just a source you read/copy from. This
      avoids the heavy FS refactor (no per-drive CWD, no mounting).
      - **HW:** a second CF port at its own decode (e.g. `$FF18–$FF1F`) — one more
        `'138` term + buffers + socket. (Master/slave on one channel is too
        unreliable for True-IDE CF; the driver also hardwires `$E0`=drive 0 today.)
      - **BIOS:** make sector I/O drive-aware — `CFRDSEC`/`CFWRSEC` select the
        drive (port base / DEV bit) per transfer; the read stream carries its
        source drive and the write stream its dest drive, so `FGETB`(drive 1) and
        `FPUTB`(drive 0) interleave in one copy loop. Add a select call / per-init
        IDENTIFY+SET FEATURES for card 1.
      - **OS:** honor a leading `N:` drive prefix on **source** paths in the
        resolve/`FOPEN` path (unprefixed = drive 0, with CWD). Then `CP 1:/BIN/X
        /BIN/X` works as-is (cp reads src/writes dst). Add a bulk `IMPORT 1:/BIN`
        (walk drive 1 with the find/dir-R recursion, copy each file to drive 0).
      - **Emulator:** a 2nd image (`-c2 disk2.img`) modelling the 2nd device.
        `p8xfs.py` is already per-image (build the master with it).
      Bonus: this also solves the post-`FORMAT` bootstrap (repopulate `/BIN`
      with no host), which **unblocks the minimal-kernel split** (DIR/PWD→/BIN)
      below. Effort: HW small, BIOS moderate/low-risk (additive), OS `N:`+IMPORT
      is the real work but far less than general dual-volume.

- **P8XFS v2 — remaining loose ends** (the hierarchy itself is DONE; see DONE):
    - **on-target FORMAT — DONE** (2026-06-22, see DONE). Added the `FORMAT`
      command; it fit once the OS moved to $4000 (rev D).
    - **OS code size — ceiling lifted to 16 KB (rev D).** The boot loader (CMD_B)
      loads the OS to $4000 upward, and the CF LBA pointer is BIOS-pinned at $9D47,
      so the image must still end below $9D47 — but from $4000 that's ~23.8 KB (46
      sectors). The tighter cap is the on-disk OS region (LBA 1–32), so **16 KB / 32
      sectors max**. The OS is ~7165 B today, so there's now ~9 KB of headroom (was
      ~3 B). LBA/SBUF/vars are unchanged ($9D47/$9E00/$A000).


- [ ] **Shared-source helper convention for /BIN commands.** There's no linker
      and no `#include`, so reusable helpers (the basic-regex `match()` in
      `grep.c` is the first; more commands will want it) are currently shared by
      copy-paste. When a 3rd consumer appears, add a small build step that
      concatenates a shared `os/commands/lib*.c` ahead of the command source
      before `p8cc` (run.sh + the test harness). Helpers must stay within the
      native `p8cc.c` subset: no forward decls / mutual recursion, no `++`/`--`,
      declarations at function top.

- [ ] **`p8cc.c` miscompiles the file-argument parse in `sed.c` and `diff.c`.**
      Native-bootstrap bug: host-compiled `SED s/a/b/ FILE` / `DIFF A B` mis-parse
      their file argument(s) — sed reads empty stdin, diff diffs the wrong files —
      though the same commands work via pipe/under `p8cc.py`, and `openarg()` is
      fine in head/tail/find on the host. Common factor: advancing the arg pointer
      past one token then opening a *second* word (the `abspath()`-returns-count /
      `a = a + n` idiom). `p8cc.py` compiles both correctly, so run.sh ships the
      working binaries; `c_textutils_test`/`c_findiff_test` build sed/diff with
      p8cc.py. Track down + fix in compiler/p8cc.c (it's the self-host oracle).
      (Related p8cc subset gotchas now documented in os/commands/README "Shared
      code": `<`/`>` are unsigned, `int` index arrays misbehave, no `break`/
      forward-decls, don't pass `array+expr` to a function.)

- [ ] **`>>` append redirection.** Today the shell has `>` (REDSCAN -> FWOPEN,
      create/overwrite). Add `>>` to append a command's stdout to an existing
      file. Catch: P8XFS files are **contiguous extents** written at the boot-block
      free pointer, so you can't grow a file in place. So `>>` means
      copy-then-extend: stream the existing file's bytes into a fresh write stream
      first, then the command's output, then close+register (replacing the old
      entry); the old extent is reclaimed by PACK — same pattern as cp/mv. Parser:
      REDSCAN must recognize `>>` before `>`. Mind the SBUF ordering (FRESOLVE the
      target before FWOPEN) and that the source read uses ROBUF, not SBUF.
      ATTEMPTED 2026-06-25, reverted: added REDAPP + `>>` parse + a DORUN prepend
      (open old via SETCWDDIR/FNORM/FOPEN, FWOPEN, copy FGETB->FPUTB, then stdin
      bind, exec, FCLOSE). The prepend's FGETB read a *directory* sector (ROLBA
      ended up at a dir LBA, e.g. /BIN at 37) so the appended-onto bytes came out
      garbage — even with the read buffer at $E000 (matching cp). cp does the
      identical FOPEN(read)->FWOPEN->copy and works, so the bug is specific to
      doing it inside DORUN after LOADF (shared read-stream/LBA state? FFIND
      returning the wrong start LBA for the leaf name?). The attempt also
      reordered DORUN to open output before stdin (so the prepend finishes before
      `<file` reuses the single read stream) — re-verify that reorder doesn't
      regress `<IN >OUT`/pipes when retrying. Next step: instrument FOPEN's ROLBA
      in the DORUN context vs the cp context to find the divergence.

- [ ] **Multi-stage pipes (`a | b | c`).** The shell's pipe state machine
      (`PIPEF`/`PIPESCAN`/`PIPE_RHS`) handles exactly **two** stages: it splits on
      the first `|`, runs the left into `PIPE.TMP`, then re-dispatches the right.
      The re-dispatch jumps to `DISPATCH` without re-scanning for `|`, so a third
      stage is swallowed as args of the second command. To support N stages,
      `PIPE_RHS` would need to re-run `PIPESCAN` on the remaining line (chaining
      temp files), or the splitter could iterate left-to-right. Until then,
      `CAT f | GREP x | WC` silently drops the `| WC`.

- [ ] **Minimal-kernel split: move the pure-viewer built-ins (DIR/PWD/TREE/DUMP)
      to /BIN.** Built-in CAT is already gone (2026-06-24): bare `CAT file` falls
      through DISPATCH to implicit-RUN of `/BIN/CAT.BIN`. The open question is how
      much further to push it. Reasoning (2026-06-24):
      - In normal provisioning the OS boot region and `/BIN` are written together
        (run.sh / p8xfs), so an "OS but no /BIN" disk basically never happens in
        day-to-day use — the old bare-disk argument is weak.
      - The ONE real exception: `FORMAT` preserves the OS (it stashes OSCNT; "card
        stays bootable") but empties the filesystem, so a freshly-FORMATted card
        boots the OS with no `/BIN`. Decision hinges on: should that card be usable
        standalone, or is "re-image from the host after FORMAT" acceptable?
      - **Irreducible — must stay native** (can't be /BIN programs): `RUN` (it
        launches /BIN programs; chicken-and-egg) + the implicit-run dispatch; the
        on-target authoring/FS primitives `SAVE`/`DEP`/`LOAD`/`DEL`/`MKDIR`/`RMDIR`
        /`CD` (these let you rebuild /BIN with no host — DEP bytes + SAVE → a .BIN;
        if they were /BIN-only a FORMATted card with no host would be a brick);
        plus `HELP`/`EXIT`/`MON`/`FORMAT`/`FSCK`/`PACK`.
      - **Movable (pure viewers, no bootstrap role):** `DIR`, `PWD`, `TREE`,
        `DUMP`. DIR is the big win (~70 lines: DODIR/DENT2OS/DPRENT + MDIRHDR/
        MDIRTAG); PWD ~4; TREE/DUMP each a chunk. `os_format_test` (DIRs a fresh
        volume) and `os_test` (`DIR >DLIST`) lean on built-in DIR and would need
        reworking (install /BIN/DIR.BIN, or verify via p8xfs host-side).
      Lean: minimal kernel (Unix-ish) — keep the kernel above, push the viewers to
      /BIN. Cost is only that a just-FORMATted card can't `DIR` until /BIN is
      repopulated. Decide + do as one migration. NOTE: the "second CF master /
      transfer drive" item above removes that last objection — `IMPORT 1:/BIN`
      repopulates a fresh card with no host — so doing that first makes this safe.

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

- The **OS stdio stream model and pipes are DONE** (see DONE — OS stream
      syscalls, program `<`/`>` redirection, and `|`). Remaining sugar, if
      wanted: useful **filter commands** to pipe through (a `MORE`/`WC`/`GREP`
      as C programs — now writable over `getchar`/`putchar` + the BIOS), and a
      separate `stderr` stream (errors currently go to the console via the BIOS
      directly, which is the desired behaviour, just not a distinct syscall).
- [ ] **Make the BIOS file routines hierarchy-aware (paths, not just root).** The
      ROM FS calls (`$0118 FFIND` / `$011B FCREATE`) currently operate only on the
      P8XFS v2 **root** directory (LBA 33), so BASIC `SAVE`/`LOAD` and any BIOS-FS
      client are flat — they can't reach `/BIN/FOO`. Teach them to **resolve a
      path** through the `.`/`..` entries (walk components, DESCEND into each
      subdir extent) so a name like `/BIN/PROG` or a relative path works, matching
      what P8X/OS already does internally. Open questions: (a) carry a notion of
      "current directory" across calls (a CWD extent in the BIOS ABI) vs requiring
      absolute paths; (b) ROM size — path resolution is ~the OS's RESOLVE/DESCEND
      (a few hundred bytes), and ROM has room. This is the natural precursor to the
      "offload OS commands" item below (those need dir iteration + paths too), and
      it would let BASIC save into subdirectories. Keep the root-only fast path or
      replace it. Update the BIOS ABI doc + a hierarchy round-trip test.
- [ ] **Offload OS commands to loadable programs via the ROM FS routines.** Now
      that the monitor publishes a shared filesystem API (`$0118 FFIND` /
      `$011B FCREATE`, see DONE — BASIC SAVE/LOAD), the heavy/self-contained OS
      commands can move OUT of the resident OS image into `.COM`-style programs
      loaded into the TPA and `RUN` — shrinking the kernel and freeing boot-ceiling
      space. Good candidates: **PACK** (~1 KB), **FSCK** (~0.5 KB), **TREE**,
      **DUMP**, **DEP** — anything that mostly needs sector/file access rather than
      live shell state. Two enablers: (a) widen the ROM FS API beyond flat root
      files to what these need — directory *iteration*, delete/tombstone, free-
      pointer read/write, ideally path resolution (or each program re-walks via
      FFIND); (b) a stable program ABI for args (the OS already passes a command
      tail). Net effect: the OS keeps only the shell, parser, path layer, and thin
      built-ins; everything else lives on disk and shares one ROM FS layer with
      BASIC and any user program. Sequence after the FS API grows those few calls;
      pairs with the on-target assembler/editor ideas below.
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
    - `busnet()` is duplicated in gen_eagle.py, gen_bus_pdf.py, and gen_bus_card.py
      (kept in sync by hand; drift risk). De-dup is now feasible: gen_eagle's
      file-writing is gated behind `EMIT = (__name__ == "__main__")` (DONE), so it
      is importable WITHOUT side effects — the other scripts could import its
      busnet instead of keeping their own copies. (The import-scatters-board-files
      footgun itself is fixed.)
    - Smoke tests test1-3.asm overlap test_isa.asm (per-opcode). They give
      higher-level scenario coverage (banner, JSR/RTS, countdown); keep as
      complementary unless trimming.
- [ ] **C compiler — Milestone A DONE (self-compiling, host-run); Milestone B
      (run on the P8X) is the open work.** Both compilers exist and are tested:
      `compiler/p8cc.py` (Python, the everyday tool + reference oracle, never
      removed) and `compiler/p8cc.c` (the same compiler in p8cc's own small-C
      subset). p8cc.py compiles p8cc.c cleanly — "small C written in small C" —
      and a differential test (`c_selfhost_test.sh`) proves the gcc-built
      p8cc.c and p8cc.py agree on output. The language in p8cc.c is complete; see
      DONE for details. **KEEP p8cc.py** — it bootstraps p8cc.c and is the diff
      oracle.

      **(B) Self-host: run `p8cc.c` ON the P8X.** Gated by RAM, exactly like the
      assembler was. The P8X has ~48 KB RAM ($4000–$FEFF) and a compiler's
      working set (source buffer, symbol/struct tables, string pool) plus its own
      ~20 KB+ code won't fit a whole translation unit at the $B000 TPA — so it
      needs the same streaming/single-pass discipline we gave ASM (stream source
      in, emit asm out, bounded tables; today p8cc.c slurps stdin into a fixed
      `src[]`). It depends on the on-target assembler (DONE) to turn the emitted
      asm into a binary. Likely an even smaller working subset, possibly
      multi-pass through temp files on disk. Forth remains an orthogonal track.
- [ ] **Native toolchain follow-ups** (EDIT + ASM landed — see DONE). Remaining
      polish on the on-target assembler/editor, none blocking:
        - **Tools write to the flat root only.** EDIT `W` and ASM output go to
          the P8XFS root via the BIOS FFIND/FCREATE layer, so they can't save
          into `/BIN` etc. Folds into the "make the BIOS file routines
          hierarchy-aware" item above — once that lands, the tools inherit paths.
        - **ASM capacity — mostly lifted (2026-06-23).** Source + output are now
          streamed to/from disk (bounded by the disk, not RAM); symbol table is
          ~850 entries. Remaining caps: 12-char names, 127-char source lines,
          single `.org` (backward `.org` rejected). Multiple `.org` would need
          per-region output rather than one monotonic stream.
        - **ASM features not yet supported:** `.equ NAME,expr` form (only
          `NAME = expr`), string escapes in `.ascii` (raw chars only), and
          macros/conditional assembly (the host has none either).
        - **Self-host check — DONE (2026-06-23).** ASM assembles its own ~37 KB
          source on-target to a binary byte-identical to the host build
          (`make test-asm-selfhost`).
        - **EDIT:** 8-bit line count (≤255 lines), whole-file rewrite on `W`
          (orphans sectors until PACK), no search/replace or block ops.
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

- **OS stdio stream model + redirection + pipes** (2026-06-24). Gave the OS a
  Unix-style I/O layer over the `$4000` syscall table. New syscalls `SYS_PUTC`
  ($4009), `SYS_GETC` ($400C), `SYS_PUTS` ($400F) route through the OS output
  sink `OUTCH`, which gained a file-stream mode (`REDIRF=2` -> `FPUTB`).
  `DORUN` binds a program's stdout (`> file`, `FWOPEN`/`FCLOSE` around exec) and
  stdin (`< file`, `FOPEN` into a dedicated `IBUF` at $A200, `SYS_GETC`->`FGETB`;
  `getchar` returns -1 at EOF). Both compilers emit `putchar`/`puts`/`getchar`
  as these syscalls, so every compiled program is redirectable with no source
  change — `RUN CAT.BIN <IN >OUT` copies a file. **Pipes** (`cmd1 | cmd2`) are a
  `SHELL` state machine (`PIPEF`): `INSCAN`/`PIPESCAN` split the line, the left
  runs into `PIPE.TMP`, the right re-dispatches with stdin from it, then it's
  deleted — no existing command changed. Examples `os/commands/cat.c`
  (filter), `pwd.c`; tests `c_redirect_test`/`c_stdin_test`/`c_pipe_test`
  (differential, both compilers). A program that iterates a directory *and*
  streams output (`DIR`) calls `FSDIRBUF` ($0145) to move `FNEXT`'s sector
  buffer off `SBUF` onto its own page, so it streams per entry and redirects/
  pipes like any other program (no listing buffer, no size cap).

- **C compiler Milestone A — p8cc.c self-compiles ("small C in small C")**
  (2026-06-24, #57). Rewrote the compiler in its own small-C subset as
  `compiler/p8cc.c`, ALONGSIDE `p8cc.py` (kept as bootstrap + reference oracle).
  p8cc.c is both valid standard C and valid p8cc-subset C, so it builds two
  ways: `cc p8cc.c` → a native bootstrap that reads C on stdin and writes asm to
  stdout, and `p8cc.py p8cc.c` → the self-compile proof (the subset accepts its
  own source). Built in 8 increments, each behaviourally differential-tested
  (host bootstrap vs p8cc.py, identical P8X output): lexer → first codegen slice
  + harness → full operator ladder → globals/assignment/control-flow →
  params/locals/recursion (a __csp/__fp frame; args pushed left-to-right so
  param i is at __fp+2*(pcount-i)) → char/int types + pointers via an
  lvalue-address model (a leaf leaves an lvalue's ADDRESS in __ax; rvalue()
  derefs by width on demand, making &x free and *p/x= uniform) → arrays +
  indexing + string-literal pool + puts → structs/unions with `.`/`->`.
  Enabling subset additions to p8cc.py: `#`-line skipping (so `#include
  <stdio.h>` works for gcc) and function prototypes (mutual recursion in a
  recursive-descent parser needs forward decls). Single-pass, so declare-before-
  use. Test: `emulator/test/c_selfhost_test.sh`. **Milestone B** (run p8cc.c ON
  the P8X) stays open — a RAM/streaming problem, not a language gap.
- **C cross-compiler v0.2/v0.3 — params, recursion, pointers, I/O** (2026-06-23,
  #45–47). Grew `p8cc.py` from the v0.1 skeleton into a usable small-C:
    - **#45 calling convention.** A software C-stack (`__csp`, grows down from
      $F800) holds call frames; `__fp` is the frame pointer; params at
      `__fp+2,+4,…`, locals at `__fp-2,-4,…`; helpers `__enter`/`__leave`. So
      functions take arguments and **recursion/reentrancy works** (e.g. `fact`).
    - **#46 pointers, arrays, `& * [] / %`.** Type-aware codegen `(base,ptr,
      count)`: dereference loads/stores the right width (int/ptr 2 B, char 1 B),
      pointer arithmetic scales by element size, `gen_address` handles `&lvalue`/
      `*e`/`a[i]`. Added unsigned 16-bit `/` and `%` (`__divmod`). (Fixed a
      `__divmod` high-byte/quotient-bit bug — quotients had garbage high bytes.)
    - **#47 input + libc-in-C.** `getchar()` builtin (BIOS CONIN $0100) gives
      programs console input; the realization is that with pointers/arrays/char
      working, the rest of a libc (`strlen`, `getline`, …) is just ordinary C
      compiled alongside the program — so the builtin surface stays at three
      I/O calls. Test `c_libc_test.sh` proves it end to end.
    Suite grew to 26 (`c_compile_test` covers recursion/multi-arg/ptr-fill/`&`+
    ptr-param/`/`+`%`; `c_libc_test` covers getchar+a C-written strlen). The
    compiler is still host-Python — see IDEAS "C compiler" for the bootstrapping
    roadmap (rewrite in its own subset, then self-host on the P8X).
- **C cross-compiler v0.1** (2026-06-23). `compiler/p8cc.py` — a tiny C compiler
  on the host emitting P8X asm (for p8xasm.py), targeting the TPA so output is a
  RUNnable `/BIN` program. Lexer + recursive-descent parser + codegen. Subset:
  `int`(16)/`char`(8), function definitions (no params), global vars, `if`/`else`/
  `while`/`return`, operators `= == != < > <= >= + - *` and unary `- !`, and the
  `putchar`/`puts` builtins over the BIOS. Execution model: a 16-bit pseudo-
  accumulator `AX` (memory word) since the machine has no 16-bit acc; the P3
  hardware stack holds temporaries (PHA/PLA) + return addresses; binary ops are
  compact runtime helper calls (`__add/__sub/__mul/__eq/__lt/__not`, emitted only
  if used); `*` is a shift-add `__mul`. v0.1 gives every variable static storage
  (no frame → no recursion/reentrancy, user funcs take no args) — the next phase
  adds a stack frame + calling convention. Test `c_compile_test.sh` (`make
  test-c`) compiles a while-loop + user-function program, assembles, RUNs it, and
  checks the output (`12345`, `SQ-OK`). See IDEAS "C compiler" for the roadmap.
- **Native toolchain: EDIT + ASM (on-target, self-hosting for machine code)**
  (2026-06-23). The P8X can now edit a `.asm` file and assemble it to a runnable
  binary without the host. Four pieces, all TPA programs / BIOS-only, tested:
    - **Program-arg ABI:** `DORUN` enters a program with `P2` -> the command tail
      after the program name (`SKIPWORD` past the name+spaces), so
      `RUN EDIT FOO.ASM` hands `FOO.ASM` to the program; programs `RTS` to the
      shell. Test os_argv_test.sh.
    - **BIOS `FDELETE` ($011E):** tombstones a root file (flag -> $FF) so a file
      can be overwritten (FDELETE + FCREATE). Append-only jump-table slot.
      Test fdelete_test.sh. (Also fixed: FDELETE was clobbering the caller's
      FSRC via dead scratch — surfaced by ASM.)
    - **EDIT** (apps/p8xedit.asm): line editor, `RUN EDIT.BIN NAME` -> 12 KB
      LF-line buffer at $C000; L/A/I n/D n/W/Q/?. DELETE forward-copies the gap
      closed, INSERT opens it with DEP-based backward copy. Test os_edit_test.sh.
    - **ASM** (apps/p8xasm.asm): two-pass assembler, `RUN ASM.BIN SRC OUT`.
      Labels, equates, all operand shapes, LDPn pseudo, .org/.byte/.word/.ascii/
      .asciiz/.fill, $/decimal/'c'/symbol exprs with +/- and </>. Opcode table
      generated from genucode.OPC (generators/gen_p8xopc.py) and concatenated at
      build — can't drift from the microcode. P1=source cursor, P3=system stack
      untouched, errors long-jump to the OS via a saved SP. Output load/exec 0,
      which the OS maps to TPA base $B000 (DEFADDR in DORUN) so `.org $B000`
      programs are directly RUNnable. Test os_asm_test.sh assembles on-target,
      proves the bytes are byte-identical to the host assembler, and RUNs the
      result. run.sh installs /BIN/EDIT.BIN + /BIN/ASM.BIN on the demo disk.
      Remaining polish in IDEAS ("Native toolchain follow-ups").
- **BIOS file-operations upgrades — streams, paths, FNORM** (2026-06-23). Reworked
  the monitor FS layer from flat-root, whole-file calls into a proper file API:
    - **Read stream** `FOPEN` ($0124) + `FGETB` ($0127): sequential byte read over
      a caller-supplied 512 B buffer; refills sectors internally.
    - **Write stream** `FWOPEN` ($012A) + `FPUTB` ($012D) + `FCLOSE` ($0130):
      streams output to disk a sector at a time, FCLOSE registers the file.
    - **Path-aware** `FRESOLVE` ($0133): walks `/a/b` via the `.`/`..` tree to a
      directory extent + leaf; `FFIND`/`FOPEN`/`FCREATE`/`FDELETE`/`FCLOSE` all run
      in the resolved directory and revert to root after (so root-only callers
      like BASIC SAVE/LOAD are unaffected). Subdir LBAs assumed <256, like the OS CWD.
    - **`FNORM`** ($0136): string -> upper-cased, space-padded `FNAME`.
    - **Directory iteration** `FOPENDIR` ($0139) + `FNEXT` ($013C): list a
      directory's live entries (separate iteration state; skips deleted, stops at
      the end marker). Enables offloading the OS DIR/TREE/PACK to loadable programs.
    The assembler was migrated onto the read+write streams (−520 B; self-host
    still byte-identical). Jump table grew, so the monitor body moved $0130->$0160.
    Tests: fopen/fwrite/fresolve/fwrdir/fnorm/fnext (`make test-cf`); full suite green.
    Caught two real bugs (FCLOSE/COLD jump-table collision; FFIND wrapper carry).
    This supersedes the old "make BIOS file routines hierarchy-aware" idea (done).
    Remaining FS ideas: richer error status (an FERR byte vs the carry flag) —
    deferred until a consumer needs it; cluster allocation to retire PACK (v3);
    actually offloading the OS commands onto FOPENDIR/FNEXT.
- **P8XFS v1 retired — v2 is the only format** (2026-06-22). Removed all v1 (flat)
  support now that v2 is mature and on-target FORMAT exists. Monitor `F` now writes
  a v2 boot block + root extent at LBA 33 (inline `.`/`..` builder; host fsck
  confirms it byte-for-byte). `p8xfs.py create` defaults to v2 (the `--v2` flag is
  a no-op kept for compat); dropped the v1 constants, helper functions, and the
  v1 branches in create/put/get/ls/fsck. OS dropped the COLD version-detect (sets
  the v2 layout unconditionally), the `ROOTN==32` v1 guards in MKDIR/RMDIR/TREE/
  FSCK, the `MK_NOV2`/`MNOV2` reject, and the entire single-pass v1 PACK path
  (rename DOPACK2→DOPACK) — the OS shrank to 6967 B. Existing v1 cards no longer
  mount (acceptable — solo project, no v1 cards in use). Full suite green.
- **BASIC SAVE/LOAD + BIOS filesystem API** (2026-06-23). Added file-level calls
  to the monitor ROM — `$0118 FFIND` (find a root file -> start LBA + length) and
  `$011B FCREATE` (create a root file from a buffer: allocate at the free pointer,
  write data + a directory entry, bump free) — a shared P8XFS v2 root-file layer
  for BASIC, the OS, and any program (ABI: FNAME/FSRC/FLEN at $9D4A/$9D56/$9D58;
  CFWRSEC refactored to expose CFWRP1). BASIC gained `SAVE "NAME"` / `LOAD "NAME"`
  (tokens $97/$98) that round-trip the program through the filesystem in the ROM
  and disk builds. Tests: fs_bios_test.sh (FCREATE/FFIND round-trip + host fsck)
  and basic_saveload_test.sh (SAVE -> NEW -> LOAD -> LIST/RUN). Caught: FFIND
  clobbered FLEN during its scan, so FCREATE saves/restores the requested length.
- **On-target FORMAT (P8XFS v2)** (2026-06-22). Added the OS `FORMAT` command:
  asks Y/N, then rewrites the boot block (`P8`, version 2, free pointer 37) and a
  clean root extent at LBA 33 (4 sectors, `.`/`..`) by reusing the `MKDIR` extent
  builder (`MKEXT` with NEWLBA=PSL=33, PSN=4), and adopts the v2 layout in RAM
  (ROOTN/DATABASE/CWDL/CWDN + `PATHROOT`) so it lands exactly where `COLD` would
  after booting a fresh v2 card. **OSCNT is preserved** (read from the old boot
  block, kept across the rewrite), so the OS image at LBA 1–32 is untouched and
  the card stays bootable. ~288 B; the OS is now 7453 B (15 sectors) — would not
  have fit under the old $8000 14-sector ceiling, fits easily at $4000 (32). Test:
  `emulator/test/os_format_test.sh` formats a populated card, checks /OLD is gone
  + a fresh /NEW + on-target FSCK OK, and host-verifies the boot block (version 2,
  OSCNT preserved, free=41 after one MKDIR). Wired into `make test-os`.
- **OS load address moved to $4000 (rev D)** (2026-06-22). With rev D putting RAM
  at $4000, the monitor's `CMD_B` now loads the OS image (and disk BASIC) to $4000
  and JMPs there, instead of $8000. This lifts the boot ceiling from ~7 KB (14
  sectors) to **16 KB** (32-sector on-disk OS region; the RAM ceiling at $9D47 is
  ~23.8 KB), unblocking on-target FORMAT/editor/bigger programs. The BIOS ABI is
  untouched — `$0100` jump table in ROM, LBA `$9D47` and SBUF `$9E00` still in RAM
  — so only the load address changed. Changes: `CMD_B` ($8000→$4000), the OS's
  `.org` + `--base`, disk BASIC's `BASORG` ($8000→$4000); the emulator needed
  nothing (rev D already made $4000 RAM). os_test's self-check SAVE addresses
  moved $8000→$4000. Full suite (OS/OS-v2/BASIC-disk/CF/...) green. Docs swept:
  cf-os design, monitor + system-design, os/basic READMEs, programmer's guide.
- **Memory card rev D: 16 KB ROM + 48 KB RAM** (2026-06-22). Shrank the ROM
  window to `$0000–$3FFF` (16 KB; the 28C256 stays, only its low half is now
  addressed — monitor+BASIC end at $3307, well under 16 KB) and grew RAM to 48 KB
  (`$4000–$FEFF`) by adding a second 62256 (U10) at `$4000–$7FFF`. New decode from
  A15+A14: ROM `!CE=A15|A14`, U10 `!CE=NAND(!A15,A14)`, main RAM (U2) unchanged
  (`NAND(A15,-IOPG)`, $8000–$FEFF). It reuses spare gates in U7/U8 — **no added
  logic IC**; the only new parts are U10 + its 100 nF. Memory card is the *only*
  board that changed (backplane, CF, I/O, control, regbank, ALU untouched).
  Emulator memory map updated to match; **no firmware/OS change** — everything at
  $8000+ stays put, so the new `$4000–$7FFF` is just unused RAM for now. This sets
  up (but doesn't yet take) the future move of loading the OS lower to lift the
  14-sector boot ceiling. Test: `make test-mem` (write+readback of $5000). Full
  suite (ISA/CF/OS/BASIC/IO) still green. Docs: memory-card theory + README,
  cf-os design map, top-level README.
- **Multi-byte LBA in the CF BIOS ABI** (2026-06-22). CFREAD/CFWRITE were
  capped at 256 sectors (128 KB): CFSETL zeroed LBA1/LBA2. Widened to a 24-bit
  little-endian LBA at `$9D47..$9D49` (LBA0/LBA1/LBA2). `CFINIT` now zeros
  LBA1/LBA2, so the change is backward-compatible — legacy callers set only LBA0
  and the high bytes stay 0, meaning **no OS code growth** (the OS is at its
  14-sector boot ceiling). `CFSETL` reads all three bytes; the emulator already
  assembled a 24-bit LBA, so no emulator change was needed. Test:
  `emulator/test/cf_hilba_test.sh` reads sector 300 and writes sector 301 via the
  BIOS on a 512-sector image, proving LBA1 is honoured (no mod-256 wrap). The
  jump table at $0100 is unchanged — this is a compatible extension, not a
  reorder. (To address >8 GB you'd also drive LBA3 in CFHEAD; not needed.)

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
