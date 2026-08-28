# P8X Graphics Engine — Programmer's Guide

How to draw things, from every seat in the house. The engine has four
doors, cheapest first:

| From | You write | Best for |
|---|---|---|
| the shell | `gl DRAW3 90,-90,300` or `gl FILE.GL` | exploring, scene files, demos |
| BASIC | native verbs: `MDROTY 20 : POLY3 3,...` | programs, animation, teaching |
| C | `//#use gfx` / `//#use g3d` / GL bytes | commands, tools |
| assembly | `;#use gfx` equates + the same registers | when it must be small |

All four reach the same silicon; the same scene renders identically
from any of them, and identically in the emulator and on the board.
Hardware internals: [p8x-graphics-theory.md](p8x-graphics-theory.md).
Reference cards on-target: `man gl`, `man gfx`, `man g3d`, `man basic`.

## 1. First light (any door)

Probe first — an absent display floats the bus:

    BASIC:  IF POINT(0,0) ... only after the OS booted with a display
    C:      if (!gpresent()) { puts("?No display"); return 1; }
    shell:  gl (prints ?No display / ?No GL engine itself)

Then, at the shell:

    gl VWPORT 0 479 0 271 WINDOW 0 479 0 271
    gl COLOR 0 63 0 PRMFIL 1
    gl MOVE 100,100 RECT 380,171

Everything after `gl` is one ASCII GL line (wrapped `CA ... CX` for
you). Numbers separate on spaces or commas; `man gl` is the verb card.

## 2. Coordinate spaces — the one thing to internalize

- **Screen space**: 480x272, origin top-left, y DOWN. BASIC's own
  statements (PLOT/LINE/BOX/CIRCLE/GTEXT/POINT) and the C gfx library
  live here, unclipped-but-discarded at the edges.
