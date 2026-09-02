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
are pure fabric. The fix (LANDED 2026-08-24): **the compose engine's
scratch matrices moved into a small 1W2R scratchpad RAM** (a mirrored
distributed-RAM pair; M/VR/MS/CT at fixed offsets), serialized through
registered read ports — the FSM was already sequential, so the cost was
nine states and a two-cycle read bubble per term, invisible at command
time. With that, 10b PLACES: 18,703 LUT4 (90%) + 4,404 ALU, BSRAM
44/46, Fmax 45 MHz against the 27 MHz clock. The proof chain held
through the rework untouched: op-stream constants (tb_gl), both scenes
byte-identical emulator-vs-RTL (c_gl_rtl_test), 92-PASS make test.

## Client story

- **BASIC:** ASCII mode makes graphics a string problem. Minimum: a
  `GL` statement (`GL "MDROTY 45"` / `GL "DRAW3";X;Y;Z`) that writes
  bytes to GLDATA honouring GLSTAT. Every manual example then types in
  almost verbatim.
  **As built (2026-08-26), BASIC went further: the verbs are NATIVE
  statements** — 51 of them (`MDROTY A*2`, `POLY3 3,-80,...`,
  `CLBEG 1 : MDROTY 5 : CLEND : CLOOP 1,7`), tokens $B4..$E6 driven by
  ONE generic handler through a table gen_glkw.py emits alongside the
  C and Verilog ones (basic/glkwtab.inc + glvtab.inc — token order is
  ABI). Native statements emit HEX opcodes directly (no translator
  round-trip, no 32-char string cap — which a 9-coordinate POLY3
  cannot fit anyway), record inside CLBEG/CLEND, and DRAIN GLSTAT
  busy on exit so `POINT()` after a draw is deterministic on silicon;
  `GL s$` stays the async text path. `COLOR` feeds both pens. The GL
  `POINT` verb and `NOOP` stay string-only (name/ABI reasons).
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

  **10c as designed (2026-08-24; emulator half + console family +
  RTL SHIPPED 2026-08-25 — places at 19,129 LUT4/92%, all three
  emulator-vs-RTL frames byte-identical; BOARD-VERIFIED same day:
  every POINT probe exact, cube spins itself via CLOOP).** The retained-scene system, PGC
  chapter 3.9 shrunk to the P8X:

  - **Storage**: 256 lists in SDRAM at $100000 (the retired record
    list's home; the g-port master returns for exactly this), fixed
    4KB slots — list n at $100000 + n*4096, byte length in the slot's
    first halfword, stream from byte 2. A 256-bit DEFINED bitmap lives
    in fabric (CLRUN of a never-recorded slot must error, and SDRAM
    powers on as garbage).
  - **Recording** (CLBEG n ... CLEND): bytes flow through the NORMAL
    decoder — it must track command boundaries anyway, or a parameter
    byte equal to CLEND's opcode would end the list — but execution is
    suppressed and every consumed byte is appended to the slot instead.
    An unknown opcode logs error 1 and is skipped, not stored. CLEND at
    a command boundary finishes the list, writes the length, sets the
    bitmap bit.
  - **Replay** (CLRUN n / CLOOP n count): the interpreter's byte SOURCE
    switches from the command FIFO to a fetcher walking the slot; the
    decode/execute machinery is untouched (one interpreter, two byte
    sources). GLDATA bytes queue in the FIFO meanwhile and run after.
    CLOOP rewinds and replays count times; matrix DELTAS inside a
    looped list therefore accumulate — MDROTY 2 per pass spins, VWROTY
    per pass orbits, and a tail of FLIP + WAIT 1 paces each pass to the
    panel: the FLY-THROUGH, zero bytes from the CPU after launch.
  - **CLAPP n** (P8X-only, opcode 79): CLBEG that APPENDS at the stored
    length instead of replacing — the PGC has no append, but the shell
    needs one (`tri ... k` grows the scene list without read-back,
    which does not exist until 10e).
  - **Nesting is refused**: CLBEG/CLAPP while recording, CLRUN/CLOOP
    while recording or replaying — error 5. Undefined list — error 6.
    A list outgrowing its 4KB slot — error 7, recording aborted, slot
    left undefined. CLDEL n clears the bitmap bit; RESETF clears them
    all (the SDRAM bytes are dead, not erased).
  - **The console commands come home**: tri records/appends the SCENE
    LIST (list 0) and runs it; rotate = MDROT* + CLRUN 0; camera =
    VW*/DISTAN + CLRUN 0 — both shed their ?No engine interim. cube
    records its cube once and CLOOPs a spin tail, CPU idle.
  - **Fabric budget**: the g-port revival + fetcher + bitmap land near
    the known placement cliff, so 10c also moves the T-path polygon
    arrays (qx/qy/qz, the far-pass mirror, qsx/qsy) into the compose
    scratchpad RAM — the same registered-read rework that made 10b
    place, applied to the walker's biggest remaining register file.
- **10d — ASCII mode in fabric.** Tokenizer + decimal parser, CA/CX;
  BASIC GL statement; the `gl` console command; manual examples run.

  **10d as built (2026-08-25; emulator + RTL + clients SHIPPED, all
  FOUR emulator-vs-RTL frames byte-identical — 10a scene, 10b matrix,
  10c fly-through, 10d ASCII; places at 18,943 LUT4/91%, seed 1).**

  - **A pure translator front-end**: ASCII mode never touches the
    decoder. A small FSM ahead of the byte source turns keywords into
    opcodes and decimal numbers into width-correct parameter bytes
    (byte-count params first, then int16 LE), and feeds them through a
    4-byte queue into the same consumer the hex path uses. CA/CX just
    flip the mode bit — they emit nothing. Lists store HEX bytes
    regardless of input mode, so a list recorded from ASCII replays
    identically.
  - **The keyword table lives in the scratchpad BSRAM** (addresses
    128+), generated by gen_glkw.py into glkwtab.vh + glkwtab.h — 110
    entries, long and short forms, one meta word each
    ({var,arity,bcnt,opcode}); the RTL, the emulator and the docs are
    generated from the same table.
  - **Deterministic recovery**: early keyword → error 2 + zero-fill
    the missing params; unknown keyword → error 1 + swallow its
    numbers; orphan number → error 2. Same sequences in the emulator
    and the bench.
  - **Clients**: `gl` (one ASCII line, or a .gl file streamed
    verbatim — the house.pga workflow on a P8X disk) and BASIC's GL
    statement (string expression, wrapped CA ... CX).
  - **The placement diet** (the translator costs ~600 LUT4 and 10c
    left no slack): what finally moved the needle was removing ADDERS,
    not muxes — nextpnr's LUT4 count ≈ yosys LUT4 + 2·MUX2_LUT5 +
    2·ALU, so every 16-bit add/sub/compare is ~34 "LUTs". Three cuts
    shipped: (1) the muldiv operands md_a/b/c became raw pairs
    (md_a1-md_a2 ...) with THREE shared subtractors where every FSM
    arm used to carry its own (-405); (2) one shared post-adder forms
    every `X ± md_q` apply, base loaded at launch (md_r/md_rn); (3)
    every aligned lane/slot address became a CONCAT — the scratchpad
    bases are 8/16-aligned and the SDRAM list slots 4KB-aligned, so
    base+offset never carries and needs no carry chain (-285). The
    anti-lessons are recorded too: migrating small register arrays
    (tv*, par[0..8]) into BSRAM lanes and time-sharing comparator
    banks behind state-keyed muxes both came out NET WORSE — wide
    muxes are nearly free in MUX2_LUT5 pairs, and every new
    state-keyed select costs more fabric than the ALUs it saves.
    Sharing pays only where the routing mux ALREADY exists.
- **10e — read-back + error FIFOs.** MATXRD/FLAGRD/CLRD/CLMOD; error
  codes for every parse/exec fault.

  **10e status (2026-08-26): built and sim-complete, then BACKED OUT** --
  the rung costs ~900 LUT4 more than the chip has (20,047 vs the
  ~19,150 cliff). The full implementation (emulator + BASIC GLRD + RTL
  with the state-mirror design) lives in commit c0931f0 and its revert;
  resurrect it when the successor board (or a retirement) frees room.
  10f was taken instead -- smaller appetite, see below.

- **10f — drawing modes.** LINFUN on the line/fill writers.

  **10f as built (2026-08-27; emulator + RTL + BASIC SHIPPED, placed at
  19,048 LUT4/91% seed 1, Fmax 54.5 MHz).**

  - **LINFUN m** (EB, modes 0 replace / 1 complement / 2 OR / 3 AND /
    4 XOR; >4 = error 2; RESETF and power-up = replace). The mode is
    DEVICE state: a new GMODE register on the 2D engine ($FF2E's write
    side, GID1 keeps the read; gen_memmap is the authority), so BASIC's
    direct LINE/PLOT honour it exactly like GL primitives.
  - **Scope: the single-pixel path only** -- lines, points, outlines
    (PLOT/LINE/BOX outline/CIRCLE/ELLIPSE). Every fill and CLS always
    replaces: the burst span filler stays a burst, and the modal
    classifier is one per-command bit at dispatch. Divergence noted in
    man gl.
  - **RMW in gfx_mem**: nonzero mode turns the pixel write into
    read-combine-write (one new state; the read path existed for
    POINT). ~3 extra cycles per modal pixel, invisible at 12 MHz.
  - **Ordering**: the GL walker's GMODE write WAITS for the engine to
    go idle (W_LF polls GSTAT like S_LINB) -- found the hard way when
    a mode change overtook a line still drawing and the frames diverged
    mid-primitive. The emulator is synchronous; the contract is
    "LINFUN applies between primitives".
  - **The placement fight, round two**: 10f's gross cost was ~360 LUT4
    (19,303, all seeds failed). Funded by TWO now-verifiable diets:
    the ellipse error step serialized through ONE shared 40-bit
    add/sub (was ~526 bits of parallel carry chains; -146) and the
    circle error step (outline + fill) routed through the SAME shared
    adder as three more mux arms (-109). Both became legitimate only
    after **tb_gl_cpx.v** closed a real coverage hole: circle/ellipse
    had never had RTL pixel proof (they are unreachable from GL). The
    proof chain now has SIX byte-identical frames: 10a scene, 10b
    matrix, 10c fly-through, 10d ASCII, 10f LINFUN, and the $FF20
    circle/ellipse device scene.
- **10g — flood fill.** FLOOD/AREA seed-fill walker.

  **10g as built (2026-08-28; emulator + RTL pixel-exact on the first
  bench run; card personality).**

  - **AREA** (C0, no params: fill from the 2D current point with the
    pen, boundary = pen) and **AREABC r g b** (C1: boundary = the
    stated colour). The emulator's `gl_afill` IS the contract, and the
    RTL walker reproduces it step for step: outcode the seed against
    the window (off-window = error 2), viewport-map it, then the
    classic scanline loop -- pop a seed, re-probe it (spans painted
    since the push may have absorbed it), probe the span left and
    right, paint it, and push ONE seed per interior run on the rows
    above and below.
  - **Seed on the boundary (or on already-pen pixels) is a silent
    no-op** -- gl_af_in's verdict is `v != boundary && v != pen`, so
    painted pixels are the visited mark. That is also why **AREA
    forces GMODE to replace** before it starts: a fill under XOR/AND
    would break its own invariant (documented in man gl).
  - **The stack is explicit and in SDRAM**: 16384 x/y halfword pairs
    at $180000 (the g-port address {00,11,00,sp,00}; lists sit at
    $100000, so the region was free). Hitting the cap is error 8 and
    a DETERMINISTIC partial fill -- both implementations stop the
    same way. The replay fetcher defers to the fill (`af_g` gates it)
    so an AREA inside a command list cannot race the walker's stack.
  - **Probes are real device POINTs**: the walker gained a `gm_rd`
    strobe (plumbed through both tops and every bench) and pops
    GDATA's low/high bytes exactly as the CPU would -- the fill sees
    the framebuffer only through the public register window, card-edge
    clean. Paints are device LINEs (L..R on one row). Both waits use
    the S_LINB idiom: engine idle before GCMD, engine idle before
    reading the pixel back.
  - **Proof**: tb_gl_arx.v replays c_gl_area_test's gl_ar.c scene
    (red rect + AREA, blue diamond + green AREABC, off-window seed ->
    GLERR 2 then 0) through the real pixel stack; the frame is
    byte-identical to the emulator's gl_ar.ppm. The proof chain is now
    SEVEN frames (stage 8 in c_gl_rtl_test.sh). tb_gl still passes
    untouched -- the fill is purely additive to the walker.
- **10h — text.** TEXT + attributes + user-defined glyphs (TDEFIN),
  drawn in window space through the 2D pipeline.

  **10h as built (2026-08-29; emulator + RTL pixel-exact; card
  personality). The TEXT/TSIZE/TANGLE subset, plus TDEFIN because the
  card NEEDS it: SDRAM is volatile, so a font must stream in after
  power-up regardless -- TDEFIN is that loader.**

  - **A glyph IS a command list**: relative MOVER3/DRAWR3 strokes plus
    a trailing pen-up advance, in a SECOND 64-slot bank at $140000 --
    one address bit (bit 18) on the existing slot concat, one
    rec_bank/rp_bank flag pair, and the entire recording and replay
    machinery is reused unchanged. Slots map ASCII 32..95 (space
    through underscore -- the classic uppercase machine); lowercase
    folds in TEXT and TDEFIN both.
  - **TSIZE s / TANGLE d are compose ALIASES** of MDSCAL s s s and
    MDROTZ d (TSIZE copies pw0 into the scale lanes and jumps into the
    MDSCAL arm; TANGLE is the MDROTZ arm with cax forced to Z). So
    size and angle transform strokes AND baseline through the ordinary
    matrix path, compose like every matrix verb, and pivot about
    MDORG. Divergence from the PGC (absolute TSIZE) is documented in
    man gl. Window-space text wants PROJCT 0: at the power-up
    perspective camera, z=0 sits behind the near plane.
  - **TEXT (80, count + chars)** is a small per-char loop (G_TX): pop
    a char, fold, map (slot = ch[5:0]^$20), and if the glyph is
    defined replay it via the unchanged fetcher with rp_bank set; the
    G_OP redirect re-enters the loop while chars remain. Undefined
    glyphs skip silently. TEXT/TDEFIN inside a list is DEFERRED
    (error 5, both when recorded and when replayed) -- a second replay
    context is the cost, noted for a successor.
  - **The ASCII form emits one single-char TEXT per character**
    (`80 01 c` per char): the translator's quoted-string mode needs no
    count-first buffering in EITHER implementation, and the glyph
    state carries the baseline so the drawing is identical to the
    counted hex shape. BASIC's TEXT statement (meta $FF in glvtab)
    emits the counted form.
  - **RESETF does not clear the font** (an installed resource, like
    nothing else on the card); power loss does. The keyword ROM grew
    past 128 entries and found the translator matcher's 7-bit entry
    cursor -- t_ent is 8 bits now and gen_glkw.py asserts the bound.
  - **Proof**: tb_gl_txx.v streams the GENERATED os/font.gl (64
    TDEFIN recordings) and the gl_tx.gl scene (1x, MDORG-anchored 4x,
    30-degree tilt, lowercase folding) through the real pixel stack --
    byte-identical to the emulator's gl_tx.ppm. The chain is NINE
    frames (stage 9 in c_gl_rtl_test.sh); basic_gl_test runs
    TDEFIN/TSIZE/TEXT as native statements. gen_font.py authors the
    5x7 stroke font (grid x 0..4, y 0..6, advance 6; TSIZE 256 =
    7-unit capitals).

- **10i/10j/10k — the PGC completion (2026-08-29; emulator + RTL
  pixel-exact, all three).** Everything remaining from the manual that
  was ever in scope:

  - **10i curves**: CIRCLE (38, r) / ELIPSE (39, rx ry) map their radii
    through the window->viewport scale and draw as ONE device ellipse
    (the device's radius registers are 8-bit: clamp at 255; unsigned
    coordinates clip an off-window centre to nothing; screen-clipped,
    the sole curve/window divergence). ARC (3C) / SECTOR (3D, both
    r a0 a1, integer degrees CCW from +x, a0=a1 = full turn) walk
    4-degree polylines on the shared trig ROM through the CLIPPED 2D
    line path -- the emulator's tail rule is the contract (the last
    regular vertex jumps straight to a1; an extra 2-degree step cost
    one apex pixel until the RTL matched it). PRMFIL fills
    circle/ellipse (device) and SECTOR (a fan of map-only 2D tris
    about the centre); SECTOR r 0 0 is a filled circle drawn as a
    fan. Negative radius = error 2; none move the current point.
  - **10j patterns**: LINPAT p is DEVICE state like GMODE -- the
    register map is full, so it rides GCMD 0C latching {GPARM2,GPARM};
    the Bresenham loop gates px_go on the pattern, MSB first,
    restarting each primitive, every line from every door (glyph
    strokes included). AREAPT shipped here too -- 16 words streamed
    to scratch 784+ masking fill spans through a run splitter -- but
    was REMOVED 2026-08-30 to buy placement headroom (see the round-
    four note below); opcode E7 is err1 again. AREA forces replace AND
    solid (its visited-mark invariant) with the idle-waited setup the
    W_LF lesson demands. RESETF restores everything.
  - **10k text completion**: TJUST h v (1..3 each) offsets the start
    point in MODEL units (h: 0/-3n/-6n of the 6-unit advance, v:
    0/-3/-7 of the 7-unit cap), so TSIZE/TANGLE transform the
    justification with the string. That forced the translator BACK to
    counted strings (the count must lead): chars pack two per scratch
    word at 800..831, cap 63. TEXTP (83) is TEXT's alias -- on the
    PGC, TEXT was the fixed character generator and TEXTP the
    programmable stroke text; P8X text IS stroke text. TEXT runs
    inside command lists now: the glyph replay got its OWN context
    (rpg) overlaying the list replay -- and its length-read state had
    to join the fetcher's exclusion guards (the ISSUE states race the
    prefetch leg on the same stale !sd_busy, found as glyph L's length
    halfword arriving as the chars 'IS').
  - **The placement fight, round three.** The three rungs cost ~3,100
    LUT4 gross against ~1,800 of headroom. Serialization diets washed
    out (state-arm deletions trade evenly against the source muxes
    they need). What actually paid: RETIRING the redundant pre-PGC
    device machinery (user-approved) -- the midpoint-circle rasterizer
    (a circle IS the ellipse rx=ry; cardinal pixels identical, r=0
    draws nothing now), the BOX-outline walker (four LINEs, same
    pixels), and the CLS pair-writer (BOXFILL 0,0-479,271; RESET's
    clear rides S_FILL). Monitor splash, BASIC (CIRCLE/BOX/CLS),
    lib_gfx and every bench were repointed; frames are pixel-identical
    except the circle's rasterizer change. Plus: MDMATX/VWMATX stream
    into the lanes (pbuf shrank 24->8 and the 12-way pair mux died),
    and AREA's span paint rides the S_LIN writer.
  - **TRAP for the record**: the BASIC BOX shadows were first homed at
    BASRAM $F2 -- which ALIASES SEED/POKEA/SPSAV. Every LINE wiped the
    saved stack pointer and BYE reset the machine through a fresh
    splash; the frame the test dumped was the splash. They live in the
    statement-scratch run at $E6 now, with the warning comment the
    file already carried about "free" bytes.
  - **The placement fight, round four (2026-08-30).** 20,679/20,736
    (99.7%) SYNTHESIZED but would not legalize: seeds 1-4 all failed
    placement ("design is probably at utilisation limit"). The design
    fit logically; the placer had no slack to maneuver. User-approved
    fix: REMOVE AREAPT (the patterned fill mask) end to end -- the E7
    stream state (G_AP), the WP_* run splitter, the W_APR restore and
    its regs, the scratch 784..799 rows, the keyword/glvtab entries
    (BASIC GL tokens after it shift; the verbs were days old), and
    the emulator model, with docs and the pattern tests reworked to
    assert the err1 skip. LINPAT stays (a latch and a gate). That
    measured -569 (20,679 -> 20,110) -- real, but the deeper truth
    surfaced by rounds two and four together is that the PRACTICAL
    placement cliff is ~19,150-19,250 LUT4 (19,129 placed; 19,303 and
    everything above failed every seed; placer knobs -- heap-beta
    0.98, longer legalization timeouts, the SA placer -- all failed
    too, SA by crashing). So ARC/SECTOR went as well, user-approved:
    the 3C/3D dispatch, G_CVN/G_CV/G_CV2D, the CVP0-4 arc-vertex
    subroutine and the angle-walk regs. CIRCLE/ELIPSE (CVE0-7) and
    the trig ROM (the rotation verbs' too) stay. Both removals are
    successor-board candidates, recorded in BACKLOG. Measured:
    ARC/SECTOR was worth a startling -2,045 (20,110 -> 18,065 -- the
    fan's lane loader and the angle walk's muldiv scheduling carried
    far more mux fabric than the state count suggested). **The card
    PLACES at 18,065 LUT4 / 87%, seed 1, Fmax 73.2/88.0 MHz vs 12 --
    ~1,100 under the cliff, real slack again.**

Retirement of the stage-9 record front end is its own decision point
after 10c — ASK the user (workflow rule: no silent breakage of shipped
interfaces, and it is also a disk+bitstream lockstep change).

## The single-interface migration (user-directed, 2026-08-31 ->)

The endgame: extend the language until nothing needs the $FF20 register
door, then close it. One verb at a time, each shipped end to end.

- **PIXRD x y (opcode $63) -- DONE 2026-08-31.** One pixel's colour to
  the RB FIFO: window coordinates through the same two-muldiv map as
  CVE0/1 (the FULL 16-bit unsigned <480/<272 bounds check happens
  BEFORE the 9-bit probe regs -- a wrapped negative must read 0), then
  the AF pixel-probe subroutine (return code 6), the colour staged in
  scratch word 782 and handed to the 10e G_RBP pusher (rbp_n=1). Five
  states on the numbers AREAPT freed. Records into command lists and
  reads at replay. BASIC's PIXELR() is the verb now -- its wflip died
  the same day it was born (PIXRD takes window coords natively), and
  PIXELR TRANSFORMS under WINDOW/VWPORT like PIXELW: the caveat list
  shrank to GTEXT/IMAGE. BASIC's LAST device-door READ is gone.
  MockCard grew a preloadable RB FIFO for bridge tests. Traps for the
  record: basic_gl_test's probe-window restore hit BASIC's 32-char
  string cap AGAIN (a 38-char two-verb GL string truncates and the
  starved verb EATS the following PIXRD bytes -- split the string);
  and the RTL battery's PRX bench is SELF-checking (RB words, no
  frame to compare).
