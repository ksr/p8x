---
name: p8x-gfx-clib
description: "SHIPPED 2026-08-19 (c29993f): C graphics veneer lib_gfx.c + wireframe-3D lib_g3d.c + cube demo; key facts for future graphics/C work"
metadata: 
  node_type: memory
  type: project
  originSessionId: eb839e7b-2183-47af-84cd-a059555f72b5
  modified: 2026-08-19T22:23:48.250Z
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
they save. Share only where the mux already exists. Bitstream BUILT,
NOT yet flashed; board proof + disk rebuild (new BASIC + gl) pending.
Next rungs: 10e read-back, 10f-h LINFUN/AREA/TEXT. Console GL family
is C-only (asm twins an open item). NO MERGE without ask.
