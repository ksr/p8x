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

Boot is **unchanged**: monitor → `B` → shell. The GUI is opt-in — but the
kernel needs **no loading at all**: it is part of the OS image, resident from
boot, reached through the OS syscall table.

```
  $2000            OS (resident) — INCLUDING the WM kernel (syscalls $2027-$204B)
  $5ED7            end of the OS+kernel image (~41 B growth room)
  $5F00            tab-complete scratch (256 B)
  $6000            OS/BIOS scratch
  $6A00  TPABASE   ── full TPA for apps ($6A00..CSTACKTOP, ~37.9 KB) ──
  $F800  CSTACKTOP  apps' C stack top
  $F800..$F9FF     shell command-history ring (8 × 64 B)
  $FA00..$FBFF     FSDIRBUF: the C commands' dir/glob sector page (dir, cat, glob_expand)
  $FC00..$FDFF     RDBUF: the C commands' shared file-read buffer
  $FE00..$FEFF     hardware (P3) stack, grows down from STKTOP
```

The kernel body (`os/wmkernel_body.asm`) is `.include`d at the end of
`p8xos.asm` and exposed as six syscalls right after `SYS_EXEC`: `$2027
SYS_WKINIT`, `$202A SYS_WKOPEN`, `$202D SYS_WKREPAINT`, `$2030 SYS_WKRUN`,
`$2033 SYS_WKSAVE`, `$2036 SYS_WKLOAD`. Apps load into the **full** TPA with
the normal C stack — nothing is compiled with a special `--cstacktop`, no TPA
is surrendered. The OS image grew from 12.4 KB to 15.2 KB.

**Why the history ring moved.** The old map called `$51C5..$6000` the "OS
growth reserve", but it was never free: the shell's 2 KB command-history ring
sat at `$5800..$5FFF` and its tab-complete scratch at `$5700`. Folding the
kernel in grew the image to `$5B4C` — straight into the ring — and every typed
command line overwrote live kernel code with ASCII (the crash trace showed
`wk_draw` executing the bytes of "`un /bin/d`"). OS + kernel + a 32-line
history cannot fit in 16 KB in *any* arrangement, so the ring shrank and moved
above `CSTACKTOP` — to `$F800`, and to **8 lines**, because only `$F800..$F9FF`
(512 B) is free up there: `$FA00` is the commands' FSDIRBUF dir/glob page and
`$FC00` their RDBUF read buffer — fixed `#define`s in `lib_*.c`, invisible to a
memmap-anchor search, which is how a first 16-line attempt briefly overlapped
FSDIRBUF. The completion scratch moved to `$5F00`. All single-sourced in
`gen_memmap.py`; the ring code is fully symbolic (`#HISTN-1` mask,
`#>HISTRING`), so no shell code changed.

The 36 KB C `desk` also runs in the full TPA; it is superseded by the resident
kernel, not broken by it. (History: the kernel was first a standalone blob at
`$D800` above the TPA — a 28 KB app cap, and it collided with desk — then
briefly at `$5600`, which sat inside the history ring; both retired 2026-09-07.)

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

`desk` becomes a ~1 KB launcher with no loading step at all: `SYS_WKINIT`,
`SYS_WKOPEN` its windows, then `SYS_WKRUN`. The kernel is already resident.

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
5. **Launch + resume — DONE 2026-09-07, as a real program.** `wdesk` is the
   thin launcher: `SYS_WKINIT`, `SYS_WKOPEN` its windows (SHAPES with a
   card-list scene), `SYS_WKPATH "/bin/paint.bin -w"`, `SYS_WKRUN`. Pressing
   `l` makes the kernel `SYS_EXEC` paint OVER wdesk; paint, seeing `-w`, calls
   `SYS_WKRUN` on quit and the desktop returns with every window and its
   card-list content intact. `c_wdesk_test` proves it end to end. The new
   `SYS_WKPATH` (`$2039`) makes the launch target the client's choice (the
   default `/bin/wapp.bin` keeps the WM tests' client). This is the payoff —
   the desktop survives launching an app — which `desk` (WM in the TPA)
   cannot do.
