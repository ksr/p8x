# Stage 9 — colour on the wire, faces on the screen

Stage 8b's engine draws white lines. This stage gives every primitive its
own colour and adds the first FACE: a 3D triangle with a fill option —
the polygon primitive (an N-gon is a fan of triangles, and the fan is the
caller's one-liner; hardware gets the primitive everything tessellates
to). Two sub-stages, each shipped end-to-end before the next begins:

- **9a — colour per record.** The list format grows a header; every
  record carries its own RGB565 colour. LINE records only.
- **9b — the TRI record**, outline or filled.

## The list format: TYPED RECORDS (replaces the raw 12-byte edge)

    byte 0    type      1 = LINE, 2 = TRI
    byte 1    flags     bit0 = FILL (TRI only)
    bytes 2-3 colour    RGB565, little-endian
    then      vertices  int16 x,y,z per vertex, little-endian
                        LINE: 2 verts -> 16-byte record
                        TRI:  3 verts -> 22-byte record

Records are even-sized (halfword walker unchanged) and self-sizing (the
walker advances by type). The count parameter becomes a RECORD count.
There is no compatibility shim with the stage-8b format: bitstream and
disk ship together, as ever — but the change is why cube.bin and the
engine must move in one sync.

## 9a: colour per record

- lib_g3d grows `g3color(c)` — the POOL pen, default white; `g3line`
  stamps it into the record. `g3render`'s software walk sets the device
  pen per record; the engine writes GCOL/GCOLH per record before its
  LINE. The engine's erase is unchanged (pen 0), and it no longer forces
  white afterwards — the device pen is left holding the LAST record's
  colour (same "set your pen after" rule the image command documents).
- cube.c colours its rings (bottom red, top green, verticals blue) —
  rotation becomes legible at a glance, and the demo doubles as the
  colour test.

## 9b: the TRI record

**Outline** (flags.FILL=0): after transform + near clip + projection +
viewport map, each polygon edge is Cohen-Sutherland-clipped in SCREEN
space against the viewport box, then drawn as a LINE. (LINE records keep
their established window-space clip; both are exact — the outline clips
post-map so it shares the fill's vertices.)

**Filled** is the new algorithm, and its clipping is the reason it is
simple: a filled triangle needs NO Cohen-Sutherland. Pipeline:

1. Transform the 3 vertices (matrix, as ever).
2. **Near clip the polygon** against z = Z3NEAR: walk the edges
   v0v1, v1v2, v2v0; keep in-front vertices, insert the muldiv
   intersection where an edge crosses. Yields 0, 3 or 4 vertices; a quad
   (a,b,c,d) fans into (a,b,c) + (a,c,d). (This is the one place a
   triangle becomes two.)
3. Project AND viewport-map each vertex — fill happens in SCREEN SPACE,
   so every implementation rounds the same three points the same way.
4. **Scanline fill, clamped to the viewport box** (clamping against an
   axis-aligned rectangle is exact — that is what replaces CS here):
   - sort the mapped vertices ascending by y (comparison-swap network;
     equal y keeps record order),
   - for each y from y0 to y2 inclusive, skip y outside the viewport,
   - span ends by muldiv interpolation, operand order fixed:
     long edge  xa = px0 + muldiv(y - py0, px2 - px0, py2 - py0)
     split edge xb = against v0v1 while y < py1, else v1v2
     (py2 == py0: the whole thing is one scanline; span = min..max x),
   - clamp both ends to [vx0, vx1], skip empty spans,
   - emit the span as the device's own BOXFILL with y0 = y1 = y — one
     register-poked command per scanline, so the SOFTWARE walk, the
     EMULATOR engine and the RTL all issue the identical device op and
     the pixels cannot disagree. The span machinery (gfx_span pair
     writes) makes it fast for free.

Cost per filled scanline: 2 muldivs + a BOXFILL issue (~40 + ~60 cycles)
plus the device's pair-write fill — a 100-line triangle in the order of
20k cycles, engine-side. The CPU still writes ~30 pokes a frame.

## API

    g3color(c)               pool pen for subsequent records (default white)
    g3line(x0,y0,z0,...)     unchanged signature, now stamps the pen
    g3tri(p, fill)           p = int[9]: three x,y,z vertices; fill 0/1
                             (an N-gon: fan g3tri calls, one line of C)

g3up/g3go/g3render/g3flags/g3flip/g3sync are unchanged. The software
fallback renders both record types with the same math — the identity-
matrix byte-compare (engine vs software, one framebuffer) remains the
crown-jewel test and now covers colour and fill.

## Verification ladder (per sub-stage, the usual order)

1. Emulator ge_render walks typed records (golden model).
2. lib_g3d + cube (9a: coloured rings; 9b: a g3tri demo face) —
   emulator suites: colour spot-asserts, tri-fill spot pixels from a
   host replica of THIS spec, engine-vs-software identity byte-compare
   over a mixed pool (lines + tris, filled + outline, clipped + not).
3. tb_geom: directed records against the same replica (expected pen
   writes now checked per record; a TRI's expected span list).
4. Bitstream (the walker FSM grows ~15 states; LUT budget has room),
   flash + disk TOGETHER (format change!), board POINT verification.

## Not in stage 9

Shading/interpolated colour, depth sorting or hidden faces (painter's
order is the caller's job — the pool draws in record order), textures,
and BASIC statements for triangles. Each is a later rung.
