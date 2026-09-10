---
name: project_p8x_two_mode
description: "Major direction (2026-09-09): P8X runs headless-serial OR graphics-desktop by a graphics_present flag; full-screen apps + Finder retire tiled wdesk; glass TTY behind CONOUT"
metadata: 
  node_type: memory
  type: project
  originSessionId: 6ffcfef7-73ca-445b-bcdb-f57735fdc98f
  modified: 2026-09-10T12:35:34.523Z
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

**P4 APPS MENU + P5 TERM/WRITE DONE (2026-09-10), on graphics-card:** finder
APPS menu (press 'a' -> dropdown, letter launches: P paint/T term/W write/C cube/
H house/G gl; reuses launch()). term.c = on-screen shell (enables glass console
GCONEN=1, each cmd runs via /TERM.RUN = "<cmd>\nrun /bin/term.bin -c" SYS_RUNSH,
persists by re-launching in continue mode -c which SKIPS GCLS to keep the screen;
exit -> SYS_EXEC finder). write.c = full-screen text editor (2KB flat buf +
cursor offset, insert/backspace/newline, arrows incl up/down via lstart/lnext/col
helpers, ^O save ^X/ESC quit->finder, wraps at 78 col, no vscroll yet). Both
C-only, in run.sh 3 lists + man pages + tests c_finder_apps/c_term/c_write
(test-gfx). WHY term re-launches: NO run-and-return syscall (SYS_EXEC/SYS_RUNSH
both REPLACE the caller). PAINT/IMAGE ADAPTED (2026-09-10): PAINT needed NO change -- launched from the
APPS menu (no -d flag) it RTS's to the shell and the Finder launch-script's 2nd
line re-launches finder (paint's -d/-w chain to desk/wdesk is legacy, unused by
Finder). IMAGE gained a VIEW mode: `image /abspath` (bare absolute path) clears +
draws full-screen at 0,0 + waits for a key (bios CONIN $0100) + returns; Finder's
open_sel now launches "run /bin/image.bin <path>" for a .P8I (isp8i helper; builds
the cmd in a global icmd[]). Test c_finder_open_test.sh. **KERMIT DONE (2026-09-10)
-> P5 COMPLETE, ALL PHASES P1-P5 DONE:** os/commands/kermit.c = `kermit send|recv
/path` over the P3 2nd ACIA ($FF08/$FF09): minimal Kermit-style packets SEQ/LEN/
data[LEN]/CHK (CHK = sum of data & 255), LEN=0 packet = EOF; a2put/a2get poll the
port directly (status bit1 TDRE to send, bit0 RDRF to recv). Fire-and-forward
(no ACK/NAK). recv DELETES then FWOPENs the target, verifies each CHK (?checksum
on mismatch). Run from the shell or Term, NOT the APPS menu (needs a verb+path
arg). C-only (asm twin BACKLOGGED with screen's -- twin needs the 2nd-ACIA poll +
FS wrappers). Wired into run.sh 3 lists + man/kermit + Makefile test-io. Test
c_kermit_test.sh = byte-exact send->cap.dat(-2o)->recv->cmp round-trip, one P8X as
both peers via the emulator's file-backed 2nd port.

