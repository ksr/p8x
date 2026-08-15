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

# COLOR 3 then CLS: if CLS clobbered the pen, the filled box would come out pen 0
# and vanish. The NOFILL box is checked in its middle; the LINE at its ends.
printf 'B\rbgfx\r10 COLOR 3\r20 CLS\r30 BOX 10,10,60,60,FILL\r40 COLOR 1\r50 BOX 100,10,150,60,NOFILL\r60 COLOR 2\r70 LINE 10,120,229,120\r80 END\rRUN\rLIST\rFILL\rBYE\r' \
    > bgfx.in
../p8xemu -N -i bgfx.in -c bgfx.img -l 120000000 -g bgfx.ppm eeprom.bin > bgfx.out 2>/dev/null || true

python3 - <<'PY' || exit 1
import sys
bad = []
out = open("bgfx.out","rb").read().replace(b"\r", b"")

# 4. LIST round-trips every new keyword
for kw in [b"10 COLOR 3", b"20 CLS", b"30 BOX 10,10,60,60,FILL",
           b"50 BOX 100,10,150,60,NOFILL", b"70 LINE 10,120,229,120"]:
    if out.count(kw) < 2:            # once as typed, once from LIST
        bad.append("LIST did not round-trip %r" % kw.decode())

# 5. a bare FILL is not a statement
if b"?SYNTAX ERROR" not in out:
    bad.append("a bare FILL line was accepted - CKLEAD is not rejecting the modifier")

d  = open("bgfx.ppm","rb").read()
px = d[d.index(b"255\n")+4:]
W  = 480
BLACK, WHITE, RED, GREEN = (0,0,0), (255,255,255), (255,0,0), (0,255,0)
NAME = {BLACK:"pen0", WHITE:"pen1", RED:"pen2", GREEN:"pen3"}
def fb(x, y):
    i = ((y*2*W) + x*2)*3
    return tuple(px[i:i+3])
def want(x, y, c, why):
    got = fb(x,y)
    if got != c:
        bad.append("(%d,%d) is %s, want %s - %s"
                   % (x, y, NAME.get(got,got), NAME.get(c,c), why))

# 2. CLS cleared to background, and did NOT eat COLOR 3
want(  0,   0, BLACK, "CLS did not clear to the background")
want( 35,  35, GREEN, "CLS clobbered the current COLOR (GPEN shadow not restored)")
# 1. BOX ,FILL is solid; BOX ,NOFILL is an outline
want( 10,  10, GREEN, "filled BOX corner missing")
want( 60,  60, GREEN, "filled BOX corner missing")
want(100,  10, WHITE, "NOFILL BOX edge missing")
want(150,  60, WHITE, "NOFILL BOX edge missing")
want(125,  35, BLACK, "NOFILL drew a SOLID box - FILL was matched inside NOFILL")
# 3. LINE endpoints are inclusive
want( 10, 120, RED, "LINE start point not drawn")
want(229, 120, RED, "LINE end point not drawn (exclusive end?)")
want(120, 120, RED, "LINE middle missing")

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
printf 'B\rbgfx\r10 CLS\r20 COLOR 2\r30 PALETTE 3,15,0,15\r40 BOX 5,5,40,40,FILL\r50 COLOR 3\r60 CIRCLE 120,68,50,FILL\r70 COLOR 1\r80 CIRCLE 120,68,60\r90 PLOT 200,20\r100 PRINT POINT(120,68)\r110 PRINT POINT(200,20)\r120 PRINT POINT(0,135)\r130 PRINT POINT(7,7)\r140 END\rRUN\rLIST\rBYE\r' \
    > bgfx2.in
../p8xemu -N -i bgfx2.in -c bgfx.img -l 120000000 -g bgfx2.ppm eeprom.bin > bgfx2.out 2>/dev/null || true

python3 - <<'PY' || exit 1
import sys
bad = []
out = open("bgfx2.out","rb").read().replace(b"\r", b"")

# POINT reads back what was drawn. 3 = filled circle, 1 = the plotted pixel,
# 0 = untouched corner, 2 = inside the box drawn AFTER PALETTE.
if b"\n3\n1\n0\n2\n" not in out:
    bad.append("POINT sequence wrong; wanted 3,1,0,2 in %r"
               % out[out.find(b"RUN"):out.find(b"RUN")+40])

for kw in [b"30 PALETTE 3,15,0,15", b"60 CIRCLE 120,68,50,FILL",
           b"80 CIRCLE 120,68,60", b"90 PLOT 200,20", b"100 PRINT POINT(120,68)"]:
    if out.count(kw) < 2:
        bad.append("LIST did not round-trip %r" % kw.decode())

d  = open("bgfx2.ppm","rb").read()
px = d[d.index(b"255\n")+4:]
W  = 480
BLACK, WHITE, RED, MAGENTA = (0,0,0), (255,255,255), (255,0,0), (255,0,255)
NAME = {BLACK:"pen0", WHITE:"pen1", RED:"pen2", MAGENTA:"pen3=magenta"}
def fb(x, y):
    i = ((y*2*W) + x*2)*3
    return tuple(px[i:i+3])
def want(x, y, c, why):
    got = fb(x,y)
    if got != c:
        bad.append("(%d,%d) is %s, want %s - %s"
                   % (x, y, NAME.get(got,got), NAME.get(c,c), why))

# PALETTE recoloured pen 3 to magenta, and did NOT steal the drawing pen:
# the box on line 40 must still be pen 2 (red), not pen 3.
want(  7,   7, RED,     "PALETTE stole the drawing pen (GPEN not restored)")
want(120,  68, MAGENTA, "PALETTE did not recolour pen 3")
# CIRCLE ,FILL is solid; the bare CIRCLE is an outline with a gap inside it
want(120, 118, MAGENTA, "filled CIRCLE does not reach its bottom edge")
want(120,   8, WHITE,   "outline CIRCLE top not drawn")
want(120,  13, BLACK,   "gap between the two circles is filled - CIRCLE drew solid")
# PLOT put a single pixel down
want(200,  20, WHITE,   "PLOT did not draw")
want(202,  20, BLACK,   "PLOT drew more than one pixel")

if bad:
    print("BASIC-GFX TEST: FAIL")
    for b in bad: print("  " + b)
    sys.exit(1)
print("BASIC-GFX TEST: PASS (draw, plot, circle, palette, point)")
PY
