#!/bin/sh
# BASIC's graphics statements: COLOR / LINE / BOX [,FILL|,NOFILL] / CLS.
#
# MIGRATED 2026-08-30/31: ONE coordinate system, the PGC's -- window
# space, y UP, everywhere. The drawing statements emit GL; GTEXT (baseline
# anchor), IMAGE (bottom-left anchor) and PIXELR() stay device-implemented
# but BASIC flips their y at the door (272 - y - extent), so window (x,wy)
# lands at screen (x, 271-wy). The frame probes below read the PPM in
# screen rows; in-program PIXELR() probes use window coords like the
# drawing that put the pixels there.
# What is checked HERE is the interpreter side, where the failures are quiet:
#
#   1. NOFILL must draw an OUTLINE. It has to be a real keyword rather than just
#      "the default", because with FILL tokenised and NOFILL not, CRUNCH matches
#      FILL *inside* the word NOFILL -- so asking for an outline would silently
#      give you a solid box. That is the single nastiest bug available here, and
#      it is invisible unless something checks the middle of the box.
#   2. CLS must clear to the BACKGROUND but leave the current COLOR alone --
#      it is a GL FLOOD 0,0,0 now, which carries its own colour and cannot
#      touch the pen; the check stays because it once could. COLOR takes
#      either one PACKED value (RGB(), or a POINT round-trip) or three
#      numbers R,G,B -- part 1 uses BOTH forms on purpose, and LIST must
#      round-trip the three-number one.
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
python3 "$ROOT/assembler/p8xasm.py" "$ROOT/os/p8xos.asm" -o bgfx_os.bin --base 0x2000 >/dev/null \
    || fail "the OS did not assemble"
python3 "$ROOT/tools/p8xfs.py" boot bgfx.img bgfx_os.bin >/dev/null \
    || fail "could not install the fresh OS (part 4 needs its boot font load)"
python3 "$ROOT/tools/p8xfs.py" put bgfx.img bgfx.bin --name /bin/bgfx.bin \
    --load 0x6A00 --exec 0x6A00 >/dev/null || fail "could not install the test BASIC"

# COLOR RGB(0,63,0) then CLS: if CLS clobbered the pen, the filled box would
# come out black and vanish. The NOFILL box is checked in its middle; the LINE
# at its ends. Colours go through RGB(), which also proves BASIC hands all 16
# pen bits to GCOL+GCOLH -- an interpreter that dropped the high byte draws
# these primaries as near-black and fails every pixel check.
printf 'B\rbgfx\r10 COLOR 0,63,0\r20 CLS\r30 BOX 20,20,120,120,FILL\r40 COLOR RGB(31,0,0)\r50 BOX 200,20,300,120,NOFILL\r60 COLOR 0,0,31\r70 LINE 20,240,458,240\r80 END\rRUN\rLIST\rFILL\rBYE\r' \
    > bgfx.in
../p8xemu -N -i bgfx.in -c bgfx.img -l 120000000 -g bgfx.ppm eeprom.bin > bgfx.out 2>/dev/null || true

python3 - <<'PY' || exit 1
import sys
bad = []
out = open("bgfx.out","rb").read().replace(b"\r", b"")

