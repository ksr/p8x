# P8X Project Backlog

Add ideas as they come; move items between sections as they progress.
Last updated: 2026-07-22

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

> **THE BOARD HAS TWO STALENESS SURFACES; A FEATURE MAY NEED BOTH.** The
> BITSTREAM carries the CPU, microcode, monitor ROM and graphics RTL
> (`build.sh lcd load`); the SD CARD carries the OS, `/bin` and BASIC
> (`tools/imgsend.py`). The ellipse spanned RTL *and* BASIC, and updating only
> the bitstream left the hardware understanding a command nothing could issue --
> `?SYNTAX ERROR` from a BASIC that could not parse it. Check both.
>
> **And check `p8x_cpu.fs`'s MTIME after a build.** This has hidden two separate
> failures (a 48/46 placement failure, and a multiply-driven `st` net). `build.sh`
> itself now stops correctly -- `set -euo pipefail` plus an explicit `exit 1` on
> each of synthesise / P&R / pack, so `load` is unreachable after a failed build.

- [x] **BASIC now honours the OS current directory (fixed 2026-08-13).** From the
      OS shell, `cd src` then `basic` then `SAVE "T"` used to write `/T`; it now
      writes `/src/T`.
      - **Cause:** the BIOS resolvers (`FRESOLVE`/`FOPEN`/`FOPENDIR`) always start
        at the **root**. `/bin` commands prefix the CWD first (`lib_apath.c`'s
        `abspath`); BASIC made no OS calls at all, so every name resolved from `/`.
      - **Fix:** `APATH` in `basic/p8xbasic.asm` — prefixes `SYS_GETCWD` ($2003)
        onto any path not starting with `/`, wired into `SAVE`, `LOAD` and the
        `OPEN` data-file path. Gated on `MONITOR` being non-zero, so the disk-boot
        build (no OS underneath, root already correct) compiles it to a no-op
        without needing conditional assembly.
      - **Also fixed the same day: `BYE` no longer reboots the OS.** It did
        `JMP MONITOR` = `$2000` = the OS COLD entry, so leaving BASIC reprinted
        the banner and reset the CWD to the root. It now restores the entry stack
        and `RTS`es to the shell, as every `/bin` program does. `os_basic_test.sh`
        had been asserting the banner appeared *twice*, i.e. encoding the reboot
        as the pass condition; that expectation is inverted now.
      - **Regression test:** `emulator/test/basic_cwd_test.sh`, in `make test-basic`.
        It checks the file lands in the subdirectory, does **not** also land in the
        root, and that an absolute path still works — and was confirmed to FAIL
        against the unfixed BASIC, so it actually detects the bug.
