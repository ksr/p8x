#!/bin/sh
# BASIC's graphics statements: COLOR / LINE / BOX [,FILL|,NOFILL] / CLS.
#
# These drive the $FF20 display, whose own behaviour is covered by gfx_test.sh.
# What is checked HERE is the interpreter side, where the failures are quiet:
#
#   1. NOFILL must draw an OUTLINE. It has to be a real keyword rather than just
#      "the default", because with FILL tokenised and NOFILL not, CRUNCH matches
#      FILL *inside* the word NOFILL -- so asking for an outline would silently
#      give you a solid box. That is the single nastiest bug available here, and
#      it is invisible unless something checks the middle of the box.
#   2. CLS must clear to the BACKGROUND but leave the current COLOR alone. GCOL
#      is write-only in the device, so the pen cannot be read back and restored;
#      BASIC keeps the GPEN shadow for exactly this.
#   3. LINE endpoints are inclusive.
#   4. LIST must round-trip the new keywords -- a token with no KWTAB entry
#      lists as garbage while running perfectly.
#   5. FILL and NOFILL are modifiers, not statement leaders: a line that is just
#      "FILL" has to be rejected by CHECKLINE.
set -e
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$(dirname "$0")"
fail() { echo "BASIC-GFX TEST: FAIL — $1"; exit 1; }

python3 "$ROOT/assembler/p8xasm.py" "$ROOT/basic/p8xbasic.asm" -o bgfx.bin --base 0x6A00 \
    -D BASORG=0x6A00 -D BASRAM=0xC500 -D PBUF=0xE000 -D MONITOR=0x2000 >/dev/null \
    || fail "BASIC (TPA build) did not assemble"

# A fresh disk copy each run: p8xfs put does NOT replace an existing file, so
# re-installing over a stale name would silently keep testing the OLD binary.
cp "$ROOT/os/run-disk.img" bgfx.img 2>/dev/null || fail "need os/run-disk.img (run os/run.sh once)"
python3 "$ROOT/tools/p8xfs.py" put bgfx.img bgfx.bin --name /bin/bgfx.bin \
    --load 0x6A00 --exec 0x6A00 >/dev/null || fail "could not install the test BASIC"

# COLOR 28 then CLS: if CLS clobbered the pen, the filled box would come out
# pen 0 and vanish. The NOFILL box is checked in its middle; the LINE at its
# ends. The pens are the 3-3-2 primaries rather than 1/2/3 -- at 8 bpp a pen is
# a whole byte, and COLOR 224 also proves BASIC hands all eight bits to GCOL.
printf 'B\rbgfx\r10 COLOR 28\r20 CLS\r30 BOX 20,20,120,120,FILL\r40 COLOR 224\r50 BOX 200,20,300,120,NOFILL\r60 COLOR 3\r70 LINE 20,240,458,240\r80 END\rRUN\rLIST\rFILL\rBYE\r' \
    > bgfx.in
../p8xemu -N -i bgfx.in -c bgfx.img -l 120000000 -g bgfx.ppm eeprom.bin > bgfx.out 2>/dev/null || true

python3 - <<'PY' || exit 1
import sys
bad = []
out = open("bgfx.out","rb").read().replace(b"\r", b"")

# 4. LIST round-trips every new keyword
for kw in [b"10 COLOR 28", b"20 CLS", b"30 BOX 20,20,120,120,FILL",
           b"50 BOX 200,20,300,120,NOFILL", b"70 LINE 20,240,458,240"]:
    if out.count(kw) < 2:            # once as typed, once from LIST
        bad.append("LIST did not round-trip %r" % kw.decode())

# 5. a bare FILL is not a statement
if b"?SYNTAX ERROR" not in out:
    bad.append("a bare FILL line was accepted - CKLEAD is not rejecting the modifier")