**P4 FIRST CUT DONE (2026-09-09), on graphics-card:** finder.c = full-screen
Finder desktop (NO tiling): white menu bar (FINDER + cwd + key hints) + the dir
as a scrolling file list (dirs cyan, selection = yellow bar). Keyboard: Up/Down,
ENTER opens dir / LAUNCHES .BIN full-screen (SYS_EXEC = BECOME the app),
Backspace up, q quits to shell. Claims screen (GTSUSP=1) + draws own GL; MUST set
PROJCT 0 itself (gsetup: WINDOW/VWPORT/PROJCT 0/MDIDEN/TSIZE -- no WM kernel to do
it) else TEXT near-clips invisible. Decodes arrow ESC-seqs ITSELF (rawkey is RAW,
returns bytes; the 128-131 arrow codes came from the WM kernel which finder
doesn't use). p8cc GOTCHAS hit: NO `break` (use a `going` flag); array size must
be a LITERAL (char fnam[312], not [NN*13]). Reuses desk's fscan/pjoin/pup/ftype.
In run.sh's 3 GUI build lists + man page (os/man/finder, auto-installs) + tests
c_finder_test.sh + c_finder_ret_test.sh (test-gfx). C-ONLY (no asm twin).
AUTO-RETURN DONE: launching a .BIN writes /FINDER.SCR = "run <app>\nrun
/bin/finder.bin <cpath>" and SYS_RUNSH's it (NOT SYS_EXEC) -- app quits (plain RTS
to shell) flows to the re-launch line, no per-app flag (the wdesk-TERM trick).
finder takes an optional dir arg (argstr) to resume where it was. FSCAN GOTCHA:
the dir list includes ".." FIRST (even at root), so the selected .BIN is usually
NOT index 0 -- a launch test must DOWN past "..". DEFER -> BACKLOG: Apps menu,
mouse, rename/dup/move, Term+Write apps (P5), retire desk/wdesk.

**P3 emulator DONE (2026-09-09), on graphics-card:** 2nd serial port = 2nd ACIA
at ACIA2S $FF08 / ACIA2D $FF09 (memmap), register-identical to the console ACIA
($FF04/$FF05): status bit0 RDRF, bit1 TDRE; data rd=RX, wr=TX. Emulator backs it
with a FILE PAIR -- `-2i <file>` RX, `-2o <file>` TX (self-testable + pipeable to
host kermit). Additive (new addrs/flags, nothing else touched). Test
c_serial2_test.sh (in test-io). HW = a 2nd 6850 at the same window (FPGA/TTL
track, not built). The serial-terminal/Kermit command that drives it is P5.

