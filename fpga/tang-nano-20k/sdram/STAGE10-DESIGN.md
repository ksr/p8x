# Stage 10 — the graphics language (a PGC-class subsystem)

The FPGA becomes a FULL graphics subsystem: it holds the geometry, owns
every transform (modeling, viewing, projection, window/viewport), and is
driven by a **command language** through a FIFO — not by register pokes.
The reference design is the **Matrox PG-640A** (IBM Professional
Graphics Controller compatible; manual: `docs/reference/pg640a.pdf`,
chapter 3 + 4). Where its semantics fit the P8X we borrow them —
including verb names, so the manual doubles as our background reading —
and where they don't (16.16 reals, indexed colour + LUT, CGA emulator)
we deliberately diverge.

Decisions taken with the user 2026-08-23:

- **Execution model: the PGC model.** Commands draw IMMEDIATELY when
  received; persistence comes from **command lists** stored on the card
  (CLBEG/CLRUN/CLOOP). The stage-9 retained scene store is eventually
  subsumed by command lists (see "Relationship to the stage-9 engine").
- **ASCII mode is parsed in fabric**, true PGC style: the card accepts
  both ASCII strings and hex (binary) opcodes, switchable at runtime
  (CA/CX). BASIC — or a human at the serial console — drives graphics
  by writing text at a port, zero host software.
- **2D window-space primitives are in scope** (MOVE/DRAW/POLY/RECT/
  CIRCLE...); the S-series direct-screen primitives are NOT (redundant
  with the $FF20 register interface, which remains).
- **Text commands, flood fill, and drawing modes (LINFUN) are IN
  scope** — as the final rungs, not deferred to the backlog.
- Out of scope, per the user: the CGA emulator, LUT/palette operations,
  indexed colour.

## P8X flavour (deliberate divergences)

| PGC | P8X stage 10 |
|---|---|
| 16.16 "Real" parameters | **int16**, with **8.8 fixed point** where fractions matter (scale factors, matrix entries) — the house format since stage 8b |
| COLOR index 0-255 + LUT | **COLOR r g b** → RGB565 direct, like BASIC's COLOR |
| polygons are outlines; fills separate | keep **filled TRI3** (stage-9 scanline fill); POLY3 gains a PRMFIL-style fill that fans through it |
| onboard 8088 runs firmware | **fabric FSM interpreter** (we have no card CPU — see Interpreter) |
| 640×480×8 | 480×272 RGB565 (and whatever panels stage "800×480" brings) |
| angles in degrees | **degrees, integer** (PGC-compatible feel); sin/cos via quarter-wave BRAM table in 8.8 |

## Architecture

```
                +----------------------------- FPGA ------------------------------+
  P8X bus       |  $FF48-4F GL port                                               |
  writes  ----->|  CMD FIFO (BRAM) -> INTERPRETER FSM -> exec units               |
  reads   <-----|  RB FIFO / ERR FIFO <-+       |                                 |
                |                       |   +---+------------------+              |
                |                       |   | matrix unit (MDU)    |              |
                |                       |   | sin/cos BRAM         |              |
                |                       |   | transform+clip+map   | -> gfx.v     |
                |                       |   | (stage-8b/9 datapath)|    ($FF20    |
                |                       |   +----------------------+    registers,|
                |  SDRAM: framebuffer pages | command lists ($100000+)  mastered) |
                +-----------------------------------------------------------------+
```

The stage-8b/9 walker datapath (matrix MAC, near clip, project, viewport
map, line/tri draw mastering gfx.v) is REUSED as the interpreter's
execution back end — stage 10 replaces how work *arrives* (a language,
not registers/records), not how pixels get drawn.

### The GL port ($FF50-$FF57; gen_memmap is the authority)

