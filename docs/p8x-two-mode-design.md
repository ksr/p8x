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

- **P1 — `graphics_present` flag.** Monitor probes + prints + sets `GFXPRES`; OS
  re-affirms; `has_graphics()` helper; convert GL programs to it. Small, unblocks
  everything.
- **P2 — Glass TTY behind `CONOUT`.** Text console on the GL screen (framebuffer,
  cursor, scroll) in ROM; `CONOUT` draws+mirrors when `GFXPRES`; monitor inits the
  screen + prints "Graphics Available"; console-suspend hook for apps. The big
  foundational piece.
- **P3 — Second serial port** (emulator + hardware). Enables Kermit later.
- **P4 — Finder desktop + full-screen-app frame.** File browser (navigate/open
  first; rename/duplicate/move next), menu bar, launch/return. Retire the tiled
  wdesk.
- **P5 — Apps.** Adapt Paint/Image; the Term app; **Write** (new); the
  serial-terminal / Kermit command.

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
