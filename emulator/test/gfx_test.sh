#!/bin/sh
# The $FF20 graphics display model draws what it is told.
#
# p8xemu is the golden model for the FPGA, so this file pins down the exact
# behaviour the Verilog engine will have to reproduce. Every assertion below is
# a decision someone could plausibly implement the other way round:
#
#   1. endpoints are INCLUSIVE — a full-screen box paints x=0, x=479, y=0, y=271.
#      An exclusive-end loop still looks fine everywhere except those four lines.
#   2. off-screen pixels are DISCARDED, not clipped and not wrapped. Coordinates
#      hold far more than the screen is wide, so x>=480 is reachable, and
#      off = y*480 + x folds those
#      straight onto the START OF THE NEXT ROW. This is the whole reason gpu_px
#      bounds-checks instead of masking.
#   3. BOX is an outline and BOXFILL is solid — checked on a box whose interior
#      nothing else touches.
#   4. SETPAL recolours the pen named by GCOL, and takes effect for later drawing.
#   5. drawing order is last-writer-wins (the green diagonal overpaints the red
#      border at the origin).
#   6. a pen is a whole BYTE. The payload draws in $E0/$1C/$03/$FF rather than
#      1/2/3, so an engine that only carried the low bits of the pen — which is
#      what a 2 bpp design left behind would look like — fails here instead of
#      passing with plausible colours.
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

# The default palette is the 3-3-2 ramp expanded to RGB444 then to 8 bits, so
# these four pens are the unambiguous primaries. YELLOW is not from the ramp:
# it is what SETPAL wrote over pen $FF (which is white by default).
BLACK, RED, GREEN, BLUE = (0,0,0), (255,0,0), (0,255,0), (0,0,255)
YELLOW = (255,255,0)
NAMES = {BLACK:"pen $00 black", RED:"pen $E0 red", GREEN:"pen $1C green",
         BLUE:"pen $03 blue", YELLOW:"pen $FF, SETPAL'd yellow",
         (255,255,255):"pen $FF, still the DEFAULT white — SETPAL did not take"}

def fb(x, y):                       # the framebuffer IS the panel now: 1:1
    i = (y*W + x)*3
    return tuple(px[i:i+3])

bad = []
def want(x, y, c, why):
    got = fb(x, y)
    if got != c:
        bad.append("(%d,%d) is %s, want %s — %s"
                   % (x, y, NAMES.get(got, str(got)), NAMES.get(c, str(c)), why))

# 1. inclusive endpoints: all four extreme edges of the full-screen box
want(240,   0, RED, "top edge y=0 not drawn")
want(240, 271, RED, "bottom edge y=271 not drawn (exclusive end?)")
want(  0, 136, RED, "left edge x=0 not drawn")
want(479, 136, RED, "right edge x=479 not drawn (exclusive end?)")

# 5. last writer wins: the green diagonal starts on the red border corner
want(  0,   0, GREEN, "diagonal did not overpaint the border at the origin")

# 4. SETPAL: pen $FF was recoloured to yellow BEFORE the fill used it
want(240, 136, YELLOW, "BOXFILL interior is not the SETPAL yellow")

# BOXFILL covers its corners exactly, and stops one pixel later
want(180, 100, YELLOW, "BOXFILL top-left corner missing")
want(300, 172, YELLOW, "BOXFILL bottom-right corner missing")
want(301, 172, BLACK,  "BOXFILL ran past x1")
want(300, 173, BLACK,  "BOXFILL ran past y1")

# 3. BOX is hollow: edges painted, interior untouched
want(160, 224, GREEN, "outline BOX left edge missing")
want(280, 224, GREEN, "outline BOX right edge missing")
want(220, 200, GREEN, "outline BOX top edge missing")
want(220, 248, GREEN, "outline BOX bottom edge missing")
want(220, 224, BLACK, "outline BOX interior is filled — BOX behaved like BOXFILL")

# 2. off-screen discard. The clipped line runs (400,240)-(510,240): it must be
# drawn through x=479 and must not fold onto row 241.
want(479, 240, BLUE, "clipped line stopped early — it should draw up to x=479")
for x in range(1, 8):               # x=0 is the legitimate left border
    want(x, 241, BLACK, "pixel wrapped onto the next row — x>=480 was not discarded")

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
# Geometry is little-endian: 480 = e0 01, 272 = 10 01. The pen count is 256,
# which wraps a byte to 0 -- that is the record saying "8 bpp", and it is the
# one field a reader must not treat as "no pens".
got  = open("gfx2.out","rb").read()
want = b"P8X-GFX" + bytes([1, 224,1, 16,1, 0, 0]) + b"PG"
if got != want:
    bad.append("IDENT/signature stream is %r, want %r" % (got, want))

d  = open("gfx2.ppm","rb").read()
px = d[d.index(b"255\n")+4:]
W  = 480
BLACK, RED = (0,0,0), (255,0,0)
def fb(x, y):
    i = (y*W + x)*3
    return tuple(px[i:i+3])
def want_px(x, y, c, why):
    got = fb(x,y)
    if got != c: bad.append("(%d,%d) is %s, want %s - %s" % (x, y, got, c, why))

# CIRCLE centred (240,136) r=80: the four axis points the midpoint algorithm
# must hit exactly, and a hollow middle.
want_px(320, 136, RED,   "circle right axis point missing")
want_px(160, 136, RED,   "circle left axis point missing")
want_px(240, 216, RED,   "circle bottom axis point missing")
want_px(240,  56, RED,   "circle top axis point missing")
want_px(240, 136, BLACK, "CIRCLE filled its interior - it is the outline command")

# 16-bit coordinates. Case 1 wrote GX0=100 then GX0H=2, so x=612 is off-screen;
# if the high byte were ignored the pixel would land exactly here.
want_px(100, 60, BLACK, "high coordinate byte ignored - pixel landed at x=100")
# Case 2 wrote GX0H=2 and then GX0=100: the low write must CLEAR the high byte.
want_px(100, 70, RED,   "a low-byte write did not clear the high byte (stale x=612)")

if bad:
    print("GFX TEST: FAIL")
    for b in bad: print("  " + b)
    sys.exit(1)
print("GFX TEST: PASS (drawing, identify, diagnostics, 16-bit coords)")
PY
