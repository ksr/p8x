# P8X Project Backlog

Add ideas as they come; move items between sections as they progress.
Last updated: 2026-07-16

## How to use
- **NEXT** — committed, in rough priority order
- **IDEAS** — captured, not yet committed
- **VERIFY** — open questions / checks before trusting something
- **WONT-DO / SUPERSEDED** — settled decisions NOT to do something, kept so they
  are not re-litigated. Check here before starting anything that looks obvious.
- Completed work lives in **[BACKLOG-DONE.md](BACKLOG-DONE.md)** — the project
  log, plus every finished item lifted out of the sections above. Nothing here is
  done; if it is in this file, it is still live.

`[~]` marks a partially-done item: the finished part is described inline, the
remainder is why it is still here.

---

## NEXT

- [~] **Second CF drive — FULL DUAL-VOLUME core DONE (2026-06-27); cross-drive
      single-command copy deferred.** Landed (emulator + firmware + OS, hardware
      card deferred): two CF cards as equal read/write P8XFS volumes, each with
      its own current directory, `0:`/`1:` prefixes, a switchable current drive,
      drive 0 = boot/default.
      - **Emulator** (`a886a47`): `struct cf_state cf[2]`, `-c2 <img>`, ATA
        DEV-bit routing (`CFHEAD` bit 0), absent-device safe.
      - **Firmware** (`30f388b`): `DRVSEL` ORed into `CFHEAD` by `CFSETL`/`CFINIT`;
        `CFSEL` ($0148) / `CFCURDRV` ($014B) jump-table entries; bounded
        `CFWAIT`/`CFDRQ` (~4096 polls) so an absent drive times out, not hangs.
        `cf2_test.sh`.
      - **OS** (`dd7beb4`): `CURDRIVE` + a drive-1 CWD backing block; `SWITCHDRV`
        (swap working↔backing CWD, lazy `CFINIT` via a `DRVINIT` bitmask);
        `PARSEDRIVE` in `RV_START` (one-shot `N:` prefix → resolve from that
        drive's root); bare `0:`/`1:` switch (`CKDRIVESW`), `CD N:/dir`, prompt
        shows the drive; `SYS_SETDRIVE`/`SYS_GETDRIVE`. `os_dualvol_test.sh` (prefix
        + switch + isolation). Single-drive behavior byte-identical; full suite
        green.
      **Bulk cross-drive copy DONE — `IMPORT N:/dir` built-in.** Provisions a
      fresh card from a "master": walks the source directory (drive N) collecting
      its files, then for each one reads the whole file into a RAM buffer on the
      source drive and writes it into the CWD on the destination drive — flipping
      the ATA device bit between the read and the write of every file.
      `os_import_test.sh` (build a boot volume + a master with `/BIN/{ALPHA,BETA}`,
      `IMPORT 1:/BIN`, host-verify both land on drive 0 with exact content).
      **Root-cause fix that unblocked cross-drive I/O (emulator):** the CF model
      stored the LBA/feature task-file registers *per device* and routed writes to
      the currently-selected device. But `CFSETL` writes `CFLBAx` **before** it
      writes `CFHEAD` (the device-select), so on a drive switch the LBA landed on
      the *old* device and the newly-selected one executed with a stale LBA — the
      `dev=1 lba=0` / wrong-refill-LBA symptom that had blocked cross-drive copy.
      Real ATA has a **shared task-file bus** (both drives latch LBA writes; the
      DEV bit picks who runs the command), so the emulator now mirrors feature/LBA
      writes to both devices and routes only data/command to the active one. This
      is the same defect that stalled single-command `CP 1:/X 0:/Y`.
      **Firmware foundation (`152a51a`):** `CFSEL` lazy-`CFINIT`s a drive on first
      select (`CFIMASK`); BIOS read/write streams carry their own drive
      (`ROSDRV`/`WOSDRV`, captured by `FOPEN`/`FWOPEN`, re-asserted by
      `FG_FILL`/`FW_FLUSH`/`FCLOSE`). Full suite green; single-drive byte-identical.
      **SUPERSEDED (2026-07-08) by the Unix-style mount migration** (branch
      `mount-drives`, see `docs/mount-drives-design.md`). The `0:`/`1:` prefix
      model below was replaced by mounting drive 1 at `/D1` in one namespace: the
      drive decision moved into a single `FRESOLVE`/`RV_START` mount redirect, so
      `lib_drive.c` and all per-command prefix code were deleted and commands are
      drive-unaware (`CAT /D1/X`, cross-mount `CP /D1/A /B`). **This retires the
      filter-tool limitation** — `grep`/`wc`/`sed`/… reach `/D1` for free (they
      build absolute paths → `FRESOLVE`) with zero code growth, because no command
      parses a drive. The historical record of the `N:`-prefix work is kept below.

      **Inline `N:` prefix on `/BIN` commands — DONE for cat/dir/cp/mv/diff
      (2026-07-07).** New shared `lib_drive.c` (`hasdrive`/`pdrive`/`seldrive`
      over BIOS `CFSEL`) wired into the self-contained openers `catpath` (cat) and
      `dir`, and into `abspath` (cp/mv/diff). A path may carry a `0:`/`1:` prefix
      (`CAT 1:/X`, `DIR 1:/BIN`, `DIR 1:/*.C`), and `cp`/`mv`/`diff` take a prefix
      on **either** path — so single-command cross-drive `CP 1:/A 0:/B` works:
      each stream keeps its own drive (`ROSDRV`/`WOSDRV`) and the shell's
      per-command `SYNCDRV` means routing to the other card never leaks. The
      earlier revert failed only because of the emulator's per-device task-file
      bug (fixed with the shared-bus model); with that gone the per-stream
      approach is correct. `os_binprefix_test.sh` verifies `CAT`/`DIR`/`CP` across
      drives (and that `CP` doesn't leak onto the wrong card).
      **Deliberately excluded:** the stdin-filter tools (`grep`/`wc`/`head`/`tail`/
      `more`/`sort`/`uniq`/`sed`) share `lib_stdin`/`lib_globx`; the largest,
      `grep` (which also carries the `-r` tree walk), sits right at the TPA ceiling
      — its globals already overlap the `$EA00` FSDIRBUF page and it works only at
      its exact current size, so the ~1.2 KB of prefix code pushed it into its own
      `$FA00`/`$FC00` I/O buffers and corrupted `-r`/glob. Those tools follow the
      current drive (switch-then-run). Would need a size cut (or a per-command
      lib) to include them. **Also open:** drive-scoped `PACK`/`FORMAT`/`FSCK` act
      on the current drive via `DRVSEL` (no dedicated test); `find`/`tree` walk the
      current drive's CWD only (no path arg to prefix).

      Original scope note (superseded — we went full dual-volume, not read-only):
      keep a "master" CF holding core files (e.g. `/BIN` binaries) and, in the
      field with no host, provision a fresh card by copying from it — `FORMAT`,
      insert master, `IMPORT 1:/BIN`, done. Scope was to be **read-from-
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
    - **OS code size — 16 KB ceiling (rev E).** The boot loader (CMD_B) loads the
      OS to $2000 upward. The firmware/BIOS scratch sits at $6000 (monitor line
      buffer $6000, param/state block $6040, SBUF $6100), so the OS image must end
      **below $6000** — i.e. **16 KB** of RAM ($2000–$5FFF). This now matches the
      on-disk OS region (LBA 1–32 = 16 KB) exactly, so RAM and disk impose the same
      cap. The OS is ~9.5 KB today → ~6.5 KB headroom. (rev E dropped the OS to
      $2000 and the scratch/TPA −$1000, growing the TPA to ~37.9 KB.) BIOS
      scratch/SBUF/OS vars: LBA $6047, SBUF $6100, OS vars $6300.

- [ ] **History persistence (optional).** The history ring is RAM-only (cleared at
      cold start). If cross-session history is wanted, add explicit `history -w
      [file]` / `history -r [file]` (dump/load the whole ring in one FCREATE/FOPEN)
      rather than a per-command append — P8XFS is contiguous one-extent-per-file, so
      appending each command would rewrite+reallocate the file and churn the disk.

- [ ] **memmap: build-time regeneration.** `generators/gen_memmap.py` emits the
      committed `memmap.{inc,h,py}`. They must be re-run by hand after editing the
      canonical MAP. Follow-up: have `run.sh` / the Makefiles invoke `gen_memmap.py`
      before assembling/compiling so the generated files can never be stale (the
      "option 2" deferred when this landed). Low urgency — the table changes rarely.

- [ ] **memmap: fold the file-local temps in (full flat map).** `TMP`/`TMP2`/`CNT`
      are kept out of `memmap.inc` because firmware and the OS each define them at
      different addresses (a name collision). Forcing them in means renaming the OS
      side (`TMP` alone = 97 refs, 131 total) to unique names. Deferred as
      high-churn / low-value (they're working temps, not layout).

- [ ] **memmap: auto-single-source the compiler-emitted `.org`.** `apps/p8xcc.asm`
      and `compiler/p8cc.c` emit `.org $6A00` (= `TPABASE`) as literal text — they
      can't `.include memmap.inc` (their TPA buffers reuse OS-scratch names like
      `NAMEBUF`) nor interpolate a symbol into emitted text. `p8cc.py` already reads
      `memmap.TPABASE`. Options: rename the internal buffers to avoid the clash then
      `.include`, or teach the emit path to substitute the value. Pointer comments
      mark the coupling meanwhile.

- [ ] **Multi-stage pipes (`a | b | c`).** The shell's pipe state machine
      (`PIPEF`/`PIPESCAN`/`PIPE_RHS`) handles exactly **two** stages: it splits on
      the first `|`, runs the left into `PIPE.TMP`, then re-dispatches the right.
      The re-dispatch jumps to `DISPATCH` without re-scanning for `|`, so a third
      stage is swallowed as args of the second command. To support N stages,
      `PIPE_RHS` would need to re-run `PIPESCAN` on the remaining line (chaining
      temp files), or the splitter could iterate left-to-right. Until then,
      `CAT f | GREP x | WC` silently drops the `| WC`.

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

---

## IDEAS

- [ ] **`ln` command — symbolic links (2026-07-12).** Wanted: `ln /bin/dir /bin/ls`
      so `ls` runs `dir` (command aliasing, and general path aliasing). Design
      decided after analysis: implement as a **symlink**, NOT a hard link. The
      P8XFS v2 entry (`name12|startLBA4|len4|load2|exec2|flag1|spare7`, flags
      `$00`/`$01`/`$02`/`$FF`) has **no reference counting**, and `PACK` relocates
      extents by rewriting the single owning directory entry — so a hard link (a
      2nd entry sharing an extent) dangles the moment either name is deleted or the
      volume is packed. Making hard links safe = adding per-extent refcounts to the
      on-disk format + delete/PACK changes (a format change; rejected).
      Symlink plan: a new flag `$03` whose file content is the target path string.
      Work: (1) firmware `FRESOLVE` detects a `$03` leaf, reads its stored path, and
      re-resolves it (absolute, or relative to the link's directory) behind a depth
      counter (≤8) to break cycles — decide whether `FFIND`/`FOPEN` follow; this is
      the boot-critical, highest-risk piece. (2) `tools/p8xfs.py`: recognize `$03`,
      `ls` prints `ls -> dir`, optional host `ln` subcommand. (3) OS `DIR` shows
      `-> target`; `RUN` follows for free (loads via `FOPEN`). (4) new `ln` command
      C **and** asm twins (reuse `FWOPEN`/`FPUTB`/`FCLOSE`, set flag `$03`), man
      page, `os_ln_test`, `/src` tree + an `ln` target in the `/src/commands/*`
      Makefiles. NB: `cp /bin/dir
      /bin/ls` already aliases a command today, safely, at the cost of a duplicate
      binary — so `ln` is convenience, not a capability gap.

- [ ] **Move `tools/clib.py` -> `compiler/clib.py`.** clib.py is a C-toolchain
      preprocessing pass (the `//#use lib_*.c` splicer) — conceptually a sibling
      of `p8cc.py`/`p8cc.c` and the prototype of the future native CPP pass, not a
      disk/ROM utility like the rest of `tools/`. Grouping it under `compiler/`
      makes the toolchain legible. The `lib_*.c` files STAY in `os/commands/`:
      they're command-specific helpers and clib resolves `//#use NAME` to
      `lib_NAME.c` relative to the *source* dir. Low-risk but mechanical — update
      the `$ROOT/tools/clib.py` refs in `os/run.sh` and the ~8 `c_*`/`os_*` test
      scripts, plus doc mentions, then re-run the suite. Deferred (2026-06-26).

- [ ] **ISA additions to shrink program size** (2026-06-26). `p8cc` codegen is
      bulky partly because the ISA lacks ops the compiler emits constantly. The
      approach: histogram the generated asm, find the most frequent
      multi-instruction idioms, collapse each to one opcode — but **only where it
      shrinks *real* programs** (each opcode costs microcode/emulator/assembler +
      a `genucode.OPC` entry). Complements the codegen-improvement and asm-rewrite
      items — an ISA-level win that helps every compiled program at once.

      **Data-driven priority (measured on 5 compiled commands, 19,897 instrs):**
        - **Done — the move idioms (the big win):** `PHW`/`PLW` + `LPW1`/`LPW2`
          (pure microcode, −15.3%) and now **`MOVW`** (the mem→mem move, adds the
          PT2 scratch pointer — software done 2026-06-27, −3.6% more; hardware
          regen pending). See the PROTOTYPED note below and the MOVW item. 67% of
          instructions were `LDA`/`STA` (16-bit data shuffled byte-by-byte through
          A); the rev-D ops together are now ~−18–19% off compiled command size.
        - **DROPPED — generic memory inc/dec & 16-bit ALU (`INCM`/`DECM`/`ADDW`).**
          Originally floated, but arithmetic (`ADD`/`SUB`/`INC`/`DEC`) is only
          **1.1%** of instructions — new opcodes here would shrink real programs by
          a fraction of a percent. Not worth it for size; would only help speed in
          arithmetic-heavy code, which the text-tool workload isn't.
        - **PROMOTED — frame-relative addressing for local access (best remaining
          microcode-only lever).** `LDA __csp` appears **192×** — every local-var
          access has the compiler compute `local_addr = __csp + offset` inline
          (`LDA __csp … LDA __csp+1`, then load a pointer) right after each
          `JSR __enter`. Far more frequent than arithmetic. A targeted op —
          `LPW1 __csp,#off` (load P1 = the word at `__csp`+immediate offset), or a
          general `(Pn+disp)` load/store mode — would collapse these. Likely
          **pure microcode** (compute base+offset through the ALU into `PT`, then
          access — the ALU is free mid-instruction; no 2nd scratch pointer). This
          is now the **best remaining microcode-only lever** — `MOVW` (below) is
          done, so frame-relative addressing is the next size win to prototype.
        - **Hardware:** `MOVW`+`PT2` (separate item below) — the biggest single
          idiom, the only one needing a chip. **Software done 2026-06-27**
          (microcode/emulator/assembler/p8cc.py); register-bank schematic regen
          pending.

      **PROTOTYPED & MEASURED (2026-06-26):** an empirical histogram of 5 compiled
      commands showed 67% of all instructions are `LDA`/`STA` — 16-bit data moved
      one byte at a time through A. Three pure-microcode 16-bit ops were added and
      validated (full suite green, both compilers):
        - `PHW a` / `PLW a` (0x74/0x75) — 16-bit push/pop of a memory word, replace
          the compiler's `LDA/PHA/LDA/PHA` & `PLA/STA/PLA/STA` (push_ax/pop_t).
        - `LPW1 a` / `LPW2 a` (0x76/0x77) — load a 16-bit pointer from a memory
          word, replace `LDA a/TAP1L/LDA a+1/TAP1H` (ax_to_p1). Read-via-PT /
          write-to-Pn is sequential, so **no 2nd scratch pointer needed**.
        Measured on sed/sort/grep/dir/cat/wc: `PHW`/`PLW` alone **−12.1%**, plus
        `LPW1` (wired only into the central `ax_to_p1` site) **−15.3% total**
        (sed −16.9%, dir −17.2%). All pure microcode: opcodes + emulator runs the
        regenerated `u*.bin` directly + assembler gets them via `genucode.OPC`;
        only `genucode.py` + `p8cc.py` + `p8cc.c` changed. **Remaining to finish
        this op set:** convert p8cc.c's `LPW1` sites (only p8cc.py's central one is
        done) + the remaining inline/once-per-program `LPW1` sites in both, then
        update the ISA docs (opcode table in `docs/p8x-monitor.md`, the
        programmer's-guide PDF via `gen_progguide.py`).

- [ ] **Userland text tools — `awk`, `vi`, richer `find` (2026-07-08).** Wanted:
      more `/BIN` utilities. Findings from a build attempt:

      - **`awk` does NOT fit — blocked on codegen size.** Built a genuine minimal
        integer-only awk (rules/`BEGIN`/`END`, `/re/` + expression patterns,
        fields `$0..$NF`/`NR`/`NF`, `a`–`z` vars, `+ - * / %`, comparisons, `~`,
        `&& || !`, `print`/assignment/`if`). It compiles logically but the binary
        is **> 64 KB** — over the whole address space and **~2.3× the ~37.9 KB TPA**
        (`$6A00..$FE00`). 15,584 lines of asm from ~400 lines of C. Root cause is
        p8cc's non-optimizing codegen exploding the recursive `eval()` (16-bit ops
        expanded byte-by-byte); `grep` (much simpler) is already 32.5 KB at the
        ceiling, so any expression language is over budget. **Not a design flaw —
        blocked on program size.** Unblocked by the codegen/ISA-shrink work above
        (frame-relative addressing, finishing the `LPW1`/`MOVW` adoption) and/or a
        p8cc peephole/temp-reuse pass; or by a larger TPA (code overlays / bank
        switching). Revisit awk once compiled command size drops materially.
      - **`vi` — DONE (2026-07-08).** A minimal modal VT100 screen editor shipped
        as `os/commands/vi.c` (`RUN /BIN/VI.BIN NAME`). Unlike awk it has no
        expression evaluator, so it fits: ~18 KB code + a flat 150×80 line buffer
        = 30 KB total, ending `$EF6B`, below the `$FC00` read buffer. Reads keys
        raw via BIOS CONIN (`$0100`, no echo), drives the cursor with ANSI escapes
        (VT100 committed), and uses selective redraw (one line per char edit, full
        only on scroll) so it is usable at real serial baud, not just in the
        emulator. Commands: `hjkl 0 $ G i a A o x dd :w :q :wq :q!`, plus **`u`
        undo** (single-level, op-based — reverts the last x/dd/o/single-line
        insert, so it costs one saved line, not a whole 2nd buffer) and **`/`pat +
        `n` search** (literal substring, forward, wraps once) added 2026-07-08.
        The search+undo code grew the binary, so the line buffer was trimmed from
        150 to **110 lines** to stay below the `$FC00` read buffer; `os_vi_test`
        drives all of it headlessly. **Still future:** word motions (`w`/`b`),
        multi-level undo + redo, regex search, arrow-key escape parsing, and
        longer lines / bigger files. The capacity and multi-level-undo limits both
        point at replacing the flat fixed-width line array with a **gap buffer**
        (compact storage → more lines + cheap snapshots) — the natural next vi
        refactor.
      - **`find` already exists** (`os/commands/find.c`: `FIND pattern`, recursive
        name/glob/substring over the CWD tree). Enhancements if wanted: `-type f|d`,
        `-name`, `-exec`, or an `N:` path arg (it's one of the two — with `tree` —
        that still has no drive-prefix support). Small, in-budget.
      - **Regex `+` and `?` — DONE (2026-07-08); classes `[..]` blocked.**
        `lib_regex` gained `+` (one-or-more) and `?` (zero-or-one) single-char
        quantifiers, so `grep`/`sed` handle `colou?r`, `ab+c`, etc. (`c_filters`
        covers both). Adding them pushed grep's **host (p8cc.c) build** over —
        grep was already at the razor's edge where its globals overlap the
        `$EA00` (-r) / `$FA00` (glob) FNEXT iteration pages — so grep's `-r`
        buffer was trimmed 48→**36 files** and `line`/`cur` 256→176 to land the
        host build back below `$FA00`. **Character classes `[a-z]`/`[^..]` and
        `\` escapes did NOT fit** — even minimal buffers overflowed once the class
        code (variable-length atoms: atomlen/atomone) was added. They're the
        highest-value regex feature but are **blocked on grep's host-build size**,
        i.e. on the p8cc codegen-size work (ISA-shrink item above) or restructuring
        grep (e.g. splitting `-r` content-search into its own command to free
        grep's globals). vi search is still literal (would also need this).
      - **Fits-now alternative — a "field tool," not awk.** Drop the expression
        evaluator entirely: a `CUT`/`SELECT`-style filter — `/re/` or `$n OP num`
        pattern + a fixed field list to print (`{print $2 $4}`), no arithmetic /
        vars / `if`. No `eval()` ⇒ small enough to ship; covers the common awk use
        (field extraction + simple filtering). Reuses `lib_stdin` + `lib_regex`.

      **p8cc subset gaps confirmed while writing awk** (bite any ambitious command;
      note in the compiler docs): **no `break`/`continue`** (restructure loops with
      a flag / condition), and **no forward declarations or mutual recursion**
      (self-recursion is fine — write one self-recursive function, e.g. a
      precedence-climbing `eval(minbp)`, instead of `expr`↔`primary`).

- [~] **`MOVW dst,src` — 16-bit memory→memory move — SOFTWARE DONE (2026-06-27);
      register-bank hardware regen PENDING.** Opcode `$78`, shape `a,a` (5 bytes:
      opcode + dst16 + src16), 12 microcode steps. Landed: microcode (`genucode.py`
      `MOVW` + `PT2=5`), emulator (`P[6]`, PT2 init), assembler (`MOVW dst,src`
      two-operand encoder), and **`p8cc.py`** (a `mov16` helper at the two hot
      absolute→absolute sites — assignment-yields-value and int var-load). Measured
      on the /BIN commands: sort −833 B, grep −1106 B, sed −931 B (~3–5% each, on
      top of the −15.3% from PHW/PLW/LPW). Tested: `isa_wordops_test.sh` gained a
      MOVW round-trip (mem→mem via both scratch pointers); full suite green.
      Docs synced (ISA card + programmer's guide PDFs regen'd → 88 opcodes,
      system-design §9, bus-definition, regbank theory).
      **Two findings while doing it:**
        1. **No backplane change** — `PSEL` is already 3 bits (`PSEL0–2` on
           C20/C21/C27) and `U33` already decodes select 5. Confirmed against the
           regbank generator's exported bus set.
        2. **The register-bank hardware needs more than "+2 chips", and there's a
           latent gap:** `MOVW` increments BOTH scratch pointers, and the
           already-shipped `PHW`/`PLW`/`LPW` also `PINC` `PT` — but the current
           `PT` is load-only 74377 latches ("PT does not count"). So `PT` must
           become four 74169 counters, `PT2` is another four 74169s + a 74244
           buffer pair, and the count/load decoders (`U39`/`U40`) must produce
           `-CNT4/-CNT5` + `-LDL5/-LDH5`. ~10 chips, all on the regbank card, no
           backplane/control-card change. Documented in the regbank theory as
           rev-D PENDING. **The remaining work is the `gen_eagle.py` schematic
           regen + BOM + placement PDFs + DRC** — deliberately its own pass (canon
           generator, no DRC backstop; the project warns against rushing bus-facing
           schematic edits).
        3. **`p8cc.c` does NOT yet emit MOVW** — its codegen is P1-indirect
           (address-through-`__ax`), so it lacks the absolute→absolute idioms MOVW
           targets; benefiting would need a codegen refactor. p8cc.py (which builds
           every /BIN command) gets the win; p8cc.c adoption is a follow-up.
      Original analysis below.

- [ ] **`MOVW` register-bank hardware regen (rev D).** See the MOVW item above and
      the regbank theory rev-D note: turn `PT` into 74169 counters, add `PT2`
      (PSEL=5) counters + `-SEL5` buffers, extend `U39`/`U40` count/load decode.
      Regenerate `gen_eagle.py` → regbank `.sch/.brd`, `gen_bom.py`, the placement
      PDFs; DRC for one-hot pointer-bus drive. No backplane/control-card change.
      Also teach the on-target assembler (`apps/p8xasm.asm` + `gen_p8xopc.py`) the
      two-operand shape if MOVW is ever to be assembled on the target (host-only
      today; the opcode table and cover-test currently skip two-operand shapes).

- [ ] **(orig)** `MOVW dst,src` — 16-bit memory→memory move (needs a 2nd scratch pointer
      = HARDWARE) (2026-06-26). The single largest idiom from the histogram:
      `LDA src/STA dst/LDA src+1/STA dst+1` (~3,335 sites across the 5 commands),
      12 bytes that `MOVW dst,src` would collapse to 5. Deferred from the
      PHW/PLW/LPW prototype because, unlike those, it can't be done in pure
      microcode: a mem→mem move needs **two** addresses live at once (read src /
      write dst), but there's only one hidden scratch pointer (`PT`); `P1`/`P2`
      belong to the running program. And the pure-microcode shortcut (`LDAX`/`STAX`
      on a fixed pseudo-accumulator) is impossible because `__ax` is a per-program
      label, not a fixed address microcode could name. So `MOVW` requires:
        - **Hardware:** a second hidden scratch pointer `PT2` (PSEL=5) — one more
          74169 counter pair + extend the register-bank PSEL decode (74138 U33,
          currently decodes 0–4) to output 5. ~2 chips; PSEL is already 3 bits so
          the control word needs no change. `PT2` would also enable future
          two-address ops. Nothing's fab'd, so this is free to design now.
        - **Emulator:** widen `P[]` to 6 entries (P[5]=PT2); psel is already 3-bit.
        - **Assembler:** a two-operand absolute shape `MOVW dst,src` (the parser
          currently handles a single `a` operand).
        - **Compiler:** a `movw(dst,src)` helper replacing the scattered inline
          `LDA/STA/LDA/STA` mem→mem moves, mirrored in p8cc.py + p8cc.c.
      Microcode sketch (12 steps, fits the 16-step budget): load dst→PT2, src→PT
      (4 steps each via the `_ld_pt` pattern), then 2× (read mem[PT]→T, PT++; write
      T→mem[PT2], PT2++). Projected to stack on top of the −15.3% already measured,
      plausibly reaching the 25–40% total from the original analysis. The one item
      in the ISA-shrink program that needs hardware — do it as a deliberate
      hardware decision, after the pure-microcode ops above are banked.

- [ ] **Emulator: optional real-clock-pace mode** (2026-06-26). `p8xemu` currently
      runs as fast as the host (bounded only by `-l` cycle cap or TTY blocking).
      Add a mode that throttles execution to the hardware's actual clock rate so
      timing, I/O pacing, and the interactive feel match the real machine — useful
      for sanity-checking that programs aren't relying on host speed, demoing at
      realistic speed, and validating any future timing-sensitive I/O. Needs the
      target clock frequency as a parameter and a host-time pacing loop (sleep to
      align cycle count to wall-clock); keep it opt-in so the test suite stays
      fast. Cross-check against the planned hardware clock once a board exists.

- [ ] **Hardware changes enabling "deep" (multi-step) instructions to assist the
      ISA** (2026-06-26). The current microcoded engine sequences each instruction
      through control-store steps; richer instructions (block moves, deeper
      addressing modes, the ISA additions above) may need more microcode steps or
      wider control than the present sequencer/step-counter and control-word
      budget allow. Explore the hardware mods that would unlock longer/deeper
      microprograms: a wider step counter, more control-word bits (spare backplane
      lines exist — see `SPARE12–SPARE23`), or a second-level sequencer. Since no
      board is built yet, this is free to design now. Tie the scope to whichever
      ISA additions (item above) prove worthwhile, so the hardware serves real
      instructions rather than speculative ones.

- [ ] **Disassembler (reverse assembler): point it at an address block, get
      assembler back.** A tool that walks a memory/file region and decodes each
      byte stream back into P8X mnemonics + operands — the inverse of `p8xasm`.
      Counterpart to the on-target ASM (#43); together they round-trip code on
      the machine (DUMP shows hex, this shows instructions). Sketch:
      - **Core:** a single opcode→(mnemonic, addressing-mode, length) table —
        ideally *generated from the same source the assembler/emulator use* so it
        can't drift (the ISA table is canon; don't hand-maintain a second copy).
        Linear sweep from the start address: read opcode, look up length, format
        the operand per its mode (`#imm`, `$abs`, `$zp`, relative-branch target
        as `$abs` so output re-assembles), advance, repeat.
      - **Output:** re-assemblable text — emit a leading `.org`, optional `addr:
        bytes` columns (like a listing), and resolve branch displacements to
        absolute targets. Round-trip test: `disasm` a known `.bin`, re-`p8xasm`
        it, assert byte-identical (the strongest correctness check).
      - **Where:** start as a **host tool** (`tools/p8xdis.py`, fast to iterate +
        easy round-trip test in `make test`), then optionally an on-target `/BIN`
        program (`disasm.c`) once the table can be shared — pairs with DUMP for
        on-machine reverse-engineering. Caveat: pure linear sweep mis-decodes
        data interleaved with code (no control-flow tracing) and can't recover
        labels/comments — acceptable for a v1; a later pass could follow branches
        to mark code vs. data.

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
      **Progress (2026-07-09):** TREE was already a `/bin` command. **DUMP and DEP
      offloaded** — they need only `peek`/`poke` + a console key (no FS state), so
      they became `os/commands/{dump,dep}.c` + byte-identical hand-asm twins, run
      by bare name via PATH; the kernel shrank ~400 bytes. **FSCK** (~392 asm
      lines, read-only via `$010C CFREAD`) and **PACK** (~832 asm lines,
      filesystem-*mutating* via `$010F CFWRITE`) remain resident: both are
      feasible on the current BIOS (raw sector I/O is exposed) but each would be a
      large C + hand-asm reimplementation, and PACK is delicate enough (a bug
      corrupts a card) that kernel residence is defensible. Revisit FSCK next
      (safe, read-only); treat PACK as opt-in.

- [~] **`/src/os-bios/asm` — OS + monitor sources on-card (partial, 2026-07-11).**
      The OS + BIOS-monitor asm sources now ship under `/src/os-bios/asm` with a
      `bin` output dir, and `make os-bios` (script `/src/mk/os-bios`) assembles
      both. Browsing works; blocker #2 (subdir-source read) is now FIXED, so a
      subdir source of any size streams correctly (the 58 KB monitor assembles
      on-target, standalone or under `sh`/`make`). Both original blockers are now
      fixed:
        1. **>64 KB files — FIXED (2026-07-12, branch `feature/24bit-filesize`).**
           The BIOS file length is now **24-bit** (`FLEN`/`FSAV`/`ROREM`/`ROCNT`/
           `WOTOT`/`FLAREM`), matching `ROLBA` — max file 16 MB. The FS scratch
           block was reflowed for 3-byte length fields (all callers + `sh` read-
           stream save/restore updated), and the read AND write math widened
           (`FSCAN`/`FNEXT`/`FOPEN`/`FGETB`/`FG_FILL`/`FLOADAT`; `FWOPEN`/`FPUTB`/
           `FCLOSE`/`FCOM_CORE`, 16-bit sector count for >255-sector files). No
           on-disk format change (the entry already stored 4 length bytes).
           Verified: 66–70 KB files read + write round-trip byte-identical
           on-target (`os_bigfile_test`), and an on-target assemble resolves a
           label living past the 64 KB source mark (was `?undefined`). So the 121 KB
           `os/p8xos.asm` now assembles on-target — though it's slow in the emulator
           (~wall-time bound, minutes). `PACK`/`FSCK` are 24-bit too (OS `SECCOUNT`
           → 16-bit `SECCNT:SECCH`; `del`+`pack` relocates a 66 KB file byte-intact
           in `os_bigfile_test`). `dir`'s size column and `wc`'s counts are 24-bit
           too (byte-wise divmod10 in both twins). See `firmware/WIDE_FILELEN.md`.
           Nothing about 24-bit file lengths remains open.
        2. **Subdirectory source read empty / over-read — FIXED (2026-07-12).**
           ROOT CAUSE (found via emulator memory-watch on `FLEN`/`ROREM` + an LBA
           trace, `apps/p8xasm.asm`): the size/`sh`/`LINEBUF` theories were all
           wrong. The startup sequence resolved the source path
           (`FRESOLVE` → `DIRLBA`=parent, `FNAME`=leaf), then called `FFIND` to
           confirm it exists — but `FFIND` ends in `FRESET`, reverting `DIRLBA` to
           the root. `SAVESRC` ran *after* `FFIND`, so it recorded the source's
           directory as **root**, not the real parent. Each pass, `PASSINIT` →
           `RESTSRC` restored `DIRLBA`=root and `FOPEN`→`FFIND` scanned root for the
           leaf, found nothing, left `ROREM`=0, and streamed a **0-byte** output.
           A root-level source worked only because its parent *is* root. Under
           `sh` the empty read then over-read one sector into the adjacent script
           file, surfacing as `?syntax: pwd` — which mislabeled the bug as
           size/`sh`-dependent. FIX: call `SAVESRC` *before* `FFIND` so it captures
           the resolved parent dir. Guard: `os_asm_test.sh` check (4) assembles a
           source in `/src/os-bios/asm/` and requires byte-identical output to the
           same source at root.

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

- [ ] **BASIC: name the line on the other runtime errors too.** A runtime
      `?SYNTAX ERROR` now reports its line (`?SYNTAX ERROR IN 100`) via the
      `RUNNING` flag + `CURLINE`. Extend the same to `?UNDEF'D LINE` (`run_undef`)
      and `?RETURN WITHOUT GOSUB` — both have their own handlers that print a
      bare message and would benefit from `IN <line>`. Small, mechanical: reuse
      the SYNERR pattern (check `RUNNING`, read the line number from `CURLINE`,
      `PRDECU`).

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

---

## VERIFY

- **Register bank: address bus floats for PSEL = 6, 7** (2026-06 review; updated
  rev D). U33 (74138) is always enabled; in rev B/C only PSEL 0-4 are populated
  (P0-P3 + PT), and the address drivers U25/U26 are always on, so unpopulated
  codes drive an undefined value onto A0-15. **Rev D adds PT2 at PSEL = 5** (MOVW),
  so 5 is now a real driver — only 6, 7 remain undriven. Safe ONLY if microcode
  never emits PSEL > 5 (PT2 = 5 is the max in rev D). Confirm the constraint, or
  add a default-select / pull so the bus can't float.

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

- [ ] PSU sizing — measure actual draw at bring-up vs the 4–5 A budget. ESTIMATE
      (~130 HCT chips + ~52 LEDs): HCT dynamic draw at a few MHz is a handful of
      mA/chip → ~1 A logic; LEDs (bus-monitor arrays via 330R + status LEDs via
      1K) ~0.3–0.4 A; memory/ACIA ~0.1 A ⇒ **~1.5 A typical, ~2 A worst case** —
      comfortable margin under 4–5 A. Confirm with a meter at bring-up.

---

## WONT-DO / SUPERSEDED

Decisions already made and deliberately not being revisited. Each was reached
with real analysis; the full reasoning is in
[BACKLOG-DONE.md](BACKLOG-DONE.md) under the entry named.

- **Do NOT make p8cc's `<` `>` `/` `%` signed.** It looks like a bug and is not.
  p8cc has no `unsigned` type, so the codebase uses `int` AS an unsigned 16-bit
  value for every size/offset/count and depends on the unsigned compare/divide.
  Acting on this (from a CODE_REVIEW finding) shipped a BUFFER OVERFLOW that the
  full 87-test suite passed — cmp.c counts past its 8K buffer deliberately, and a
  signed `<` made a 40000-byte file write b1[40000] into an 8192-byte array
  (reverted, 88ba592). The real fix is adding `unsigned` to the subset and
  migrating every size onto it — a language feature, not a bug fix.
  `>>` is separately fine to leave: every shipped use is masked (`(v >> 8) & 255`).

- **Do NOT chase the last ~3.4% of native-cc code size** (temp reuse, peephole
  fusion such as `MOVW __ax,V` + `PHW __ax` -> `PHW V`). It needs lookahead /
  buffering in a single-pass emit-as-you-parse compiler, which grows cc.bin
  (already 22.6 KB of the ~37 KB TPA, and it must fit WHILE compiling) and risks
  the miscompile class the code review found. The cheap wins are all taken —
  wc.c is 4617 instructions vs p8cc.py's 4467. Revisit only if a real command
  misses the TPA by a few KB. See "C compiler — Milestone A/B".

- **Rejected paths for the on-target codegen wall** (from the Milestone B
  analysis): sharding the existing optimizing codegen — the shared infra defeats
  it; a bigger flat memory region — tops out ~46 KB, still short of the ~82 KB
  needed, so it would require banking (major firmware/OS/hardware work). The
  answer was a NEW deliberately-small codegen (`apps/p8xcc.asm`), which exists.
  The earlier cpp|lex|cc1 split front end is deprecated and no longer shipped.

- **Milestone A is self-ACCEPT, not self-compiling.** p8cc.c cannot compile
  itself and this is not a near miss — its own source (61,337 B) is twice its own
  `src[32768]` buffer, and it has 780 string literals against `soff[64]`. The
  property built and tested is that the subset accepts its own source
  (`p8cc.py p8cc.c`). Do not "fix" the [64] tables to chase it: they are latent
  for every real workload (heaviest command, vi, has 39 globals vs the 64 limit).
