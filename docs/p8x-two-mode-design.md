# P8X two-mode operation — headless console vs. graphics desktop (design)

Status: **design, 2026-09-09.** A major direction change (checkpoint tag
`checkpoint-wm-tty-2026-09-09` marks the state before it). Supersedes the tiled
resident-window `wdesk` model (see [p8x-wm-design.md](p8x-wm-design.md)) with a
full-screen-app + Finder-desktop model. Reuses that work's *plumbing*; retires
its *tiled UI*.

## The vision

The P8X runs the same OS in two modes, chosen automatically by whether a graphics
card is present (real hardware or emulated — identical logic):

1. **No graphics (headless).** The CPU (Mac emulation or FPGA) is a serial
   console: I/O over the hardware serial port, exactly as today. GL programs
   (`cube`, `house`, `image`, the desktop) print an error and exit.
2. **With graphics.** The screen becomes the system's text display *and* hosts a
   Mac-style windowed desktop. Serial stays connected (input, and a mirror of
   output).

## Decisions (locked 2026-09-09)

- **GUI = full-screen apps + a Finder desktop.** One app owns the screen at a
  time; quitting an app returns to the desktop; quitting the desktop returns to
  the command-line OS. The tiled/resident-window `wdesk` UI is **retired**.
- **Console output mirrors.** When graphics is present, text renders on the
  screen AND is echoed to serial (a debug/headless log).
- **The ROM monitor itself is on-screen.** The glass TTY reaches down into the
  monitor (firmware), so the machine is usable on-screen from power-up.

## Architecture

### 1. `graphics_present` — one flag, probed at wake

The monitor probes the GL card at reset (`GLID` == `'G'`, `$FF54`) and sets a
reserved RAM byte **`GFXPRES`**, then prints on serial `graphics available` /
`no graphics`. On real hardware the same probe runs. The OS re-affirms `GFXPRES`
at boot (a resident copy programs can trust across the monitor→OS handoff), and a
`has_graphics()` lib helper (and/or a syscall) reads it. Every GL program checks
it instead of probing `GLID` itself (replacing the scattered `peek(GLID)!=71`
"?No display" checks in `cube`/`house`/`image`/`wdesk`/…).

### 2. The glass TTY lives behind BIOS `CONOUT` (the linchpin)

The monitor, the OS (`OUTCH`→`OUTTTY`→`CONOUT`), and every program's
`putchar`/`puts` all emit through the BIOS `CONOUT` (`$0103`, ROM). So the glass
TTY goes THERE:

> **`CONOUT` (ROM): if `GFXPRES`, render the char to the on-screen text console
> AND write it to the serial ACIA; else serial only.** `CONIN` (`$0100`) is
> unchanged — input stays serial (the Mac keyboard in emulation; a real keyboard
> later).

Consequences, all near-free:
- The **monitor** is on-screen (its prompt/`E`/`D`/dumps go through `CONOUT`).
- The **booted OS** and **every command** are on-screen with zero changes.
- **Mirror-to-serial** is just "`CONOUT` does both."

The glass TTY keeps a small text framebuffer in reserved RAM (rows×cols, ~1.5 KB
for ~30×53) plus a cursor; it draws each char with GL `TEXT`, and on newline past
the bottom it scrolls the buffer and repaints. It MUST live in ROM (the monitor
needs it before any OS loads) — so ROM space is a real constraint to measure.

**Screen ownership — console vs. app.** A GL program (paint, an app, the desktop)
draws graphics to the SAME screen the glass TTY uses. So there is a mode: the
glass TTY owns the screen for the console/OS, but a full-screen app **claims** it
on start (glass TTY suspended, screen cleared) and **releases** on quit (glass TTY
repaints the console from its framebuffer). A `console_suspend()`/`resume()` hook
(a `GFXPRES`-adjacent flag) gates whether `CONOUT` draws.

### 3. Full-screen-app desktop (retires tiling)

One program owns the screen at a time — the natural fit for the single-TPA
machine (this is the *old* `desk` System-1 philosophy, done right). No tiling, no
z-order, no per-window records.

- **Finder desktop** — a file browser as the default app: navigate folders,
  open, **duplicate**, **rename**, **move**. Grows out of `wdesk`'s FILES logic +
  `cp`/`mv`/`mkdir`/`del` FS ops.
- **Menu bar** — a top bar with dropdowns. The desktop shows **File** and
  **Apps**; each app draws its OWN bar (always **File ▸ Quit**, plus app menus).