($FF48 was the first draft; GEVALH already sits at $FF4A, so the block
moved to the free $FF50 range.)

    GLDATA  $FF50  write: push one byte into the command FIFO
    GLSTAT  $FF51  read:  bit7 FIFO full, bit6 interpreter busy,
                          bit1 error FIFO non-empty, bit0 RB non-empty
    GLRB    $FF52  read:  pop one byte from the read-back FIFO
    GLERR   $FF53  read:  pop one byte from the error FIFO (0 = empty)
    GLID    $FF54  read:  'G' ($47) — the presence probe

Contract mirrors the PGC's three-FIFO model (manual 3.3) shrunk to a
byte port: the host checks GLSTAT bit7 before writing (or trusts a
depth-guaranteed burst), and drains GLRB after a read-back verb. FIFO
depths: command 256 bytes, read-back 256, error 16 — BRAM, PGC-sized.
Error codes: 1 unknown opcode, 2 bad parameter, 3 mode not fitted
(ASCII before 10d), 4 command-FIFO overflow.

### Command encodings (manual 3.2)

**Hex mode**: one opcode byte, then binary parameters, int16
little-endian, 8.8 where the verb says so. We adopt the PGC's opcodes
verbatim where we adopt the verb (e.g. DRAW=28, DRAW3=2A, CLBEG=38) so
the reference card in appendix K stays useful; P8X-only verbs (TRI3,
FLIP, PAGE...) take unused opcodes.

**ASCII mode** (power-up default, like the PGC): keyword + decimal
parameters, delimiters space/tab/comma/semicolon/CR/LF, `-` negates.
Long and short keyword forms (DRAW3 / D3). CA switches to ASCII, CX to
hex, in either encoding.

Fabric ASCII parsing is tractable because the grammar is flat: a
keyword tokenizer (ROM-table match over ≤6 chars) and a decimal
accumulator (×10+digit — one small FSM). No expressions, no nesting.

## Verb set

Core state + control:

    CA / CX            command mode (ASCII / hex)
    NOOP RESETF WAIT   as PGC (RESETF = all state to power-up defaults)
    CLEARS             clear screen to colour index -> clears BOTH pages
    COLOR r g b        RGB565 pen (P8X form)
    FLIP / PGSYNC      P8X page verbs (engine flip rule / rejoin)

Transforms (manual 3.4 — all state lives on the card):

    MDIDEN                       modeling matrix := I
    MDORG x y z                  modeling origin (rotation/scale pivot)
    MDROTX/Y/Z deg               compose rotation (card computes sin/cos)
    MDSCAL sx sy sz              compose scale (8.8 params)
    MDTRAN tx ty tz              compose translation
    MDMATX <12 x 8.8>            load modeling matrix directly
    VWIDEN VWRPT VWROTX/Y/Z      viewing matrix family (orbit the viewer
    VWMATX                         around the viewing reference point)
    DISTAN dist                  viewer distance
    PROJCT angle                 field of view; 0 = orthographic
    DISTH/DISTY dist             hither/yon plane distances
    CLIPH/CLIPY flag             enable/disable hither/yon clipping
    WINDOW x0 y0 x1 y1           2D window (as today)
    VWPORT x0 y0 x1 y1           screen viewport (as today)

