# SDRAM framebuffer — where this stands (2026-08-20)

## Achieved and on hardware

480x272 **RGB565 direct colour** (stage 6 — the 8 bpp palette era below is
history), framebuffer in the in-package SDRAM behind the streaming
controller; `IMAGE`/P8I photographs; and the full 3D arc — the software
pipeline (stage 7), the MDU (8a) and the geometry engine with page-flip
double buffering (8b) — all verified on the board. The chronology below is
kept as written, oldest first; the **State** section at the bottom is
current.

240x136 and `SCREEN` were retired -- nothing needed them, and dropping them
removed the read-modify-write path entirely (a 2 bpp artefact, never an SDRAM
one).

## The placement blocker: found, and it was not the scanout fix

The branch spent a long time believing the scanout fix (`75e166a`) cost +2,544
LUT4 and pushed the design off the placement cliff. Three controlled builds say
otherwise:

| tree | LUT4 | places? |
|---|---|---|
| `741430a` (pre-counter) | 12,853 (61%) | yes |
| `+ bfcdf27` fetch counter | 14,643 (70%) | no |
| `+ 75e166a` scanout XOR | 15,397 (74%) | no |

So the growth was split across TWO commits, and the design already failed to
place without the scanout fix -- reverting it never would have produced a
bitstream. `lbuf` was never the problem either: it maps via `$__GOWIN_SDP_` in
all three builds and BSRAM stays at 41/46 throughout.

**The real cause was `CF.buf_`, the 512-byte SD sector buffer in `rtl/cf_sd.v`,
which has nothing to do with graphics.** Bucketing the flattened netlist by
instance path put the entire growth in `CF`, and yosys said `using FF mapping
for memory p8x_top.CF.buf_` in every build:

```
                      pre        HEAD
CF.buf_ DFF          4,096       4,096
CF.buf_ LUT          5,671       7,365
CF.buf_ MUX          1,924       4,052
```

4,096 flip-flops plus a 512-entry read mux -- over half the logic in the whole
design -- and the mux half re-optimised to a different size on every unrelated
edit. That is what made "changes with no logical effect" move the LUT count by
thousands.

It was FF-mapped because IDENTIFY wrote the whole buffer in one cycle (a `for`
loop over all 512 entries plus 40 more for the model string). 552 write ports
means no RAM primitive can be used at all. **The same accident as the palette,
in a different file.**

The fix (`rtl/cf_sd.v`): the IDENTIFY fill walks the buffer a byte per clock
with BSY held, every writer muxes onto one write port, and both readers share
one asynchronous read. `idx` is a register, so yosys merges the address flop
into the RAM (`merged address FF to cell`) and the buffer maps via
`$__GOWIN_DP_` with the read timing unchanged.

| | before | after |
|---|---|---|
| LUT4 | 15,397 / 20,736 (74%, failed to place) | **7,226 (34%)** |
| DFF | 5,657 | 1,581 |
| BSRAM | 41 / 46 | 42 / 46 |
| Fmax | — | 51.6 MHz (PASS at 12) |

−4,076 flops and +1 block is the buffer, exactly.

## Then, in order

1. [x] **Load and confirm on hardware.** Done, from FLASH, after a power cycle:
   `I` prints the model string through the rewritten IDENTIFY against a real
   card; `BOX 0,0,479,271` reads back pen 224 at all four extreme edges, with
   the pixel one inside each edge background (outline exactly one pixel);
   `BOX ...,FILL` interior reads back and stops at its edge.
2. [x] Pixel-assertion tests -- reworked, and it was more than mechanical: two
   payload cases had quietly stopped testing anything (a "full-screen" box at
   (239,135), a clipping line to x=255 that is now on-screen), and the pens
   moved to the 3-3-2 primaries $E0/$1C/$03 so all eight pen bits are
   exercised. All suites and the co-sim pass.
3. [x] `SCREEN` removed from BASIC; `$B0` left deliberately unassigned (saved
   .BAS files are tokenised and old programs on disk still contain it).
4. [x] Docs: man page, language guide, READMEs, GLOSSARY, `gen_memmap.py`, and
   `STAGE2-DESIGN.md` now opens with a HISTORICAL header recording what of that
   design survived (16-bit coordinates, 0-255 pens, the 12-bit palette, 80-col
   GTEXT) and what did not (the modes themselves).

Nothing remains open in this handoff.

## Open question, not area-related