- **GTEXT -- RETIRED OUTRIGHT 2026-09-01 (user: "go full with PGC
  TEXT").** No migration: PGC TEXT with a LOADED font replaced it.
  The OS streams /FONT.GL to the GL port at boot (FONTLD, after
  PATHINIT; GLID probe + FOPEN/FGETB with GLSTAT backpressure; no
  engine or no file = silent skip) -- the glyph bank survives RESETF
  by design, so one load per power-on. BASIC lost the whole software
  rasterizer, the font57 bitmap table (generator deleted), the GT*
  BASRAM working set, AND the GPEN pen shadow (GTEXT was its last
  consumer -- COLOR is pure GL emission now). Two contract facts the
  rung surfaced, now load-bearing in tests and docs: (1) TEXT anchors
  at the 3D current point and its strokes live at z=0, which the
  NATIVE camera near-clips (the stage-9 z>=16 rule) -- so BASIC
  cold-starts with PROJCT 0 (2D-first; RESETF deliberately restores
  the native camera); the idiom is MOVE3 x,y,0 : TEXT s$. (2) TSIZE
  scales the ANCHOR too (the documented absolute-TSIZE divergence):
  under TSIZE 512, MOVE3 coordinates are model units. Text is now
  card-side stroke replay -- on the board this replaces GTEXT's
  per-pixel bridge writes with a few dozen stream bytes.
- **BLIT (opcode $64) -- DONE 2026-09-01.** Header x y w h (window-
  coord BOTTOM-left anchor through the PIXRD/CVE map; w,h device
  pixels <= 512), then 2*w*h RAW bytes eaten straight off the source
  (glst G_BL, the G_AP pattern) -- paired into pixels, each written
  as a REAL PIXELW (BL_W0..2: colour+coords, idle-wait, GCMD -- GMODE
  applies, patterns do not; the emulator draws through the same
  gpu_px). Rows top-down = the P8I layout, so BASIC's IMAGE is one
  BLIT per row with file bytes streamed verbatim -- ~14 wire bytes +
  a GWAIT round trip per pixel became 2 streamed bytes (the emulator
  -B layer answers GLPUT's bit7 polls LOCALLY while a burst builds,
  so the wire sees ~97% payload). Recording refuses it err2 with the
  payload consumed-and-discarded (rskip grew the discard arm); replay
  headers err2 owing nothing. TRAPS for the record: BASIC's IMX sat
  at \$E6/\$E7 -- and \$E7 is GLTMP, which GLPUT scribbles per byte:
  the anchor's high byte became the last byte sent and the image
  vanished off-window with no errors (IMX now \$DD/\$DE); and iverilog
  multi-line comments must not swallow code lines. FUNDED by removing
  CLMOD (user-approved; measured 342 LUT4 by ablation synth -- always
  measure before asking): 19,296 failed EVERY seed, 18,916/91% places
  seed 1, Fmax 68/85. The cliff ledger stands at ~19,250. ON SILICON
  2026-09-01: silicon_blit.py PASSES (golden 4x3 spot reads, retired-
  CLMOD err1, the full mandrill streamed and file-verified by PIXRD),
  and the MEASURED payoff through the real runcard path: BASIC
  IMAGE of the 256x256 mandrill went from 393.5 s (the device
  per-pixel loop, HEAD~1, measured the same way) to 37.7 s -- 10.4x.
  The ~15 s over the 23 s line-rate floor is host-side (FGETB
  interleave + per-burst ACKs); the UART raise remains the next
  lever.
- **The last CPU-side users -- MIGRATED 2026-09-01 (door-closing phase
  A).** lib_gfx.c became a GL veneer that KEEPS its screen-space API
  (y mapped through the identity flip, 271-y): compressed emission
  helpers (glmov/glrgb/glpf, RECT for the box) because the first
  version overflowed cube.bin past CSTACKTOP, and LAZY ground-state
  init in glbyt (identity window/viewport + outline fill + white pen,
  flag set first so the init's own bytes recurse safely) because g3d
  clients never call gpresent(). The shell `image` twins ride BLIT
  (draw) and PIXRD (grab), keeping screen-space coords -- and the ASM
  twin re-taught the same lesson: it probed GLID but skipped the
  ground state, and the power-up DEGENERATE window garbled every row
  mapping (found as one phantom row at screen 0; the fix is the same
  24 init bytes the C side emits). The monitor splash is a flat GL
  byte table (DSPTAB) streamed with GLSTAT bit7 backpressure; BASIC's
  GCHECK is GLID-only and the dead device helpers (GWAIT/GEXEC/
  GSTORE/GARG + their BASRAM scratch and every $FF2x equate) are
  gone. NOTHING SHIPPED TOUCHES $FF20 ANY MORE.
- **THE DOOR CLOSED -- phase B, 2026-09-01.** The $FF20 CPU window is
  gone from the fabric: the bridge dropped its device path (device idx
  read $FF, writes swallowed -- the wire contract of a closed window),
  the card top wires the walker straight into gfx with no mux, and
  gfx.v shed the CPU-only furniture (IDENT record + cursor, the
  GID0/GID1 "PG" signature, RESET/SELFTEST decode, the GSTAT ERR bit).
  The register file survives as the walker's private property. The
  emulator matches: $FF20-$FF2F floats $FF, gpu_cmd and its state
  deleted, -B forwards GL only. glbridge's pixelr/pixelw/probe became
  GL verbs, so every silicon script ran unchanged -- ALL PASS on the
  flashed doorless bitstream, retired-idx float verified on the wire.
  MEASURED: 18,912/91% LUT4 seed 1 vs 18,916 before -- the door's
  fabric cost was ~4 LUT4, i.e. NOTHING (narrow plumbing; the walkers
  were always where the area went). The payoff is architectural: one
  interface to define, test, bridge and co-simulate. Coverage moved,
  not lost: the door tests retired after their unique radii/edge cases
  were folded into the GL curve rung (both sides); tb_gcard asserts
  the closed-door $FF float through real protocol bytes; the 14-rung
  battery stayed byte-identical throughout.

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