6. **Focus + close boxes in the kernel — DONE 2026-09-07.** Focus IS the top
   record: `k_raise` moves a record to the top slot (TAB raises the bottom
   window; a mouse press hit-tests ALL windows top-down via `k_hit` and raises
   the hit one). `wk_draw` gives every window desk's chrome — a 14-row title
   bar, white when focused and grey otherwise, a 9×9 black close box at
   `x+3..x+11`, black title text at `x+16`; pressing the close box pops the
   (now top) record. `wm_focus_test` proves TAB, the bar colours and the
   close. Cost: **+673 B** — the OS image now ends `$5E16`, **234 B** short of
   the completion scratch at `$5F00`.
   **THE WALL.** A menu bar with a press-slide-release pull-down is ~400 B of
   this asm and does not fit; FILES, TERM and VIEW (thousands of bytes) never
   will. The OS image is at the 16 KB cap, so the kernel must stay a SMALL
   resident core — windows, z-order, chrome, drag, launch-and-resume — and the
   rich UI belongs in the CLIENT, which has the 37 KB TPA.
7. **`SYS_WKEVENT` — the client-driven loop — DONE 2026-09-07.** `wk_run`'s
   internal loop is now a one-event *step*, `wk_event` (`SYS_WKEVENT`, `$203C`):
   it handles the events the kernel owns (TAB focus, arrows, mouse press/drag/
   release → raise/drag/close) and returns to the client — **carry set = quit**,
   else `A = 0` (kernel handled it) or the **key byte** the kernel does not own.
   `SYS_WKRUN` becomes a thin loop over it, so every existing test still passes
   (behaviour unchanged) at **+20 B**. `wm_event_test` proves a client drives
   the loop: the kernel moved the window on an arrow and handed the client an
   unowned `x`. This is the split that lets the rich desktop live in the
   client: `wdesk` can now draw its own menu bar and run FILES/TERM/VIEW,
   acting on the keys and (next) the menu-bar clicks the kernel returns, while
   the kernel keeps the windows alive across launches.
8. **The client's menu bar — DONE 2026-09-07.** `wdesk` is now a real
   `SYS_WKEVENT`-driven client with **its own menu bar** (`DESK  L=PAINT
   C=CLOSE  Q=QUIT`, drawn in the top rows by the client, not the kernel). It
   drives the kernel one event at a time; the kernel handles window mechanics
   and returns the keys it does not own, and the bar acts on them: **L** launches
   paint over wdesk, **C** closes the top window (the one new kernel primitive,
   `SYS_WKCLOSE` `$203F`, +14 B), **Q**/`^D` quits. The launch/resume now brings
   back the *client*: paint `-w` re-execs `wdesk -r` (RESUME: windows are in the
   kernel, so it just redraws them and the bar) instead of the kernel's bare
   `SYS_WKRUN`. `c_wdesk_test` proves the bar is drawn, the launch runs paint,
   and the resume restores windows + content + bar. The rich UI is in the client
   (37 KB TPA); the OS grew only the 14-byte primitive.
9. **A CLICKABLE menu bar — DONE 2026-09-07.** `SYS_WKEVENT` now returns a
   third kind of event: a mouse press in the top rows (cell y ≤ 2, below no
   window) comes back as `A = 2` with the cursor **column** in a new one-byte
   accessor `SYS_WKARG` (`$2042`). Keys likewise moved behind `SYS_WKARG`
   (event `A = 1`, byte via `SYS_WKARG`), so the `SYS_WKEVENT` return is now a
   clean event *code* (0 handled / 1 key / 2 bar-click / carry quit). `wdesk`
   draws its words (`DESK  PAINT  CLOSE  QUIT`) at known columns and maps a
   click's column to the same action as the L/C/Q keys. `wm_barmenu_test`
   clicks the CLOSE zone and the window closes. **Gotcha fixed:** an accessor
   that returns a value must `CLC` — `SYS_WKARG` first returned a stray carry,
   which `bios()` folded in as bit 256 (`26 → 282`), picking the wrong action
   nondeterministically. Kernel headroom is now ~143 B before `$5F00` — the
   core is nearly full, as intended.