d  = open("bgfx.ppm","rb").read()
px = d[d.index(b"255\n")+4:]
W  = 480
BLACK, RED, GREEN, BLUE = (0,0,0), (255,0,0), (0,255,0), (0,0,255)
NAME = {BLACK:"pen $00", RED:"pen $E0 red", GREEN:"pen $1C green", BLUE:"pen $03 blue"}
def fb(x, y):
    i = (y*W + x)*3
    return tuple(px[i:i+3])
def want(x, y, c, why):
    got = fb(x,y)
    if got != c:
        bad.append("(%d,%d) is %s, want %s - %s"
                   % (x, y, NAME.get(got,got), NAME.get(c,c), why))

# 2. CLS cleared to background, and did NOT eat COLOR 28
want(  0,   0, BLACK, "CLS did not clear to the background")
want( 70,  70, GREEN, "CLS clobbered the current COLOR (GPEN shadow not restored)")
# 1. BOX ,FILL is solid; BOX ,NOFILL is an outline
want( 20,  20, GREEN, "filled BOX corner missing")
want(120, 120, GREEN, "filled BOX corner missing")
want(200,  20, RED,   "NOFILL BOX edge missing")
want(300, 120, RED,   "NOFILL BOX edge missing")
want(250,  70, BLACK, "NOFILL drew a SOLID box - FILL was matched inside NOFILL")
# 3. LINE endpoints are inclusive
want( 20, 240, BLUE, "LINE start point not drawn")
want(458, 240, BLUE, "LINE end point not drawn (exclusive end?)")
want(240, 240, BLUE, "LINE middle missing")

if bad:
    print("BASIC-GFX TEST: FAIL")
    for b in bad: print("  " + b)
    sys.exit(1)
print("BASIC-GFX TEST: draw statements ok")
PY

# --- part 2: PLOT / CIRCLE / PALETTE / POINT --------------------------------
# The trap here is PALETTE: SETPAL names the pen it recolours through GCOL, the
# same register that selects the DRAWING pen. If BASIC does not hand the pen back
# from its GPEN shadow afterwards, PALETTE silently changes what you draw with
# next -- and since it only bites the *following* statement, it looks like that
# statement is broken rather than PALETTE.
printf 'B\rbgfx\r10 CLS\r20 COLOR 224\r30 PALETTE 3,15,0,15\r40 BOX 10,10,80,80,FILL\r50 COLOR 3\r60 CIRCLE 240,136,100,FILL\r70 COLOR 28\r80 CIRCLE 240,136,120\r90 PLOT 400,40\r100 PRINT POINT(240,136)\r110 PRINT POINT(400,40)\r120 PRINT POINT(0,271)\r130 PRINT POINT(14,14)\r140 END\rRUN\rLIST\rBYE\r' \
    > bgfx2.in
../p8xemu -N -i bgfx2.in -c bgfx.img -l 120000000 -g bgfx2.ppm eeprom.bin > bgfx2.out 2>/dev/null || true

python3 - <<'PY' || exit 1
import sys
bad = []
out = open("bgfx2.out","rb").read().replace(b"\r", b"")

# POINT reads back what was drawn. 3 = filled circle, 28 = the plotted pixel,
# 0 = untouched corner, 224 = inside the box drawn AFTER PALETTE. The two
# large values matter on their own: POINT has to return a whole BYTE, which is
# the read-back half of 8 bpp.
if b"\n3\n28\n0\n224\n" not in out:
    bad.append("POINT sequence wrong; wanted 3,28,0,224 in %r"
               % out[out.find(b"RUN"):out.find(b"RUN")+40])

for kw in [b"30 PALETTE 3,15,0,15", b"60 CIRCLE 240,136,100,FILL",
           b"80 CIRCLE 240,136,120", b"90 PLOT 400,40", b"100 PRINT POINT(240,136)"]:
    if out.count(kw) < 2:
        bad.append("LIST did not round-trip %r" % kw.decode())