- [~] **FPGA build (Tang Nano 20K) — MILESTONES 0-4 DONE (2026-08-12); clock-up
      and IRQ remain.** A standalone FPGA P8X running the same microcode and the
      same unmodified monitor/OS/toolchain. Parallel track to the TTL build, not
      a replacement. See [fpga/README.md](fpga/README.md).
      - **Done:** first light (UART echo); the CPU core co-simulated against the
        emulator cycle-for-cycle across all 88 opcodes; ACIA + driven console with
        console output diffed; the core on real hardware with the full 64K map;
        SD-over-SPI behind the `$FF10..$FF17` CF task file, with P8X/OS booting
        from a microSD and running the whole `/bin` toolchain. P8X is in the
        board's flash, so it comes up standalone on power.
      - **Milestone 5 — clock up.** Currently **9 MHz**: the fabric runs at 27 MHz
        and a microcycle takes three phases, because it needs two *dependent*
        block-RAM reads (the microcode word first, since its PSEL field picks the
        pointer that drives `mem_addr`, then the memory byte). Fmax is ~50 MHz, so
        there is a lot on the table. Options: overlap the two reads by pipelining
        the microcode fetch a cycle ahead; drop to two phases; or raise the fabric
        clock with a PLL. Any change must still diff clean against the emulator
        (`fpga/sim/run.sh` x3) — that is the regression test.
      - **Milestone 5 — IRQ.** `irq_set` is currently tied low in
        `fpga/tang-nano-20k/rtl/p8x_top.v`. The core already implements the rev-C
        forcing-buffer entry ($08 injection, vector $0808, EI/DI/RTI) and
        `isa_test.asm` exercises it in simulation; it just needs a real source
        wired up (timer and/or the ACIA).
      - **Milestone 6 — graphics display for BASIC.** A 4.3" Sipeed 480x272 RGB
        panel, driven only by new BASIC statements (`LINE`, `COLOR`, `BOX
        fill/nofill`) — NOT a text console, so no font ROM, no `PUTC` hook and no
        OS changes; serial stays the console.
        - **Geometry is forced by block RAM.** 6 spare blocks = 12288 bytes;
          480x272 needs 16320 at even 1 bpp, so the panel resolution does not fit
          at any depth. The framebuffer is **240x136 at 2 bpp** (8160 bytes, 4
          blocks, 2 spare), pixel-doubled to fill the panel with square pixels.
          Four pens index a 12-bit RGB palette. 8 colours (3 bpp) would cost all 6
          remaining blocks and straddle byte boundaries; 16 colours at full
          resolution is an SDRAM project.
        - **The drawing engine is in the DEVICE**, not in software: BASIC loads
          registers and writes a command byte. Spends the resource there is spare
          (12.7k LUT4) instead of the one there is not. A full-screen fill is ~1 ms
          instead of ~180 ms, and BASIC never has to mask sub-byte pixels.
        - **DONE: the emulator models it** (`$FF20-$FF26`, `p8xemu -g/-G`,
          `make test-gfx`), which is the golden model the RTL gets written against.
          Two rules are load-bearing and pinned by `test/gfx_test.sh`: endpoints
          are INCLUSIVE, and off-screen pixels are DISCARDED rather than clipped
          (coordinates are bytes, and `y*60 + (x>>2)` would otherwise fold x>=240
          onto the next row).
        - **The bus card is the SAME device (2026-08-14).** The planned physical
          card is a Tang Nano 20K plus this same 4.3" panel, so resolution,
          command set, RTL core and golden model are shared; only the front-end
          differs (internal CPU bus vs. an external bus interface). That kills the
          earlier worry that a smart engine was affordable on the FPGA but not in
          TTL — there is no TTL engine to build. Command set is settled and
          modelled: PLOT/LINE/BOX/BOXFILL/CLS/SETPAL/CIRCLE/CIRCLEFILL/POINT plus
          SELFTEST/RESET/IDENT, with a "PG" presence signature and an IDENT record
          carrying the geometry. Coordinates are 16-bit pairs (a low-byte write
          clears its high byte) so 480x272-over-SDRAM stays reachable without a
          protocol change.
        - **Card hardware, still open:** the P8X bus is 5 V TTL and the Nano is
          3.3 V, so the interface needs level translation on D0-D7 (bidirectional)
          plus the address/control inputs — `74LVC245`-class parts. Address decode
          is the standard I/O-page detect from `docs/p8x-card-standards.md` plus
          A7..A4 = `0010`. The bus write strobe is asynchronous to the Nano's
          27 MHz, so it needs synchronising, and per-IC 100nF decoupling applies
          as on every card.
        - **DONE: the BASIC statements (2026-08-14).** `COLOR pen`, `CLS`,
          `LINE x0,y0,x1,y1`, `BOX x0,y0,x1,y1[,FILL|,NOFILL]` — tokens `$A5-$AA`,
          covered by `emulator/test/basic_gfx_test.sh`. Three things that are not
          obvious: `NOFILL` HAS to be a real keyword (with `FILL` tokenised and
          `NOFILL` not, CRUNCH matches `FILL` inside the word and an outline
          silently comes out solid); `CLS` needs the `GPEN` RAM shadow because
          `GCOL` is write-only in the device, so the pen cannot be read back and
          restored; and `FILL`/`NOFILL` had to be added to `CKLEAD`'s blacklist or
          a bare `FILL` line would be accepted as a statement.
        - **DONE: the RTL (2026-08-14).** `fpga/rtl/gfx.v` (registers, drawing
          engine, framebuffer, palette) + `fpga/rtl/video_rgb.v` (480x272 timing,
          2x-doubled scanout). `fpga/sim/gfx.sh` byte-compares the frame the RTL
          produces against `p8xemu -g` for both payloads: **identical**.
          Fits the board: **BSRAM 44/46**, Fmax 49 MHz, and NO PLL (9.009 MHz
          wanted, 27/3 = 9.000 delivered by the divider the CPU already uses).
        - **The BUSY contract, learned the hard way.** The emulator draws
          instantaneously; the RTL takes roughly 9 ms for a full fill, and a command
          written while another runs ABORTS it. Software MUST poll GSTAT bit 7.
          Code written against the emulator alone looks perfect there and draws a
          few scattered pixels on the RTL -- which is exactly what the first frame
          diff showed. BASIC now has GWAIT/GEXEC and the payloads call GWAIT before
          every command; the poll is free when BUSY is never set, so one binary is
          correct on both. This is also why graphics cannot be CYCLE-diffed: a
          program polling GSTAT legitimately reads different values on the two
          models, so the framebuffer is the thing that must agree.
        - **DONE ON HARDWARE (2026-08-16).** `build.sh lcd load`, then `I`/`B`/
          `basic`, and BASIC draws on the panel. Pinout and timings verified from
          Sipeed's own 480x272 example (CLK 77, DEN 48, R 38-42, G 32-37,
          B 27-31; 560x297 at 9 MHz = 54.11 Hz; DE-only, no HSYNC/VSYNC).
          BSRAM 44/46, Fmax ~48 MHz, no PLL.
        - **Two display bugs, both invisible in simulation:**
          1. `fb_data >> ((2'd3 - ax[2:1]) << 1)` -- a shift AMOUNT is
             self-determined in Verilog, so it evaluated in TWO bits and gave
             shifts of 2,0,2,0 instead of 6,4,2,0. Every pixel in the left half
             of a byte was invisible and every pixel in the right half drawn
             twice. Same class as the `px_row` truncation.
          2. the framebuffer inferred as TRUE dual port, which halves a Gowin
             block's depth: 8 blocks instead of 4, 48/46, would not place. It now
             shares ONE port with the engine holding one cycle in three. Writing
             the shared read with two destination registers is NOT synthesisable
             as block RAM (falls back to 1020 RAM16SDP4); one read register
             feeding both is, at the cost of a pipeline stage.
        - **A STALE `p8x_cpu.fs` can be reprogrammed without anyone noticing** --
          that hid the 48/46 failure for two rounds. The script's own guards are
          now correct (see the note at the top of this file); what is left is the
          shared bitstream FILENAME between the `cpu` and `lcd` targets. Check
          `p8x_cpu.fs`'s mtime if a fix appears to do nothing.
        - **Test gap that let bug 1 through, now closed:** `tb_video` checked
          frame shape and `gfx.sh` checked framebuffer contents; nothing checked
          the MAPPING between them. `sim/tb_scanout.v` does.
        - **FIXED (2026-08-17): CPU register writes were gated by the scanout
          hold.** The `if (sel && wr)` block sat inside the engine's `else` -- the
          branch that does not run while the scanout owns the framebuffer port --
          so any write landing on a scanout cycle was silently dropped: one in
          four in simulation, one in three on the board. That is the whole of the
          "RTL misses SETPAL and BOXFILL" mystery: their GCMD write happened to
          collide with a hold and the command never arrived, while every command
          that did not collide went through. It also explains the earlier clue
          that only commands where GWAIT had to SPIN were skipped -- a spin puts
          the following write at a different, unluckier phase.
          Register writes now live in their own always block, ungated; they touch
          no framebuffer port, so there was never anything to gate. `gfx.sh`
          passes on all three payloads.
        - **OPEN:** the co-sim exercises the shared port (irregular LFSR hold),
          but reintroducing the pending-write bug did NOT make it fail. The
          contention coverage is therefore unproven and worth understanding.
        - **DONE (2026-08-17): ELLIPSE ($0A) / ELLIPSEFILL ($0B) in the RTL**,
          matching the emulator pixel for pixel; `test_gfx3.asm` covers a wide
          outline, a tall fill and a near-circle and is part of `gfx.sh`. Two
          bugs the frame diff caught, neither visible by reading: the region-1
          initialiser is 4*ry2 - 4*rx2*ry + rx2 and the middle term was written
          ry2*ry, so the walk never started; and a FILL must load its first span
          through the span-init state, because the circle begins its walk at x=r
          (seeding cx to ccx-r is right there) while the ellipse begins region 1
          at x=0, where the span is the single pixel ccx.
        - **OPEN, emulator/RTL parity:** SELFTEST ($F0) is implemented in the
          emulator but NOT in the RTL, where it falls through to `default` and
          sets the error bit. Nothing exercises it, so the frame diff stays green
          -- the payloads never issue it. Worth closing: it is the one command
          that proves a card with no software behind it.
      - **SD error paths are now tested** (`fpga/tang-nano-20k/sim/tb_sd_spi.v`
        with `sd_model.v +sdfail=1|2`); that found and fixed two lockups. Still
        unexercised: CRC failure, a card that reports write-protect, and card
        removal mid-transfer.
      - **Console newlines: FIXED (2026-08-13).** `CONOUT`/`PUTC` now expands a
        bare LF into CR LF, so P8X no longer depends on a host tty doing it.
        Files and pipes are untouched (they route through `OUTCH` to a file or
        capture buffer and never reach `CONOUT`), and an existing CR LF is not
        doubled (`TTYLST`). `TTYRAW` ($60A1) disables it for binary transfers.
        BASIC's private PUTC/GETC — a leftover from the retired standalone build
        — now tail-call the BIOS, so it inherits the same behaviour.
        The **standalone BASIC build** (`BASORG=$0000`, BASIC as the whole ROM) is
        now genuinely dead — it would fail at the BIOS call — and is marked RETIRED
        in `basic/README.md`. See the separate NEXT item for BASIC's CWD bug.
      - **Not done:** nothing uses the board's 64 Mbit SDRAM — it turned out to be
        unnecessary once the microcode ROM was compacted (see
        `fpga/tang-nano-20k/mk_compact_ucode.py`), but it is there if a future
        build wants more than 64K.

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