- **Launch / return** — launching an app is a full-screen program swap (TPA);
  quitting re-execs the desktop. This is `SYS_RUNSH` + the `-w`/`-r` resume chain
  generalized (the mechanism from the sink work).
- **Apps**: **Paint** (adapt the existing one), **Write** (new — a text/word
  editor), **Image** viewer (adapt), **Term**.
- **Term** = a real console: runs any `/bin` command, output on-screen (it IS the
  glass TTY in an app frame). Inside Term you can launch a new **serial-terminal**
  command for **Kermit-style file transfer over a SECOND serial port**.

### 4. Second serial port

A 2nd ACIA in the emulator + hardware spec, for the serial-terminal / Kermit
command. Independent of the graphics work; needed before the transfer app.

## What carries forward vs. retires

| Recent work | Fate under this design |
|---|---|
| OUTCH→window sink (`SYS_WKSINK`, glyph-into-list) | **Foundation** → the glass TTY (text-to-screen + cursor + scroll) |
| `SYS_RUNSH` + `-w`/`-r` launch-return | **Foundation** → app launch / quit-to-desktop |
| `wdesk` FILES browser | **Foundation** → the Finder desktop |
| `wdesk` TERM | **Foundation** → the Term app |
| scattered `peek(GLID)` checks | **Replaced** by the `GFXPRES` flag |
| resident WM kernel: tiled windows, z-order, drag, per-window records, `SYS_WKOPEN/RAISE/GET/TOP/…` | **Retired** (not needed for full-screen apps) — keep only what the app frame reuses |

## Phases (dependency order)

- **P1 — `graphics_present` flag. DONE (2026-09-09).** The monitor's `DISPINIT`
  probes `GLID` at wake, records the result in the resident byte `GFXPRES`
  (`$60A4`, a memmap anchor shared by firmware + OS + programs), and prints
  `GRAPHICS AVAILABLE` / `NO GRAPHICS` on serial; the OS `COLD` re-affirms
  `GFXPRES` after the banner so programs can trust it across the monitor→OS
  handoff. `has_graphics()` (in `lib_gfx.c`) reads the flag, and `gpresent()` now
  sources presence from it rather than a fresh `GLID` probe. Every GL program was
  converted off the scattered `peek(GLID)` checks (the redundant second probe was
  removed where `gpresent()` already gated; `desk`/`paint`/`wdesk` read `GFXPRES`
  directly). The emulator gained `-ng` (float `GLID` to `$FF`) so both modes boot
  from one build; `c_gfxpres_test.sh` boots the same disk with and without `-ng`
  and checks the monitor message, the flag a program reads, and the GL-program
  `?No display` exit all track the mode.
