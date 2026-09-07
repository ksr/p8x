# P8X Resident Window Manager — design

Status: **the ladder is complete (2026-09-04).** The resident kernel
draws windows (chrome, titles, card-list content) that outlive the app,
its event loop takes keyboard + grab-relative mouse-drag input, it
LAUNCHES an app and RESUMES with every window intact
(`wm_launch_test`), and each window keeps a resident STATE blob so apps
remember their place across launches (`wm_switch_test`). Chrome polish
(multi-window focus/close/menu) and the deluxe full-suspend switcher
are optional follow-ons; the core resident-WM goal is met.

## Why resident, and why assembler

The C window system (rungs 1–4, `desk` + `lib_wm` + `lib_ptr`) proved the
mechanism — per-window hardware clipping, painter's repaint, menus, a file
browser, a picture viewer, and launching programs the System-1 way
(`SYS_EXEC`). But that `desk` is a **36 KB TPA program**: launching an app
means *replacing desk in memory* and chaining back on exit. There is no
"switch between running windows" because there is only one program at a time
and desk is not one of them while an app runs.

The user's insight: make desk **resident** (like the shell), so launching a
program into the TPA does not destroy it. Then a saved-context scheme can
switch focus between windows.

The obstacle is memory. The WM *core* alone (`lib_wm` + `lib_ptr` + the C
runtime, no browser/viewer/terminal) compiles to **17.6 KB** — too big to sit
resident alongside a TPA large enough for real apps in 56 KB of RAM. So the
resident kernel must be **hand assembler**, like the OS: the project's own
C-vs-asm ratio (2.3–5.8×) puts it at ~4–6 KB.

## Memory layout

Boot is **unchanged**: monitor → `B` → shell, nothing resident, the full TPA
free. The GUI is opt-in — `desk` loads the kernel into the OS reserve, once,
and it stays.

```
  $2000            OS (resident)
  $51C5            OS growth reserve (~1 KB free)
  $5600  WMBASE    ── resident WM kernel: code + window records + stack ──
  $6000            OS/BIOS scratch
  $6A00  TPABASE   ── full TPA for apps ($6A00..CSTACKTOP, ~37.9 KB) ──
  $F800  CSTACKTOP  apps' C stack top
  $FEFF  STKTOP    OS/monitor hardware stack
```

The kernel lives **below** the TPA, in the OS growth reserve — the ~1 KB of
`$2000..$6000` the 12.4 KB OS does not use. Apps load into the **full** TPA
above it (`$6A00..$F800`) with the normal C stack: nothing is compiled with a
special `--cstacktop`, and no TPA is surrendered to the kernel. `wm_reside_test`
proves the reservation: a program stamps `WMBASE`, a second *full-TPA* app
(running a real call chain) runs and exits, and the stamp is intact.

The 36 KB C `desk` also runs in the full TPA (it ignores `WMBASE`); it is
superseded by the resident kernel, not broken by it — and since the kernel is
no longer at `$D800`, a large desk no longer collides with it. (Staged
relocation off `$D800`, 2026-09-07; a later step folds the kernel into the OS
image as syscalls, freeing even the reserve.)

## The card-resident-list lever

The enabling trick, already proven in rung 2: **window content can live as a
card-resident command list** (`CLBEG`/`CLEND` on the graphics card). The card
holds the picture, so the resident kernel redraws any window with `CLRUN`
(two wire bytes) — *even after the program that drew it has left the TPA.* A
window's content survives its author. This is what makes both later
task-switching options work, and it keeps the kernel's per-window cost tiny
(a rect, z-order, title, and a list id).

The exception is the **terminal** window: `TEXT` cannot be recorded into a
list (the documented limitation), so the kernel owns terminal content
directly — a small ring of text lines redrawn by resident code.

## Kernel surface (syscalls, planned)

Appended to the OS syscall table after `SYS_EXEC` ($2024):

- `SYS_WMOPEN(rect, title, kind)` → window id. Register a window; `kind`
  selects content backing (card-list id, terminal, or app-drawn).
