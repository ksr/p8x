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

### The GL port (proposed $FF48-4F; gen_memmap is the authority)

    GLDATA  write: push one byte into the command FIFO
    GLSTAT  read:  bit7 FIFO full, bit6 interpreter busy,
                   bit1 error FIFO non-empty, bit0 RB FIFO non-empty
    GLRB    read:  pop one byte from the read-back FIFO
    GLERR   read:  pop one byte from the error FIFO
    GLID    read:  'G' (0x47) — the presence probe

Contract mirrors the PGC's three-FIFO model (manual 3.3) shrunk to a
byte port: the host checks GLSTAT bit7 before writing (or trusts a
depth-guaranteed burst), and drains GLRB after a read-back verb. FIFO
depths: command 256 bytes, read-back 256, error 16 — BRAM, PGC-sized.

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

Primitives (immediate; current-point pen model, one 2D and one 3D
current point, manual 3.6):

    MOVE x y       MOVER dx dy        DRAW / DRAWR      POINT
    POLY n x1 y1 ... / POLYR          RECT x y / RECTR
    CIRCLE r       ELIPSE rx ry       ARC ...           (2D, window space)
    MOVE3/MOVER3   DRAW3/DRAWR3       POINT3
    POLY3 n .../POLYR3                TRI3 x0..z2       (3D)
    PRMFIL flag    closed primitives fill when 1 (TRI3/POLY3/RECT/CIRCLE)
    CONVRT         3D current point -> 2D current point

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
    FLOOD colour / AREA   seed fill (needs a pixel-readback walker)
    TEXT "s" TSIZE TANGLE TJUST TDEFIN...   on-card text in window space

## Relationship to the stage-9 engine

The $FF40 record engine (GEUP/GESEL/GEVAL/GECMD, typed records,
persistent scene) KEEPS WORKING while stage 10 grows alongside — cube,
tri, rotate, camera, and lib_g3d stay green through 10a-10c. Once
command lists ship, the stage-9 scene store is redundant (a scene is a
command list) and the console commands migrate to trivial GL emitters;
retiring the record front end then reclaims fabric for the text/flood
rungs. **LUT budget is the watch-item:** stage 9 sits at 13,487 LUT4
(65%); the interpreter + ASCII parser + matrix composer must fit in the
remainder, and the retirement of the record path is the relief valve.

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
