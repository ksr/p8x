---
name: p8x-gfx-clib
description: "SHIPPED 2026-08-19 (c29993f): C graphics veneer lib_gfx.c + wireframe-3D lib_g3d.c + cube demo; key facts for future graphics/C work"
metadata: 
  node_type: memory
  type: project
  originSessionId: eb839e7b-2183-47af-84cd-a059555f72b5
  modified: 2026-08-31T11:46:14.643Z
---

SHIPPED 2026-08-19, commit c29993f (branch sdram-framebuffer): os/commands/
lib_gfx.c (//#use gfx -- peek/poke veneer: gpresent/grgb/gcolor/gcls/gplot/
gline/gbox(f)/gcircle(f)/gellipse(f)/gpoint), lib_g3d.c (//#use g3d --
STAGE7 wireframe pipeline), cube demo command, lib_gfx.inc equate twin,
emulator/test/c_g3d_test.sh. Design + measured budget:
fpga/tang-nano-20k/sdram/STAGE7-DESIGN.md.

Durable facts learned:
- p8cc.c (native self-host subset) has NO array brace-initializers --
  p8cc.py and the on-target cc do. C-only-command precedent: disasm.
  Libraries must stay native-parity clean (c_g3d_test part 3 enforces).
- muldiv fast path: when a*b fits 16 bits (test: a <= 65535/b), native */
  beat the all-C 32-bit loops ~10x (118k -> 10k cycles). p8cc statements
  cost ~500 cycles each through __ax; loops are brutal, builtins cheap.
- Display coordinate regs are UNSIGNED (zero-extended) -- negative coords
  land at ~65535, not off the left edge; software must clip first.
- cube: 13.9 fps (1.94M cycles/frame); ~130k cycles/edge; erase ~free.
- os/mandrill.p8i is now a TRACKED asset installed by run.sh (was only
  inside run-disk.img and a rebuild would have lost it).

STAGE 8a SHIPPED same day (f781547): the MDU — hardware muldiv at $FF30,
bit-exact to the lib_g3d contract, in BOTH build flavours; regs in
gen_memmap (MDA..MDQH, MDID probe reads 'M'/77); emulator instant-model;
lib_g3d probes (m3has) and falls back; tb_mdu.v 2022 vectors; 7964 LUT4
38%, flashed + verified on silicon (PEEK(65334)=77, cube corners).
muldiv ~4k cycles (poke-bound), cube 19.6 fps.

STAGE 8b SHIPPED AND ON SILICON (197f75e + fixes ff10c80, docs ea423ff):
p8x_geom.v at $FF40 — SDRAM edge list ($100000), S7.8 matrix param file
(GESEL/GEVAL/GEVALH indexed), walker FSM around shared mdu_core, draws by
mastering gfx.v's registers; page flip (addr bit19, display<=draw,
draw<=~draw at frame_tick); GECMD 4 = PGSYNC (draw rejoins display — the
ONLY way back to single-buffer). sdram_arb g master. lib_g3d: g3probe/
g3par/g3up/g3mat/g3flags/g3go/g3flip/g3sync; g3render auto-routes
(identity = BIT-IDENTICAL to software, tested byte-for-byte). cube v2:
static upload + per-frame matrix, ~85k CPU cycles/frame, vsync-paced.
Board verified: 69/77/-1-1-1/0 (GEID/MDID/corners/centre). 10,801 LUT4.

DURABLE LESSONS (sideband bug, ff10c80): power-on framebuffer pages are
UNDEFINED (raw SDRAM stripes); engine erase is viewport-scoped BY DESIGN;
flipping programs must clear BOTH pages once (gcls/g3flip/gcls with gwait
between — flip mid-CLS splits the clear) and exit via g3sync. Emulator now
powers both pages with FIXED garbage so this bug class dies in sim. Also:
composed matrix != two sequential shifts (rounding) — engine cube is the
software cube's sibling; identity is the bit-exact bridge.

