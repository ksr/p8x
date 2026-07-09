# P8X Project Backlog

Add ideas as they come; move items between sections as they progress.
Last updated: 2026-07-08

## How to use
- **NEXT** — committed, in rough priority order
- **IDEAS** — captured, not yet committed
- **VERIFY** — open questions / checks before trusting something
- **DONE** — kept for the project log

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
    - **OS code size — ~12 KB ceiling (after the 2026-06-26 memory remap).** The
      boot loader (CMD_B) loads the OS to $4000 upward. The firmware/BIOS scratch
      now sits low (monitor line buffer $7000, param/state block $7040, SBUF
      $7100), so the OS image must end **below $7000** — i.e. **~12 KB** of RAM
      ($4000–$6FFF). (Before the remap the scratch was at $9D40, giving ~23.8 KB
      of RAM headroom; the remap traded that down to grow the TPA to ~31.6 KB.)
      The on-disk OS region is still LBA 1–32 (16 KB), so RAM is now the tighter
      cap. The OS is ~8.5 KB today → ~3.5 KB headroom. BIOS scratch/SBUF/OS vars
      moved with the remap: LBA $7047, SBUF $7100, OS vars $7300.



- [ ] **Multi-stage pipes (`a | b | c`).** The shell's pipe state machine
      (`PIPEF`/`PIPESCAN`/`PIPE_RHS`) handles exactly **two** stages: it splits on
      the first `|`, runs the left into `PIPE.TMP`, then re-dispatches the right.
      The re-dispatch jumps to `DISPATCH` without re-scanning for `|`, so a third
      stage is swallowed as args of the second command. To support N stages,
      `PIPE_RHS` would need to re-run `PIPESCAN` on the remaining line (chaining
      temp files), or the splitter could iterate left-to-right. Until then,
      `CAT f | GREP x | WC` silently drops the `| WC`.

- [x] **Minimal-kernel split: move the pure-viewer built-ins to /BIN.**
      **DONE 2026-06-25** — removed the `DIR`/`PWD`/`TREE` built-ins from the OS
      (`DODIR`/`DENT2OS`/`DPRENT`, `DOPWD`, `DOTREE`, their dispatch + keyword
      strings + HELP lines + `MDIRHDR`/`MDIRTAG`); they now run from `/BIN` by
      bare name (`dir.c`/`pwd.c`/`tree.c`, installed by `os/run.sh`). OS shrank
      ~7977→7350 bytes. **`DUMP` kept native** — as a `/BIN` program it would load
      into the `$B000` TPA and overwrite the very memory it's asked to dump (its
      most common use). `TR_PUSH`/`TR_POP`/`READCUR` stayed (shared with
      FSCK/PACK). Tests reworked: `os_test` installs `/BIN/DIR.BIN`; `os_v2_test`
      installs `/BIN/{DIR,PWD,TREE}`; `os_format_test` verifies the post-FORMAT
      tree host-side (no typed DIR); `os_basic`/`os_argv`/`os_lineedit` use native
      sentinels (`MKDIR`/`HELP`) instead of the moved commands. Consequence
      remains: a freshly-`FORMAT`ted card (no `/BIN`) can't `DIR` until `/BIN` is
      repopulated (host, or the future second-CF master). Original analysis below.

      Built-in CAT is already gone (2026-06-24): bare `CAT file` falls
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

- [ ] **Move `tools/clib.py` -> `compiler/clib.py`.** clib.py is a C-toolchain
      preprocessing pass (the `//#use lib_*.c` splicer) — conceptually a sibling
      of `p8cc.py`/`p8cc.c` and the prototype of the future native CPP pass, not a
      disk/ROM utility like the rest of `tools/`. Grouping it under `compiler/`
      makes the toolchain legible. The `lib_*.c` files STAY in `os/commands/`:
      they're command-specific helpers and clib resolves `//#use NAME` to
      `lib_NAME.c` relative to the *source* dir. Low-risk but mechanical — update
      the `$ROOT/tools/clib.py` refs in `os/run.sh` and the ~8 `c_*`/`os_*` test
      scripts, plus doc mentions, then re-run the suite. Deferred (2026-06-26).

- [x] **Wildcards on the filters — wc/grep/sort/sed/head/tail/more/uniq — DONE
      (2026-06-27, see DONE).** Made `lib_stdin` glob-aware: `openarg` expands a
      `*`/`?` arg via `lib_globx` and `nextc()` reads all matches as one
      concatenated stream, so every `//#use stdin` command got globs for free
      (`GREP x *.C`, `SORT *.TXT`, `WC *.LOG`). Unblocked by the TPA remap (~31.6
      KB) + the ISA-shrink (~−24%); needed a `clib.py` recursive-`//#use` change
      and a bump of `p8cc.c`'s 16 KB source buffer to 32 KB (sed's spliced source
      is ~17 KB). Full suite green.
      **Still open:** `DEL *.TMP` (destructive OS built-in in `p8xos.asm`, not a
      `/BIN` command — needs the shell-level/asm `gmatch`+`FNEXT` path) and the
      `CP`/`MV` multi-source-into-a-directory idiom (separate item below).