10. **FILES — a directory listing in a client-drawn window — DONE 2026-09-07
    (read-only).** The content model that FILES / TERM / VIEW all need: the
    kernel exposes a window's rect (`SYS_WKGET` `$2045`, index in `A`, record →
    `P1`) and the top index (`SYS_WKTOP` `$2048`). `wdesk` opens a FILES window,
    reads the CWD once (`FOPENDIR`/`FNEXT`, cached — not per repaint), and after
    each kernel repaint draws the entries as stroke text **inside** the window:
    it sets `WINDOW`/`VWPORT` to the body (desk's `wm_vwin` idiom, `cw=w-2`,
    `ch=h-15`) so the card clips the text to the window, then restores the
    identity camera for the menu bar. It draws the listing **only when FILES is
    the top window** (`SYS_WKTOP`), so client-drawn dynamic content composites
    correctly without a full kernel compositor. `c_wfiles_test` proves the
    listing text is in the window body while SHAPES' card-list content coexists.
    **The kernel is now essentially full: ~94 B before `$5F00`.** Further window
    *accessors* are cheap, but no more sizable kernel code fits — which is the
    point: FILES selection + open, TERM, and VIEW are all CLIENT work from here
    (in-window clicks/keys can ride the existing `SYS_WKEVENT` return; a content
    callback is the alternative if per-window compositing is needed). **Next:**
    FILES selection + open (click a row → launch a `.BIN` / navigate a dir),
    then TERM, then the asm `/bin` twin.
11. **FILES is now interactive — DONE 2026-09-07 — pure client, no kernel
    change.** With FILES focused, `n`/`p` move a highlighted selection (the
    selected row is drawn yellow, the rest cyan-for-dir / white-for-file) and
    `ENTER` opens it: a directory re-reads the CWD into `wdesk`'s cache and
    relists (`..`/`.` go up), a `.BIN` launches via `SYS_EXEC` with `-w` so it
    resumes the desktop on quit, other files are skipped. Keys that FILES does
    not own still fall through to the menu-bar letters. This validated the
    rung-10 content model end to end — the kernel handed over only the window
    rect and the unowned keys; selection, the directory cache, navigation and
    launch are all in the ~37 KB TPA client. **The p8cc unsigned-compare trap
    bit here:** the "no action" sentinel was `-1`, but p8cc compares are
    UNSIGNED, so `a = -1; a >= 0` is *true* (`-1` == `0xFFFF`); non-menu keys
    fell into `act(-1)` → the default `return 1` → quit. Fixed with a `99`
    sentinel and an explicit `a < 3` test (in both the key branch and the
    bar-click branch, and `act_at` returns `99`). `c_wfiles_test` now also
    asserts the selection moves on `n` and that `ENTER` changes the listing.
