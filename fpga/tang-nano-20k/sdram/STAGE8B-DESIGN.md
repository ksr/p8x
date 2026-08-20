# Stage 8b — the geometry engine: vertices that never meet the CPU

The MDU (stage 8a) proved the arithmetic datapath and measured the wall
that remains: at 19.6 fps, two-thirds of a cube frame is p8cc-compiled
plumbing — call frames, pool indexing, port pokes. No peripheral absorbs
that; the operands themselves must stop transiting the CPU. This stage
builds the walker: the edge list lives in SDRAM, a matrix lives in
registers, and ONE command transforms, clips, projects and draws the
whole list in fabric. Page-flip double buffering (deferred since stage 7)
rides along, because at engine speeds the in-place erase becomes the
dominant artifact.

## The shape

    CPU (per frame):  ~30 pokes -- matrix, flags, GO
    engine (per edge, ~1k cycles):
      fetch 12 bytes from SDRAM          (3 word reads, one row)
      v' = M*v >> 8 + T                  (9 DSP multiplies per vertex)
      near clip -> project -> window clip -> viewport map
                                         (the muldiv datapath, ~8 ops)
      issue LINE                         (drives gfx.v's registers, as
                                          software would -- gfx.v is
                                          UNCHANGED)

The engine does not own a rasterizer: it is a hardware BASIC, poking
GX0..GCMD and waiting on GSTAT exactly like every other client of the
display. That composition is the lowest-risk piece of the design — the
line engine, its arbiter port, and the co-sim that proves them are all
untouched.

## The math contract (bit-exact across all four implementations)

The lib_g3d software pipeline IS the specification. The emulator engine,
the RTL, and the library fallback must produce identical pixels; the
directed vectors and the frame-0 cube replica in c_g3d_test pin all of
them to one reference. Precisely:

- **Transform**: matrix elements are S7.8 fixed point (256 = 1.0), int16.
  For each output axis: acc = m0*vx + m1*vy + m2*vz summed in 32-bit
  signed; v' = (acc >>> 8) + t, arithmetic shift (FLOOR — distinct from
  muldiv's truncate-toward-zero, both specified), wrapped to int16.
  Sane ranges (|m| <= 2.0, |v| <= 16383) never overflow; garbage wraps.
- **Everything after the transform** is lib_g3d verbatim: Z3NEAR=16 near
  clip BEFORE the divide (interpolations via muldiv), perspective
  sx = muldiv(x,d,z) (d=0 selects orthographic), Cohen-Sutherland in
  window space with muldiv slides (outcode order L,R,B,T; the same
  formulas, the same operand order — operand order changes truncation),
  viewport map with the y flip. muldiv is the stage-8a contract.

## Registers ($FF40-$FF4F) — an indexed parameter file

The engine has ~25 parameters; a flat window cannot hold them. GESEL
picks a parameter, GEVAL's low/high writes set it (the HIGH write
commits and auto-increments GESEL, so the 12-word matrix uploads as one
GESEL poke + 24 GEVAL pokes).

| addr | write | read |
|---|---|---|
| $FF40 | GESEL: parameter index | — |
| $FF41 | GEVAL low: value low byte | — |
| $FF42 | GEUP: upload one list byte at the cursor, cursor++ | — |
| $FF43 | GECMD: 1 rewind upload cursor / 2 RENDER / 3 FLIP only | — |
| $FF44 | — | GESTAT: bit7 busy, bit0 err |
| $FF45 | — | GEID: 'E' ($45) — presence probe |
| $FF4A | GEVAL high: commits reg[GESEL], GESEL++ | — |

(GEVAL follows a pair discipline adapted to the file: low latches, high
commits — write low THEN high, always, both bytes every time.)

Parameters (GESEL index): 0-8 matrix m00..m22 row-major; 9-11 tx,ty,tz;
12 focal d (0 = ortho); 13-16 window x0,y0,x1,y1; 17-20 viewport;
21 flags (bit0 = erase viewport before render, bit1 = flip after render;
default 3); 22 edge count. Reset: identity matrix, t=0, d=256, count=0,
flags=3, window/viewport zero (a zero window renders nothing sane — set
them; the library always does).

**The list** is raw stage-7 pool format — count x 12 bytes, x0,y0,z0,
x1,y1,z1 little-endian int16 — at a FIXED SDRAM base, $100000 (1MB),
clear of both framebuffer pages. No base register in v1: one list, one
place, uploaded through GEUP. Cap: 4096 edges (48K) — a bound for the
emulator's array and the count register's sanity check, far above what
the frame budget can draw anyway.

## Page flip