The scanout fix makes yosys emit `emulate_read_first` on `lbuf`: with
`rd_bank = bank ^ (px == H_TOT-1)` the read can hit the bank the fetch is
writing, at the same address, in the same cycle. Simulation is defined there;
a Gowin SDPB on a same-address collision is not. Worth confirming on the panel
before trusting column 0.

## RESOLVED (2026-08-19): the border's edges -- marginal capture on gapless CAS

The splash's 1-px border displayed with no left line and a doubled right line
while every sim was pixel-exact. The chase burned three wrong theories
(PLL-lock cold-init, capture-latency rotate, halfword-select skew -- each
predicted a subtly different wrong picture and died on evidence), and the
decisive instrument was the USER'S EYE on a two-line test pattern: both lines
visible, single width, but with SNOW -- frame-to-frame sparkle inside drawn
lines. Snow meant intermittent capture errors, which reframed everything:

  GAPLESS CAS STREAMS ARE ELECTRICALLY MARGINAL ON THIS BOARD. Mid-burst
  words mostly survive (occasional bit flips = snow); the first word of every
  line burst -- right after bus turn-on -- failed systematically (missing
  left edge); the last word misbehaved at the drain (doubled right edge).
  Single-word reads, with idle cycles around every access, have been solid
  since the vendored controller: POINT never misread once.

The fix: the stream issues its CAS every OTHER cycle (s_ph in p8x_sdram.v),
giving each capture the settled bus a single read enjoys. A 240-word line
costs ~510-560 of 1,680 cycles -- still 3x faster than the panel needs.
Verified on the panel: all four border lines, single width, no snow. The
lesson for the traps list: THE CHIP MODEL CANNOT SEE ELECTRICAL MARGIN --
sim-exact plus panel-wrong means analogue, and temporal noise (snow) is the
signature that distinguishes marginal capture from any logic bug, which are
deterministic. No logic theory explains sparkle.

## Traps this branch has already paid for

- **A LUT count that improves unexpectedly means broken logic** -- twice on this
  branch. It is not an absolute rule: the drop above is real, and the way to
  tell is that it comes with an arithmetic story (−4,076 DFF and +1 BSRAM is
  one 512-byte buffer) rather than a fold-away.
- **Attribute area before theorising about it.** Bucketing cells by flattened
  instance path found this in minutes; the previous sessions guessed at the
  module that had just changed and were wrong for hours. There is a throwaway
  script for it in the session scratchpad; the logic is ten lines.
- **A parallel write to a whole array costs a RAM.** Palette, then this. Any
  `for` loop that assigns every element of an array in one cycle is the tell.
- **Placement cliff.** Always check `p8x_lcd.fs`'s mtime before believing a
  result. (Much less pressing at 34%.)
- **imgsend's ack is transport, not content.** One clone delivered a
  binary with the right size and corrupt bytes; the program wild-jumped to
  the monitor while the same image ran clean in the emulator. A board
  program that crashes impossibly is PRESUMED CORRUPT: re-clone first,
  debug logic second. (Backlog: a verify pass.)
- **Two staleness surfaces**: bitstream and SD card. `?SYNTAX ERROR` on a
  graphics statement means the CARD is behind; `?No display` means the BITSTREAM
  is.
- **The co-sim cannot see scanout bugs.** It compares framebuffer contents.
  Anything about mapping to the panel needs `tb_sdram_scanout.v`.
- **A test that samples one pixel to measure a row property** will report the
  wrong bug when that pixel is broken. That cost several wasted iterations.
- **Writes are fire-and-forget, so their loss is silent -- and the panel is
  the only witness.** The stage-6 controller lost one engine write per ~400
  cycles under a scanout stream: a live pulse arriving in the chunk window at
  the exact edge refresh came due was preempted and fell into the one gap the
  rescue latch does not cover. Every bench passed, because no bench ever ran
  a WRITE STORM against a live stream (the interleave test used reads; the
  co-sim has no scanout). On the board the engine, window and refresh
  cadences phase-locked, so the rare race became a metronome: CLS-speed
  writes lost chunks at regular spacing -- striped bars -- while slow fills
  landed intact. tb_cls_stream.v now runs that storm and audits every word;
  the fix is SNEXT taking a live pulse before a due refresh, the ordering
  IDLE already documented.

## State