- [ ] **`SYS_OPEN` — open-by-name as a syscall (2026-07-16).** Commands each repeat
      the same four steps: `SYS_GETCWD` -> build an absolute path in their OWN
      `path[80]` -> `FRESOLVE` -> `FOPEN`. 16 of 25 commands call FOPEN directly;
      15 build their own CWD-prefixed path. That per-command buffer is exactly where
      Wave 2 found overflows in dir/cmp/mv/cat/find — five buffers, five bounds to
      get wrong. Fold it into one OS call with ONE bounded buffer.
      **No ABI change:** commands still receive a raw string, they just make one
      call instead of four. `lib_apath.c`'s abspath() stays — cp/mv/diff need the
      path STRING, not just an open.
      **Also kills the FSDIRBUF/SBUF footgun** (see the cat fix, eda2b7f): any
      command that opens a file while its stdout is a redirect must currently
      remember to FSDIRBUF its dir scan off SBUF, or the scan overwrites the
      redirect's buffered output. That belongs in the OS once, not in every command
      forever — and pipes make it systematically likelier, since every pipe stage is
      a redirect-writer.
      **Scoped 2026-07-16 — the implementation is THIN, the OS already has the
      primitive:** `RESOLVE` (p8xos.asm:1704) takes a path at **P2** and yields
      `SDIR` = parent dir + `NAMEBUF` = leaf, already handling CWD-relative
      resolution and the mount/drive redirect via `RV_START`. `SYS_MKDIR` (:1704
      area) is the model for a path-taking syscall: it just moves P1->P2 and calls a
      CORE routine. So SYS_OPEN is roughly `P2 = P1; JSR RESOLVE; bridge
      SDIR/NAMEBUF -> the BIOS FNAME/DIRLBA; JSR FOPEN`. See `FINDP2` (:1484) for
      the existing resolve-then-find bridge — reuse it rather than reinvent.
      Free syscall slots: **$2024 and $2027** (the table ends at SYS_MKDIR $2021).
      **Open design decision — no free 512-byte page in OS scratch** for SYS_OPEN to
      own a private dir buffer ($6000-$62FF is BIOS scratch + SBUF $6100; $6300-$69FF
      is fully allocated: RUNPATH $6740, PATHBUF, APBUF $6800...). Three routes:
        1. bounded OS-side path buffer only; caller still supplies the scan page.
           Kills the overflow class; cheapest; leaves FSDIRBUF with the caller.
           RECOMMENDED — most of the win, least risk.
        2. flush the write stream before the dir scan — no page needed and kills the
           footgun outright, but partial-sector flush-then-append is FS surgery.
        3. reclaim a page from $63xx-$69xx.
      Pairs with shell-side glob+argv (IDEAS): together they are the whole "stop
      making commands resolve paths and expand globs" thesis. This is the cheap half.