- [x] **`cp -r` (recursive copy) — DONE (2026-07-08); retired `IMPORT`.** `cp`
      gained `-r`: it recurses a directory tree (collecting each level's entries
      before descending, since the FNEXT cursor is global) and works across the
      `/D1` mount (`CP -r /D1/SRC /SRC`) — each file's read/write stream keeps its
      own drive. Needed a new **`SYS_MKDIR` syscall** ($4021, factored from
      `DOMKDIR` as `MKDIRCORE`) so a `/BIN` program can create directories. This
      **superseded the `IMPORT` built-in** (flat, one-level, drive-1→CWD), which
      was removed — the kernel shrank ~534 bytes. `os_cprecursive_test` covers
      single-file, same-drive `-r`, and cross-mount `-r` with nesting.
      cp/mv **wildcards** are now done too (see below). The `-r` iteration page
      sits at `$A000` (just above cp's code), giving ~40 levels of recursion headroom
      before the descending stack could reach it — deep enough for any real tree,
      but there is no explicit depth cap.

- [x] **`CP`/`MV` wildcards — `CP *.ASM /BAK`, `MV *.TMP TRASH/` — DONE
      (2026-07-09).** Went with per-command inlined glob (option 2): a `*`/`?`
      source is expanded via `lib_globx`'s `glob_expand`, and each match is copied/
      moved INTO the destination, which must be an existing directory (each lands
      at `<dst>/<basename>`; `cp -r` copies a matched subtree). Both the C builds
      (`cp.c`/`mv.c`, `//#use globx`) and the hand-asm builds (`cp.asm`/`mv.asm`
      via new `lib_globx.inc`) implemented and verified byte-identical. Adding
      globx doubled cp's C binary, so `cp`'s `copy_tree` FSDIRBUF page moved
      $A0 → $E0 (clear of the enlarged image). Also added **`TOUCH`** the same
      day (C + hand-asm). No shell-level expansion was needed.

- [x] **ASM vs C commands — hand-wrote ALL heavy `/BIN` utilities — DONE
      (2026-07-08, see DONE).** The prototype-one-command experiment turned into a
      full sweep: all 17 `/BIN` commands now have hand-written P8X assembler
      counterparts in `os/commands-asm/`, each verified byte-identical in behavior
      to its `p8cc` build and installed to a parallel `/BINA` on the demo disk.
      Overall ~2.3× smaller, up to 5.8× (mv/pwd). See DONE.

- [x] **Make OS/BIOS peek/poke a syscall ABI instead of fixed addresses**
      (2026-06-26; DONE 2026-07-07). The C `/BIN` commands used to reach BIOS
      scratch by hardcoded `peek`/`poke` of fixed addresses — FNAME `$704A`,
      FFLAG `$7070`, FLEN `$7058`, entry LBA `$7047/$7048` — which is what made
      the `$B000→$7A00` remap expensive (~30 sites across `dir`/`tree`/`find`/
      `grep`/`lib_globx`/`p8lib` moving in lockstep with the firmware EQUs).
      Resolved with the "current dir-entry accessor" option rather than one getter
      per field: two OS syscalls —
      - **`SYS_DIRENTRY` ($401B)**: copy the entry FNEXT (or FFIND) just matched
        into a caller buffer as a 17-byte snapshot — name[12], flag, len(2),
        LBA(2). One JSR + 17-byte copy per entry replaces ~5 scattered peeks.
      - **`SYS_OPENDIR` ($401E)**: begin iterating a subdirectory whose 16-bit
        start LBA is passed in P1 — replaces the `poke($7048)/poke($7049) +
        FOPENDIRAT(A=low)` idiom used to descend.

      New shared lib `os/commands/lib_dirent.c` (`//#use dirent`) wraps them as
      `de_read()/de_isfile()/de_isdir()/de_isdot()/de_len()/de_lba()/de_opendir()`
      with a `de[17]` buffer. `dir`/`find`/`grep`/`tree`/`lib_globx` converted;
      `p8lib.c`'s `loadfile()` reads its length via `SYS_DIRENTRY` too. Zero
      hardcoded scratch addresses remain in the commands — the firmware can now
      relocate FNAME/FFLAG/FLEN/LBA without touching a single command. Verified by
      the existing dir/tree/find/grep command tests (which now exercise both
      syscalls, including recursion via `SYS_OPENDIR`) + full suite.

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
        is **> 64 KB** — over the whole address space and **~2.3× the ~28 KB TPA**
        (`$7A00..$EA00`). 15,584 lines of asm from ~400 lines of C. Root cause is
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

- [x] **Recursive content search — `GREP -r pat`: match file CONTENTS by regex
      across a directory tree — DONE (2026-06-27).** Implemented as a `-r` flag on
      `grep` (Unix-familiar, reuses `lib_regex`'s `match()`). Two-phase to respect
      the global FNEXT cursor: phase 1 walks the CWD tree depth-first (same
      recursion shape as `FIND`/`DIR -R`, FSDIRBUF page `$EA`) collecting every
      file's absolute path; phase 2 opens each (`open_path` from `lib_stdin`) and
      greps it, printing hits as `path:line`. Capped at 48 files (frees C-stack —
      grep -r ends `$E877`, ~9 dir-nesting levels of recursion headroom under the
      `$F800` stack). Tested in `c_filters_test.sh` (root file + `/DOCS/D.TXT`
      subdir, both compilers). Original analysis kept below.

      The right home for regex, as
      distinct from name-matching: glob (`*`/`?`) is for file *names* (what `dir`
      and `find` already do); a **regex** is for the *search string* you look for
      inside files. This tool combines `find`'s tree walk (FNEXT recursion +
      `lib_globx`/`FSDIRBUF`) with `grep`'s regex matcher (`lib_regex`) — for each
      file under the CWD, open it and print matching lines prefixed with the path
      (`path:line`). Effectively `grep -r`. The pieces already exist as shared
      libs (`lib_regex` + the find/dir recursion), and there's TPA room now, so it
      mostly composes. (Decide: extend `grep` with a `-r` flag that walks, or a
      separate `RGREP`/`FIND … -e pat` — leaning `GREP -r` for Unix familiarity.)
      Note: this is why `find` itself stays name-glob only — regex lives where the
      content is.

- [x] **`TOUCH name` command — DONE (2026-07-09).** Unix `touch`: creates each
      named file empty if missing (FWOPEN+FCLOSE, zero bytes), leaves an existing
      file untouched (NOT truncated). Shipped as `os/commands/touch.c` and the
      hand-asm `os/commands-asm/touch.asm`, verified byte-identical, on a
      CWD-resolved absolute path like the other file commands. **Still future:**
      once the **DS1302 RTC** lands (see IDEAS) and P8XFS entries carry an mtime,
      extend it to bump the timestamp of an existing file (the classic behaviour;
      P8XFS has no timestamps yet).

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
- [x] **Hierarchy-aware BIOS file routines — DONE (2026-07-09).** Resolved in two
      parts. The *resolver* already exists: **`$0133 FRESOLVE`** (FS upgrade 3)
      walks a path through the `.`/`..` entries and sets the target directory +
      leaf `FNAME`, so `FFIND`/`FCREATE`/`FOPEN` run in that directory. What was
      left was the flat *clients*: BASIC `SAVE`/`LOAD` and the data-file `OPEN`
      called `FFIND`/`FCREATE`/`FNORM` with no `FRESOLVE`, so they were root-only.
      **Retrofitted them to FRESOLVE the name** (`GETPATH` reads a case-preserved
      path, `SETFNAME` resolves the string), so `SAVE "/SRC/GAME"` and
      `OPEN "/LOGS/A"` reach subdirectories while a bare name still means root.
      Design decision (open question (a)): the **BIOS stays stateless — no CWD in
      the ABI**. A current directory is shell/OS state (it would add shared mutable
      state to a re-entrant ROM and has no meaning at boot), so clients resolve
      absolute/root-relative paths; the OS owns the CWD. `basic_savepath_test`
      covers root + subdir round-trips (program and data file).
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
- [x] **Man-page-style OS command reference — DONE (2026-07-09), on-target.**
      Went further than the doc-only plan: authored a per-command manual page
      (NAME / SYNOPSIS / DESCRIPTION / OPTIONS / EXAMPLES / SEE ALSO) for every
      `/bin` command AND every OS built-in in `os/man/`, installed to `/man` by
      `run.sh`, and added a **`man` command** (`os/commands/man.c` + byte-identical
      `os/commands-asm/man.asm`) so `man dir` prints `/man/dir` on the machine.
      HELP lists `man`; `os_man_test` covers it. **Still future:** a `man -k`
      apropos/keyword search, and a `SEE ALSO`-driven index page.
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
- [~] **C compiler — Milestone A DONE (self-compiling, host-run); Milestone B
      FRONT END self-hosted on the P8X (cpp|lex|cc1); back end stays host-side
      (codegen won't fit the TPA — see the measured finding below).** Both
      compilers exist and are tested:
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
      - **Multipass driver / separate pass binaries.** If the compiler won't fit
        one TPA pass, split it into staged `/BIN` binaries driven through temp
        files (like early Unix `cc` → `cpp`/`cc1`/`as`). The **source preprocessor
        is naturally the first pass**: `tools/clib.py` (the host `//#use` splicer,
        added 2026-06-26) is the prototype for that native pass — a C rewrite of
        it (reading via BIOS `FOPEN`/`FGETB`, writing the combined source) becomes
        the on-target `CPP.BIN`. So `clib.py` is a host-era convenience that this
        milestone subsumes, not a throwaway.
      - **Pass 1 — CPP.BIN DONE (2026-07-09).** `os/commands/cpp.c` (→ `/bin/cpp.bin`)
        splices `//#use` on-target; its output compiles **byte-identical** to the
        `clib.py` path (`os_cpp_test`). Single read stream → cpp emits libs ahead
        of the source (compiles the same; p8cc orders by symbol table) and calls
        `FSDIRBUF` so file-opens don't clobber a redirected write stream (the SBUF
        read-scan vs write-partial conflict `cp -r` also hit). C-only (a compiler
        pass, no asm twin). Sizing reality that shapes the rest: `p8cc.c` compiles
        to **~72 KB** vs a ~32 KB TPA (~46 B/line), so the front/back split needs
        the **codegen-shrink first** (frame-relative locals / MOVW) — even the
        parser alone overflows today. Next: shrink, then the CC1/CG split. KNOWN
        LIMIT: P8XFS's 12-char names block storing `lib_abspath.c`/`lib_readline.c`
        on-card for on-target preprocessing (rename or widen FS names).
      - **Codegen-shrink step 1 — DONE (2026-07-09).** Added `__ldw`/`__ldb`
        (load local word/byte) and `__stw`/`__stb` (store local) runtime helpers
        + a `var = expr` fast path (scalar local via `__stw`, global via `MOVW`),
        so a local read is `JSR __ldw ; .word off` instead of `__lea` + 4 loads,
        and a scalar store skips the old address→AX→P1 round-trip. **p8cc.c's own
        compiled asm: 30372 → 25383 lines (−16.4%)** (~72 KB → ~60 KB). Applied to
        **`p8cc.py` only** — the compiler binary is host-built by p8cc.py, so this
        shrinks it without touching `p8cc.c`; the self-host differential test is
        behavioural (same program output), so it still passes. Mirroring to
        `p8cc.c` (so the ON-target compiler emits the same tight code) is a
        deferred refinement, not needed to fit the binary. Next: reduce the
        binary-op `PHW/PLW` (779×) and revisit `__push` (1157×), then the split.
        NOTE: this makes the `os/commands-asm` size scoreboard stale (p8cc builds
        are now smaller) — regenerate it.
      - **Codegen-shrink step 2 — `__entf` (2026-07-09).** Fold each function's
        inline frame-alloc into `JSR __entf ; .word localsize`. Only +0.9% (most
        functions have no locals — params need no frame), total now **−17.2%**
        (30372 → 25157 lines, ~59 KB). PLATEAU: the remaining bulk is structural —
        `__push` (1157×, call args) and `PHW/PLW` (779×, binary-op operand stack)
        resist peephole shrinking, and the front end (lex+parser+symtab, ~70% of
        the source) would still be ~40 KB after a 2-way split — over the ~32 KB
        TPA. So fitting needs EITHER a bigger structural rewrite (an accumulator/
        temp scheme to kill the per-op stack traffic) OR a **3-way split**
        (lex | parse | codegen, each ~⅓ ≈ 20 KB) through two temp files. Decide
        the direction before more peephole work — it's low ROI from here.
      - **Split direction chosen: 3-way (lex | parse/cc1 | codegen/cg).** The
        toolchain becomes `cpp | lex | cc1 | cg`, each a `/bin` binary chained
        through temp files (like early Unix `cpp`/`cc1`/`as`). Temp files carry
        text formats between passes so each is independently testable against a
        host reference (`p8cc.py --tokens`, later `--ir`).
      - **Pass 2 — LEX.BIN DONE (2026-07-09).** `os/commands/lex.c` (→
        `/bin/lex.bin`, ~10.9 KB) tokenizes a (preprocessed) C source on-target
        and emits the token stream `<line> <T> <payload>` (T = K/I/N/S/O/E). Its
        output is **byte-identical** to the new host reference `p8cc.py --tokens`
        (`dump_tokens`) — verified by `os_lex_test` on a mixed-token source AND a
        ~1900-token real source. Streams via the BIOS read stream with a one-char
        pushback (no whole-file buffer). Line counting matches p8cc.py to the
        letter (only top-level newlines count; block-comment newlines don't). Char
        literals emit as `N` (byte value); keyword set matches p8cc's lexer.
        C-only (a compiler pass, no asm twin). NEXT: **CC1** (parse token stream →
        IR) needs an IR text format + a `p8cc.py --ir` reference, then **CG**
        (IR → asm). The parser+symtab is the ~70%-of-source risk; getting it under
        the TPA on its own is the crux of the whole split.
      - **IR format designed + host-validated (2026-07-09).** The pass-2→pass-3
        boundary is the **AST** (not a lower three-address IR): cc1 = parse token
        stream → serialize AST; cg = deserialize AST → the existing codegen (Gen).
        This keeps the whole type/symbol/struct analysis in ONE pass (cg, mirroring
        p8cc.py's `Gen`) instead of splitting it. Format: a whitespace-separated
        pre-order atom stream (`<tag>` + fields; lists = `<count>` + nodes; options
        = `0` | `1 <node>`; type triple = `<base> <ptr> <count>`, count -1 = infer;
        byte string = `<len>` + decimal bytes). Added `p8cc.py --ast` (serialize)
        and `--from-ast` (deserialize → Gen) as the references. PROVEN lossless:
        `--ast | --from-ast` is **byte-identical** to direct compilation across all
        23 command sources AND `p8cc.c` itself (85 KB AST). NB p8cc.c is single-pass
        (emits asm while parsing, no AST), so cc1/cg aren't a mechanical split of it
        — the AST layer is introduced fresh, following p8cc.py's two-phase shape.
        NEXT: cc1.c (emit AST, byte-identical to `--ast`), then cg.c (AST → asm,
        matching `--from-ast`).
      - **Pass 3 — CC1.BIN DONE (2026-07-09).** `os/commands/cc1.c` (→
        `/bin/cc1.bin`, ~29.5 KB) parses a LEX token stream into the serialized
        AST. Recursive descent mirroring p8cc.py's `P`, emitting the AST as it
        parses (no whole-program tree). Two tricks make streaming work: (1) infix
        operators (`a+b`, `a=b`, `a[i]`, `a.b`) parse the left operand before the
        tag is known, so cc1 splices the tag in front of it with an in-buffer
        `einsert()`; (2) since an einsert only reaches back within one expression,
        eb[] is flushed at every statement boundary — the buffer holds at most one
        statement, so cc1 handles functions far larger than the TPA. Output is
        **byte-identical** to `p8cc.py --ast` — verified on-target by `os_cc1_test`
        (the real `lex | cc1` chain) and, during development, via a gcc build of
        cc1.c against `--ast` across all 24 command sources AND p8cc.c itself.
        Wire format switched from count-prefixed lists to `;`-terminated lists so
        the append-only write stream needs no seek-back. Purely syntactic; all
        type/symbol/struct analysis is deferred to cg. C-only (no asm twin).
        Sizing: cc1.bin ~29.5 KB fits the TPA ($7A00+29.5K < $F800) with ~2.7 KB
        headroom.
      - **CG DOES NOT FIT — measured (2026-07-09).** The codegen cannot run
        on-target as one pass, and a simple cg+runtime split doesn't rescue it:
          * full p8cc.c compiles to ~82-96 KB (won't even ASSEMBLE — the assembler
            has a hard 64 KB address ceiling and p8cc.c overflows it). Earlier
            "~59 KB" was wrong.
          * moving the runtime-helper emitters (emit_add..emit_lea, string-literal
            heavy) OUT of the compiler saves only ~14 KB (→ ~82 KB).
          * the NON-walk infrastructure alone — symbol tables + type analysis +
            emit primitives + globals/struct/toplevel — is ~55 KB. It is SHARED by
            every part of codegen, so sharding the expr/stmt walk (only ~18 KB)
            into sub-passes doesn't help: each shard still needs most of that 55 KB.
          vs a 31.5 KB TPA, codegen is ~2.5-3x too big and cannot be cleanly cut.
        CONCLUSION: porting the existing optimizing p8cc codegen to run within the
        TPA is not viable.
      - **DECISION (2026-07-09): ship the self-hosted FRONT END; stop at cc1.**
        `cpp | lex | cc1` all run on-target and each fits the TPA, so the P8X can
        natively preprocess, tokenize, and parse C to an AST. Code generation
        stays host-side (p8cc.py / p8cc.c). This is the coherent, finished shape
        of Milestone B given the codegen wall. A true on-target back end would be
        a SEPARATE future milestone — a NEW, deliberately-small codegen written to
        fit 31.5 KB (NOT a port of the optimizing p8cc; the ~55 KB shared infra
        makes a port impossible). Filed below as a stretch goal, not blocking.
        Other rejected paths: sharding the existing codegen (the shared infra
        defeats it); a bigger flat memory region (tops out ~46 KB, still < 82 KB —
        would need banking, i.e. major firmware/OS/hardware work).
      - [ ] **STRETCH (future milestone): a NEW minimal on-target codegen (cg).**
        Not a port of p8cc's optimizing back end — a from-scratch, size-first
        code generator that reads the cc1 AST stream and emits correct (not
        optimal) asm within the 31.5 KB TPA. It reuses the proven front end
        (cpp|lex|cc1) and the on-target assembler; the host p8cc.py/p8cc.c stay
        the reference. Verification would be BEHAVIORAL (compile a program
        on-target, run it, diff output) since its asm won't match p8cc byte-for-
        byte. Chief risk: the symbol-table + type-analysis + emit machinery must
        be written FAR more compactly than p8cc's ~55 KB. Only worth starting if
        true end-to-end on-target compilation becomes a priority.
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
- [x] **BASIC string-valued variables** — DONE (2026-07-09). `A$`-style
      variables (16 fixed 32-byte slots), assignment, `+` concatenation,
      `=`/`<>`/`<`/`>`/`<=`/`>=` comparison in `IF`, `PRINT`/`INPUT` of strings,
      and `LEN`/`ASC`/`CHR$`/`LEFT$`/`RIGHT$`/`MID$`. `STR$`/`VAL` deferred.
- [x] **BASIC data files** — DONE (2026-07-09). One sequential channel over the
      BIOS byte streams: `OPEN name$ [FOR] OUTPUT|INPUT`, `PRINT#`, `INPUT#`,
      `CLOSE` (root files; one value per CR record). No `EOF()` test yet.
- [x] **BASIC: check syntax on line entry, not just at RUN** — DONE (2026-07-09)
      via `CHECKLINE` (option (a): a lightweight structural validator — legal
      statement leader, balanced parens, terminated strings; forward line
      references stay runtime). Original notes below.
      Today entering a
      program line runs `CRUNCH` (tokenizes keywords in place) and stores it
      (`DOLINE`, ~p8xbasic.asm:1821) with no grammar validation — a malformed
      statement (`10 PRINT )`, a bad expression, a missing operand) is only
      caught later when RUN reaches that line, so you can type a whole program
      and not learn line 10 is broken until it executes. Add an entry-time
      syntax pass so an error is reported immediately, against the line just
      typed, with the line still on screen to fix. Options: (a) a lightweight
      validator that walks the crunched line confirming each statement's shape
      (keyword + well-formed operands/expression) and rejects on the spot; or
      (b) reuse the real statement/expression parser in a "check, don't execute"
      mode (no side effects — no variable writes, no I/O) so entry-time and
      run-time grammar can't diverge — (b) is more code but keeps one source of
      truth. Print the usual `SYNTAX ERROR` (SNERR) with the column/offset if
      cheap. Keep it entry-only: don't try to resolve `GOTO`/`GOSUB` targets or
      undefined variables at entry (those are legitimately runtime). Interactive
      immediate-mode lines already execute (and error) at once; this is about
      the *numbered* lines that are stored deferred.
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

- **ASM vs C commands — hand-coded assembler versions of all 17 `/BIN` commands**
  (2026-07-08). What started as "prototype one heavy command to calibrate" became
  a full sweep: every `/BIN` command was rewritten by hand in P8X assembler under
  `os/commands-asm/` (`pwd mv more sed head wc uniq cat dir tree vi grep tail sort
  cp find diff`), each a drop-in replacement (same `$7A00` entry, same `P2`
  arg-tail ABI, same OS/BIOS calls) and verified **byte-identical in behavior** to
  its `p8cc` build in the emulator (`compare.sh`/the behavioral harness), not just
  assumed. Result: **~2.3× smaller overall**, ranging from 1.4× (diff) up to 5.8×
  (mv) / 5.4× (pwd) — see the scoreboard in `os/commands-asm/README.md`. `run.sh`
  installs the hand builds to a parallel **`/BINA`** (via `mkasm.sh` + `p8xasm.py
  --base 0x7A00`) alongside the C `/BIN`, so the two can be run and compared
  on-target (`RUN /BINA/GREP.BIN` vs `RUN /BIN/GREP.BIN`). This is the concrete
  data behind the "reach for asm where a command is size-pressured and stable"
  question (grep/sed/vi sit at the TPA ceiling on the C codegen). The C sources
  stay as the primary builds + `p8cc` regression corpus.

- **Wildcards on the stdin filters** (2026-06-27). Made `lib_stdin` glob-aware so
  `wc`/`grep`/`sort`/`sed`/`head`/`tail`/`more`/`uniq` all accept a `*`/`?` arg:
  `openarg` expands it via `lib_globx`'s `glob_expand`, and `nextc()` reads the
  matched files back-to-back as ONE concatenated stream — identical to
  `CAT *.X | cmd`, no per-command logic (`GREP foo *.C`, `SORT *.TXT >OUT`,
  `WC *.LOG`). `wc` also gained file-arg support in the process. Enabled by the
  recent headroom (TPA → ~31.6 KB after the remap, programs ~−24% after the
  ISA-shrink ops) — the glob machinery (~12 KB) now fits in every filter. Two
  supporting changes: `tools/clib.py` made recursive (`lib_stdin` declares
  `//#use globx`, which declares `//#use glob`, deduped) so a lib can pull its own
  deps; and `compiler/p8cc.c`'s source buffer bumped 16 KB → 32 KB (`slurp` cap
  too) because sed's clib-spliced source is ~17 KB and silently truncated under
  the host bootstrap. New `c_filters` glob assertions (`WC *.LOG`, `GREP key
  *.LOG`); full suite green (53 PASS) on both compilers. (`DEL`/`CP`/`MV`
  wildcards remain — they're OS-builtin / multi-source, see IDEAS.)

- **Removed ROM-resident BASIC** (2026-06-26). BASIC was overlaid into the
  monitor EEPROM at `$2000` and launched by the monitor `X` command (DONE #9).
  Since it also ships as the disk program `/BIN/BASIC.BIN` (same source,
  `basic/p8xbasic.asm`), the ROM copy was redundant; stripped it to reclaim ROM
  space and simplify the program ROM to just the monitor + BIOS (~4.3 KB,
  ends ~`$1100`; the chip is otherwise erased). Removed: the monitor `X`
  command + `BASIC` equate + the `X` line from the in-ROM help (kept `?`/`H`);
  `tools/build_basic_rom.py` (the monitor+BASIC overlay builder); the stale
  `p8x-rom-basic.{bin,hex}`. `tools/build_rom.sh` and `os/run.sh` now assemble
  the monitor directly; `emulator/test/basic_rom_test.sh` became
  `mon_test.sh` (monitor D-paging + `?` help smoke test) and
  `basic_saveload_test.sh` now boots **disk** BASIC (`B`) instead of ROM BASIC
  (`X`). Docs swept (monitor ref, memory maps, basic/rom/tools/firmware READMEs,
  the BASIC guide, system-design + hardware maps). Full suite green. This is a
  first step toward the larger memory-map repack (see the TPA-expansion notes).

- **`CAT *.glob` multi-file concatenation + FSCAN/write-stream firmware fix**
  (2026-06-26). `cat` now expands a glob argument into multiple files: a new
  shared helper `os/commands/lib_globx.c` (`glob_expand(pat, out, maxn)`, pulled
  in by `//#use globx`, which depends on `lib_glob`'s `gmatch`) iterates the
  pattern's directory (or the CWD via `SYS_OPENCWD`) and returns the matching
  *file* paths; `cat` streams each in turn. So `CAT *.ASM` and, crucially,
  `CAT *.ASM >ALL.TXT` work. The hard part was the redirect case: a write stream
  is already open, and every file's `FRESOLVE` walks the directory through
  `SBUF` — the same buffer the write stream uses — so the first version
  overwrote each file's buffered output with directory bytes (`.   BBB`). Root
  fix in **firmware**: `FSCAN` (the engine behind `FRESOLVE`/`FFIND`/`FOPEN`)
  now reads directory sectors into the repointable `DIBUFH` page (the one
  `FSDIRBUF`/`FNEXT` already use) instead of a hardcoded `SBUF`; `DIBUFH`
  defaults to `$9E`=`SBUF` at COLD boot, so every caller that doesn't repoint it
  is byte-identical. `cat` points `FSDIRBUF` at `$FA` (a high-TPA scratch page,
  clear of the `$FC00` read buffer and the code below it), so its per-file path
  walks leave the open write stream's `SBUF` intact. This is the general
  enabler for *any* glob-expanding command that redirects to a file (future
  `wc`/`grep`/`sort`). Both compilers; `c_cat_test.sh` gained glob + glob-redirect
  assertions; clib.py wired into the cat-compiling sites (`os_v2`, `c_pipe`,
  `c_stdin`; `os_append` already had it). Full suite green.

- **Regex factored to `lib_regex.c`; sed gained regex** (2026-06-26). grep's
  basic-regex matcher (`match`/`matchhere`, the `. * ^ $` dialect) — long flagged
  as a future shared helper — is now `os/commands/lib_regex.c`, pulled in by
  `//#use regex`. grep de-inlines it (no behavior change). **sed's `s///` is now
  a regex** on the left side (was literal `matchat`): `matchhere` gained a global
  `rend` (match end) so sed replaces the whole matched span; sed handles a leading
  `^` (anchor to col 0), `$` is in the matcher, `*` is non-greedy, zero-length
  matches are skipped. Tests: `c_filters` (grep, unchanged) + `c_textutils` (sed
  `.`/`*`/`^`), both compilers. Gotcha hit & documented: a `*/` inside a C comment
  (a regex example like `s/a*` + `/`...) closes the comment early — reword.

- **DIR wildcards (glob) + `lib_glob.c`** (2026-06-26). `DIR` filters by a glob
  when the path's last component has `*`/`?`: `DIR *.ASM`, `DIR /BIN/*.BIN`,
  `DIR -R *.C` (case-insensitive). New shared `lib_glob.c` (`gmatch`, a
  self-recursive `*`/`?` matcher in grep's style) via `//#use glob`; dir.c splits
  the path into dir + pattern and filters entries (recursing all subdirs under
  -R). Because dir.c gained `gmatch` its `p8cc.c` build grew to `$E31D`, past the
  `$E000` FSDIRBUF page — same collision class as sed/diff — so dir/tree/find's
  FSDIRBUF moved `$E0` → `$E8` (clears the bigger code, keeps ~5 KB for their
  recursive stack). Test `c_dirglob_test.sh` (both compilers). Phase 2 (other
  commands / shell-level expansion) is in IDEAS.
  - **FIND glob mode** (2026-06-26): `FIND` now `//#use glob`s too — if its
    pattern has `*`/`?` it `gmatch`es, else the original substring (so `FIND *.C`
    works, `FIND BIN` still substring). find already walked+matched, so it was a
    near-free fit. (find's `p8cc.c` build is ~14.2 KB ending `$E796`, so its
    FSDIRBUF page moved `$E8` → `$EA` for margin.) Tested in `c_findiff_test.sh`.

- **sed/diff on the native `p8cc.c` — was a buffer collision, not a miscompile**
  (2026-06-26). For months `sed`/`diff` built with `p8cc.c` (host) misbehaved on
  a file argument, filed as a "file-arg parse miscompile". The real cause: the
  shared file read buffer was hardcoded at `$E000` (only ~12 KB above the `$B000`
  TPA base), and `p8cc.c`'s codegen is ~8% larger than `p8cc.py`'s — so the two
  biggest commands overran it (host `sed` ends `$E333`, `diff` `$F4C9`) and
  `FGETB` read file data into their own code. Fix: moved the read buffer to
  `$FC00` (just under the stack page) in `lib_stdin.c`/`cat`/`cp`/`mv`/`diff`.
  Both now build+pass on **both** compilers; dropped the `p8cc.py`-only guards in
  `c_textutils`/`c_findiff`. This also closes the last gap for Milestone B (every
  `/BIN` command compiles correctly on the native compiler). Watch `diff`'s
  headroom (~17.6 KB on `p8cc.c`).

- **`>>` append redirection** (2026-06-26). The shell now appends a command's
  stdout to a file with `>>` (programs and built-ins). P8XFS extents are
  contiguous (no in-place growth), so it's copy-then-extend: stream the existing
  file's bytes into a fresh write stream, then the command's output, then
  `FCLOSE` registers it over the old entry (old extent → `PACK`). `REDSCAN`
  parses `>>` (sets `REDAPP`); `DORUN` (programs) and `FLUSHRED` (built-in
  capture) both prepend the old bytes via a shared `APCOPY` using **raw
  `CFREAD`s** into `APBUF`, not the read stream. KEY fix vs. the 2026-06-25
  attempt: every redirect target is resolved with `FFIND` *before* `FWOPEN` — an
  `FFIND` after `FWOPEN` scans through the write stream's unflushed `SBUF` and
  corrupted the output (the "< in >> out reads a directory sector" bug; the
  original attempt also read into `$E000`, which overlaps the loaded program).
  Test: `emulator/test/os_append_test.sh`.

- **Shared-source helper convention for /BIN commands** (2026-06-26). Reusable
  helpers are now shared by concatenation instead of copy-paste. A command opts
  in with a `//#use NAME` directive; the build step `tools/clib.py` splices in
  `os/commands/lib_NAME.c` ahead of the source before `p8cc` (no `#include`/
  linker needed, both compilers see the same combined source). First library:
  `lib_stdin.c` (`path`/`fromfile`/`nextc()`/`openarg()` — the file-or-stdin
  input pair), adopted by `grep`/`head`/`tail`/`more`/`sort`/`uniq`/`sed` (was
  duplicated in all 7). Wired into `run.sh` and the `c_filters`/`c_pager`/
  `c_textutils` harness; spliced text goes above `main()` so callees precede
  callers (stays in the `p8cc.c` subset). See `os/commands/README.md` "Shared
  code".

- **16-bit directory LBAs — directories at LBA ≥ 256 usable** (2026-06-25).
  The whole directory-LBA path used 1-byte cursors, so a directory whose
  4-sector extent started past sector 256 was truncated to its low byte:
  `CD` into it + `DIR` iterated the wrong sector (garbage), and creating files
  inside it corrupted the volume. The volume free pointer is 16-bit, so one
  high byte per cursor suffices. Widened across two layers:
  - **firmware/p8xmon.asm**: `DIRLBA`/`DILBA` gain high bytes; FSCAN, FNEXT,
    FRESOLVE, FRESET, COLD, FCREATE carry + 16-bit-increment their sector
    cursors; `FOPENDIRAT` takes a 16-bit LBA (A=low, `LBA1`/$9D48=high).
  - **os/p8xos.asm**: `CWDL`/`SDIRL`/`STARTLO`/`DLBA`/`NEWLBA`/`PSL`/`RMDL`/
    `CURLBA` gain high bytes through FINDENT/FINDSLOT/DESCEND/DIREMPTY/MKDIR/
    MKEXT/SAVECORE/LOADF/CD/FORMAT; the scanners restore an "LBA1=0 at rest"
    invariant so boot-block reads stay correct. New syscall `SYS_OPENCWD`
    ($4012) opens the CWD with its full 16-bit LBA.
  - **PACK + FSCK**: the shared tree-walk (`CDST`+`TFRAME` frames 3→4 bytes,
    `READCUR`, `CHKDD`), `PK2FIND`/`PK2MOVE`/`PK2FIX`/`PK2DD`, and
    `NF`/`MINSTRT`/`PPSEC`/`PARST`/`FMAXE`/`FUSED`/`FREE` are all 16-bit, so
    PACK relocates high extents byte-exact and FSCK reports correctly. (This
    was a pre-existing 8-bit limit affecting any extent ≥256, files included.)
  - **os/commands/{dir,tree,find}.c**: use `SYS_OPENCWD` for the CWD and record
    16-bit child LBAs (poking the high byte into `LBA1`) for `-R`/recursion.
  - Tests: `os_bigdir_test.sh` (create/CD/DIR/SAVE at LBA≥256) and
    `os_bigpack_test.sh` (DELETE→PACK relocates a high dir+file across sector
    256; on-target FSCK OK + host fsck + byte-exact `get` of the moved file).

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