Branch `sdram-framebuffer`, `main` untouched throughout. **STAGE 6 SHIPPED
(2026-08-18, same day it was designed):** the board is RGB565 end to end. The
7,450-LUT4 bitstream is IN FLASH; the SD card carries the RGB() BASIC (cloned
over serial with imgsend.py, all 3,260 sectors acked). Verified on hardware
from BASIC itself: COLOR RGB(31,0,0) box edges read back -2048 through
POINT's two-byte GDATA stream, the green fill reads 2016, RGB() packs
correctly on-target. The panel showed the full-screen $F800 fill. The
streaming controller underneath was proven at 8 bpp first (0 underruns,
asserted in a bench that runs the real controller against a protocol-checking
chip model validated against the vendored RTL).

The first flashed build turned out to lose engine writes under the scanout
stream (see the trap below); the CORRECTED build (7,355 LUT4) is what is in
flash now, verified on the panel: a CLS write-storm plus colour bars, solid.
A power-cycle boot from this exact flash image has not itself been observed.

**2026-08-19: the machine drew its first photograph.** `IMAGE x,y,name$`
(BASIC, token $B2) loaded a 256x256 P8I of the USC mandrill off the SD card
and put it on the panel -- PNG -> tools/p8img.py -> P8I -> FGETB -> GCOL/
GCOLH -> PLOT -> SDRAM -> the streaming scanout, every link built and
verified on this branch. The emulator's -g screenshot predicted the panel
exactly, as the golden model should.

**2026-08-19/20, stages 7-8b, one arc: the machine learned 3D.** Stage 7
(SOFTWARE only, c29993f): lib_gfx.c (the C register veneer) + lib_g3d.c
(edge pool, window/viewport, muldiv-based pipeline) + the `cube` command —
2.4 fps as first built, 13.9 after the muldiv native-*// fast path, all
measured in the emulator. Stage 8a (f781547): the MDU, a hardware muldiv
at $FF30, bit-exact to the software contract, in BOTH build flavours;
cube 19.6 fps, the rest of the frame being p8cc plumbing. Stage 8b
(197f75e): the GEOMETRY ENGINE at $FF40 — edge list in SDRAM ($100000),
S7.8 matrix registers, a walker FSM around the shared mdu_core that
fetches/transforms/clips/projects/maps and then draws by mastering
gfx.v's OWN registers (gfx.v unchanged); PAGE-FLIP double buffering
(framebuffer pages at $00000/$80000, addr bit 19; flips latch at
frame_tick, rule: display <= draw, draw <= ~draw); sdram_arb gained the
g master (video > refresh > geometry > pixels). CPU cost of a cube frame:
1.94M -> 1.38M -> 85k cycles across the three stages. Verification:
tb_mdu (2,022 vectors), tb_geom (directed lines vs the SAME host replica
that pins the emulator; caught a MAC state-return bug and an upload-FIFO
overrun before silicon), all four prior SDRAM benches, and c_g3d_test's
crown jewel — the same pool rendered by the software walk and by the
engine (identity matrix) is BYTE-IDENTICAL. Designs:
STAGE7-DESIGN.md / STAGE8-DESIGN.md / STAGE8B-DESIGN.md. The 8b
bitstream places at 10,801 LUT4 (52%), 51 MHz.

The first 8b board run found the FLASHING-SIDEBAND bug (ff10c80): flipping
alternated the splash-cleared page 0 with never-written page 1 — raw SDRAM
stripes outside the viewport-scoped erase — and exposed the latent gap that
flips leave draw/display OPPOSITE with no way back. Fixes: GECMD 4 (PGSYNC,
draw rejoins display), lib g3flip()/g3sync(), cube clears BOTH pages on
entry and syncs on exit, and the EMULATOR now powers both framebuffer pages
on with fixed garbage (undefined DRAM, like silicon) so the new sideband
test fails on the unfixed cube — this class of bug now dies in simulation.
Rules of thumb: power-on framebuffer contents are undefined; a flipping
program clears both pages once and exits through g3sync.

**2026-08-20/21, stage 9 (branch g3d-stage9): colour, faces, and a
console for 3D.** 9a: TYPED RECORDS — every primitive carries its own
RGB565 colour (LINE 16 bytes). 9b: the TRI record (22 bytes), outline or
FILLED — screen-space scanline fill clamped to the viewport, every span
a height-1 BOXFILL, near clip to a quad fanned in fabric; tb_geom pins
105 exact spans to the same host replica as the emulator. 9c: parameter
READBACK (GEVAL/GEVALH read par[GESEL]) turned the engine into a
PERSISTENT SCENE STORE, and the shell grew a console: `tri` builds and
stacks (k appends via count readback), `rotate x y z [pivot]` respins
(no pivot = translation preserved, cube-style; pivot = T=P-R*P,
tri-style — the distinction was a user-found bug), `page` fronts the
flip machinery. 9d: `camera ex ey ez ax ay az` — the look-at eye/aim
camera, software-only on the matrix path (lib_g3cam, i3sqrt). 13,487
LUT4 (65%). Everything verified emulator -> bench -> panel -> POINT.
New traps paid: imgsend acks are transport not content (a corrupt clone
wild-jumped the machine); pipeline exit codes laundered a red suite
(twice); `break` is not p8cc; shared-lib growth taxes every client
(64K); unsigned m3mul needs magnitudes; g3d clients must watch the
CSTACKTOP gap; a wedged board needs a human reset.

