---
name: project_p8x_two_mode
description: "Major direction (2026-09-09): P8X runs headless-serial OR graphics-desktop by a graphics_present flag; full-screen apps + Finder retire tiled wdesk; glass TTY behind CONOUT"
metadata: 
  node_type: memory
  type: project
  originSessionId: 6ffcfef7-73ca-445b-bcdb-f57735fdc98f
  modified: 2026-09-09T16:18:26.125Z
---

**BIG DIRECTION CHANGE, user, 2026-09-09.** Full design in
docs/p8x-two-mode-design.md. Checkpoint tag `checkpoint-wm-tty-2026-09-09`
(commit 8d79d43 on graphics-card) marks the state right before this.

The P8X runs the SAME OS in two modes, auto-selected by a **graphics_present**
flag the monitor sets at wake (real hw or emulated, identical):
1. **No graphics** = serial console (as today); GL programs error+exit.
2. **With graphics** = the screen is the text display AND hosts a Mac-style
   full-screen-app desktop; serial stays (input + a mirror of output).

**Decisions LOCKED (user chose all three recommended):**
- GUI = **full-screen apps + a Finder desktop** (one app owns the screen; app
  quit -> desktop; desktop quit -> CLI OS). **Tiled/resident-window wdesk is
  RETIRED** — see [[project_p8x_resident_wm]] (its plumbing carries forward, its
  tiling UI does not).
- Console output **mirrors** to both screen and serial.
- The **ROM monitor itself** is on-screen (glass TTY reaches into firmware).

**KEY ARCHITECTURE INSIGHT:** put the glass TTY **behind BIOS CONOUT ($0103,
ROM)** — monitor + OS (OUTCH->OUTTTY->CONOUT) + every program's putchar already
emit through CONOUT, so "CONOUT: if GFXPRES, draw to screen + mirror serial; else
serial" makes the WHOLE system on-screen from power-up with ~zero changes. CONIN
unchanged (input stays serial). Glass TTY = small text framebuffer (~30x53 ~1.5KB)
+ cursor + scroll, drawn with GL TEXT, in ROM (monitor needs it pre-OS). Console
vs app screen ownership: an app CLAIMS the screen on start (suspend glass TTY,
clear), RELEASES on quit (glass TTY repaints console).

**CARRIES FORWARD (foundation):** OUTCH->window sink -> glass TTY; SYS_RUNSH +
-w/-r launch-return -> app launch/quit; wdesk FILES -> Finder; wdesk TERM -> Term
app. **RETIRED:** tiled windows, z-order, drag, per-window records, most SYS_WK*.

**PHASES:** P1 graphics_present flag (small, unblocks all) -> P2 glass TTY behind
CONOUT (big, ROM work, "monitor on screen") -> P3 2nd serial port (emu+hw, for
Kermit) -> P4 Finder desktop + full-screen-app frame (retire tiled wdesk) ->
P5 apps: Paint(adapt)/Image(adapt)/Term/Write(NEW)/serial-terminal(Kermit).

**P1 DONE (2026-09-09), on graphics-card:** GFXPRES = resident byte $60A4 (memmap
anchor, gen_memmap.py). Monitor DISPINIT probes GLID -> sets GFXPRES + prints
"GRAPHICS AVAILABLE"/"NO GRAPHICS" on serial; OS COLD re-affirms after banner.
lib_gfx.c gained has_graphics() (reads GFXPRES); gpresent() now sources from it.
ALL GL programs converted off peek(GLID): redundant 2nd probe removed where
gpresent() already gated (house/camera/gl/page/rotate/clsave), peek(GLID)==71 ->
has_graphics() (cube/tri/image), and desk/paint/wdesk (no //#use gfx) read GFXPRES
directly. Emulator: `-ng` floats GLID to $FF (test headless). Test
c_gfxpres_test.sh boots same disk +/- -ng. NOTE monitor now prints a line between
"? FOR HELP" and prompt on EVERY boot -- os_test's `P8X MONITOR` count unaffected.

**OPEN Qs:** ROM budget for the glass TTY (8KB ROM — if it doesn't fit, fall back
to OS-level console, losing "monitor on screen"); font geometry (480x272 -> cols
x rows); scroll method (CPU repaint vs card blit); Write scope; no-mouse file-op
UX (keyboard-driven like current FILES).