- [ ] **CWDPATH is 48 bytes — deep paths truncate (2026-07-16).** `SETPATH` now
      bounds appends (b41f5f1), so a path deeper than the buffer clamps instead of
      overflowing into INMODE/INARM/CWDLH — but it still *truncates*. A real tree
      deeper than 47 chars leaves CWDPATH short, and since `SYS_GETCWD` hands that
      string to programs to resolve relative paths, a command run from a deep
      directory can resolve against the wrong (truncated) path. `CWDL`/`CWDN` stay
      exact, so the OS itself is fine; only the string is short.
      Bounded, not solved. Options: (a) grow CWDPATH — needs space in OS scratch
      ($6300-$69FF is fully allocated, same wall as `SYS_OPEN`'s dir buffer);
      (b) make `cd` refuse a path that would not fit, which is honest but makes a
      legal directory unreachable; (c) store the CWD as LBAs and *render* the text
      on demand by walking parents, which removes the buffer as a limit but costs
      a directory walk per prompt. Depth of ~5 components with 8-char names is the
      practical ceiling today. Nobody has hit this in normal use — /src/os-bios is
      12 chars — so it is recorded, not urgent.


### Bus test card (USB bring-up controller)

Design is settled and the schematic is complete at 27 parts on a standard
160×100 Eurocard. See `hardware/bustest-card/p8x-bustest-card-design.md`. The
thesis: a control card you can *type at*, driving the backplane one microcycle
at a time over a USB serial line, with the emulator as the reference model.
Nothing below has been built or measured.

- [ ] **Make `buscon.c` actually build (2026-07-22).** The firmware
      (`hardware/bustest-card/firmware/buscon.c`, 241 lines) has the whole
      protocol — field lookup against the microcode's own `DOE`/`DLD`/`PSEL`
      names, ownership groups, the rest→A→B→rest phasing, the 5V-present
      interlock — but **there is no `CMakeLists.txt`, so it has never been
      compiled**, and `mcp_write`/`mcp_read` are empty shells marked `TODO(hw)`.
      Needs: pico-sdk build wiring, the real MCP23S17 SPI transaction, and SPI
      timing chosen against the datasheet (clock rate, CS setup/hold).
      **Do this before placing copper.** It is the cheapest way to find a design
      error: the pin map, the field→(chip,bit) allocation and the netlist all
      have to agree, and a compile plus a host-side harness catches a swapped
      chip or an off-by-one bit while it is still a text edit.

- [ ] **Generate the field→(chip,bit) map instead of asserting it
      (2026-07-22).** `FIELDS[]` in `buscon.c` maps each microcode field to an
      expander chip and bit, and the comment says it "MUST match the netlist
      allocation" in `gen_eagle.py`. That agreement is currently maintained by
      hand and checked by nobody — the classic way to lose an afternoon on the
      bench. `gen_eagle` already computes the allocation (`alloc`), so it can
      emit a `buscon_pins.h` the firmware includes, making the two structurally
      one source. Same pattern as `gen_memmap.py`.

- [ ] **Place and route the bus test card (2026-07-22).** The `.brd` is
      forward-annotated but unplaced — all 27 parts parked off the outline, zero
      copper. Auto-flow confirms they fit 160×100 at 31 % area with ~10 mm slack,
      so this is a layout job, not a fit problem. Note the workflow rule: once
      the `.brd` is touched in Fusion the generator is retired as an emitter for
      it (regenerating would discard placement); schematic, BOM, PDFs and docs
      can still be updated after that.

- [ ] **Resolve the design doc's own open items before fab (2026-07-22).**
      Carried in §10: where `CLK` parks when halted (affects listen-mode sampling
      only); the eight status LEDs in §5.4 are a guess and want a second opinion;
      and contention margin — dropping the bus series R means a wrong `drive` is
      limited only by device R_on (~25–50 mA, abs-max-safe but not indefinite),
      accepted for a careful bench tool and reversible by adding 100 Ω. Also
      blocked on the project-wide **DIN 41612 mating-orientation** check already
      listed above, which bites this card as much as any other.

---

## IDEAS

- [ ] **imgsend: VERIFY pass (2026-08-21, from a real corruption).** A clone
      delivered trit.bin with the right SIZE but corrupt content — "acked
      every sector, finished with 'K'" certifies transport, not bytes — and
      the corrupt program wild-jumped the machine to the monitor while the
      identical image ran perfectly in the emulator. A re-clone fixed it.
      Fix: per-sector checksum in the protocol, or a read-back verify pass
      after the clone (loader-side CRC of the whole image vs host). Until
      then: a board program that crashes impossibly while emulator-clean is
      PRESUMED CORRUPT — re-clone before debugging logic.
- [ ] **md: a panel (Tier B) renderer (2026-08-28).** The console `md`
      command's parser, re-targeted at the 480x272 panel via GTEXT:
      size-2 colour headings, green code, 80x34 grid, keypress paging.
      ~200 extra lines; GTEXT paints a page in a second or two, fine
      for reading. Gets genuinely good after stage 10h vector text
      (proportional sizes). The parser is already structured for a
      second back end (esc()/nl()/spaces() are the only output paths).
- [ ] **p8cc: block-local declarations in NESTED blocks miscompile
      (2026-08-28, found building md).** Locals declared in a block
      nested deeper than function level (e.g. `char *t; char *u;`
      inside an else-arm inside a while) silently corrupt: a branch
      testing those pointers took the wrong path while the identical
      shape at function scope worked, and the same shape in a tiny
      standalone program ALSO worked -- it needs surrounding function
      locals to collide with. Workaround (applied in md.c): declare
      every local at function top, C89-style. Fix: p8cc block-scope
      allocator; add a compiler test with nested-block locals beside
      live function locals.
- [ ] **Faster image transfer (2026-08-29, user).** Moving pixels is
      the slowest thing the machine does: host->board rides the 115200
      bridge (a full-screen P8I is ~256KB = ~22 s of line time) and
      on-target IMAGE draws pixel-by-pixel through the register window
      (563 cycles/px asm; the mandrill ~1.4 s). Candidate rungs, mostly
      independent: (a) raise the UART -- the BL616 USB-serial on the
      Tang Nano runs 2 Mbaud+; bridge DIV is one parameter on each side
      and protocol v1 is rate-agnostic; (b) a card-side BLIT command:
      set a rect, then stream raw RGB565 bytes into the span filler
      (the burst writer exists -- this is the P8I inner loop moved into
      fabric, turning IMAGE into FGETB+poke at wire speed); (c) cheap
      RLE in P8I v2 for flat-colour art (photos won't compress, UI
      will). Measure (a) first; it may make (b) moot for the SD path.
- [ ] **Mouse-type input (2026-08-29, user).** No pointer hardware on
      the board, so two doors: forward the HOST's mouse over the card
      bridge (a protocol v2 message pair -- runcard.sh's terminal can
      capture deltas; cleanest for the emulator-CPU era) or real
      hardware later (PS/2 needs two pins + a tiny shifter in fabric;
      the TTL bus era could use a serial mouse on a second ACIA).
      On-target shape either way: a pointer BIOS call (SYS_PTR: x, y,
      buttons) + a cursor drawn in LINFUN 4 (XOR) -- draw/undraw is
      board-proven, no save-under needed. First client: `md` paging,
      or a BASIC PTR() function trio.
- [ ] **LCD as a terminal (2026-08-29, user).** Let the console live
      on the panel: mirror BIOS CONOUT to the display so the machine
      is usable head-down, serial only for file transfer. With 10h the
      card can already draw text (TEXT via the glyph bank -- ~60x33
      chars at TSIZE 256), so the missing pieces are a console state
      machine (cursor, CR/LF, backspace) and SCROLL, which the card
      cannot do today (no blitter). Scroll options: (a) redraw the
      whole screen from a line ring (TEXT is fast enough for a demo,
      not for `dir` spam); (b) a scanout base-offset register --
      vertical scroll becomes one register write, the classic
      terminal trick, ~30 LUT in sdram_video + a wrap rule; (c) a
      fabric copy-rect (a real blitter rung, also what image GRAB
      wants). (b) is the cheap win. Keyboard stays the serial RX.
      Fits the FPGA-CPU era (idea 2): CPU and console on one board.
- [ ] **Move BASIC's remaining device drawing onto the PGC interface
      (2026-08-30, user).** The naming epoch landed first (PIXELW/
      PIXELR; POINT freed for the GL verb). Next: reimplement the
      category-2 statements (LINE, BOX, CIRCLE, CLS, PIXELW) as GL
      emission so BASIC's DRAWING all flows through $FF50, leaving the
      device door only the DMA-gap pair (PIXELR read, IMAGE write).
      Decisions on the way in: the screen-vs-window y-flip (per-call
      flip vs redefining the statements as window-space), and PIXELW's
      speed (a GL MOVE+POINT per pixel is ~20-40x the raw path -- fine
      for singles, wrong for loops; IMAGE stays raw regardless). End
      state enables the single-interface card: add a GL pixel-read
      verb (IMAGER/PIXRD through the RB FIFO, ~50-80 LUT) and the
      card-side blit (the faster-image-transfer item), and the $FF20
      window can close for ~100-150 LUT net of the read verb.
- [ ] **Restore AREAPT and ARC/SECTOR on a successor board (2026-08-30,
      user-approved removals).** Two cuts bought placement headroom
      against the chip's PRACTICAL cliff (~19,150-19,250 LUT4, well
      under the nominal 20,736 -- see STAGE10-DESIGN.md "round four"):
      AREAPT (opcode E7, the patterned fill mask; -569 measured) and
      ARC/SECTOR (3C/3D, the 4-degree polyline walk + fan fill).
      CIRCLE/ELIPSE, LINPAT and the trig ROM stayed. The as-built
      designs are fully documented in STAGE10-DESIGN.md and in git
      history at a518415..HEAD; re-adding either is a revert plus
      keyword regeneration. Until then: arcs = short DRAW chains at
      4-degree steps, patterned fills = software span masks.