**STAGE 10a IN PROGRESS (2026-08-23, branch graphic-test):** the GRAPHICS
LANGUAGE — the PGC-class command port (STAGE10-DESIGN.md; the Matrox
PG-640A manual at docs/reference/pg640a.pdf is the reference, its opcodes
kept verbatim). $FF50 GLDATA feeds a 256-byte FIFO; a consumer FSM in
p8x_geom decodes hex-mode commands and executes them through the SAME
walker pipeline the record engine uses (S_MAC for 3D, S_CS for 2D lines,
the T-path for fills, a new W-path for boxes), so the crown-jewel test is
op-stream EQUALITY: tb_gl drives one scene through both interfaces and
the register-write recordings must match element for element (they do);
the emulator's c_gl_test does the same as a framebuffer byte-compare.
Verbs live in 10a: COLOR/FLOOD/CLEARS (both pages!), MOVE/DRAW/POLY/RECT
(+R, 2D window space, no matrix — PGC semantics), MOVE3/DRAW3/POLY3(+R),
POINT/POINT3, PRMFIL, WINDOW/VWPORT (PGC x1 x2 y1 y2 order), FLIP/PGSYNC
(P8X opcodes 02/03), WAIT (real frame pacing), CA/CX stubs, error FIFO.
Trap paid: a walker state that raises gm_wr and drops to S_IDLE in the
SAME cycle loses the write — gm_own is already low when the strobe lands;
every issuing state must exit through a non-idle landing state (W_BOXC ->
W_BOXD). POINT is a degenerate LINE (same pixel, no new datapath); POLY
streams — one primitive per vertex, so 255 vertices never need more than
one vertex of buffer.

**STAGE 10b BUILT AND SIM-PROVEN (2026-08-24, graphic-test):** the matrix
verbs. MD*/VW* families, PROJCT/DISTAN, DISTH/DISTY/CLIPH/CLIPY, CONVRT
-- all card-side, all at COMMAND time: verbs compose two master matrices
(modeling, about the MDORG pivot; viewing, about VWRPT with negated
angles) and rebuild par[0-11]; the per-vertex datapath gained only a
parameterized near plane (par[23]) and its far mirror (par[24], 32767 =
off). Trig from generated twin tables (gen_trig.py -> trigtab.h +
trigtab.v). Defaults stay stage-9 native (K=256, dist=0): PGC projection
is opt-in via PROJCT, and RESETF's replay of the 10a scene byte-matches
gl_b.ppm -- the compatibility keystone test. Proof chain: c_gl_mat_test
(host replica marks + RESETF replay), tb_geom/tb_gl unchanged-green,
c_gl_rtl_test now byte-compares BOTH scenes emulator-vs-RTL through the
real pixel stack (10a and the 10b matrix scene: both identical, every
pixel). Board verification pending (card was unplugged).

**THE RECORD ENGINE IS RETIRED (2026-08-24, user-approved):** the $FF40
interface (GEUP/GECMD/GESEL/GEID) is gone from emulator and RTL; the GL
port is the one hardware 3D path, and GLSTAT bit6 now covers the walker
(there is no GESTAT to poll). Migrations shipped with it: image (C and
asm twin) does PGSYNC through GL, page speaks GL FLIP/PGSYNC, tri is a
GL emitter with the software path kept for the TTL machine; rotate and
camera answer ?No engine until GL command lists (10c) restore retained
scenes; cube runs its software path. Suites re-anchored: c_gl_test's
crown jewel compares GL against the LIB'S SOFTWARE WALK (stage 9 proved
software == engine), plus a new FLIP/PGSYNC semantics part; tb_geom is
deleted; tb_gl checks directed constants (105 exact spans). The command
FIFO shrank to 64 bytes -- poll GLSTAT bit7, the documented contract.