Man pages: man gfx / man g3d / man cube on-target. Docs fully swept
2026-08-20 (BASIC guide four-pen fossils killed, all READMEs current).

PUSHED to GitHub 2026-08-20 (user said "push"): origin/sdram-framebuffer
tracks, synced through 086b885. Merge to main remains the user's call.

**8b leftovers -> BACKLOG.md IDEAS** (stage-9: colour edges, list base,
indexed meshes, BASIC statements; BASIC-on-MDU; board successors).

Formerly: **NEXT (user: "we can come back to 8b")**: stage 8b fabric geometry
engine — walker FSM around the MDU datapath, edge list in SDRAM via a
streaming upload port, matrix regs, one render command; SDRAM gains a 4th
client (priority scanout > refresh > geometry > pixels — the arbitration
is where the hard bugs live); page-flip double buffer rides along. Sketch
at the end of fpga/tang-nano-20k/sdram/STAGE8-DESIGN.md; needs its own
full design doc first.

Also open: asm muldiv/lib_g3d twin (smaller rung, partly obsoleted by the
MDU), `image X Y FILE` OS command (second lib_gfx client).

STAGE 9 SHIPPED AND ON SILICON (branch g3d-stage9 through e1f3e00):
TYPED RECORDS (type/flags byte + RGB565 colour + verts; LINE 16B, TRI
22B), g3color pool pen, g3tri(p,fill) — filled = screen-space scanline
fill clamped to viewport, spans as height-1 BOXFILLs; outline = screen-
space CS. Four implementations, one oracle; RTL bench checks 105 exact
spans. 13,487 LUT4 (65%). Board: coloured cube ✓, fabric-filled tri ✓
(POINT -2048/-2048/-2048/0). STAGE 9c SHIPPED + ON SILICON (168fa31+): GEVAL/GEVALH READBACK of
par[GESEL] (RTL+emu+bench); the engine list is a PERSISTENT SCENE —
`tri` builds, `tri ... k` APPENDS (count readback, cursor persists),
`rotate x y z [px py pz]` (brads; pivot T=P-R*P — origin-pivot swings
z~400 scenes off-window) redraws it; bare rotate = identity. Board
verified by user's eyes AND scripted POINT(-2048). Pool right-sized to
2816 INTS with int-counted guards (cube was 51 bytes from CSTACKTOP).
Scripted-session discipline that finally works: lsof pre-flight, ALWAYS
openFPGALoader reload (unsilenced), sleep 6, then the session; a WEDGED
board needs a human reset. STAGE 9d SHIPPED + ON SILICON (2c4d7b6+): the look-at CAMERA.
lib_g3cam.c (//#use g3cam AFTER gfx+g3d — its OWN lib: folding ~6K of
camera math into lib_g3d pushed EVERY g3d client past 64K): i3sqrt
(32-bit try-a-bit sqrt on m3mul), n3orm/c3ross, g3cam(int[6] eye+aim)
-> params 0-11 (rows right/up/forward, T=-M*eye). `camera [ex ey ez ax
ay az]` command redraws the persisted scene from the eye; bare = home.
LESSONS: m3mul is UNSIGNED — magnitudes before squaring (s3acc bug:
identity tests can't catch sign bugs, off-axis views can); shared-lib
growth is a fleet-wide size tax. Board proof: POINT -2048 at the
replica-predicted oblique pixel. Toolkit complete: tri/rotate/camera/
page/cube/image. Remaining BACKLOG: 800x480 notes, imgsend verify,
stage-9 leftovers. g3d-stage9 MERGED to main + branch deleted 2026-08-21 (e3aa10b); back to main-only workflow.

BRANCH STATE: g3d-stage9 merged to main and deleted 2026-08-21 (user
said "sync"); commit to main per the normal workflow.

NEW TRAPS (2026-08-21): imgsend acks certify TRANSPORT NOT CONTENT — a
clone delivered a right-sized corrupt binary that wild-jumped to the
monitor while emulator-clean; re-clone first, debug logic second
(backlog: verify pass). And cube.bin now ends 161 bytes below CSTACKTOP
$F800 — g3d clients must check their memory map.

Related: [[p8x-project]] [[p8x-cc-caps]] [[p8x-new-command-dual]]

STAGE 10 (branch graphic-test, ON SILICON 2026-08-25): the GRAPHICS
LANGUAGE — PGC-style command port $FF50 (GLDATA/GLSTAT/GLRB/GLERR/GLID
'G'), hex opcodes per the PG-640A manual (docs/reference/pg640a.pdf).
10a: primitives 2D/3D + WINDOW/VWPORT (PGC x1 x2 y1 y2 order!) + FLOOD/
CLEARS(both pages)/FLIP(02)/PGSYNC(03). 10b: card-side MD*/VW* matrices
composed at COMMAND time into par[] (per-vertex datapath unchanged);
PROJCT/DISTAN (dist 0 = stage-9 camera); hither/yon par[23]/[24];
CONVRT; trig via gen_trig.py twin tables. 10c: COMMAND LISTS — 64 x 4KB
SDRAM slots at $100000, CLBEG/CLEND/CLRUN/CLOOP/CLDEL + P8X CLAPP(79);
recording rides the decoder pops; CLOOP deltas accumulate = fly-through.
THE $FF40 RECORD ENGINE IS RETIRED (user-approved); lib_g3d falls back
to software; GESTAT gone — poll GLSTAT bit6. Console: tri records/
appends LIST 0 (the scene), rotate (DEGREES now, not brads) + camera
(g3bas basis → VWMATX/VWRPT) replay it, cube CLOOPs a self-spinning
frame CPU-idle, page speaks GL, image PGSYNCs via GL.
FABRIC LESSONS: nextpnr's LUT% under-reports (ALU carry cells share LUT
sites — 92% shown was ~114% real); big tables/scratch → BSRAM as
clocked ROMs; a 1W2R scratchpad = ONE true-dual-port BSRAM (port A
write-else-read; a mirrored pair = exact-fit 46/46 death, distributed =
+700 LUT); build.sh now passes -family gw2a (DSP inference) + PNR_SEED.
Proof chain: tb_gl directed ops, c_gl_rtl_test byte-identical frames,
92-PASS make test, board POINT probes all exact (BASIC banner is
"P8X BASIC V0", not READY).
STAGE 10d (2026-08-25): ASCII mode — translator front-end ahead of the
byte source (keywords→opcodes via a 110-entry BSRAM table from
gen_glkw.py, decimals→width-correct params, CA/CX, deterministic err
recovery); lists store hex either way. Clients: gl command + BASIC GL
($B3). FOURTH byte-identical frame added. THE PLACEMENT DIET that made
it fit (18,943 LUT4/91%, seed 1, was 19,747 failing all seeds):
nextpnr LUT4 ≈ yosys LUT4 + 2·MUX2 + 2·ALU, so kill ADDERS —
(1) three shared muldiv-operand subtractors (md_a1-md_a2; arms load
raw pairs), (2) one shared ±md_q post-adder (md_r/md_rn at launch),
(3) aligned lane/slot addresses as CONCATS (bases 8/16/4K-aligned
never carry). ANTI-LESSONS (tried, net WORSE, reverted): small reg
arrays (3-deep tv*, par[0..8]) into BSRAM lanes; comparator banks
time-shared behind state-keyed muxes — wide muxes are near-free as
MUX2_LUT5 pairs, and new state-keyed selects cost more than the ALUs
they save. Share only where the mux already exists. BOARD-VERIFIED
2026-08-26: bitstream IN FLASH, fresh disk cloned, translator (GL
strings) probe 2016 + native-verb probe -2048 both exact on silicon.
SILICON TRAP FIXED: GL walker masters the 2D device -> GID reads
garbage while busy -> GCHECK now drains GLSTAT bit6 first (emulator
is synchronous, cannot see this class). Port-open does NOT reset the
board; probe for state (may be sitting in BASIC); imgsend needs the
MONITOR (reload bitstream first).
BASIC NATIVE GL VERBS (2026-08-26): all 51 verbs are BASIC statements
(tokens $B4-$E6, ONE generic handler + gen_glkw.py-emitted tables in
basic/glkwtab.inc+glvtab.inc; token order is ABI append-only). They
emit hex directly (BASIC strings cap at 32 chars — a 9-coord POLY3
never fit; the old basic_gl_test passed on a SPLASH pixel), record
inside CLBEG/CLEND, and DRAIN GLSTAT bit6 on exit (sync semantics; GL
s$ = async path). COLOR drives both pens. Scenes must RESETF first
(the boot splash leaves composed matrices).
STAGE 10e (2026-08-26): built sim-complete then BACKED OUT by user
choice -- ~900 LUT4 over the cliff; commit c0931f0 + revert preserve
it for the successor board.
STAGE 10f (2026-08-27): LINFUN PLACED at 19,048 (seed 1) and
BOARD-VERIFIED same day (XOR -2017 / restore 31 / complement -1 --
emulator-exact; the machine's first un-draw). Mode lives
in the DEVICE (GMODE $FF2E write side) so BASIC LINE/PLOT honour it;
single-pixel path only, fills always replace; GL's mode write WAITS
for engine idle (else it overtakes an in-flight primitive -- frames
diverged until W_LF polled GSTAT). Funded by ellipse+circle error-step
serialization through ONE shared 40-bit adder (-255 total), made legal
by NEW tb_gl_cpx.v (circle/ellipse RTL pixel proof -- a coverage hole:
those paths are unreachable from GL). SIX byte-identical frames now.
Next rungs: 10g AREA, 10h TEXT (both need room or the successor
board); 10e resurrection when room exists. Console GL family is C-only
(asm twins an open item). MERGED TO MAIN 2026-08-27 (597c0b9, user-
approved) -- work on main again per the normal workflow. CARD ARC
(branch graphics-card, 2026-08-28, IN FLIGHT): the FPGA becomes a pure
GRAPHICS CARD behind the card-edge contract (CARD-EDGE-DESIGN.md; the
$FF20-$FF57 window + BRIDGEV/BRIDGID, serial protocol v1: PING /
rd/wr / ack'd 64-byte bursts / STATUS; idx = ioaddr-$FF20; IDLE IS TWO
POLLS: GLSTAT then GSTAT -- the engine drains its last span after GL
busy clears). DONE sim-side: glbridge.py+MockCard (mock-proven),
p8x_bridge.v + p8x_gcard_top.v + build.sh `card` (PLACES at 16,808
LUT4/81%, BSRAM 5/46 -- 41 blocks + ~2.2k LUT freed = 10e/10g/10h
room), tb_gcard (the 10a frame byte-identical THROUGH protocol bytes),
p8xemu -B (BASIC session against MockCard over a pty; GLDATA as single
writes because P8X software already polls bit7). Mock gotcha: identity
regs have CONSTANT read sides split from write sides (GCOLH vs GID0 at
$FF2D). FIRST LIGHT + ARC COMPLETE 2026-08-28: PING/identity on silicon, PLOT
readback exact, the house drawn with NO CPU ON CHIP; p8xemu -B ran
LINFUN (-2017/31/-1), cube 32 (2016/31/-2048) and the tri/rotate/
camera/gl family (2016/2016/0) ALL golden-exact -- the software stack
runs UNCHANGED (that is the contract's point). -B batches GLDATA into
ack'd bursts w/ synthetic busy-not-full polls + age-based flush;
RESYNC-ON-CONNECT (66 zeros) recovers a card left mid-command by a
dead host. os/runcard.sh = the daily driver (emulator CPU, card
panel). CARD PERSONALITY IS IN FLASH, cold-boot verified -- power-up =
graphics card, no CPU; lcd rebuildable (stage10-complete tag). NEW
MODEL NOTES: the SD/imgsend clone flow is OBSOLETE in card mode
(run-disk.img is the EMULATOR's disk now); panel shows garbage until
a master CLEARS (no CPU to draw a splash); `house` joins cube as the
demo (the manual's example is genuinely 3D). lcd-target regression
stays mandatory (lcd RETIRED AS PLACEABLE 2026-08-28, user choice: new
rungs land unconditionally in shared RTL, lcd keeps synthesizing for
benches, stage10-complete tag preserves the all-in-one machine).

STAGE 10e RESURRECTED ON THE CARD (a7f3206, 2026-08-28): FLAGRD/
MATXRD/CLRD/CLMOD + GLRB + BASIC GLRD($FB) + clsave; card placed
17,470/84%. STAGE 10g SHIPPED 2026-08-28 (0a971a8, RTL PIXEL-EXACT ON
FIRST BENCH RUN): AREA(C0)/AREABC(C1) scanline seed fill -- 30-state
walker mirroring gl_afill exactly; probes = real device POINTs via NEW
gm_rd strobe (plumbed through both tops + all benches), paints =
device LINEs, seed stack = SDRAM $180000 ({00,11,00,sp,00}, 16384
pairs, cap = err8 deterministic partial fill), replay fetcher gated by
af_g (AREA inside a list can't race the stack), GMODE forced replace
first (visited-mark invariant -- now explicit in gl_afill too).
Off-window seed = err2; seed on boundary/pen = silent no-op. Proof:
tb_gl_arx.v frame == gl_ar.ppm; c_gl_rtl_test = SEVEN frames;
basic_gl_test now executes AREA/$EC + AREABC/$ED tokens (yellow rect +
teal diamond, PPM-probed). Card places 18,032 LUT4/86% (+562), Fmax
74.6 vs 12. Docs swept (man gl/basic, guide new §7, theory, BASIC
guide, STAGE10-DESIGN as-built), disks rebuilt. BOARD FLASH PENDING
(no cable at commit time): ./build.sh card load, then glbridge AREA
probe. STAGE 10h SHIPPED 2026-08-29 (b34d878; emulator + RTL PIXEL-EXACT and
ON SILICON same day -- card 18,926 LUT4/91% FLASHED as power-up
default, 10g+10h both board-verified over the bridge, every probe
exact; STAGE 10 COMPLETE a-h): TEXT(80 count chars)/TSIZE(81)/TANGLE(82)/
TDEFIN(84). A glyph IS a command list (relative MR3/DR3 strokes + pen-
up advance) in a SECOND 64-slot bank $140000 (one addr bit + rec_bank/
rp_bank on the UNCHANGED record/replay machinery); slots = ASCII
32..95, lowercase folds. TSIZE/TANGLE = compose ALIASES of MDSCAL sss/
MDROTZ (pw0 copied into scale lanes / cax=Z) -- divergence from PGC's
absolute TSIZE documented; anchor big/tilted text with MDORG at the
MOVE3 point. WINDOW-SPACE TEXT NEEDS PROJCT 0 (z=0 is behind the
perspective camera's near plane -- cost a debugging round). ASCII form
emits ONE SINGLE-CHAR TEXT PER CHAR (80 01 c): kills count-first
buffering in BOTH implementations (design decision, in STAGE10-DESIGN).
TEXT/TDEFIN in lists DEFERRED (err5 recorded AND replayed). RESETF
does NOT clear the font (installed resource; power does). gen_font.py
authors the 5x7 stroke font -> os/font.gl (shipped /FONT.GL, load with
`gl /FONT.GL`); scene files start "CA \n" -- the space is PART of the
hex-mode transport switch, and end "CX " with NO trailing newline (a
stray 0A in hex mode = err1). TRAP FOUND: keyword ROM crossed 128
entries and wedged the translator matcher's 7-bit t_ent (infinite
walk, "FIFO never drained") -- now 8 bits + gen_glkw assert. tb_gl_txx
drain timeouts need 5M cycles (CLS is a per-pixel-pair walk; >1M with
a full FIFO). Proof chain = NINE frames; basic_gl_test runs TDEFIN/
TSIZE/TEXT native (BASIC TEXT = glvtab meta $FF -> glv_str string
handler; tokens $EE-$F1). Stage 10 rungs a-h ALL COMPLETE. 10i/j/k SHIPPED
2026-08-29/30 (a518415): curves, patterns, TJUST/TEXTP/TEXT-in-lists --
12 byte-identical frames; funded by RETIRING device CLS/BOX-outline/
CIRCLE (user-approved; a circle IS the ellipse rx=ry now; monitor
splash = BOXFILL + 4 LINEs). FIT ENDGAME 2026-08-30: the chip's
PRACTICAL placement cliff is ~19,150-19,250 LUT4 (19,129 placed, 19,303+
failed every seed; placer knobs incl. SA all failed) -- NOT the nominal
20,736. User-approved removals to get under it: AREAPT (-569 measured;
E7=err1) then ARC/SECTOR (-2,045 measured!! the fan lane-loader+angle
walk carried huge mux fabric; 3C/3D=err1; CIRCLE/ELIPSE + trig ROM
stay). CARD PLACES 18,065/87% seed 1, Fmax 73/88 vs 12, FLASHED +
SILICON-CERTIFIED 2026-08-30 (silicon_10gh + silicon_10ijk both PASS
incl. retired-keyword err paths). Both removals BACKLOG'd for the
successor board; arcs = 4-degree DRAW chains meanwhile. Diet lesson
PROVEN with clean flat builds: state-arm serialization diets trade
~evenly against their source muxes (two measured net-NEGATIVE and were
reverted); only real REMOVALS pay. NEVER run two build.sh in parallel
(shared logs -> garbage numbers). macOS gotcha: oss-cad-suite's vvp is
a bash WRAPPER -- iverilog-compiled benches can't exec via shebang
(ENOEXEC); keep homebrew iverilog first in PATH for test runs, suite
PATH only for yosys/nextpnr/openFPGALoader. NAMING EPOCH 2026-08-30:
the pixel pair is PIXELW/PIXELR at EVERY layer (BASIC statements
[tokens $AB/$AE unchanged, text renamed], lib_gfx gpixelw/gpixelr,
GC_PIXW/GC_PIXR equates, RTL S_PIXW/S_PIXR, glbridge.pixelr()/pixelw()
helpers); POINT now names ONLY the PGC drawing verb and is a native
BASIC statement (appended token $F9). man basic marks DEVICE vs PGC
statement families. USER DIRECTION: migrate BASIC's category-2 drawing
(LINE/BOX/CIRCLE/CLS/PIXELW) onto GL, keep the DMA-gap pair
(PIXELR/IMAGE) + GTEXT device-side; endgame = single-interface card
via a GL pixel-read verb + card-side blit (BACKLOG'd). BASIC MIGRATION
SHIPPED 2026-08-31: LINE/BOX/CIRCLE/CLS/PIXELW emit GL, WINDOW-space
(user chose y-up redefinition over screen-compat); BASIC establishes
the full-screen window at cold start AND after native RESETF because
the raw port's power-up/RESETF window is DEGENERATE (all-zero, draws
nothing -- the bug class to remember); PRMSH (BASRAM+$FB) shadows
PRMFIL for BOX/CIRCLE force+restore; BXS moved $E6->$EA (GLPUT/GLVSEP
scratch GLTMP $E7/GLFST $E9 are LIVE during migrated statements).
Bridge protocol: GL bytes cross as BURST frames into the card FIFO,
device regs as (idx,val) writes at $FFxx-$20 indexes. COORDINATE
UNIFICATION 2026-08-31 (f1ef3eb, user rule): EVERYTHING counts y UP --
GTEXT (BASELINE-left anchor, glyphs rise 7*size)/IMAGE (BOTTOM-left)/
PIXELR() stay device-implemented but BASIC wflips y (272-y-extent);
fixed mapping, no WINDOW re-scale. SILICON TRAP FOUND BY USER: the GL
walker masters the device and leaves ITS colour in write-only GCOL
(CLS=FLOOD 0,0,0 -> pen BLACK -> GTEXT invisible ON BOARD ONLY; the
emulator passes colours as args and can't show it) -- GTEXT now
asserts GPEN at entry. Emulator-vs-RTL divergences hide in WRITE-ONLY
device state: check both when a device-door user misbehaves on silicon
but passes emulation. C lib_gfx still device-side/screen-space -- next
migration candidate.

SINGLE-INTERFACE MIGRATION (user-directed 2026-08-31->): goal = extend
GL until $FF20 closes. PIXRD DONE+ON SILICON (9a222b6): opcode $63,
window coords through the 2D map, RB FIFO reply; BASIC PIXELR() IS the
verb (transforms under WINDOW like PIXELW); cost a startling ~1,040
LUT4 (muldiv source muxes) -> card 19,103/92%, JUST under the cliff --
BLIT must be lean/funded. GTEXT RETIRED OUTRIGHT 2026-09-01: PGC TEXT
+ OS boot-streamed /FONT.GL (FONTLD after PATHINIT) replaced it; GPEN
shadow died with it (COLOR = pure GL). CONTRACT FACTS: TEXT anchors at
the 3D current point (MOVE3 x,y,0, NOT 2D MOVE) and strokes at z=0 are
NEAR-CLIPPED by the native camera -> BASIC cold-starts PROJCT 0
(2D-first; RESETF restores native); TSIZE/TANGLE are COMPOSE ALIASES of MDSCAL/MDROTZ -- they COMPOUND
per issue (512 twice = 4x; 256 = no-op NOT restore; MDIDEN resets) and
scale the ANCHOR (model coords). The PGC's TSIZE was absolute; P8X's
diverges DELIBERATELY. A 'TSIZE restore' bug report is USER-MODEL
error, not silicon: emulator and RTL agree. Glyph bank survives RESETF ("a font
is installed, not drawn"). Device door now: IMAGE pixel writes ONLY.
Debug lesson: a "shell broken by X" symptom was a STALE TEST IMAGE
(p8xfs put lost by re-cp) -- rebuild the image in the SAME command as
the probe. MockCard has a preloadable rb FIFO for RB-verb bridge tests.
Silicon scripts live IN THE REPO now: fpga/tang-nano-20k/tools/silicon_*.py.

BLIT SHIPPED + ON SILICON 2026-09-01 (6768a9b; silicon_blit.py PASS;
MEASURED: mandrill via BASIC IMAGE 393.5s -> 37.7s = 10.4x on the
real bridge): opcode $64, window
bottom-left anchor via PIXRD's map, 2*w*h raw P8I-layout bytes eaten
pre-buffer (emulator) / glst G_BL (RTL), pixels = real PIXELW (GMODE
applies). IMAGE = one BLIT/row, file bytes verbatim; BASIC's last
device WRITE gone -- $FF20 now BASIC-free (C lib + monitor remain).
FUNDED by CLMOD removal (user-approved, MEASURED 342 LUT4 by ablation
synth BEFORE asking -- the pattern that works): card 18,916/91% seed 1.
Wire: ~14B+poll/px -> 2B bursts (the -B bridge answers GLPUT bit7
LOCALLY while bursting); floor = 115200 itself, UART raise backlogged.
TRAP: BASIC IMX was $E6/$E7 -- $E7 IS GLTMP, GLPUT scribbles it per
byte; any BASIC var alive across GLPUT emission must avoid $E7 (and
the $E0-$F1 scratch map generally). Removed so far, all BACKLOG'd:
AREAPT, ARC/SECTOR, CLMOD, GTEXT(+GPEN), device BOX/CLS/CIRCLE.

GTEXT REBORN 2026-09-01 (a482764, user demand: 'easier 2D text... use
the PGC interface'): old signature GTEXT x,y,size,s$ + old token $AF
(saved programs dispatch again), PURE GL emission -- PROJCT 0, MDIDEN,
TSIZE size*256, MDTRAN x y 0, MOVE3 0 0 0, TEXT via glv_str. THE KEY
TRICK: MDTRAN composes AFTER TSIZE (issue order = apply order), so the
anchor lands UNSCALED at window (x,y) at any size. Resets matrix+camera
each call BY DESIGN (documented); 3D uses raw verbs. Lesson: sugar
statements over GL emission are cheap (~70 lines asm, no FPGA change)
-- the right answer to ergonomics complaints about raw PGC idioms.

DOOR-CLOSING PHASE A COMPLETE 2026-09-01 (software $FF20-free; commit
pending): lib_gfx.c = GL veneer keeping the screen-space API (271-y
flip inside), compressed helpers glmov/glrgb/glpf + RECT-as-box
(first draft overflowed cube.bin past CSTACKTOP), LAZY ground-state
init inside glbyt (flag set BEFORE init bytes so recursion passes;
needed because g3d clients never call gpresent). image twins = BLIT
draw + PIXRD grab, screen-space kept. THE ASM-TWIN BUG: probed GLID
but skipped ground state -- the power-up DEGENERATE window garbled
the BLIT map (symptom: one phantom row at screen 0, everything else
missing; bridge/mock traces looked PERFECT because the mock doesn't
render and my "asm" traces actually ran the C disk ci.img -- trace
the artifact the failing test actually built, cia.img). Fix: 24
init bytes (WINDOW+VWPORT identity, PRMFIL 0, COLOR white) at
i_disp. Monitor splash = flat GL table DSPTAB (96 bytes, GLSTAT
bit7 backpressure, band 124..147 maps to itself under the flip).
BASIC: GCHECK = GLID-only (no walker drain needed -- GLID answers
while busy); GWAIT/GEXEC/GSTORE/GARG + all $FF2x equates deleted
($DB/$DC/$DE freed). PHASE B NEXT: remove the CPU-facing $FF20
window from gfx.v/p8x_bridge.v + emulator door, glbridge pixelr/w
-> GL, retire gfx_test/test_gfx*.asm/c_gfx_ce_test, tb splash preps
gpoke->GL, GID0/GID1 sweep, measure freed LUTs, flash + silicon.

PHASE B COMPLETE 2026-09-01 (commit pending): the $FF20 door is out of
the DESIGN. Emulator: door cases deleted (floats $FF), gpu_cmd/IDENT/
SELFTEST/RESET + gx0..gparm2/gpt/gident state gone (gcol+gmode stay --
GL-owned), bridge_card = $FF50-57 only. RTL: bridge gx path removed
(device idx: reads $FF, writes swallowed -- protocol frames unchanged),
gcard top mux collapsed (walker sole master), gfx.v trimmed (IDENT+
gidx, GID0/GID1, F1/F2 decode, gerr; ptid/GDATA stream stays -- the
walker's PIXELR pops it), lcd top door also closed. MEASURED: 18,912
vs 18,916 LUT4 -- the door cost ~4 LUTs, NOTHING; the win is
architectural. Silicon: flashed + ALL scripts pass (pixrd/blit/10gh/
10ijk); mandrill 24.6s ~ wire floor. glbridge pixelr/pixelw/probe are
GL now (scripts unchanged); wait_idle dropped its GSTAT arm -- SAFE
because the walker sequences PIXRD behind the engine drain (only
wall-clock timing could tell); GLSTAT bit6 does NOT include engine
drain (known, documented). Coverage lore: retire a test only after
folding its unique cases into a survivor (ce radii -> curve rung both
sides); tb_gcard now asserts the closed-door $FF float on the wire.
Traps: c_gl_pixrd's devrd() cross-check spun forever on the floating
$FF (busy bit reads 1) -- grep tests for 6531x/6532x pokes when
closing a window; emu_bridge echo string "$FF" got shell-interpolated.