# 4. LIST round-trips every new keyword
for kw in [b"10 COLOR 0,63,0", b"20 CLS", b"30 BOX 20,20,120,120,FILL",
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
NAME = {BLACK:"$0000", RED:"$F800 red", GREEN:"$07E0 green", BLUE:"$001F blue"}
def fb(x, y):
    i = (y*W + x)*3
    return tuple(px[i:i+3])
def want(x, y, c, why):
    got = fb(x,y)
    if got != c:
        bad.append("(%d,%d) is %s, want %s - %s"
                   % (x, y, NAME.get(got,got), NAME.get(c,c), why))

# window (x,wy) -> screen (x, 271-wy): the statements draw y-UP now
# 2. CLS cleared to background, and did NOT eat COLOR
want(  0,   0, BLACK, "CLS did not clear to the background")
want( 70, 201, GREEN, "CLS clobbered the current COLOR")
# 1. BOX ,FILL is solid; BOX ,NOFILL is an outline
want( 20, 251, GREEN, "filled BOX corner missing")
want(120, 151, GREEN, "filled BOX corner missing")
want(200, 251, RED,   "NOFILL BOX edge missing")
want(300, 151, RED,   "NOFILL BOX edge missing")
want(250, 201, BLACK, "NOFILL drew a SOLID box - FILL was matched inside NOFILL")
# 3. LINE endpoints are inclusive (window y 240 = screen row 31)
want( 20,  31, BLUE, "LINE start point not drawn")
want(458,  31, BLUE, "LINE end point not drawn (exclusive end?)")
want(240,  31, BLUE, "LINE middle missing")

if bad:
    print("BASIC-GFX TEST: FAIL")
    for b in bad: print("  " + b)
    sys.exit(1)
print("BASIC-GFX TEST: draw statements ok")
PY

# --- part 2: PIXELW / CIRCLE / RGB / POINT ------------------------------------
# PALETTE is gone with the palette; what this part pins instead is the 16-bit
# colour path end to end: RGB() packs, the pen carries all 16 bits, and POINT
# hands them back THROUGH BASIC'S SIGNED INTEGERS -- $F81F magenta prints as
# -2017, which is the documented wart (STAGE6-DESIGN.md), asserted here so it
# stays a wart and not a surprise.
printf 'B\rbgfx\r10 CLS\r20 COLOR RGB(31,0,0)\r40 BOX 10,10,80,80,FILL\r50 COLOR RGB(31,0,31)\r60 CIRCLE 240,136,100,FILL\r70 COLOR RGB(0,63,0)\r80 CIRCLE 240,136,120\r90 PIXELW 400,40\r100 PRINT PIXELR(240,136)\r110 PRINT PIXELR(400,40)\r120 PRINT PIXELR(0,271)\r130 PRINT PIXELR(14,14)\r140 END\rRUN\rLIST\rBYE\r' \
    > bgfx2.in
../p8xemu -N -i bgfx2.in -c bgfx.img -l 120000000 -g bgfx2.ppm eeprom.bin > bgfx2.out 2>/dev/null || true

python3 - <<'PY' || exit 1
import sys
bad = []
out = open("bgfx2.out","rb").read().replace(b"\r", b"")

# PIXELR reads back the 565 colour through SIGNED 16-bit ints, in the
# SAME window coordinates the drawing used (the flip is BASIC's now):
#   $F81F magenta = -2017, $07E0 green = 2016, 0 = untouched, $F800 red = -2048.
# The negative prints are the high pen byte coming home -- the read-back half
# of 16 bpp -- wearing the signed-integer wart on purpose.
if b"\n-2017\n2016\n0\n-2048\n" not in out:
    bad.append("PIXELR sequence wrong; wanted -2017,2016,0,-2048 in %r"
               % out[out.find(b"RUN"):out.find(b"RUN")+48])

for kw in [b"20 COLOR RGB(31,0,0)", b"60 CIRCLE 240,136,100,FILL",
           b"80 CIRCLE 240,136,120", b"90 PIXELW 400,40", b"100 PRINT PIXELR(240,136)"]:
    if out.count(kw) < 2:
        bad.append("LIST did not round-trip %r" % kw.decode())

d  = open("bgfx2.ppm","rb").read()
px = d[d.index(b"255\n")+4:]
W  = 480
BLACK, RED, GREEN, MAGENTA = (0,0,0), (255,0,0), (0,255,0), (255,0,255)
NAME = {BLACK:"$0000", RED:"$F800 red", GREEN:"$07E0 green",
        MAGENTA:"$F81F magenta"}
def fb(x, y):
    i = (y*W + x)*3
    return tuple(px[i:i+3])
def want(x, y, c, why):
    got = fb(x,y)
    if got != c:
        bad.append("(%d,%d) is %s, want %s - %s"
                   % (x, y, NAME.get(got,got), NAME.get(c,c), why))

# the box drew in red (window y 10..80 = screen 191..261) and the filled
# circle in RGB(31,0,31) magenta -- both halves of both pens intact
want( 14, 257, RED,     "the box lost its red (high pen byte dropped?)")
want(240, 135, MAGENTA, "filled CIRCLE is not magenta")
# CIRCLE ,FILL is solid; the bare CIRCLE is an outline with a gap inside it
want(240, 235, MAGENTA, "filled CIRCLE does not reach its screen-bottom edge")
want(240,  15, GREEN,   "outline CIRCLE top not drawn")
want(240,  26, BLACK,   "gap between the two circles is filled - CIRCLE drew solid")
# PIXELW put a single pixel down (window (400,40) = screen (400,231))
want(400, 231, GREEN,   "PIXELW did not draw")
want(404, 231, BLACK,   "PIXELW drew more than one pixel")

if bad:
    print("BASIC-GFX TEST: FAIL")
    for b in bad: print("  " + b)
    sys.exit(1)
print("BASIC-GFX TEST: draw, plot, circle, rgb, point ok")
PY

# --- part 3: CIRCLE's optional second radius makes it an ellipse ------------
# The parser has to tell a second radius from the FILL modifier by TOKEN: a
# keyword is >= $80, anything else starts an expression. That is also why NOFILL
# must be a real keyword -- otherwise `CIRCLE x,y,r,NOFILL` would try to EVAL it.
printf 'B\rbgfx\r10 CLS\r20 COLOR 1\r30 CIRCLE 60,68,30\r40 COLOR 2\r50 CIRCLE 170,68,60,20\r60 COLOR 3\r70 CIRCLE 170,110,15,20,FILL\r80 PRINT "A";PIXELR(90,68);PIXELR(60,68);PIXELR(230,68);PIXELR(10,130);PIXELR(170,110)\r90 END\rRUN\rBYE\r' \
    > bgfx3.in
../p8xemu -N -i bgfx3.in -c bgfx.img -l 120000000 eeprom.bin > bgfx3.out 2>/dev/null || true

python3 - <<'PY' || exit 1
import sys
out = open("bgfx3.out","rb").read().replace(b"\r", b"")
# PIXELR probes (SCREEN rows; the shapes drew in window space, so each
# window row wy reads at screen 271-wy), in order:
#   (90,203)  right edge of the pen-1 circle r=30 about window (60,68) -> 1
#   (60,203)  its centre, an outline, so background                    -> 0
#   (230,203) right edge of the pen-2 ellipse rx=60, window (170,68)   -> 2
#   (10,130)  far from every shape                                     -> 0
#   (170,161) centre of the pen-3 FILLED ellipse, window (170,110)     -> 3
want = b"A10200" if False else b"A1"
i = out.find(b"\nA")
got = out[i+1:i+7] if i >= 0 else b"?"
if got != b"A10203":
    print("BASIC-GFX TEST: FAIL - ellipse probes are %r, want b'A10203'" % got)
    print("  (circle edge, circle centre, ellipse edge, gap, filled-ellipse centre)")
    sys.exit(1)
print("BASIC-GFX TEST: ellipse ok")
PY

# --- part 4: text is PGC TEXT with the boot-loaded font --------------------
# GTEXT died 2026-09-01 (the single-interface migration): the OS streams
# /FONT.GL to the card at boot (bgfx.img is a run-disk copy, so it HAS the
# font), BASIC cold-starts with PROJCT 0 (text strokes live at z=0, which
# the native camera near-clips), and the idiom is MOVE3 x,y,0 : TEXT s$.
# Checked: strokes actually land (out-of-the-box, no manual font load);
# lowercase folds to the SAME cell as uppercase (ink-for-ink); TSIZE 512
# doubles the glyph's rise; a string off the right edge clips, not wraps;
# TEXT "" is legal and draws nothing; and a typed GTEXT line is rejected
# AT ENTRY (the retired token no longer dispatches, like PALETTE).
printf 'B\rbgfx\r10 CLS\r20 COLOR RGB(31,0,0)\r30 MOVE3 10,10,0 : TEXT "A"\r40 COLOR RGB(0,63,0)\r50 MOVE3 40,10,0 : TEXT "a"\r60 COLOR RGB(0,0,31)\r70 TSIZE 512\r80 MOVE3 30,20,0 : TEXT "A"\r90 TSIZE 256\r100 COLOR RGB(31,0,0)\r110 MOVE3 470,80,0 : TEXT "WW"\r120 MOVE3 5,110,0 : TEXT ""\r130 END\rRUN\rLIST\rGTEXT 1,1,1,"X"\rBYE\r' \
    > bgfx4.in
../p8xemu -N -i bgfx4.in -c bgfx.img -l 400000000 -g bgfx4.ppm eeprom.bin > bgfx4.out 2>/dev/null || true

python3 - <<'PY' || exit 1
import sys
bad = []
out = open("bgfx4.out","rb").read().replace(b"\r", b"")
d  = open("bgfx4.ppm","rb").read()
px = d[d.index(b"255\n")+4:]
W  = 480
BLACK = (0,0,0)
def fb(x, y):
    i = (y*W + x)*3
    return tuple(px[i:i+3])
def ink(x, wy):                       # window coords, any colour
    return fb(x, 271-wy) != BLACK
def cell(x0, wy0, w=6, h=8):
    return [(i,j) for i in range(w) for j in range(h) if ink(x0+i, wy0+j)]

# the 1x 'A' drew, inside its cell, nothing under the baseline or above cap
a = cell(10, 10)
if len(a) < 5: bad.append("1x TEXT 'A' drew %d px - font not loaded at boot?" % len(a))
for x in range(8, 18):
    if ink(x, 8):  bad.append("ink under the baseline at x=%d" % x); break
# lowercase folds: the SAME ink pattern, cell for cell
if cell(40, 10) != a:
    bad.append("'a' did not fold onto the 'A' glyph (cells differ)")
# TSIZE 512 doubles the rise -- AND the anchor: TSIZE scales the whole
# model transform (the documented PGC divergence), so MODEL (30,20)
# lands at screen (60,40)
big = cell(59, 38, 18, 20)
if len(big) <= len(a): bad.append("TSIZE 512 'A' no bigger than 1x (%d vs %d px)" % (len(big), len(a)))
if not any(j > 10 for (i,j) in big):
    bad.append("TSIZE 512 'A' never rises past the 1x cap - TSIZE ignored")
# clipping: nothing wrapped to the left edge rows
for wy in range(78, 90):
    for x in range(0, 12):
        if ink(x, wy):
            bad.append("(%d,wy%d) lit - TEXT wrapped past the right edge" % (x,wy)); break
# "" drew nothing
for wy in range(108, 120):
    for x in range(4, 24):
        if ink(x, wy):
            bad.append('TEXT "" drew at (%d,wy%d)' % (x,wy)); break

# LIST round-trips the TEXT lines; the dead GTEXT token is rejected at entry
for kw in [b'30 MOVE3 10,10,0 : TEXT "A"', b'70 TSIZE 512', b'120 MOVE3 5,110,0 : TEXT ""']:
    if out.count(kw) < 2:
        bad.append("LIST did not round-trip %r" % kw.decode())
if b"?SYNTAX ERROR" not in out.split(b"130 END")[-1]:
    bad.append("immediate GTEXT was ACCEPTED - the dead token still dispatches")

if bad:
    print("BASIC-GFX TEST: FAIL")
    for b in bad[:12]: print("  " + b)
    sys.exit(1)
print("BASIC-GFX TEST: text ok (boot font, fold, TSIZE, clip, empty, GTEXT dead)")
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
#   2. the colour survives the framebuffer round trip -- 5 and 200 are dim
#      blues now rather than pens, but the identity check is the same.
printf 'B\rbgfx\r10 CLS\r20 COLOR 5\r30 BOX 0,0,479,271,FILL\r40 COLOR 200\r50 PIXELW 400,250\r60 PRINT "A";PIXELR(479,271);",";PIXELR(400,250);",";PIXELR(480,0)\r70 END\rRUN\rLIST\rBYE\r' \
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
for kw in [b"30 BOX 0,0,479,271,FILL", b"50 PIXELW 400,250"]:
    if out.count(kw) < 2:
        bad.append("LIST did not round-trip %r" % kw.decode())
if bad:
    print("BASIC-GFX TEST: FAIL")
    for b in bad: print("  " + b)
    sys.exit(1)
print("BASIC-GFX TEST: full screen ok (479,271 reachable, colours survive)")
PY

# --- part 6: IMAGE x,y,name$ -- the P8I loader ------------------------------
# What can break, each checked: the header must be VALIDATED (a text file or
# a truncated file says ?NOT P8I, a missing one ?No file); the pixels must
# land at (x,y) with nothing outside the image's rectangle touched; both
# colour bytes must arrive (the values are chosen to exercise the high byte);
# and an image at the screen edge must CLIP, not wrap or error.
python3 - <<'MKPIC'
import struct
w, h = 8, 5
px = [0x1111 * ((y*w + x) % 15 + 1) & 0xFFFF for y in range(h) for x in range(w)]
px[0] = 0xF800; px[w-1] = 0x07E0; px[(h-1)*w] = 0x001F; px[-1] = 0xFFFF
open("pic.p8i","wb").write(b"P8I" + bytes((1,)) + struct.pack("<HH", w, h)
                           + bytes((16, 0)) + struct.pack("<%dH" % len(px), *px))
open("junk.bin","wb").write(b"NOT AN IMAGE AT ALL, JUST BYTES")
MKPIC
python3 "$ROOT/tools/p8xfs.py" put bgfx.img pic.p8i  --name /PIC.P8I  >/dev/null
python3 "$ROOT/tools/p8xfs.py" put bgfx.img junk.bin --name /JUNK.BIN >/dev/null

printf 'B\rbgfx\r10 CLS\r20 IMAGE 100,217,"/PIC.P8I"\r30 IMAGE 476,-2,"/PIC.P8I"\r40 IMAGE 0,0,"/JUNK.BIN"\r50 IMAGE 0,0,"/NOPE"\r60 END\rRUN\rLIST\rBYE\r' \
    > bgfx8.in
../p8xemu -N -i bgfx8.in -c bgfx.img -l 200000000 -g bgfx8.ppm eeprom.bin > bgfx8.out 2>/dev/null || true

python3 - <<'PY' || exit 1
import sys
bad = []
out = open("bgfx8.out","rb").read().replace(b"\r", b"")
if b"?NOT P8I" not in out:
    bad.append("a non-P8I file was accepted (no ?NOT P8I)")
if b"?No file" not in out:
    bad.append("a missing file did not say ?No file")
for kw in [b'20 IMAGE 100,217,"/PIC.P8I"', b'30 IMAGE 476,-2,"/PIC.P8I"']:
    if out.count(kw) < 2:
        bad.append("LIST did not round-trip %r" % kw.decode())

d  = open("bgfx8.ppm","rb").read()
px = d[d.index(b"255\n")+4:]
W  = 480
def fb(x, y):
    i = (y*W + x)*3
    return tuple(px[i:i+3])
def x888(p):                       # the emulator's exact 565->888 expansion
    r5,g6,b5 = (p>>11)&31, (p>>5)&63, p&31
    return ((r5<<3)|(r5>>2), (g6<<2)|(g6>>4), (b5<<3)|(b5>>2))
def want(x, y, p, why):
    if fb(x,y) != x888(p):
        bad.append("(%d,%d) is %s, want %s - %s" % (x, y, fb(x,y), x888(p), why))

# the image landed at (100,50), corners exact, both colour bytes intact
want(100, 50, 0xF800, "image top-left corner (its red marker)")
want(107, 50, 0x07E0, "image top-right corner")
want(100, 54, 0x001F, "image bottom-left corner")
want(107, 54, 0xFFFF, "image bottom-right corner")
want(103, 52, 0x1111*((2*8+3)%15+1) & 0xFFFF, "an interior pixel")
# nothing outside the rectangle was touched
want( 99, 50, 0x0000, "left of the image was painted")
want(100, 49, 0x0000, "above the image was painted")
want(108, 54, 0x0000, "right of the image was painted")
want(107, 55, 0x0000, "below the image was painted")
# the edge draw clipped: on-screen part present, nothing wrapped to (0,271)
want(476, 269, 0xF800, "clipped image lost its on-screen corner")
want(479, 269, 0x1111*4 & 0xFFFF, "clipped image wrong at the screen edge")
for x in range(1, 6):
    want(x, 270, 0x0000, "clipped image wrapped onto the left edge")

if bad:
    print("BASIC-GFX TEST: FAIL")
    for b in bad: print("  " + b)
    sys.exit(1)
print("BASIC-GFX TEST: image ok (placement, colours, header rejects, clipping)")
PY

echo "BASIC-GFX TEST: PASS (draw, pixelw, circle, ellipse, rgb, pixelr, text, full screen, image)"