Framebuffer pages at $00000 and $80000 — 512K-aligned so the page is
ONE ADDRESS BIT ({page, y, x[8:0], 1'b0}), preserving the no-multiplier
addressing. The engine owns the page state: a display page (what scanout
reads) and a draw page (what gfx_mem writes — the CPU's own PLOTs and
the engine's lines alike; POINT reads the draw page, so read-back stays
self-consistent). The flip rule AS SHIPPED (a plain swap would be a no-op
from the shared power-on page): display <= draw — show what was just
drawn — and draw <= the OTHER page. Boot is single-buffered on page 0
until the first flip splits the pages. RENDER with flags.bit1 flips after
drawing; FLIP (GECMD 3) flips alone, for CPU-drawn double buffering.

A pending flip is APPLIED BY SCANOUT at its frame boundary (frame_tick),
never mid-frame — no tearing — and GESTAT stays busy until a pending
flip is consumed, so back-to-back RENDERs self-pace to the panel's
54.11 Hz and never draw into the visible page.

## Hardware plan

- `fpga/rtl/mdu_core.v` — the a,b,c -> q datapath EXTRACTED from
  p8x_mdu.v (which becomes a thin register wrapper around it). One
  definition of the contract in silicon, used by both the CPU-facing MDU
  and the engine.
- `fpga/rtl/p8x_geom.v` — parameter file, upload port, walker FSM,
  transform datapath (DSP multiplies), one mdu_core, and a gfx-register
  master port.
- p8x_top: $FF40 decode; a MUX on gfx.v's register port (engine owns it
  while rendering — CPU gfx writes during GESTAT busy are dropped, so
  don't draw during a render; poll first, as ever); page-bit wires into
  gfx_mem (draw) and sdram_video (display, latched at frame_tick).
- sdram_arb: a fourth client — the engine's read-only word port for
  edge fetches. Priority video > refresh > geometry > engine pixels.
  The arbitration is where this branch's hardest bugs have lived: the
  bench for this port reproduces the busy-drop/data-ready timing that
  tb_sdram_arb already pins for the others.

## Library and demo

lib_g3d grows the engine path behind the same API plus three calls:

- `g3up()` — upload the pool to the engine list (12 pokes/edge);
  1 if an engine took it, else 0.
- `g3mat(m)` — m is int[12]: the 8.8 matrix then tx,ty,tz.
- `g3go()` — RENDER the uploaded list with the current matrix, window,
  viewport, focal; erase+flip flags on. 0 when no engine.
- `g3render()` — unchanged everywhere it matters: when an engine is
  present it becomes upload + identity matrix + g3go (bit-identical
  pixels, ~30x fewer CPU cycles); the software walk remains the
  fallback, forever, same source.

cube.c v2 shows the pro path: upload the static +/-90 cube ONCE, then
per frame compose the 12-word matrix from its sine table (the two
rotations in closed form; the cross terms go through muldiv for the
32-bit product) and g3go(). AS MEASURED, the composed matrix is NOT
bit-identical to stage 7's two sequential shifts — one rounding
(m22 = 240*240>>8 = 225) versus two (x*120>>7 twice) lands corners a
pixel or two apart — so the engine cube is the software cube's sibling,
not its twin, and the test replicates each path's own arithmetic. The
CPU's per-frame work drops to ~60 pokes (~85k cycles, 3.2 ms, measured);
the rate is set by the engine and the vsync-paced flip.

## Verification ladder (in build order)

1. Emulator engine (golden model): same registers, instant busy, the
   contract math in C. c_g3d_test grows the strongest single assertion
   available: the same pool rendered by the software walk and by the
   engine with the IDENTITY matrix (exact: (v*256)>>8 == v) must be
   BYTE-IDENTICAL framebuffers — two full pipelines, one answer — plus
   engine-cube corners against an engine-math replica, and the page-flip
   semantics (including the manual FLIP back).
2. lib_g3d + cube v2 on the emulator; measure; software fallback re-run
   (m3has-style forcing) so both paths stay green.
3. tb_mdu still passes with mdu_core extracted (wrapper refactor proven
   before anything new uses the core).
4. tb_geom.v: the engine against a small SDRAM stub, capturing its gfx
   register writes; directed edges (plain, near-clip, every CS side,
   reject, saturation, rotation matrix) with expected line coordinates
   generated by the c_g3d_test host replica — RTL pinned to the same
   reference as everything else.
5. tb_full_stack: one engine render through the REAL arbiter/controller/
   chip model — the bench that catches arbitration lies.
6. Bitstream (placement + timing), flash, disk, board: probe GEID,
   cube frame-0 POINT corners (must equal stage 7's numbers exactly),
   then the spin.

## Not in 8b

Faces/fill/hidden lines; multiple lists or a list-base register; matrix
helpers in hardware (sin/cos stays software); BASIC statements for the
engine; textures, obviously. Each is a later rung on a now-proven ladder.