- **Window space**: the GL 2D world, y UP. `WINDOW x1 x2 y1 y2` (PGC
  order: both x's first!) declares the world extent; `VWPORT x1 x2 y1
  y2` maps it to screen pixels, flipping y. GL 2D primitives
  (MOVE/DRAW/POLY/RECT) are clipped to the window — off-window
  geometry is CUT, not discarded.
- **Model space**: 3D verbs (MOVE3/DRAW3/POLY3) pass through the
  modeling matrix, the viewing matrix, projection, and near/far
  clipping before landing in window space.

A faithful PGC stream may set WINDOW and assume the PGC's power-on
full-screen viewport; the P8X powers up with a degenerate viewport, so
lead scene files with `VWPORT 0 479 0 271` (BACKLOG has the note).

## 3. Drawing 2D

    gl COLOR 31 0 0                       red pen (r 0-31, g 0-63, b 0-31)
    gl MOVE 0,0 DRAW 239,135              line in window space
    gl PRMFIL 1 POLY 4 10 10 100 10 100 80 10 80    filled quad
    gl RECT 200,100                       rect from current point
    gl FLOOD 0 0 0                        erase the viewport

BASIC's screen-space statements coexist: `LINE 0,0,479,271` draws
corner to corner regardless of the GL window. Use GL 2D when you want
clipping and a world coordinate system; use the BASIC/C primitives
when you want pixels.

## 4. Drawing 3D

    gl RESETF
    gl VWPORT 104 375 0 271 WINDOW -120 120 -120 120
    gl COLOR 0 63 0 PRMFIL 1
    gl MDY 30                             compose: rotate model 30 deg
    gl POLY3 3 -80 -80 300 80 -80 300 0 40 420

Rules of thumb:

- **Matrices compose.** `MDY 20` twice is 40 degrees. `MDIDEN` resets
  the modeling matrix; `VWIDEN` the camera; `RESETF` everything.
- **The camera**: `VWRPT x y z` picks the point the viewer orbits,
  `VWX/VWY/VWZ deg` orbit it, `DISTAN d` backs the viewer off, `PROJCT
  angle` sets the lens (0 = orthographic; power-up = the native
  focal-256 camera, which is also what `DISTAN 0` means).
- **Fills are fans**: `PRMFIL 1` + `POLY3 n ...` fan-fills convex
  polygons through the triangle engine. Outlines clip per edge.
- **Depth**: near clipping is always on (z >= 16 in eye space); yon
  arrives with `DISTY d CLIPY 1`.

## 5. Scenes that persist: command lists

Immediate commands draw and are gone. A LIST is a recorded byte stream
on the card (64 slots x 4KB):

    gl CLBEG 2 CLEARS 0 0 0 POLY3 3 ... FLIP CLEND
    gl CLRUN 2                            one full frame
    gl MDIDEN MDY 40 CLRUN 2              redraw at a new angle

Record the erase and the FLIP INSIDE the list and every CLRUN is a
complete frame. For self-running animation, put the matrix delta
inside and loop — deltas accumulate per pass, the CPU is idle:

    gl CLBEG 1 MDY 5 CLRUN 2 CLEND       (a list may not run a list --
    gl CLOOP 1 72                         so spin via a second list that
                                          redraws the scene... see below)

(Nesting is refused, so the idiomatic spinner records the WHOLE frame
— delta, erase, draw, FLIP, WAIT 1 — in one list and CLOOPs it; `cube`
is the worked example, `man cube`.) `tri`/`rotate`/`camera` maintain
list 0 as "the scene"; `CLAPP` grows a list in place; `CLDEL` frees a
slot. Lists survive anything except power (SDRAM) and `RESETF`.

## 6. Drawing modes (LINFUN)

    gl LINFUN 4                           XOR mode
    gl MOVE 10,10 DRAW 200,200            draw...
    gl MOVE 10,10 DRAW 200,200            ...and un-draw: ground restored
    gl LINFUN 0                           back to replace

Modes: 0 replace, 1 complement (invert dest, pen ignored), 2 OR,
3 AND, 4 XOR. They apply to lines, points and outlines from EVERY door
(the mode lives in the display device), take effect between
primitives, and fills always replace. XOR is the rubber-band idiom;
complement is visible on any background. `RESETF`, reset, and power-up
restore replace mode.

## 7. Filling arbitrary shapes (AREA)

    gl COLOR 31,0,0                       red pen
    gl MOVE 100,100 RECT 200,150          an outline...
    gl MOVE 150,125 AREA                  ...seed-filled from inside

`AREA` flood-fills from the 2D current point with the pen, bounded by
pen-coloured pixels. `AREABC r g b` bounds on a stated colour instead,
so the fill and the outline can differ:

    gl COLOR 0,0,31                       blue outline
    gl POLY 4 300,200 350,150 400,200 350,250
    gl COLOR 0,63,0 MOVE 350,200          green pen, seed at centre
    gl AREABC 0,0,31                      fill up to the blue

The fill walks real framebuffer pixels (a scanline flood), so anything
already drawn is a boundary candidate. A seed outside the window is
error 2; a seed sitting ON the boundary colour (or on pen-coloured
pixels) quietly fills nothing. `PRMFIL 1` remains the right tool for
filled primitives you are about to draw; `AREA` is for shapes that
exist only as outlines — and it always paints in replace mode,
whatever `LINFUN` says.

## 8. From BASIC

Every GL verb is a native statement (no quotes, expressions allowed):

    10 RESETF : CLEARS 0,0,0
    20 WINDOW -120,120,-120,120 : VWPORT 104,375,0,271
    30 COLOR RGB(0,63,0) : PRMFIL 1
    40 FOR A=0 TO 350 STEP 10
    50 MDIDEN : MDROTY A
    60 POLY3 3,-80,-80,300,80,-80,300,0,40,420
    70 NEXT A

`COLOR` feeds both pens; `GL s$` sends a raw ASCII line when you need
string-building (`GL "MDY "+STR$(A)`); native list verbs
(CLBEG/CLEND/CLRUN) are synchronous, `GL "CLOOP 1 72"` is the
non-blocking spin. POINT(x,y) reads pixels (screen space). The full
statement list: `man basic`, GRAPHICS; the language guide chapter in
`basic/p8x-basic-guide.md`.

## 9. From C

    //#use gfx      screen-space primitives over $FF20 (man gfx)
    //#use g3d      the software 3D pipeline / GL-era compatibility (man g3d)

For the GL port itself the idiom is three lines (as used by gl.c,
tri.c, cube.c):

    int glb(int v) { while (peek(0xFF51) & 128) { } poke(0xFF50, v); return 0; }
    int glw(int v) { glb(v & 255); glb((v / 256) & 255); return 0; }
    /* hex: glb(opcode); params glw(...)  --  drain GLERR when done */

Wait for idle with `while (peek(0xFF51) & 64) { }` before reading
results or exiting. Named constants: `//#use abi` + the `//#define`
header pattern; never raw magic numbers in shipped code.

## 10. Scene files

A `.GL` file is the ASCII language verbatim — `gl FILE.GL` streams it.
Start files with `CA ` (the hex-mode escape is the literal
space-terminated three bytes) and end with `CX `; lead with a VWPORT.
The PG-640A manual's examples convert mechanically (its hex files
carry 4-byte coordinates; re-emit as ASCII). `docs/reference/pg640a.pdf`
chapter 3 is effectively this engine's extended manual.

## 11. Performance model

- Command bytes are cheap; PIXELS are the cost. A fullscreen fill is
  ~65k pixel-pairs through the burst filler; a spinning cube is ~40
  bytes per frame.
- Matrix verbs cost a compose run at COMMAND time (microseconds);
  vertices then transform at fixed per-vertex cost.
- LINFUN modes add a read-modify-write per pixel — noticeable only in
  principle; invisible at panel rates.
- `WAIT n` inside lists paces to real frames; poll GLSTAT bit6 from
  outside rather than sleeping.
- The serial console is slower than everything above: stream scene
  FILES rather than typing long lines (the line editor keeps 63
  chars).
