# Stage 7 — wireframe 3D: a world of vectors, a window, a viewport

> **SHIPPED, 2026-08-19 — designed and on the machine the same day.**
> lib_gfx.c (the parked C graphics library, register veneer + asm-equate
> twin), lib_g3d.c (this pipeline, verbatim), and the `cube` demo command
> (man page, /src, Makefile). Tested by emulator/test/c_g3d_test.sh: muldiv
> vectors vs a host reference, cube frame-0 spot pixels computed by an
> independent host replica of the pipeline, and native-p8cc.c parity for
> both libraries (cube itself is p8cc.py/on-target-cc only — its sine/edge
> tables are brace-initialized arrays, the disasm/lib_distab precedent).
> The budget section below now carries MEASURED numbers; the one design
> change measurement forced is recorded there (the muldiv fast path).

> DESIGN. Unlike stages 2-6 this stage is SOFTWARE-ONLY: no RTL changes, no
> new registers, no emulator changes. Everything below runs on the CPU and
> draws through the existing engine — which is the point: the hardware LINE
> command turns a 16-bit CPU into a plausible wireframe machine, because the
> CPU computes two numbers per vertex and the fabric does the million pixel
> steps. Black and white for now: pen white, background black, nothing in the
> pipeline knows about colour.

## Where the model lives (the question that started this)

In the TPA, as C data. The deciding fact: the CPU's 64K address space does
not contain the SDRAM — the only readers of SDRAM are the scanout and the
drawing engine, so "model in FPGA memory, drawn from there" means a geometry
engine in the fabric (matrix registers, DSP multipliers, a mesh walker).
That is a real and attractive stage — the GW2AR-18's DSP blocks are sitting
unused — but it is STAGE 8+ material, and its data formats should be
DISCOVERED by this stage, not guessed ahead of it. The third option, SDRAM
as passive storage with the CPU transforming, buys nothing: the TPA already
holds thousands of edges and the CPU cannot transform even hundreds per
frame. Storage was never the bottleneck; arithmetic is.

So: a retained EDGE POOL in the TPA. `g3line` appends to it; `g3render`
walks it. 12 bytes per edge (two vertices x three int16), no shared-vertex
indexing in v1 — the API adds edges one call at a time, so independent
storage is the honest match (indexed meshes are a stage-8 format question).
512 edges default (6K of TPA) — a cube is 12, a decent polyhedron scene is
~200.

## The API (lib_g3d.c, `//#use g3d`, atop `//#use gfx`)

This stage BUILDS the parked lib_gfx.c first (see the C graphics library
design: peek/poke veneer over $FF2x — gpresent, gcolor, gcls, gline...);
the 3D library is its first client, and needs only gline/gboxf/gcolor from
it. C identifiers cannot start with a digit, so BASIC-flavoured "3DLINE"
becomes g3line:

    g3clear();                       /* empty the world                    */
    g3line(x0,y0,z0, x1,y1,z1);      /* add one edge, world coords, int16  */
    g3window(wx0,wy0,wx1,wy1);       /* view-plane rectangle to look at    */
    g3view(vx0,vy0,vx1,vy1);         /* screen rectangle to draw into      */
    g3persp(d);                      /* focal length; 0 = orthographic     */
    g3render();                      /* clip -> project -> map -> draw     */

All arguments are plain 16-bit ints — no fixed point in the API. The
window/viewport split is the classic CORE/GKS pipeline and it earns its
keep here: the window chooses WHAT you see (pan/zoom by moving it — zoom is
integer-exact, no scale factor anywhere), the viewport chooses WHERE it
lands, and because clipping happens in window space (below), viewports are
true clip rectangles — two viewports side by side give a stereo pair or a
plan+elevation split for free.

Deliberately NOT in v1: camera position/rotation calls. The camera is fixed
at the origin looking down +z. Animation in v1 is caller-side — recompute
the endpoints and rebuild (g3clear + g3line loop) each frame; a rotating
cube is 8 points through a sin/cos table in the demo, not in the library.
When a g3rot/g3eye is wanted, it slots into g3render's per-vertex path
without touching the API above — but it multiplies the muldiv budget (below)
by ~3, so it waits until the base pipeline's speed is MEASURED.

## Coordinates and the arithmetic (the real design work)

World: right-handed, x right, y UP, z into the screen, everything int16.
Screen: 480x272, y DOWN — the viewport map flips y, nobody else does.
The engine's coordinate registers are signed 18-bit, but nothing off-screen
is ever sent to them (see clipping), so 16-bit values always suffice.

**p8cc has exactly one arithmetic type: 16-bit int** (no long, no unsigned —
and int is routinely USED as unsigned, see the compiler notes). The
pipeline's atoms are `x*d/z` shapes whose intermediate product needs 32
bits, so the library's foundation is one routine:

    muldiv(a, b, c)     /* (a*b)/c with a 32-bit intermediate, signed */