d  = open("bgfx2.ppm","rb").read()
px = d[d.index(b"255\n")+4:]
W  = 480
BLACK, RED, GREEN, MAGENTA = (0,0,0), (255,0,0), (0,255,0), (255,0,255)
NAME = {BLACK:"pen $00", RED:"pen $E0 red", GREEN:"pen $1C green",
        MAGENTA:"pen 3, PALETTE'd magenta"}
def fb(x, y):
    i = (y*W + x)*3
    return tuple(px[i:i+3])
def want(x, y, c, why):
    got = fb(x,y)
    if got != c:
        bad.append("(%d,%d) is %s, want %s - %s"
                   % (x, y, NAME.get(got,got), NAME.get(c,c), why))

# PALETTE recoloured pen 3 to magenta, and did NOT steal the drawing pen:
# the box on line 40 must still be pen $E0 (red), not pen 3.
want( 14,  14, RED,     "PALETTE stole the drawing pen (GPEN not restored)")
want(240, 136, MAGENTA, "PALETTE did not recolour pen 3")
# CIRCLE ,FILL is solid; the bare CIRCLE is an outline with a gap inside it
want(240, 236, MAGENTA, "filled CIRCLE does not reach its bottom edge")
want(240,  16, GREEN,   "outline CIRCLE top not drawn")
want(240,  26, BLACK,   "gap between the two circles is filled - CIRCLE drew solid")
# PLOT put a single pixel down
want(400,  40, GREEN,   "PLOT did not draw")
want(404,  40, BLACK,   "PLOT drew more than one pixel")

if bad:
    print("BASIC-GFX TEST: FAIL")
    for b in bad: print("  " + b)
    sys.exit(1)
print("BASIC-GFX TEST: draw, plot, circle, palette, point ok")
PY

# --- part 3: CIRCLE's optional second radius makes it an ellipse ------------
# The parser has to tell a second radius from the FILL modifier by TOKEN: a
# keyword is >= $80, anything else starts an expression. That is also why NOFILL
# must be a real keyword -- otherwise `CIRCLE x,y,r,NOFILL` would try to EVAL it.
printf 'B\rbgfx\r10 CLS\r20 COLOR 1\r30 CIRCLE 60,68,30\r40 COLOR 2\r50 CIRCLE 170,68,60,20\r60 COLOR 3\r70 CIRCLE 170,110,15,20,FILL\r80 PRINT "A";POINT(90,68);POINT(60,68);POINT(230,68);POINT(10,130);POINT(170,110)\r90 END\rRUN\rBYE\r' \
    > bgfx3.in
../p8xemu -N -i bgfx3.in -c bgfx.img -l 120000000 eeprom.bin > bgfx3.out 2>/dev/null || true

python3 - <<'PY' || exit 1
import sys
out = open("bgfx3.out","rb").read().replace(b"\r", b"")
# POINT probes, in order:
#   (90,68)  right edge of the pen-1 circle r=30 about (60,68)      -> 1
#   (60,68)  its centre, an outline, so background                  -> 0
#   (230,68) right edge of the pen-2 ellipse rx=60 about (170,68)   -> 2
#   (10,130) far from every shape                                  -> 0
#            (170,88) was the first choice and is WRONG: the ellipse is
#            centred y=68 with ry=20, so y=88 is exactly its bottom edge.
#   (170,110) centre of the pen-3 FILLED ellipse                    -> 3
want = b"A10200" if False else b"A1"
i = out.find(b"\nA")
got = out[i+1:i+7] if i >= 0 else b"?"
if got != b"A10203":
    print("BASIC-GFX TEST: FAIL - ellipse probes are %r, want b'A10203'" % got)
    print("  (circle edge, circle centre, ellipse edge, gap, filled-ellipse centre)")
    sys.exit(1)
print("BASIC-GFX TEST: ellipse ok")
PY