- [ ] **Simple graphics editor, a C program (2026-08-29, user).** An
      on-target `draw` command (os/commands, //#use gfx): pick a tool
      and colour, place points/lines/boxes/circles/fills on the panel,
      save and reload the result. Everything it needs exists: lib_gfx
      primitives + AREA for fills, LINFUN 4 (XOR) for the rubber-band
      preview while placing (board-proven un-draw), `image grab` for
      saving the canvas as P8I and IMAGE to reload it. Cursor from the
      keyboard first (arrow keys move an XOR crosshair, step/fast
      step); the mouse backlog item slots straight in later via the
      same pointer abstraction. Save-as-GL-scene (emit the command
      list instead of pixels) is the deluxe variant -- editable vector
      drawings replayable with CLRUN, feeding the same glyph/list
      machinery. New-command rules apply: C + asm twin, man page,
      run.sh lists.
- [x] **Stage 10h subset — SHIPPED 2026-08-29 (TEXT/TSIZE/TANGLE +
      TDEFIN; the card split paid for it). Remaining from the sketch:
      TEXT-inside-lists (needs a second replay context, ~+100), TJUST,
      TEXTP. Original costing (2026-08-27):** A fabric TEXT verb is ~260 LUT4 against ~100 of
      headroom plus ~150-200 of remaining verifiable diet (the ellipse
      INITIALIZER adds and the Bresenham setup subtracts, both now
      bench-covered) -- borderline reachable. The design that makes it
      cheap: a glyph IS a command list (strokes as MOVER3/DRAWR3, so
      MDSCAL/MDROTZ give TSIZE/TANGLE through the existing compose
      path; a trailing MOVER3 advance walks the baseline in model
      space for free); glyphs live in a SECOND 64-slot SDRAM bank at
      $140000; the genuinely new fabric is the counted-string
      parameter shape (~120). First version defers TEXT-inside-lists
      (needs a second replay context, ~+100). Tier 0 (zero fabric:
      FONT.GL records glyphs into slots, a host `text` command emits
      CLRUNs) ships any time and proves the glyph format first.
- [ ] **GETLN drops input past 63 chars SILENTLY (2026-08-26, found via a
      long `gl` one-liner).** LINEBUF is 64 bytes; GETLN just stops storing
      (and echoing) at 63 — no beep, no error, no truncation marker. The
      dropped tail cost an afternoon: `gl ... CLRUN 2` lost its ` 2`, which
      left the GL decoder legally WAITING for CLRUN's parameter (no error —
      a partial command just waits), and the next `gl` invocation's
      stale-error drain silently consumed the downstream evidence. Fix
      candidates: BEL on the dropped char (one JSR), a bigger LINEBUF (the
      history ring pairs 64-byte slots — HISTLEN moves with it), or both.
      Until then: long GL content goes in a file (`gl FILE.GL` streams it),
      never a one-liner.