**P2 ALWAYS-ON + MONITOR ON SCREEN DONE (2026-09-10), on graphics-card:** the
user REVERSED the opt-in call (notes review: "the screen is the text display for
the monitor and the OS"). DISPINIT now: GCONEN=1 when GLID='G'; MONFONT installs
/FONT.GL from the CF root (CFSTAT==$FF pre-check = absent CF, skip; CFINIT; FNORM/
FOPEN with P1=IBUF/FGETB -> GLDATA with GLSTAT bit7 backpressure; root dir extent
is already the default after COLD); GTINIT blanks + homes; the GRAPHICS AVAILABLE
banner is the first text ON THE LCD pre-boot (proven: 568 px top-left, no OS).
Font is 5376 B vs ~3 KB free ROM -> disk, not ROM. Boot splash (DSPTAB) RETIRED.
CONSOLE MODEL (the key decision): clear on TAKEOVER (wake/exit) but NOT on RESUME
at the prompt -- keeps gl chains / tri k / rotate+camera replays working; `screen
on` = explicit clean console. Collision (3) (echo in byte-exact tests) is a
MEASUREMENT problem: tests switch the console off via the MONITOR from the -i
script -- `E 60AF\r00.G 014E\r` before `B\r` (E=examine/modify: two hex digits
write+advance, `.` quits; G 014E = JSR GCLS clears the E-echo) -> proven 0 px
pristine black, serial intact, NO per-disk screen.bin. LESSON: retiring the splash
EXPOSED a latent FALSE POSITIVE -- c_demo sent `exit` then asserted lit>1000 /
red px, which the splash (border + red swatch after exit->DISPINIT) satisfied,
not house/tri; fixed by grabbing while the program owns the screen. house DOES
draw fine under always-on (1557 px) -- a "PROJCT-0 glpmode pollution" theory was
tested and REJECTED (don't chase it again). ALSO: editing help.c text broke
c_help_test's literal grep ("windowed GUI") -- run a command's test after
rewording its output, not just compile it.

**P2 FIRST CUT, OPT-IN (2026-09-09), superseded above:** glass TTY WAS OFF by
default (GCONEN $60AF = 0); `screen on` (os/commands/screen.c, C-only, needs asm
twin) enables it, `screen off` disables. PUTCTX gates on GCONEN first, so default
== pre-P2 EXACTLY (boot splash restored, CONOUT serial-only, whole graphics
ecosystem untouched, all tests green). WENT OPT-IN because an always-on global
CONOUT mirror had a huge blast radius: console + every GL program share ONE
screen + card pipeline state -> THREE collision classes (return-to-console clears
a program's frame before a test grabs it; console echo pollutes a card list the
OUTCH->window sink is recording -> fixed for the ENABLED case by SH_PROMPT NOT
resuming GTSUSP during a script; command echo dirties the framebuffer byte-exact
GL tests compare). Always-on coexistence = deferred sub-project (BACKLOG). glass
TTY = on-screen text console behind BIOS CONOUT. Monitor DISPINIT clears the GL screen + homes a
cursor when GFXPRES; PUTCTX (firmware/p8xmon.asm, the byte-pusher every output
funnels through) mirrors each byte to the screen via GL TEXT + serial. Draws with
the GTEXT recipe (PROJCT 0/MDIDEN/TSIZE/MDTRAN x,y,0/MOVE3 0,0,0/TEXT); glyphs
need the card glyph bank (OS FONTLD streams /FONT.GL at boot, THEN OS calls new
GCLS BIOS $014E to clear+home so the prompt starts clean). State = memmap bytes
GTCOL/GTROW/GTSUSP/GTXL..GTYH/GTCH/GTTMP/GTCNT ($60A5+). Geometry 80x30 (6px adv,
9px line). GOTCHA that bit: PUTCTX must SAVE/RESTORE P1 (TPA1L/PHA...) around
GTPUT -- PUTS/commands keep their string cursor in P1 and the glass code uses it
(else serial spews garbage). Emulator framebuffer is UNDEFINED under -ng (card
absent) so don't assert "black screen"; assert serial-clean instead. Test
c_glasstty_test.sh. CONSOLE-SUSPEND HOOK (GTSUSP $60A7) IS REQUIRED not optional:
glass TTY + GL programs share ONE screen, so a graphics program must suspend the
console (else its text + clear-on-full WIPE the graphics -- this broke
basic_gfx). Wiring: gpresent() sets GTSUSP=1 (all //#use gfx); paint/desk/wdesk +
BASIC set it directly; OS shell SH_PROMPT clears GTSUSP=0 (console resumes on
return); PUTCTX skips screen if GTSUSP. STATE-HYGIENE the glass TTY MUST leave
clean (shared card port): GTCLS ends PRMFIL 0 (outline, else stroke TEXT fills
invisible) and GTDRAW ends MDIDEN (else its per-glyph MDTRAN translates the next
client's geometry off-screen -- BASIC raw MOVE3/TEXT assumes identity matrix).
Both bit basic_gfx (BASIC captures mid-session via BYE->shell, no reboot-clear, so
that breakage was REAL). ARCH PRINCIPLE (user, 2026-09-09): each screen-owner
(program AND console) CONFIGURES THE GL PIPELINE FROM SCRATCH; nobody trusts
inherited state -- and the console CLEARS on takeover. BIG TIME-SINK LESSON: house
"drew 0px" and tri "red=0" were a PHANTOM -- the c_demo test sent `exit`, which
reboots the monitor -> DISPINIT -> GTCLS CLEARS the screen (correct: console
reclaiming per the principle) BEFORE the -g PPM grab at the cycle cap. house/tri
draw FINE (1557/813 px) when captured WHILE the program owns the screen. Fix:
c_demo drops `exit` before the framebuffer grab + dropped a bogus `lit>red`
assertion (its non-red px came from the old exit->splash swatches, not tri). No
PROJCT-native op / gpresent glpmode reset was needed (both were phantom fixes
chasing the exit-clear -- REMOVED). Test c_glasstty_test.sh. MVP CUTS -> BACKLOG: proper scroll (clear-on-full now; no
free RAM for a framebuffer -> card-list scrollback intended), per-cell erase (BS
ghosts), pre-boot monitor-on-screen (needs a monitor-side font load), speed.
ROM after P2: ends ~$144B, ~3KB free of the 8K.

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