- **P2 — Glass TTY behind `CONOUT`. DONE, ALWAYS-ON + MONITOR ON SCREEN
  (2026-09-10; shipped opt-in on 2026-09-09 first, see below).** `PUTCTX` (the
  byte-pusher every output funnels through) mirrors each console byte to the GL
  screen via GL `TEXT` as well as the serial ACIA — so the ROM monitor, the OS
  and every program render on-screen with no change to their output code. **It
  is ON by default whenever a card is fitted:** the monitor's `DISPINIT` sets
  `GCONEN=1`, installs the stroke font from `/FONT.GL` on the CF root (`MONFONT`
  — the 5.3 KB font can't fit the ~3 KB of free ROM, so it lives on disk and the
  card keeps it), blanks the screen (`GTINIT`) and prints `GRAPHICS AVAILABLE`
  as the first text ON THE LCD — the pre-boot monitor is on screen. `screen off`
  disables the mirror for a session. The colour-swatch boot splash was retired
  (the notes want blank screen + text). No CF / no font: skipped silently and
  the OS's own `FONTLD` installs it at boot. Cursor state (`GTCOL/GTROW/GTX/GTY`),
  the `GTSUSP` console-suspend flag, and the `GCONEN` enable flag are memmap
  bytes; a `GCLS` BIOS entry (`$014E`) clears+homes the console. Geometry is
  80×30 (6px advance × 9px line). Verified by `c_glasstty_test.sh` (OS output
  renders in the top rows; gated off + serial-clean when headless).
  - **The opt-in detour, and how always-on was made safe.** The first cut
    (2026-09-09) shipped OPT-IN because an always-on global `CONOUT` mirror has a
    large blast radius: the console and every GL program share ONE card's screen
    and global pipeline state, which surfaced **three distinct collisions** — (1)
    returning to the console cleared the screen, wiping a program's frame before
    a test's framebuffer grab; (2) the console echo drew INTO a card list the
    OUTCH→window sink was recording; (3) the console's command echo landed on the
    shared framebuffer that byte-exact GL tests compare. Going always-on
    (2026-09-10) resolved them by settling the **console model**: (1) dissolved —
    resuming the console at the prompt does NOT clear (see the principle below);
    (2) fixed — `SH_PROMPT` doesn't resume the console while a script runs, so
    the sink never records the echo; (3) is a *measurement* problem — the echo is
    an independent variable in a byte-exact compare — so those tests switch the
    console off (`screen off` / `GCONEN=0`) before grabbing, exactly as a lab
    blanks a monitor. Note why a program-side "clear from scratch" can't cover
    it: programs clear only their own viewport (`gla`/`glb` use x 104–375), so
    the top-left echo region is never theirs to clear.
  - **Console-suspend hook (`GTSUSP`) — DONE.** The glass TTY and GL programs
    share one screen, so a program that draws graphics must suspend the console
    or its text (and clear-on-full) corrupt the graphics. `gpresent()` sets
    `GTSUSP=1` (covers every `//#use gfx` program); `paint`/`desk`/`wdesk` and
    BASIC set it directly; the OS shell clears it (`GTSUSP=0`) at each prompt, so
    the console resumes when a program returns. `PUTCTX` skips the screen when
    `GTSUSP`. (Found the hard way: without it, BASIC's console output triggered
    clear-on-full and wiped its own graphics.)
  - **Screen-owner configures from scratch (the governing principle).** Because
    the glass TTY and GL programs share one card's global state, the rule is:
    **whoever takes the screen fully configures the GL pipeline it needs and never
    trusts what the last owner left.** A program establishes its own window/
    viewport/camera/matrix (they already do). The console **clears on TAKEOVER
    but not on RESUME**: it blanks the screen when it first takes the card — the
    monitor's `DISPINIT`→`GTINIT` at wake, and again on `exit` — but when a
    program returns to the shell prompt the console simply resumes drawing text
    where it left off, over the program's last frame. Not clearing on resume is
    deliberate: it is what keeps incremental drawing across separate commands
    working (`gl` chains, `tri … k` scenes, `rotate`/`camera` replays), which a
    clear-on-every-prompt would destroy. `screen on` is the explicit "give me a
    clean console" when the frame has become clutter.
  - **State hygiene the glass TTY must respect** (shared card port): `GTCLS`
    leaves `PRMFIL 0` (outline) so later stroke `TEXT` — the console's own and a
    GL client's — isn't filled; `GTDRAW` ends with `MDIDEN` so its per-glyph
    `MDTRAN` doesn't translate the next client's geometry (BASIC's raw
    `MOVE3/TEXT` assumes an identity matrix).
  - **Testing gotcha (cost a lot of debugging):** a graphics program's picture
    must be grabbed **while the program owns the screen** — after `exit`, the
    monitor reboots and `GTCLS` clears it (correct: the console reclaiming). Tests
    that framebuffer-grab at the cycle cap must not send `exit`/return-to-console
    first (see the `c_demo` fix), or they capture a cleared screen and wrongly
    read the program as "drew nothing."
  - **ROM budget resolved:** the driver + `MONFONT` fit in the 8 KB with room to
    spare; the font itself lives on disk (5.3 KB), which is what made "monitor on
    screen" viable without a font in ROM.
  - **Deferred to BACKLOG (deliberate cuts):** proper **scrollback** (the console
    is clear-on-full — there is NO free RAM for a text framebuffer, so the
    intended fix is card-list scrollback); **per-cell erase** (`BS` moves the
    cursor but leaves a ghost); and a speed pass (batching /
    set-projection-once). (Pre-boot monitor-on-screen, once listed here, shipped
    with `MONFONT` on 2026-09-10.)
- **P3 — Second serial port. Emulator DONE (2026-09-09).** A 2nd ACIA at
  `ACIA2S $FF08` / `ACIA2D $FF09`, register-identical to the console ACIA
  (`$FF04`/`$FF05`): status bit0 RDRF, bit1 TDRE; data read = RX, write = TX. The
  emulator backs it with a file pair — `-2i <file>` feeds RX bytes, `-2o <file>`
  captures TX — which is both self-testable and pipeable to a host `kermit`.
  Verified by `c_serial2_test.sh` (a probe drains `-2i` to both the console and
  `-2o`). **Hardware:** a second 6850 (or equivalent) at the same `$FF08/$FF09`
  window, its own baud clock + line driver to a second connector — a card/wiring
  task on the FPGA/TTL track, not yet built. The serial-terminal / Kermit command
  that drives this port is P5. Independent of the graphics work.