- [ ] **GL power-up viewport is degenerate; the PGC's is full-screen
      (2026-08-26, found replaying the manual's HOUSE example).** par[17..20]
      power up 0,0,0,0, so a faithful PGC stream that sets WINDOW but never
      VWPORT (legal on the PGC — its power-on viewport is the whole screen)
      maps every vertex into one pixel. Workaround: lead with
      `VWPORT 0 479 0 271`. Real fix to consider: power-up + RESETF default
      par[17..20] = 0,479,0,271 in emulator + RTL (small, and it is what the
      manual's own examples assume). Check no test relies on the degenerate
      default before changing it.
- [ ] **cube.bin is 161 bytes below the C-stack top (2026-08-21).** Stage-9
      library growth pushed cube.bin (36,191 B from $6A00) to $F79F against
      CSTACKTOP $F800 — a deep call chain will collide. Options: shrink the
      E3MAX pool (512 records is generous for a demo), split lib_g3d so
      LINE-only clients skip the TRI machinery, or the long-standing p8cc
      codegen shrink. Any new g3d client must check its map.
- [ ] **800x480 panel support (5"/7") — a stage, not a flag (2026-08-21).**
      DE-only panels cannot be auto-detected (one-way interface, no EDID):
      selection = a strap pin read at config, or an SD config byte the
      monitor reads at boot. Both timing sets in one bitstream; software
      asks IDENT, as designed. The real work: ~33 MHz pixel clock (PLL;
      the 27/3 CPU symmetry breaks), stride 1024 -> 2048 (a line spans two
      SDRAM rows; scanout pays 2 activations -- headroom exists), 768 KB
      framebuffer pages (page-flip bit moves), ~4x scanout bandwidth.
      Own design doc when a panel is actually in hand.
- [ ] **Stage 9 candidates for the geometry engine (2026-08-20).** The 8b
      engine (STAGE8B-DESIGN.md) deliberately left rungs: colour per edge
      (the engine draws white-only; a per-edge or per-list pen), a list-base
      register / multiple lists (one fixed list at $100000 today), indexed
      meshes (shared vertices instead of 12 bytes per edge), camera helpers
      (sin/cos stays software by design — but a matrix-compose helper could
      live in lib_g3d), and BASIC statements over the engine (needs arrays
      or a statement-level world builder). Filled faces / hidden lines are
      a different algorithm class — their own design first.
- [ ] **BASIC could use the MDU (2026-08-20).** Interpreter multiply/divide
      still runs the software loops; routing them through $FF30 (with the
      probe-and-fallback idiom from lib_g3d) would speed every arithmetic
      program. Measure first: interpreter overhead may dominate the way
      p8cc poke overhead did.
- [ ] **Board successor scouting (2026-08-20).** If the BSRAM wall (42/46)
      arrives: ULX3S (ECP5-85F, SDR SDRAM, mature open flow) for continuity,
      or Colorlight i5/i9 + hand-built carrier for the hardware route; avoid
      DDR3-only boards (obsoletes the proven SDR controller). The emulator-
      as-golden-model discipline makes a port mostly pinout + video backend.
- [ ] **Emulator bus server — run one script against the card AND the reference
      model (2026-07-22).** The bus test card's design doc (§1.2) makes the
      emulator the reference model, and the firmware deliberately uses the
      microcode's own field names (`DOE`, `DLD`, `PSEL`, `ALUS`) so a script
      means the same thing on both sides. But nothing in `emulator/` or `tools/`
      speaks the card's ASCII protocol, so that equivalence is a claim, not a
      test. A server that accepts the same `w FIELD=VAL` / `step` / `r` lines and
      drives the emulated machine would let a single script run against silicon
      and model and diff the answers — turning "the card behaves correctly" from
      a judgement call into a check. This is what would make the card
      trustworthy, and it is a host-side program, so it can be built before any
      board exists.

- [ ] **Shell-side glob + an argv ABI (2026-07-16).** The biggest structural fix
      available, and the one real architectural drift from Unix: **the shell does
      not expand globs — the commands do.** `cat *.LOG` hands cat the literal
      string `"*.LOG"` and cat expands it itself, carrying lib_glob + lib_globx
      (~150 lines) into its binary; cat, cp, mv and lib_stdin each call
      glob_expand independently. In Unix the shell expands and passes argv, and
      the command never sees a `*`.
      Blocker: **the program-arg ABI is a raw string** (P2 = arg tail), so the
      shell *could not* pass expanded matches even if it wanted to. Fixing it
      means an argv ABI — a breaking change across all 25 commands x 2 twins.
      Payoff: lib_glob/lib_globx leave EVERY command binary; one glob
      implementation instead of four; the per-command pattern-buffer overflow
      class (e.g. dir's gpat[16], Wave 2) disappears.
      **Trigger: do this when the TPA size ceiling actually bites.** That is the
      real motivation — vi.c compiles to 32.7 KB of the 38 KB TPA, and grep sits
      close enough that a single //#use pushed its SOURCE over p8cc.c's buffer
      (b19ae24). Until something misses the TPA, the cost/benefit does not clear.
      Pairs with `SYS_OPEN` in NEXT: together they are the whole "stop making
      commands resolve paths and expand globs" thesis; SYS_OPEN is the cheap half
      and needs no ABI change, this is the expensive half.

- [ ] **CODE_REVIEW.md — the remaining findings (2026-07-16).** *All 6 HIGH-severity
      items were re-checked on 2026-08-12 and are already fixed; see the status block
      at the top of the file. The medium/low items below remain unverified, and
      nothing under `fpga/` has ever been reviewed.* ~417 items across
      68 files from the fresh-eyes review. The 6 high-severity are all fixed; two
      mechanical/logic sweeps landed (59c46f7 Wave 1, bbad538 Wave 2) plus the
      hot-path bounds (ac6f414) and BASIC STEP (f0888da). What is left is mostly
      efficiency and docs findings, and a tail of medium ones.
      **The review is PLAUSIBLE CLAIMS, NOT VERIFIED DEFECTS.** Measured on the two sweeps: **215 claims rejected vs 85 applied** —
      more than twice as many wrong as right. Several were already fixed but still
      listed; several are right about the abstract rule and wrong as an action here
      (acting on the signed-compare finding shipped a buffer overflow the 87-test
      suite passed — see WONT-DO). So this is NOT a checklist to grind: verify each
      item against current code, and treat rejecting one as a success.
      What worked: fan out one agent per command owning BOTH twins, scoped to a
      named category, told explicitly the review may be wrong. Keep the hot paths
      (p8xasm/p8xcc/p8xos/p8xmon/p8xbasic/p8xedit/p8cc/p8lib) OUT of any fan-out —
      a confident-but-wrong flag/carry edit there breaks everything.
      Given the hit rate, "finish the review" is probably not worth doing as a
      project; mine it for the real bugs when touching a file anyway.

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

- [ ] **Userland text tools — the size-blocked remainder (2026-07-08, trimmed
      2026-07-16).** Most of this item SHIPPED — `vi`, `find`, regex `+`/`?`, and a
      field-oriented `awk` are all in `/BIN` with C+asm twins and man pages; see
      DONE. What is left is blocked on program size, not design:

      - **Full `awk` with an expression evaluator — blocked.** The shipped `awk.c`
        (242 lines) is the "field tool" this item proposed as the fits-now
        alternative: `[/re/] { print items }`, `$0..$NF`, `NF`, `NR`, `-F c`, string
        literals, stdin or file. It deliberately has **no** arithmetic, variables,
        or `if`. A real awk needs a recursive `eval()`, and that was measured at
        **>64 KB — over the whole address space, ~2.3x the ~37.9 KB TPA** (15,584
        lines of asm from ~400 lines of C), because p8cc's non-optimizing codegen
        expands 16-bit ops byte-by-byte. `grep` is already ~32.5 KB at the ceiling,
        so any expression language is over budget. Unblocked by the codegen/ISA
        shrink work, a p8cc peephole/temp-reuse pass, or a larger TPA (overlays /
        bank switching). Revisit once compiled command size drops materially.
        (The old note here said to dodge p8cc's lack of mutual recursion by writing
        one self-recursive `eval(minbp)`. That limit is gone — see below — so the
        parser shape is now free; only the SIZE blocks this.)
      - **Regex character classes `[a-z]` / `[^..]` and `\` escapes — blocked.**
        The highest-value remaining regex feature. Even minimal buffers overflowed
        once variable-length atoms (atomlen/atomone) were added: it is blocked on
        **grep's host (p8cc.c) build size**, where grep's globals already collide
        with the `$EA00` (-r) / `$FA00` (glob) FNEXT pages. Unblocked by the same
        codegen-size work, or by restructuring grep (e.g. splitting `-r` content
        search into its own command to free grep's globals). vi's `/` search is
        literal and would also benefit.
      - **`find` enhancements — small, in-budget, just not done.** `-type f|d`,
        `-name`, `-exec`, and **a path argument**: `find` and `tree` are the two
        commands that take no path at all (`FIND pattern` / `TREE` walk the CWD
        only), so searching elsewhere means `cd`-ing there first. Note this is no
        longer a *drive* limitation — the `N:` prefix model was superseded by the
        `/D1` mount, and commands are drive-unaware now, so a path arg would reach
        `/D1` for free via `FRESOLVE`.

      **p8cc subset gaps confirmed while writing awk** (bite any ambitious command;
      note in the compiler docs): **no `break`/`continue`** — still true; restructure
      loops with a flag / condition (`p8cc.c` itself does this in `register_struct`).

      ~~no forward declarations or mutual recursion~~ — **NO LONGER TRUE (c57da4e).**
      Forward prototypes parse and mutual recursion works; verified on the machine
      with both compilers (`is_even`/`is_odd` round-trip: EVEN-OK/ODD-OK/MUTUAL-OK),
      and `p8cc.c` now relies on a forward prototype itself (`int toobig(char *);`).
      (Calls to an undeclared function still default to `int`, so a prototype is
      only needed to keep the host `cc` build warning-clean.)


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

- [~] **Offload OS commands to loadable programs — TREE/DUMP/DEP DONE; FSCK and
      PACK remain resident.** Now
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
      populate RC terminators (R2/C13, R3/C14 shipped DNP)

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

- **Do NOT convert the commands into pure stdin/stdout filters** (2026-07-16).
  Sounds like the clean Unix answer; it is not the fix. The 25 commands split
  three ways and only one third could convert:
    ~10 pure filters (wc/head/tail/uniq/sort/sed/more/cat/awk/grep-no-r) —
        these ALREADY work as filters via the shell's `<`, `>` and `|`.
        Converting them gains nothing; the work is done.
     2 multi-input (cmp, diff) — need two file handles; stdin gives one.
        Blocked without an fd model.
    ~12 FS manipulators (cp/mv/del/touch/mkdir/dir/tree/find/pack/fsck) —
        inherently need the filesystem. Routing their calls through the OS
        RELOCATES code, it does not remove it: dir/tree/find genuinely must
        iterate directories.
  Also note the pipe-able commands are already filters, so multi-stage pipes
  (`a | b | c`) need ZERO command changes — that blocker is a loop in the shell's
  splitter (PIPE_RHS re-scan), unrelated to this. The real drift is that commands
  resolve paths and expand globs; see `SYS_OPEN` (NEXT) and shell-side glob+argv
  (IDEAS) — those are the fix.

- **Bus test card resistor packaging policy** (2026-07-22, supersedes the
  earlier "discrete resistors" decision). The banks were briefly all-discrete;
  that was reverted. The rule now, project-wide:
    - **DIP-16 isolated networks (RNISO8D)** for 8-way isolated banks — LED
      current-limiting and any other bank where both ends of each leg differ.
      On bustest: RN1 (probe-LED 330R), RN2 (status-LED 330R), RN3 (probe series
      1k). One package per bank instead of eight parts.
    - **SIP-8 / 9-pin bussed (SIP9)** for pull-ups / pull-downs, where one side
      is a shared node. Already true of RN1/RNP on backplane/cf/io.
    - **Discrete** only for 1s and 2s (dividers, single pull-ups) — e.g. bustest
      R5–R8 (5V-sense + MISO dividers).
  A bussed SIP-8 CANNOT substitute for an isolated bank (its shared COM would
  short all eight legs), and 8 isolated resistors do not fit a 9-pin part, so
  the isolated banks are DIP-16, not SIP. Do not "unify" the two network types.

- **Bus test card indicators are 16 INDIVIDUAL labelled LEDs, not bar arrays**
  (2026-07-22). LPR/LST (LEDARR8 / DIP-16) became LED1–16 (LED1–8 probes,
  LED9–16 status), each with a silkscreen label — the point being a bench tool
  you read by glancing needs a printed name at every indicator. Status meanings
  map to ST0–7 = Pico GP7–GP14: 5V-OK, ARMED, LISTEN, CLK, CLKB, -RES, ERR,
  USB-ACT. Colors are provisional (tied to the §10 status-set open item). This is
  another deliberate part-count increase (48 → 62); same standing as the discrete
  resistors above — not to be re-arrayed without a reason beating the labelled,
  through-hole clarity.

- **Do NOT re-add the `-full.brd` companion boards** (2026-07-22, `3ab0ed9`).
  Every card used to emit a second board with the auto-flow placement left ON
  the outline, as a "starting layout". It was never any use: the placer walks
  parts in dictionary order, not signal flow, so U1 sat beside U2 because of its
  name — nothing it produced was worth dragging into shape rather than placing
  from the ratsnest. They also shipped their own silkscreen collisions (regbank
  alone had 117 labels over a neighbouring part) which read as real defects in
  every audit and had to be explained away each time. The flow placement itself
  is still computed: it orders the parked parts and answers "do these parts
  fit?". It is just not emitted as if it were a layout.

- **Do NOT widen the bus test card past 160×100** (2026-07-22, `5576bcb`). It
  was scoped at `W=200` when it was ~45 parts. After the cuts it is 27 and
  auto-flow fits them in two rows at 31 % area with 10 mm of slack. The reason
  to stay standard is mechanical, not spatial: 200 mm cantilevered off the DIN
  connector is carried by just the two mounting holes at y=±45, and this is the
  card that gets handled most — every grabber clip and USB insertion puts a
  moment through the connector. At 160 mm it sits in the card guides like
  everything else. Fab also gets one panel size across the set. Nothing is lost:
  J1 still hugs the left edge with parts flowing +x, so the USB socket, probe
  header and LED bank stay at the OUTER (reachable) end — that came from the
  flow direction, not the extra width.

- **Do NOT add bus pull-downs, bus series resistors, or D0-7/A0-15 monitor LED
  arrays to the bus test card** (2026-07-22). All three were in the first cut
  and all three were removed after being challenged; the card went 45 → 27
  parts. Pull-downs (`RPD1-6`): the scenario they defended does not need them —
  the firmware holds `CLK` low from init, so nothing latches while the bus
  floats (design doc §3.1a). Bus series R: MCP23S17 is 5 V tolerant, so the
  level-shift argument does not apply; dropping it is a deliberate tradeoff
  recorded in §3.2 (a wrong `drive` is then limited only by device R_on) and is
  reversible with 100 Ω if it proves too sharp in use. Monitor LED arrays: 10
  ICs → 7 by cutting them; the probe LEDs already cover what you actually watch.
  Re-adding any of these needs a NEW argument, not the original one.

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

- **Milestone A is self-ACCEPT; p8cc.c now ALSO self-compiles on the host, but it
  is still NOT self-hosting** (updated 2026-07-16 — the earlier wording here was
  overtaken by that day's fixes and every number in it is now wrong).
  Three different properties, kept straight:
    - **self-accept** — the subset accepts its own source (`p8cc.py p8cc.c`).
      This is what Milestone A built and tested. TRUE, and the c_selfhost test
      guards it.
    - **self-compile** — the p8cc.c bootstrap compiles p8cc.c and emits complete,
      correct asm. NOW TRUE (c57da4e fixed a forward-prototype bug that silently
      dropped 22 of 90 function bodies; b19ae24 raised src 32K->64K and 32 other
      host-side tables). 90/90 bodies, zero undefined.
    - **self-host** — the compiler RUNS on the P8X. FALSE and staying that way:
      the self-compiled output stops at the assembler with "address past 64K"
      because the compiled p8cc exceeds the machine's entire address space. That
      wall is exactly why Milestone B went the from-scratch `apps/p8xcc.asm`
      route, and that is the compiler you use on-target.
  So self-compilation is a correctness result — the compiler is good enough to
  reproduce itself — not a step toward running it on the machine. Do not chase
  self-hosting p8cc.c; `apps/p8xcc.asm` already is the native compiler.
