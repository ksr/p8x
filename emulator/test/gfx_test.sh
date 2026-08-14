#!/bin/sh
# The $FF20 graphics display model draws what it is told.
#
# p8xemu is the golden model for the FPGA, so this file pins down the exact
# behaviour the Verilog engine will have to reproduce. Every assertion below is
# a decision someone could plausibly implement the other way round:
#
#   1. endpoints are INCLUSIVE — a full-screen box paints x=0, x=239, y=0, y=135.
#      An exclusive-end loop still looks fine everywhere except those four lines.
#   2. off-screen pixels are DISCARDED, not clipped and not wrapped. Coordinates
#      hold far more than the screen is wide, so x>=240 is reachable, and
#      off = y*60 + (x>>2) folds those
#      straight onto the START OF THE NEXT ROW. This is the whole reason gpu_px
#      bounds-checks instead of masking.
#   3. BOX is an outline and BOXFILL is solid — checked on a box whose interior
#      nothing else touches.
#   4. SETPAL recolours the pen named by GCOL, and takes effect for later drawing.
#   5. drawing order is last-writer-wins (the pen-2 diagonal overpaints the pen-1
#      border at the origin).
#
# It renders to a PPM and inspects pixels rather than diffing a golden image: a
# byte-diff would fail on any harmless change and tell you nothing about which
# rule broke.
set -e
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$(dirname "$0")"
fail() { echo "GFX TEST: FAIL — $1"; exit 1; }

python3 "$ROOT/assembler/p8xasm.py" test_gfx.asm -o gfx.bin >/dev/null \
    || fail "test_gfx.asm did not assemble"

../p8xemu -l 200000 -g gfx.ppm gfx.bin >/dev/null 2>&1 || true
[ -f gfx.ppm ] || fail "no PPM written (is -g wired up?)"

python3 - <<'PY' || exit 1
import sys
d = open("gfx.ppm","rb").read()
if not d.startswith(b"P6\n480 272\n255\n"):
    print("GFX TEST: FAIL — wrong PPM header: %r" % d[:20]); sys.exit(1)
px = d[len(b"P6\n480 272\n255\n"):]
W, H = 480, 272
if len(px) != W*H*3:
    print("GFX TEST: FAIL — %d payload bytes, expected %d" % (len(px), W*H*3)); sys.exit(1)

BLACK, WHITE, RED, YELLOW = (0,0,0), (255,255,255), (255,0,0), (255,255,0)
NAMES = {BLACK:"pen0 black", WHITE:"pen1 white", RED:"pen2 red", YELLOW:"pen3 yellow"}

def fb(x, y):                       # framebuffer pixel -> its 2x2 block's top-left
    i = ((y*2*W) + x*2)*3
    return tuple(px[i:i+3])

bad = []
def want(x, y, c, why):
    got = fb(x, y)
    if got != c:
        bad.append("(%d,%d) is %s, want %s — %s"
                   % (x, y, NAMES.get(got, str(got)), NAMES.get(c, str(c)), why))

# 1. inclusive endpoints: all four extreme edges of the full-screen box
want(120,   0, WHITE, "top edge y=0 not drawn")
want(120, 135, WHITE, "bottom edge y=135 not drawn (exclusive end?)")
want(  0,  68, WHITE, "left edge x=0 not drawn")
want(239,  68, WHITE, "right edge x=239 not drawn (exclusive end?)")

# 5. last writer wins: the pen-2 diagonal starts on the pen-1 border corner
want(  0,   0, RED, "diagonal did not overpaint the border at the origin")

# 4. SETPAL: pen 3 was recoloured to yellow BEFORE the fill used it
want(120,  68, YELLOW, "BOXFILL interior is not the SETPAL yellow")

# BOXFILL covers its corners exactly, and stops one pixel later
want( 90,  50, YELLOW, "BOXFILL top-left corner missing")
want(150,  86, YELLOW, "BOXFILL bottom-right corner missing")
want(151,  86, BLACK,  "BOXFILL ran past x1")
want(150,  87, BLACK,  "BOXFILL ran past y1")

# 3. BOX is hollow: edges painted, interior untouched
want( 80, 112, RED,   "outline BOX left edge missing")
want(140, 112, RED,   "outline BOX right edge missing")
want(110, 100, RED,   "outline BOX top edge missing")
want(110, 124, RED,   "outline BOX bottom edge missing")
want(110, 112, BLACK, "outline BOX interior is filled — BOX behaved like BOXFILL")

# 2. off-screen discard. The clipped line runs (200,120)-(255,120): it must be
# drawn through x=239 and must not fold onto row 121.
want(239, 120, WHITE, "clipped line stopped early — it should draw up to x=239")
for x in range(1, 8):               # x=0 is the legitimate left border
    want(x, 121, BLACK, "pixel wrapped onto the next row — x>=240 was not discarded")

if bad:
    print("GFX TEST: FAIL")
    for b in bad: print("  " + b)
    sys.exit(1)
print("GFX TEST: draw primitives ok (%d pixel assertions)" % 21)
PY

# --- part 2: identify / diagnostics / 16-bit coordinates -------------------
# What a bus CARD needs that an on-die device does not: proving it is present,
# reporting its geometry, and drawing with no software behind it.
python3 "$ROOT/assembler/p8xasm.py" test_gfx2.asm -o gfx2.bin >/dev/null \
    || fail "test_gfx2.asm did not assemble"
../p8xemu -l 200000 -g gfx2.ppm gfx2.bin > gfx2.out 2>/dev/null || true

python3 - <<'PY' || exit 1
import sys
bad = []

# The IDENT record and the presence signature, echoed to the console by the ROM.
got  = open("gfx2.out","rb").read()
want = b"P8X-GFX" + bytes([1, 240,0, 136,0, 4, 0]) + b"PG"
if got != want:
    bad.append("IDENT/signature stream is %r, want %r" % (got, want))

d  = open("gfx2.ppm","rb").read()
px = d[d.index(b"255\n")+4:]
W  = 480
BLACK, RED = (0,0,0), (255,0,0)
def fb(x, y):
    i = ((y*2*W) + x*2)*3
    return tuple(px[i:i+3])
def want_px(x, y, c, why):
    got = fb(x,y)
    if got != c: bad.append("(%d,%d) is %s, want %s - %s" % (x, y, got, c, why))

# CIRCLE centred (120,68) r=40: the four axis points the midpoint algorithm must
# hit exactly, and a hollow middle.
want_px(160,  68, RED,   "circle right axis point missing")
want_px( 80,  68, RED,   "circle left axis point missing")
want_px(120, 108, RED,   "circle bottom axis point missing")
want_px(120,  28, RED,   "circle top axis point missing")
want_px(120,  68, BLACK, "CIRCLE filled its interior - it is the outline command")

# 16-bit coordinates. Case 1 wrote GX0=100 then GX0H=1, so x=356 is off-screen;
# if the high byte were ignored the pixel would land exactly here.
want_px(100, 60, BLACK, "high coordinate byte ignored - pixel landed at x=100")
# Case 2 wrote GX0H=1 and then GX0=100: the low write must CLEAR the high byte.
want_px(100, 70, RED,   "a low-byte write did not clear the high byte (stale x=356)")

if bad:
    print("GFX TEST: FAIL")
    for b in bad: print("  " + b)
    sys.exit(1)
print("GFX TEST: PASS (drawing, identify, diagnostics, 16-bit coords)")
PY