The modeling/viewing SPLIT is load-bearing: stage 9's single combined
matrix is why `rotate` once clobbered `cube`'s translation. Two master
matrices composed in command order (submatrix multiply on the MDU
datapath, exactly the manual's model) ends that class of bug.

**10b as implemented (the semantics contract).** Everything happens at
COMMAND time; the per-vertex datapath is stage 9's, untouched:

    v_screen = project( (VR*((M*v>>8) + Tm - r))>>8 + (0,0,dist) )

- MD* verbs compose submatrices into M on the LEFT (issue order = apply
  order: MDSCAL then MDTRAN scales first), about the MDORG pivot
  (T = o - (S*o)>>8, the rotate.c rule); rotation rows are rotate.c's.
- VW* verbs compose into VR with the NEGATED angle (the viewer orbits);
  VWRPT (r) and DISTAN (dist) are state, not compositions. The viewer
  sits dist behind the reference point: eye z = z_vw + dist, so dist=0
  is exactly the stage-9 camera and 10a streams render unchanged.
- Every verb rebuilds par[0-11] = VR o M (muldiv /256, int16 wrap adds
  -- gl_mcomp/gl_recompose in the emulator, the C_ML microprogram in
  RTL, term-for-term identical).
- PROJCT angle switches K (par[12]) from the native 256 to
  WW*128/TANH8[angle] (WW = window width; K re-derives when WINDOW
  moves); PROJCT 0 = orthographic; out-of-range logs error 2. Power-up
  and RESETF are NATIVE (K=256, dist=0) -- PGC-style projection is
  opt-in, stage-9 compatibility is the default.
- DISTH/DISTY set plane distances from the reference point; CLIPH/CLIPY
  gate them into the NEW parameter-file entries par[23] (near, floor 16
  -- the divide guard survives) and par[24] (far; 32767 = disabled,
  which is why the yon pass costs nothing when off). The pipeline's
  near clip is parameterized and a mirror-image far clip follows it
  (lines interpolate at z=far; the TRI polygon gets a second clip pass,
  up to 5 vertices, fan unchanged).
- CONVRT projects the 3D current point (z clamped to near/far) into the
  2D current point.
- P8X divergences: MDMATX takes 12 int16 (3x3 8.8 + T), VWMATX 9 (VR
  only); angles are integer degrees through the shared SIN8 table
  (generators/gen_trig.py emits the emulator's trigtab.h and the RTL's
  trigtab.v ROMs from one formula).

Primitives (immediate; current-point pen model, one 2D and one 3D
current point, manual 3.6). The PGC's 2D space has NO matrix — 2D
primitives clip to the window and map to the viewport, nothing else.
The R-variants take vertices relative to the current point:

    MOVE x y       MOVER dx dy        DRAW / DRAWR      POINT
    POLY n x1 y1 ... / POLYR          RECT x y / RECTR  (2D, window space)
    MOVE3/MOVER3   DRAW3/DRAWR3       POINT3
    POLY3 n .../POLYR3                                  (3D)
    PRMFIL flag    closed primitives fill when 1 (POLY/POLY3/RECT)
    CONVRT         3D current point -> 2D current point (10b)

There is NO separate TRI3 verb: `PRMFIL 1` + `POLY3 3 ...` IS the
stage-9 filled triangle, and larger fills fan through it (convex, like
the engine). POLY3 outlines draw as closed DRAW3 edges (window-space
clip); CIRCLE/ELIPSE/ARC/SECTOR are deferred to the 10b+ rungs (ARC and
SECTOR need the sin/cos table; the curve primitives need a
viewport-clipped device path).

Command lists (manual 3.9 — the retained-object system):

    CLBEG n ... CLEND     store list n (0-255) on the card (SDRAM)
    CLRUN n               run once        CLOOP n count   run count times
    CLDEL n               delete          CLRD n          read back
    CLMOD n off len bytes patch in place

Instancing is the manual's two-houses idiom: MDTRAN + CLRUN, twice.
Animation is a list whose tail rotates its own matrix, then CLOOP — the
CPU is idle while the card spins the object.

Read-back + errors (manual 3.12/3.13):

    MATXRD 1|2            modeling / viewing matrix -> RB FIFO
    FLAGRD n              state flags -> RB FIFO
    error FIFO            one byte per error (unknown opcode, bad param
                          count, FIFO overflow, list undefined...) —
                          card-side errors at last, not host guessing

Final rungs (in scope, shipped last):

    LINFUN mode           drawing modes: replace/complement/OR/AND/XOR
                          (rubber-band + erase-by-redraw tricks)
    AREA / AREABC         SEED fill (needs a pixel-readback walker; note
                          FLOOD is NOT this -- PGC FLOOD just paints the
                          viewport, so it ships in 10a as the erase verb)
    TEXT "s" TSIZE TANGLE TJUST TDEFIN...   on-card text in window space

## Opcode assignments (verified against the manual, ch. 4 + appendix K)

    01 NOOP    02 FLIP*   03 PGSYNC* 04 RESETF  05 WAIT    06 COLOR
    07 FLOOD   08 POINT   09 POINT3  0F CLEARS  10 MOVE    11 MOVER
    12 MOVE3   13 MOVER3  28 DRAW    29 DRAWR   2A DRAW3   2B DRAWR3
    30 POLY    31 POLYR   32 POLY3   33 POLYR3  34 RECT    35 RECTR
    38 CIRCLE  39 ELIPSE  3C ARC     3D SECTOR  43 CA/CX ("CA "/"CX ":
                                        the mode switches are their own
                                        ASCII bytes in BOTH modes)
    61 FLAGRD  62 MATXRD  70 CLBEG   71 CLEND   72 CLRUN   73 CLOOP
    74 CLDEL   76 CLRD    78 CLMOD   80 TEXT    81 TSIZE   82 TANGLE
    90 MDIDEN  91 MDORG   92 MDSCAL  93 MDROTX  94 MDROTY  95 MDROTZ
    96 MDTRAN  97 MDMATX  A0 VWIDEN  A1 VWRPT   A3 VWROTX  A4 VWROTY
    A5 VWROTZ  A7 VWMATX  A8 DISTH   A9 DISTY   AA CLIPH   AB CLIPY
    AF CONVRT  B0 PROJCT  B1 DISTAN  B2 VWPORT  B3 WINDOW  C0 AREA
    C1 AREABC  E0 PRMFIL  EB LINFUN
    (* = P8X-only verbs on opcodes the PGC leaves unused)

WINDOW and VWPORT take parameters in the PGC's order: x1 x2 y1 y2 —
manual examples must type in verbatim. P8X screen y runs DOWN (0-271);
window y runs UP, the flip happens in the viewport map, as ever.

## Relationship to the stage-9 engine

The $FF40 record engine (GEUP/GESEL/GEVAL/GECMD, typed records,
persistent scene) KEEPS WORKING while stage 10 grows alongside — cube,
tri, rotate, camera, and lib_g3d stay green through 10a-10c. Once
command lists ship, the stage-9 scene store is redundant (a scene is a
command list) and the console commands migrate to trivial GL emitters;
retiring the record front end then reclaims fabric for the text/flood
rungs. **LUT budget is the watch-item:** stage 9 sat at 13,487 LUT4
(65%); 10a's interpreter took it to 17,693 (85%), and 10b's first build
BROKE PLACEMENT at 22,151 (106%) — the trig tables had synthesized as
LUT case-ROMs. Lesson paid: **big constant tables go in BSRAM as
clocked ROMs** (gen_trig.py emits them that way now; callers hold the
address stable a cycle, which the compose FSM's C_NRM state already
guarantees).

**The retirement ledger (2026-08-24).** The record front end was retired
(user-approved): −2,504 LUT4. DSP inference was unlocked (`synth_gowin
-family gw2a` — the flag build.sh had never passed; 19 multipliers moved
to the chip's idle MULT blocks). And still 10b does not place. The
second lesson paid: **nextpnr's "LUT4: 92%" line under-reports on
Gowin** — ALU cells (carry chains: every 16-bit add/sub/compare) occupy
the SAME physical LUT sites, so real demand was 19,249 LUT + 4,368 ALU
≈ 23.6k on 20,736 sites, ~114%. p8x_geom alone is 8,739 LUT + 1,766 ALU
— half the chip — dominated by the indexed matrix/polygon register
arrays (glmm/glvm/ms/ct, qx..qsy) whose read muxes and index arithmetic
are pure fabric. The way out is the same trick as the trig tables:
**the compose engine's scratch matrices belong in a BSRAM scratchpad**,
serialized through one address port — the FSM is already sequential, so
the cost is states, not wall-clock that matters. Until that lands, 10b
is emulator-and-bench proven (byte-identical frames, all suites green)
but not on silicon; 10a-with-retirement would fit (~15.4k) if an
interim bitstream is wanted.

## Client story

- **BASIC:** ASCII mode makes graphics a string problem. Minimum: a
  `GL` statement (`GL "MDROTY 45"` / `GL "DRAW3";X;Y;Z`) that writes
  bytes to GLDATA honouring GLSTAT. Every manual example then types in
  almost verbatim.
- **C:** lib_gl.c (//#use gl) — a thin emitter over GLDATA (hex mode
  for compactness), plus glrb()/glerr() drains. lib_g3d clients migrate
  only when stage-9 retirement lands.
- **Console:** a `gl` command that passes its argument line (or a
  file, `gl -f script.gl`) straight to the port — the manual's
  house.pga workflow, on a P8X disk. The PGC monitor program's role.

## Staging (each rung shipped end-to-end before the next)

- **10a — transport + hex interpreter.** GL port + FIFOs; hex-mode
  interpreter covering COLOR/WINDOW/VWPORT/PROJCT(fixed persp),
  MOVE(3)/DRAW(3)/POLY(3)/POINT(3)/TRI3/PRMFIL/CLEARS/FLIP/PGSYNC —
  i.e. everything the stage-9 datapath already draws, arriving as a
  language. Same pixels as stage 9 for the same scene: byte-compare.
- **10b — card-side matrices.** sin/cos BRAM, submatrix compose on the
  MDU datapath; MD* and VW* families, DISTAN/PROJCT proper,
  DISTH/DISTY/CLIPH/CLIPY. rotate/camera become one-line emitters.
- **10c — command lists.** CLBEG/CLEND/CLRUN/CLOOP/CLDEL in SDRAM;
  cube becomes a stored list that spins with CLOOP, CPU idle.
- **10d — ASCII mode in fabric.** Tokenizer + decimal parser, CA/CX;
  BASIC GL statement; the `gl` console command; manual examples run.
- **10e — read-back + error FIFOs.** MATXRD/FLAGRD/CLRD/CLMOD; error
  codes for every parse/exec fault.
- **10f — drawing modes.** LINFUN on the line/fill writers.
- **10g — flood fill.** FLOOD/AREA seed-fill walker.
- **10h — text.** TEXT + attributes + user-defined glyphs (TDEFIN),
  drawn in window space through the 2D pipeline.

Retirement of the stage-9 record front end is its own decision point
after 10c — ASK the user (workflow rule: no silent breakage of shipped
interfaces, and it is also a disk+bitstream lockstep change).

## Verification ladder (per rung, the usual order)

1. **Emulator golden model first**: the interpreter (both encodings) in
   p8xemu, sharing the ge_* transform/draw code — the language's
   semantics are pinned in C before any RTL exists.
2. Host replica scripts feed identical command streams to emulator and
   replica; framebuffer byte-compare (the stage-9 crown-jewel pattern —
   now the STREAM is the interface, so the same .gl file drives every
   implementation).
3. tb: directed command streams against expected register/pixel traces;
   FIFO pacing, overflow, error-FIFO cases.
4. Bitstream; board POINT checks; the house (typed in from the manual,
   ASCII mode, over serial) as the stage's showpiece.

## Not in stage 10

CGA emulator, LUT/palette ops, indexed colour (user-excluded); S-series
direct-screen primitives (register interface already covers it);
IMAGER/IMAGEW raster block moves (the image command + P8I flow covers
it — revisit if GL scripts want inline blits); BLINK/RBAND; GIN/cursor
support (no pointing device); local pipes (appendix J).