**AND STILL 10b DOES NOT PLACE.** The retirement bought 2,504 LUTs and
`synth_gowin -family gw2a` (a flag build.sh had never passed) moved 19
multipliers into the idle DSP blocks -- but nextpnr's "LUT4 92%" line
UNDER-REPORTS on Gowin: ALU carry-chain cells occupy the same physical
LUT sites, so true demand is LUT 19,249 + ALU 4,368 ~ 114%. p8x_geom
alone is 8,739 LUT + 1,766 ALU -- half the chip -- dominated by the
indexed matrix/polygon register arrays. THE FIX LANDED the same day:
the compose scratch matrices moved into one mirrored distributed-RAM
scratchpad (M/VR/MS/CT at fixed offsets, registered read ports, a
job-driven writer state for identity/rotation/scale/translate/pbuf
loads), and 10b PLACES -- 18,703 LUT4 (90%), Fmax 45 MHz, bitstream
packed. Every suite stayed green through the rework, both pixel scenes
still byte-identical emulator-vs-RTL. Board verification is the one
step left (the card was unplugged).

**STAGE 10c EMULATOR HALF SHIPPED (2026-08-25):** COMMAND LISTS. 256
lists in 4KB slots; recording flows bytes through the normal decoder
with execution suppressed (command boundaries tracked -- a parameter
byte can never fake a CLEND); replay switches the interpreter's byte
source; CLOOP accumulates matrix deltas per pass (the fly-through,
proven byte-identical to N immediate frames); CLAPP is the P8X append.
The console family speaks it: tri records/appends LIST 0 (the scene),
rotate (DEGREES now, brads died with the sine table) and camera replay
it with new matrices, cube CLOOPs a self-spinning frame with the CPU
idle. Trap re-paid: cube's GL branch pushed the binary past CSTACKTOP
and the stack ate the code (crash-to-monitor signature); deleting its
dead stage-8b path fixed it. c_gl_list_test + the full gfx group green.
STILL OPEN: the 10c RTL -- the SDRAM port returns (store/fetch/bitmap),
paired with moving the walker's polygon arrays into the scratchpad RAM
for placement headroom. Semantics are pinned; the benches will catch
any divergence.

**STAGE 10c RTL LANDED (2026-08-25): command lists in fabric, and it
PLACES — 19,129 LUT4 (92%), Fmax 44 MHz, bitstream packed.** The SDRAM
g-port returned for the 64 x 4KB list slots; recording rides the
decoder's byte pops (opcode-length table as a wire, execution
suppressed, bytes paired into halfword writes, per-byte overflow abort);
replay is a second byte source feeding the same interpreter; CLOOP
rewinds with matrix deltas accumulating. Getting it to PLACE took three
rounds of fabric surgery, each with its own lesson:

- The T-path's polygon arrays (qx/qy/qz + the mapped pair) moved into
  the compose scratchpad as lanes at 64/72/80/88/96 — every access
  became set/bubble/capture, ~15 states, zero pixels changed.
- A 128-deep scratchpad crosses yosys's BSRAM threshold: the mirrored
  1W2R pair became 2 blocks -> 46/46 exact-fit, placement died. Forcing
  it distributed cost ~700 LUT — ALSO died.
- The unlock: ONE true-dual-port block. The FSM is single-threaded and
  never captures a port-A read in a write cycle (reads latch on the
  bubble before; cm_qa HOLDS through writes), so port A is
  write-else-read and port B read-only. No mirror, no mux tax.

Proof chain unchanged and green through all of it: tb_gl (record draws
nothing, CLRUN/CLOOP exact ops, errors 2/5/6/7), and c_gl_rtl_test's
three byte-identical frames — 10a scene, 10b matrix scene, and the 10c
CLOOP fly-through — emulator vs RTL through the real memory stack.
**BOARD-VERIFIED 2026-08-25**: bitstream flashed, fresh disk cloned
(4,190 sectors, every ack + 'K'), and the whole console family proven
on silicon in one scripted session — tri builds list 0, tri k appends,
rotate (degrees) and camera (look-at) replay it, and every POINT probe
matched the emulator's prediction exactly: -32/2047 at the oblique
camera view, 2016/-2048/31 on cube's three rings after `cube 32` spun
a CLOOP list with the CPU idle. Stage 10a+10b+10c are on silicon,
frame-exact. (Scripting note: BASIC's banner is "P8X BASIC V0", not
READY — match that in future sessions.)