- `SYS_WMCLOSE(id)`, `SYS_WMRAISE(id)`, `SYS_WMMOVE(id, x, y)`.
- `SYS_WMLIST(id)` → the card-list id to record content into.
- `SYS_WMRUN()` → hand control to the kernel event loop; returns when the
  user quits the GUI (or never, until then). Launches are `SYS_EXEC` from
  inside the loop, and because the kernel is resident, the loop resumes when
  the launched app exits.
- `SYS_WMEVENT()` → for apps that want to cooperate with the loop rather than
  own the screen: one pointer/key event, kernel-routed to the focused window.

`desk` becomes a ~1 KB launcher: ensure the kernel blob is loaded at `WMBASE`
(from `/bin/wmkernel.bin`, once), then `SYS_WMRUN`.

## Build ladder

1. **Foundation — DONE 2026-09-04.** `WMBASE` reserved; `p8cc --cstacktop`;
   `wm_reside_test` proves the high region survives launches.
2. **The kernel skeleton (asm) -- DONE 2026-09-04.** `os/wmkernel.asm`,
   assembled at WMBASE, loaded once by a stub via FRESOLVE+FFIND+FLOADAT.
   A bios()-callable jump table (WMBASE+0/3/6 = wk_init/wk_open/wk_repaint,
   +9 = 'WM' signature). Window records are copied RESIDENT (22 bytes each,
   up to 4); wk_repaint sets the text camera (RESETF, PROJCT 0 so z=0 TEXT
   is not near-clipped, MDIDEN, TSIZE), identity WINDOW/VWPORT, FLOODs the
   desktop, and draws each window's chrome + stroke-font title from the
   records. `wm_kernel_test` proves it: a stub opens two windows and EXITS,
   then a SEPARATE program calls wk_repaint and nothing else -- the two
   titled windows reappear, drawn wholly by the resident kernel from
   records the departed app left behind. ~1KB of the ~10KB budget.
   Traps: `.org $WMBASE` is required (pc starts at 0 even with --base);
   bios() needs a literal address (precompute WMBASE+3, not an expression);
   and -- the debugging saga of the rung -- a test that `exit`s to the
   monitor gets the BOOT SPLASH redrawn over its frame, so GUI frame tests
   must dump at the shell, never the monitor.
3. **Content lists -- DONE 2026-09-04; events next.** wk_draw maps each
   window's content rect (WINDOW/VWPORT, the lib_wm mapping) and replays
   its card list with `CLRUN` -- so window content lives on the card and
   redraws when the app is gone. `wm_kernel_test` now proves it end to
   end: the stub records a red box into card list 40, opens SHAPES with
   that list, and EXITS; the redraw-only program's frame still shows the
   red content, drawn by the resident kernel from a list on the card.
   THE REAL BUG this rung surfaced: **RESETF clears the card command
   lists** (`memset(cldef,...)`), so a resident repaint must never RESETF
   -- it sets PROJCT 0 / MDIDEN / TSIZE directly instead. Events are next:
   `lib_ptr`-equivalent parsing in asm (or a small resident C helper the
   kernel calls), focus, drag, close, the menu.
5. **Launch + resume:** `SYS_EXEC` from inside the loop; the launched app is
   a WM client (drawing into its window's card list) running in the full TPA;
   on exit the loop resumes with every other window intact. This is the
   payoff — desk survives the launch.
6. **Saved per-window context (the switcher):** each window keeps its app's
   state; focus-switch swaps the active TPA (state-only first, full-TPA-swap
   to disk as the deluxe variant — the two later options from the fork).

## Risks / open questions

- **Kernel event parsing in asm.** `lib_ptr`'s SGR-mouse + arrow parsing is
  ~2 KB of C. In asm it is the biggest single piece; may warrant staying a
  small loaded-high C helper the kernel calls, if the budget allows.
- **Reduced app stack.** RESOLVED by the `$5600` relocation (2026-09-07): with
  the kernel *below* the TPA, GUI apps regain the full ~37.9 KB TPA and the
  normal `CSTACKTOP` (`$F800`) — no per-app `--cstacktop`, same budget as any
  program. (The old `$D800` design gave apps only 28 KB.)
- **Kernel loading.** The blob is `/bin/wmkernel.bin` loaded to `WMBASE` on
  first `desk`; it is position-fixed (assembled `--base WMBASE`), not a TPA
  program. A presence byte at `WMBASE` lets `desk` skip reloading.