- **P4 — Finder desktop + full-screen-app frame. FIRST CUT DONE (2026-09-09).**
  `os/commands/finder.c` -- a full-screen file browser (no tiling): a white menu
  bar across the top with the current directory, the directory as a scrolling
  file list below (dirs cyan, selection a yellow bar). Keyboard-driven (Up/Down,
  ENTER opens a dir or LAUNCHES a `.BIN` full-screen via `SYS_EXEC`, Backspace
  goes up, `q` quits to the shell). It claims the screen (`GTSUSP`) and draws its
  own UI + text (sets `PROJCT 0` etc. from scratch); decodes arrow escape
  sequences itself (no WM kernel). Verified by `c_finder_test.sh`. **Auto-return** works: launching an app hands the shell a `run <app>` /
  `run /bin/finder.bin <dir>` script (`SYS_RUNSH`), so the app quitting flows on to
  re-launch Finder in the same dir -- no per-app flag (the WM-TERM mechanism);
  `c_finder_ret_test.sh` proves it. An **Apps menu** (press `a`) launches Paint/Term/Write/... by letter
  (`c_finder_apps_test.sh`). Deferred to BACKLOG: **mouse**, the file ops
  (**rename/duplicate/move**), the **Term** and **Write**
  apps, and **retiring the tiled `desk`/`wdesk`**.
- **P5 — Apps. Term DONE (2026-09-10).** `os/commands/term.c` -- an on-screen
  console in the app frame: enables the glass TTY, each typed command runs with
  output on the GL screen, Term persists by re-launching itself (`-c` continue
  mode, since no run-and-return call exists), `exit` -> Finder. Launched from the
  APPS menu (T). Verified by `c_term_test.sh`. **Write DONE (2026-09-10):**
  `os/commands/write.c` -- a full-screen text editor (open/edit/save a file,
  cursor + insert/delete/newline, ^O save, ^X -> Finder; APPS menu W); verified
  by `c_write_test.sh`. **Paint/Image adapted (2026-09-10):** Paint launches from
  the APPS menu and auto-returns (no change -- the launch script does it); Image
  gained a full-screen VIEW mode (`image /path`) and Finder opens a `.P8I` in it
  (`c_finder_open_test.sh`). **Kermit DONE (2026-09-10) -- P5 COMPLETE:**
  `os/commands/kermit.c` -- `kermit send|recv /path` moves a file over the P3
  second ACIA ($FF08/$FF09) in minimal Kermit-style packets (SEQ/LEN/data/CHK,
  LEN=0 = EOF), the console keeping port 1. Run from the shell or the Term app,
  not the APPS menu (it needs a send/recv verb + path argument). Verified by
  `c_kermit_test.sh` -- a byte-exact send->cap.dat->recv round-trip using the
  emulator's file-backed 2nd port (-2o/-2i). C-only for now; the hand-asm twin
  is on the backlog (as with `screen`). **All five phases (P1-P5) are done.**

## Open questions (resolve as we go)

- **ROM budget for the glass TTY.** The monitor+BIOS live in 8 KB ($0000-$1FFF).
  Measure the glass-TTY code + font-draw cost; if it doesn't fit ROM, fall back to
  an OS-level console (monitor stays serial — but that trades away "monitor on
  screen").
- **Glass-TTY font/geometry.** Screen is 480×272. With the GL stroke font at a
  chosen `TSIZE`, how many cols×rows? Determines the framebuffer size and scroll
  cost.
- **Scroll method** — CPU-side text-buffer repaint vs. a card blit/scroll (faster
  if the card supports it).
- **Keyboard** — input stays serial for now; a real PS/2 keyboard (backlog card)
  is a later input source that feeds the same `CONIN`.
- **Write app scope** — plain text editor vs. richer "word processor"; likely
  starts as a screen editor (evolve `vi`/`edit`, or new).
- **Desktop file ops UX** — modal dialogs vs. menu-driven for rename/duplicate/
  move on a no-mouse-yet machine (keyboard-driven selection like current FILES).