Implementation: strip signs; 16x16->32 by shift-add into a hi:lo int pair;
32/16 by long division on the pair; reapply sign. Pure C, portable to the
on-target cc (which shares p8cc's dialect). p8cc's own runtime keeps a
32-bit [__dr:__t] inside __div — an asm fast path for muldiv could reuse
that machinery ONE DAY, but v1 ships the C version and measures it first.

**Projection** (perspective, d = focal length from g3persp):

    sx = muldiv(x, d, z);        sy = muldiv(y, d, z);

d=0 selects orthographic: sx = x, sy = y, no divide at all — worth having
both because ortho is ~2x faster and is the natural mode for plan views.
Default d = 256: a point at z=256 maps 1:1, nearer grows, farther shrinks.

**Near clip, BEFORE the divide.** z <= ZNEAR (= 16) must never reach
muldiv: both endpoints near-side, drop the edge; one endpoint near-side,
slide it to the z=ZNEAR plane:

    x' = x0 + muldiv(x1-x0, ZNEAR-z0, z1-z0);   /* same for y; z' = ZNEAR */

Skipping this is the classic wireframe bug — edges crossing the camera
plane whip across the screen as the divide changes sign.

**Window clip, in window space, BEFORE the viewport map.** Cohen-Sutherland
2D clip of (sx,sy) against the window rectangle: outcode both ends, trivial
accept/reject, else slide an end to a window edge with — muldiv again. Two
reasons this is not left to the device's off-screen discard: (1) it makes
the VIEWPORT the clip boundary, not the screen edge, which is what makes
multiple viewports composable; (2) the engine rasterizes every requested
pixel and discards late, so a wild edge (z just past ZNEAR projecting to
+/-20000) would cost tens of thousands of dead pixel steps per frame.
Clip early, draw only what shows.

**Viewport map**, last, constant denominators per frame:

    px = vx0 + muldiv(sx - wx0, vx1 - vx0, wx1 - wx0);
    py = vy1 - muldiv(sy - wy0, vy1 - vy0, wy1 - wy0);   /* the y flip */

then gline(px0,py0,px1,py1) — the engine takes it from there.

`g3render` itself: gboxf the viewport in black (the no-double-buffer erase,
scoped so it never wipes a neighbouring viewport), pen white, walk the pool.
When stage 6.5/8 adds page flipping, only this erase line changes.

## Budget — MEASURED (emulator cycle counts, 27 MHz)

The estimate survived contact with the enemy only after a fight. As first
built, the all-C muldiv cost **118k cycles (4.4 ms) each** — p8cc compiles
each C statement through the __ax memory accumulator on a microcoded CPU,
so a 32-round shift-add/long-division loop is ~500 cycles per statement —
and the cube ran at 2.4 fps, all of it in the line pipeline (the rotate
was 14 ms/frame, the erase effectively free). The fix that design missed:
**when the product fits in 16 bits, the native * and / (asm runtime
routines) do the whole job** — one native divide (a <= 65535/b) tests it —
and in practice that is nearly every call: the viewport map's products are
<= 240*271, a 256-focal projection's <= |x|*256. Identical results (both
divides truncate the same way; the framebuffer was byte-identical), ~10x
cheaper. The C slow path remains for genuinely 32-bit products.

| | cycles | wall @27 MHz |
|---|---|---|
| muldiv, slow path (all-C 32-bit) | ~118k | 4.4 ms |
| muldiv, fast path (native `*`/`/`) | ~10k | 0.4 ms |
| rotate 8 verts + refill pool (demo side) | 0.39M/frame | 14 ms |
| full cube frame (erase + 12 edges) | **1.94M** | **72 ms = 13.9 fps** |

Scaling from the ~130k-cycles-per-edge slope: ~200 edges ≈ 1 fps. The
next speed rungs, in order of honesty: an asm muldiv (the p8cc runtime's
__div already keeps a 32-bit intermediate), an asm lib_g3d twin, and the
stage-8 geometry engine. Memory: 512 edges x 12 bytes = 6K pool; cube.bin
is 19.8K all-in — half the TPA free beside it.

## Verification

No golden-model work: the same binary runs on the emulator and the board,
and stage 6's co-sim already proves the LINE engine pixel-identical. The
test is a fixed scene (cube at a canned angle, two viewports, one ortho one
perspective) rendered in the emulator with spot-pixel assertions in the
basic_gfx_test style — deterministic integer math, so expected pixels are
stable forever. muldiv gets its own host-side unit test (compile the C with
cc on the Mac against reference *,/ in 32-bit — the routine is pure).

## Not in this stage

- **Double buffering / page flip** — explicitly deferred (user call). The
  viewport-scoped erase above is the interim answer; flicker within one
  viewport is accepted for v1.
- **Colour** — trivially available (gcolor before g3render) but not in the
  pipeline's contract yet.
- **Camera/model transforms in the library** — see above; measure first.
- **Hidden lines, faces, fill** — different algorithms, different stage.
- **BASIC statements** — BASIC has no arrays, so a BASIC world-builder
  would be all statement plumbing around the same C core. If ever, later.
- **The fabric geometry engine** — stage 8+, informed by this stage's
  measured arithmetic costs and settled edge format.

## Build order

1. lib_gfx.c + lib_gfx.inc twin (the parked design, unchanged).
2. muldiv + host-side unit test.
3. lib_g3d.c: pool, window/viewport state, render pipeline.
4. Demo command (spinning cube, caller-side rotation) — measure, fill in
   the budget table above.
5. Emulator spot-pixel test; man pages; /src tree + mk scripts; docs.

## Open question (user decision)

The dual-language rule — every /BIN command ships as C AND byte-identical
asm — has so far covered the file/text commands. Does it bind a 3D demo?
Recommendation: lib_gfx keeps its asm twin (register equates are exactly
the lib_abi pattern), but lib_g3d and the demo ship C-ONLY — hand-porting
muldiv-heavy render math has little of the pedagogical return the fileutils
ports had. Flagged rather than assumed.

> As shipped: the recommendation, following the existing `disasm` precedent
> for a C-only command (lib_gfx.inc equates written; cube in run.sh's
> `_ccmds`). An asm twin remains open — it is also the honest next speed
> rung (see the measured budget). Say the word to reverse.