# --- part 4: GTEXT x,y,size,string$ ------------------------------------------
# GTEXT is the one graphics statement BASIC rasterises ITSELF -- the device has
# no text command -- so the things that can break here are different in kind
# from parts 1-3:
#
#   1. The glyph must actually be the right glyph. The font offset is index*5
#      built from shifts and adds, and P8X's ADD has a FIXED carry-in: it does
#      NOT add C. A missing carry moves the font pointer by exactly 256 bytes
#      and still draws something plausible-looking, which is how it hides.
#   2. Lowercase must fold onto the uppercase glyph, not draw a blank.
#   3. size must scale the glyph, not just move it.
#   4. A string running off the right edge must STOP, not wrap onto the next
#      row. The device discards off-screen pixels, so a wrap would not come from
#      the device -- it would come from the 8-bit x cursor rolling over.
#   5. GTEXT must draw in the CURRENT pen, and "" must be legal and draw nothing.
# The glyph is 5x7 device pixels whatever the screen is, so these origins do NOT
# scale with the panel -- only the clipping case has to move, to a 'W' that
# really does straddle x=479.
printf 'B\rbgfx\r10 CLS\r20 COLOR 224\r30 GTEXT 10,10,1,"A"\r40 COLOR 28\r50 GTEXT 40,10,1,"a"\r60 COLOR 3\r70 GTEXT 4,40,2,"A"\r80 COLOR 224\r90 GTEXT 470,80,1,"WW"\r100 GTEXT 5,110,1,""\r110 END\rRUN\rLIST\rBYE\r' \
    > bgfx4.in
../p8xemu -N -i bgfx4.in -c bgfx.img -l 200000000 -g bgfx4.ppm eeprom.bin > bgfx4.out 2>/dev/null || true

python3 - <<'PY' || exit 1
import sys
bad = []
out = open("bgfx4.out","rb").read().replace(b"\r", b"")
d  = open("bgfx4.ppm","rb").read()
px = d[d.index(b"255\n")+4:]
W  = 480
BLACK, RED, GREEN, BLUE = (0,0,0), (255,0,0), (0,255,0), (0,0,255)
NAME = {BLACK:"pen $00", RED:"pen $E0 red", GREEN:"pen $1C green", BLUE:"pen $03 blue"}
def fb(x, y):
    i = (y*W + x)*3
    return tuple(px[i:i+3])
def want(x, y, c, why):
    got = fb(x,y)
    if got != c:
        bad.append("(%d,%d) is %s, want %s - %s"
                   % (x, y, NAME.get(got,got), NAME.get(c,c), why))

# The 5x7 'A': apex at column 2 of row 0, uprights at columns 0 and 4 from row 2
# down, crossbar across the whole of row 4. Pinning the apex AND the empty
# corner is what catches a font pointer that landed on the wrong glyph.
want(12, 10, RED,   "'A' apex missing - wrong glyph, or GTEXT drew nothing")
want(10, 10, BLACK, "(10,10) is lit; 'A' has no top-left pixel - font off by a glyph")
want(10, 12, RED,   "'A' left upright missing")
want(14, 12, RED,   "'A' right upright missing")
for x in range(10, 15):
    want(x, 14, RED, "'A' crossbar broken at x=%d" % x)
want(12, 16, BLACK, "row 6 of 'A' should be open between the uprights")

# lowercase folds to the SAME shape, in its own pen
want(42, 10, GREEN, "lowercase 'a' did not fold onto the 'A' glyph")
want(40, 10, BLACK, "folded 'a' is not aligned like 'A'")
for x in range(40, 45):
    want(x, 14, GREEN, "folded 'a' crossbar broken at x=%d" % x)

# size 2: every font pixel becomes a 2x2 block, so the apex is 4 pixels and the
# glyph occupies twice the extent. Origin (4,40), apex at column 2 => x 8..9.
for x in (8, 9):
    for y in (40, 41):
        want(x, y, BLUE, "size-2 apex block incomplete at (%d,%d)" % (x, y))