**2026-08-25 (later): stage 10d — ASCII mode — built and placed.** The
translator front-end (keywords → opcodes, decimals → width-correct
params, CA/CX, deterministic error recovery) shipped in the emulator
and in fabric; the proof chain grew a FOURTH byte-identical frame
(c_gl_rtl_test: 10a scene, 10b matrix, 10c fly-through, 10d ASCII) and
tb_gl's ASCII section. Clients: the `gl` console command (one ASCII
line, or a .gl file streamed verbatim) and BASIC's GL statement
(TOK_GL $B3, string expression, wrapped CA ... CX). The translator's
~600 LUT4 blew the placement budget 10c left behind; the diet that
landed it is written up in STAGE10-DESIGN.md ("10d as built") — the
short of it: share arithmetic only where the routing mux already
exists (three shared muldiv-operand subtractors, one shared ±md_q
post-adder), and turn every aligned lane/slot address into a concat.
Places at 18,943 LUT4 / 91%, seed 1, 40.8 MHz on the 12 MHz clock.
The bitstream (p8x_lcd.fs) is BUILT but NOT YET FLASHED — the board
proof (type `gl DRAW3 90,-90,300` live, run a .gl file) plus the disk
rebuild carrying the new BASIC and /bin gl are the remaining rungs.
(The GL console family — tri, rotate, camera, cube, page, gl — is
C-only so far; the asm twins are an open item for the whole family.)

**2026-08-26: the GL verbs are native BASIC statements.** All 51
(2D/3D primitives, both matrix families, lists, pages — `MDROTY A*2`,
`POLY3 3,...`, `CLBEG 1 : MDROTY 5 : CLEND : CLOOP 1,7`) as tokens
$B4..$E6 through ONE generic handler; the name/opcode/arity tables are
a third gen_glkw.py output (basic/glkwtab.inc + glvtab.inc — token
order is ABI, append-only). Native statements send hex opcodes
directly (no 32-char string cap — which, it turned out, had silently
TRUNCATED basic_gl_test's 40-char POLY3 string all along, while the
test's probe pixel passed on the boot splash's green triangle;
the test now RESETFs, clears, and probes the real sliver), they
record inside CLBEG/CLEND, drain GLSTAT busy on exit (deterministic
POINT() on silicon; GL s$ stays the async path), and COLOR now feeds
both pens. man basic, man gl, and the programmer's guide carry it.
All 11 BASIC suites green. Another disk-rebuild deliverable for the
same bench session as the 10d bitstream.

**Silicon-only trap, found by the first 10d board session: the GL
walker MASTERS the 2D device, so $FF20-block reads (GID0/GID1
included) answer garbage while it draws.** The emulator interprets
synchronously and CANNOT see it. Symptom: `?No display` from the very
next graphics statement after a GL command that leaves the walker
busy (a CLEARS is milliseconds of box-fill). Fix: GCHECK now waits
for GLSTAT bit 6 to clear (when GLID says a GL engine is fitted)
before probing GID0 -- which also makes every graphics statement
implicitly sequence after outstanding GL work.

Three operational notes for whoever drives the board over serial next:

- **Two serial clients do not error -- they silently shred each other's
  characters.** A user terminal left attached while a script drives the
  port produces mangled commands on the machine and phantom fragments in
  the terminal, with no failure indication on either side. One client at
  a time; check before scripting. (Also: characters sent while a command
  is still RUNNING are lost -- no flow control, one-byte ACIA hold -- so
  scripted waits must exceed the slowest command; a 256x256 image draw
  was minutes before the inlined loops, ~11 s after.) And a KILLED session
  can ORPHAN its serial-holding child, which then silently eats every byte
  on the port with no error anywhere -- `lsof /dev/cu.usbserial*` before
  any scripted board session is the pre-flight that catches both this and
  a user terminal left attached.

- **The board can WEDGE where no scripted keystroke lands** (every line
  answers `?` or nothing; the panel sits on the splash). A scripted session
  cannot recover it — a HUMAN reset (button or power-cycle) can, and a
  bitstream reload usually can. So: every scripted session should begin
  with the openFPGALoader reload, and when sessions repeatedly bounce, ask
  the person at the bench to reset rather than burning retries -- their
  eyes on the panel are also the best verdict available.
- **Opening the serial port resets the machine.** Any scripted interaction must
  do everything in ONE session; a second open finds the monitor again, and its
  `?` replies to BASIC lines look confusingly like an interpreter fault.
- BASIC spells the filled box `BOX x0,y0,x1,y1,FILL`; `BOXFILL` is the DEVICE
  command name and is a syntax error in BASIC.