12. **TERM — a command line in a client-drawn window — DONE 2026-09-07 — and
    windows are now addressed by TITLE, not index.** TERM is a scrollback
    (5 lines) plus an input line, drawn by `wdesk` in its window body exactly
    like FILES. While TERM is focused it owns the whole keyboard (so `l`/`c`/`q`
    type, they do not fire the menu — the bar stays clickable); `ENTER` runs the
    typed line, resolved the way the shell resolves a bare command (absolute
    path as typed, else `/bin/<name>`, `.bin` appended when missing) and
    launched with `-w`, so a WM-aware app resumes the desktop and a failed exec
    shows `?EXEC`. It is a launcher with history, like desk's TERM — `SYS_EXEC`
    *becomes* the program, so TERM does not capture a program's output (that is
    the per-window tty, a separate later rung). **The rung forced a real fix:**
    `k_raise` PHYSICALLY REORDERS the window records, so a fixed array index
    (`files_win = 1`) does not track a given window across any focus change —
    the rung-10/11 FILES code only worked because its test never changed focus
    first. wdesk now identifies the focused window by the FIRST LETTER of its
    title (`S`/`T`/`F`), which rides in the record and is stable across
    reorders: `content_draw()` reads the top window's record (`SYS_WKGET` of
    `SYS_WKTOP`) and dispatches on `title[0]`, and the key router does the same.
    This both enables TERM and fixes the latent FILES-after-TAB bug. Three
    windows now (SHAPES/TERM/FILES) against the kernel's `MAXWIN` 4, no kernel
    change. `c_wterm_test` proves it by frame-hash differentials (focus, typing
    and submit each change the frame) plus a pixel check that the white
    scrollback GROWS when a command is submitted (SHAPES has no white and TERM
    is on top of its region, so that white is TERM's own).
13. **VIEW — a picture window — DONE 2026-09-07 — and a small kernel primitive,
    `SYS_WKRAISE`.** Opening a `.p8i` from FILES opens a VIEW window sized to the
    image and streams the picture into its body, one card `BLIT` per row — desk's
    `drawview`, moved into a kernel window via the rung-10 content model (`WINDOW`/
    `VWPORT` to the body, re-read from disk each repaint, no framebuffer). VIEW is
    the on-demand 4th window (`MAXWIN` is 4): the first `.p8i` opens it (added on
    top = focused); a later `.p8i` re-fronts the *same* window. That re-front is
    the one thing the client could not do — z-order is the kernel's, and only
    `SYS_WKEVENT`'s TAB raised anything — so this rung adds **`SYS_WKRAISE`**
    (`$204B`): `A` = window index → raise it to top. It just exposes the existing
    internal `k_raise`, so it is ~7 bytes (OS ends `$5EAA`, 86 B before the
    `$5F00` ceiling). The client turns a *title* back into the *index* the syscall
    needs with `win_index()` (scan the records for the title letter) — the exact
    inverse of title-dispatch. Adding a z-order primitive to the kernel is
    on-strategy (mechanism in the kernel, policy — *which* window — in the
    client), unlike the UI, which stays out. `c_wview_test` opens a 40×30 green
    `.p8i` and asserts ~1200 green pixels appear inside a VIEW window that was not
    there before. Note the cost model: with no framebuffer the image re-streams
    from disk on every repaint, so dragging VIEW is slow — a per-window content
    cache is a later refinement.
14. **Saved per-window context (the switcher):** each window keeps its app's
   state; focus-switch swaps the active TPA (state-only first, full-TPA-swap
   to disk as the deluxe variant — the two later options from the fork).

## Per-window command output — the OUTCH→window sink (design, 2026-09-08)

The endgame: type `dir` (or `cat`, `wc`, any text command) in a window and see
its output **in that window**, with ZERO changes to the command. This is the
"real TERM" the launcher-TERM (rung 12) stands in for. It is a multi-rung OS
change; this section fixes the architecture so the rungs are well-founded.

**The stdout seam already exists.** Every text command writes through the OS's
`OUTCH` ($2009 `SYS_PUTC`), which already branches on `REDIRF`: 0 = console
(ACIA), 1 = append to a RAM capture buffer at `RPTR`, 2 = stream to an open
file (`FPUTB`). Adding a **mode 3 = "draw into the active window"** is the whole
idea — every command then renders in a window through the same seam it already
uses, unchanged.

**The scrollback is the card list, not CPU RAM.** The naïve worry — per-window
scrollback buffers (~250 B × 4 windows) in a machine with no spare RAM — is a
non-problem, because the kernel already **replays each window's card list on
every repaint** (`wkd_cnt: if klist!=0 CLRUN klist` — this is how SHAPES draws).
So mode 3 does not buffer text in RAM; it **records `MOVE3`+`TEXT` into the
window's card list** as bytes arrive. The card retains it; a repaint replays it;
persistence is free. Per-window state shrinks to a tiny **cursor** (col, row,
list-id) — a handful of bytes in a small kernel table, not a record blow-up.
Scrolling past the window bottom is the one hard case (card lists do not scroll);
v1 wraps and, on overflow, clears the list and restarts at the top (a simple
"screen-full then clear" terminal), with a real scroll a later refinement.

**Control flow — the script-chain, so wdesk stays the client.** The wall is
`SYS_EXEC`: it BECOMES the command, so control returns to the shell, not to
wdesk. Rather than move the desktop loop into the OS shell (which would undo the
kernel-lean/client-rich split we just built), wdesk chains through the OS's
existing **script mode** (`SCRIPTM`, the `sh` machinery): on TERM ENTER it (1)
points the sink at the TERM window (mode 3, cursor home), (2) writes a two-line
script — `<cmd>` then `run /bin/wdesk.bin -o` — and (3) hands the shell that
script and returns. The shell runs the command (its `OUTCH` bytes record into
the window's list) then re-execs wdesk, which resumes with the output already on
the card. wdesk stays the desktop driver; the OS gains only the sink. (Cost: the
screen shows the command run on the desktop, not live-in-window mid-run — output
appears when wdesk resumes. Acceptable for v1; true live rendering needs the
shell itself WM-aware, a later fork.)

**The budget wall is the real prerequisite.** Mode-3 code (record a glyph, wrap,
newline, clear-on-overflow) is ~80–120 B and MUST be OS-resident (it runs while
the command owns the TPA, so it cannot live in wdesk). The OS ends `$5ED7`, only
~41 B before the `$5F00` tab-complete scratch. So the first rung frees room by
relocating that scratch (`CMPPFX`/`CMPLCP`/`CMPDIR`, three strings at `$5F00`)
down into the `$6000` BIOS/FS scratch page (or folding them into existing
buffers), lifting the ceiling ~256 B. This is invasive (the completion code
names those addresses) and gated on the full suite + a tab-complete test.

**Slice plan (each a shippable, tested rung):**
- **15a — reclaim OS budget — DONE 2026-09-08.** The tab-complete scratch strings
  (`CMPPFX`/`CMPLCP`/`CMPDIR`) pinned the OS ceiling at `$5F00`. First packed to
  the top of their page (`$5F70`, +112 B); then, when 15b's sink turned out to be
  **255 B** (the 16-bit idiom is ~2× a first estimate — a MOVE3 is one opcode plus
  three little-endian pairs), the whole page was needed, so the strings were moved
  OUT of it to **alias `APBUF`** (`$6800`, the `>>` redirect-append buffer): the
  two are disjoint in time — completion runs only in the interactive line editor,
  the append buffer only during a redirect flush, and no program is loaded in
  either case. The OS may now grow to `$6000` (the full 256 B page). Safe by
  construction and referenced only symbolically; `os_complete_test` passes with
  the aliased buffers.
- **15b — the sink (mode 3) — DONE 2026-09-08.** `OUTCH` gained `REDIRF=3`
  (`OUTWIN`): each stdout byte is recorded into the target window's card list —
  printable → `TEXT 1 char` (the card's TEXT auto-advances the pen, so no per-char
  `MOVE3`), LF → drop a line + `MOVE3` home, CR → `MOVE3` home. `SYS_WKSINK`
  (`$204E`) arms it: `A` = window index → read the record's list id + height, home
  the cursor near the top (`y = h-29`, y-up local), `CLBEG` the list, set
  `REDIRF=3`; `A = 255` disarms (`CLEND`, `REDIRF=0`). No wrap/scroll yet — long
  lines and past-the-bottom output just clip. The whole thing is ~130 B of new
  asm; OS ends `$5FD6`, 42 B under `$6000`. `c_wsink_test` arms the sink at a
  window (content = card list 40), prints two lines, disarms, repaints — and the
  text appears ONLY via the kernel's `CLRUN` of the list (recording draws nothing
  live), proving it recorded into the list and persists.
- **15c — wire TERM through the script-chain.** wdesk TERM ENTER arms the sink,
  writes the `<cmd>` + `wdesk -o` script, hands it to the shell; `wdesk -o`
  resumes. `dir`, `cat FOO.TXT`, `wc` now render in the TERM window. Open issue to
  settle here: whether `REDIRF=3` survives the shell's command dispatch (the shell
  resets `REDIRF` at the prompt) — the arm may need to move into the script path.
- **15d (later) — real scroll**, and eventually a shell-WM path for live
  mid-command rendering.

## Risks / open questions

- **Kernel event parsing in asm.** `lib_ptr`'s SGR-mouse + arrow parsing is
  ~2 KB of C. In asm it is the biggest single piece; may warrant staying a
  small loaded-high C helper the kernel calls, if the budget allows.
- **Reduced app stack.** RESOLVED (2026-09-07): with the kernel folded into the
  OS image (below the TPA), GUI apps have the full ~37.9 KB TPA and the normal
  `CSTACKTOP` (`$F800`) — no per-app `--cstacktop`, same budget as any program.
  (The old `$D800` design gave apps only 28 KB.)
- **Kernel loading.** RESOLVED (2026-09-07): there is no blob and no load step.
  The kernel is `.include`d into `p8xos.asm` and reached via syscalls
  `$2027..$2036`, resident from boot. The standalone `.org`'d harness
  (`os/wmkernel.asm`) and `wm_reside_test` are retired — OS residency across
  launches is exercised by every remaining WM test.