want(10, 40, BLACK, "size-2 apex is too wide - the block is not 2x2")
want( 4, 44, BLUE,  "size-2 left upright missing (row 2 should start at y=44)")
want( 4, 42, BLACK, "size-2 upright started too early - rows are not scaled")

# clipping: 'W' at x=470 is partly on screen, the second one is off it. Nothing
# may appear at the left edge on those rows.
for y in range(80, 87):
    for x in range(0, 12):
        if fb(x,y) != BLACK:
            bad.append("(%d,%d) lit - GTEXT wrapped past the right edge" % (x,y))
            break

# "" is legal and draws nothing
for y in range(110, 118):
    for x in range(4, 20):
        if fb(x,y) != BLACK:
            bad.append('GTEXT ...,"" drew at (%d,%d)' % (x,y))
            break

for kw in [b'30 GTEXT 10,10,1,"A"', b'70 GTEXT 4,40,2,"A"', b'100 GTEXT 5,110,1,""']:
    if out.count(kw) < 2:
        bad.append("LIST did not round-trip %r" % kw.decode())

if bad:
    print("BASIC-GFX TEST: FAIL")
    for b in bad[:12]: print("  " + b)
    sys.exit(1)
print("BASIC-GFX TEST: gtext ok (glyph, case folding, scaling, clipping)")
PY

# A missing separator is a syntax error, not a half-drawn string.
printf 'B\rbgfx\r10 GTEXT 10,10,1\r20 END\rRUN\rBYE\r' > bgfx5.in
../p8xemu -N -i bgfx5.in -c bgfx.img -l 120000000 eeprom.bin > bgfx5.out 2>/dev/null || true
if ! grep -q "SYNTAX ERROR" bgfx5.out; then
    fail "GTEXT with no string argument was accepted"
fi
# --- part 5: the whole screen is reachable -----------------------------------
# This replaces the old SCREEN-mode part. There are no modes any more: the
# device is 480x272 at 8 bpp and nothing else, so SETMODE and BASIC's SCREEN
# both went away. What is still worth pinning is the half of that part which
# was never about modes at all:
#
#   1. the far corner (479,271) must read back, and one pixel past it must not
#      -- an off-by-one in the stride shows up here and nowhere else;
#   2. 8 bpp really is 256 pens, not 4 masked to 2 bits, so pen 200 has to
#      survive a round trip through the framebuffer.
printf 'B\rbgfx\r10 CLS\r20 COLOR 5\r30 BOX 0,0,479,271,FILL\r40 COLOR 200\r50 PLOT 400,250\r60 PRINT "A";POINT(479,271);",";POINT(400,250);",";POINT(480,0)\r70 END\rRUN\rLIST\rBYE\r' \
    > bgfx6.in
../p8xemu -N -i bgfx6.in -c bgfx.img -l 400000000 eeprom.bin > bgfx6.out 2>/dev/null || true

python3 - <<'PY' || exit 1
import sys
out = open("bgfx6.out","rb").read().replace(b"\r", b"")
bad = []
i = out.find(b"\nA")
got = out[i+1:out.find(b"\n", i+1)] if i >= 0 else b"?"
if got != b"A5,200,0":
    bad.append("full-screen probes are %r, want b'A5,200,0'" % got)
    bad.append("  (far corner 479,271 = pen 5; a 200 that survived 8 bpp; 480,0 off-screen = 0)")
for kw in [b"30 BOX 0,0,479,271,FILL", b"50 PLOT 400,250"]:
    if out.count(kw) < 2:
        bad.append("LIST did not round-trip %r" % kw.decode())
if bad:
    print("BASIC-GFX TEST: FAIL")
    for b in bad: print("  " + b)
    sys.exit(1)
print("BASIC-GFX TEST: full screen ok (479,271 reachable, 256 pens survive)")
PY

echo "BASIC-GFX TEST: PASS (draw, plot, circle, ellipse, palette, point, gtext, full screen)"
