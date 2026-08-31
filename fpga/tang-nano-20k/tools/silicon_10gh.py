#!/usr/bin/env python3
"""Silicon check for stages 10g (AREA) + 10h (TEXT) over the card bridge.

Drives the flashed card exactly as the benches drove the RTL: the AREA
scene from c_gl_area_test, then os/font.gl + the gl_tx.gl TEXT scene,
with device PIXELR read-backs at the emulator's golden pixels.
"""
import sys, os, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from glbridge import Bridge, SerialXport

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))
FAILS = 0

def ok(cond, what, got=None):
    global FAILS
    if cond:
        print("  ok  %s" % what)
    else:
        FAILS += 1
        print("  FAIL %s (got %s)" % (what, got))

def wp(b, x, wy):
    """Probe by WINDOW coords (identity map, y flip) -- glbridge's
    canonical PIXELR helper does the device read."""
    return b.pixelr(x, 271 - wy)

b = Bridge(SerialXport())
b.resync()
v = b.ping()
print("card protocol v%d, identity %s" % (v, b.probe()))
b.drain_errors()

# ---- 10g: the AREA scene (c_gl_area_test's shapes) ----------------------
print("10g AREA:")
for line in ["RF CLS 0 0 0",
             "WI 0 479 0 271", "VWP 0 479 0 271",
             "C 31 0 0", "M 100 100", "R 200 150",
             "M 150 125", "AR",
             "C 0 0 31", "P 4 300 200 350 150 400 200 350 250",
             "C 0 63 0", "M 350 200", "ARB 0 0 31"]:
    b.gl_line(line)
    b.wait_idle(30)
ok(wp(b, 150, 125) == 0xF800, "rect interior filled red", hex(wp(b,150,125)))
ok(wp(b, 101, 101) == 0xF800, "fill reached the corner", hex(wp(b,101,101)))
ok(wp(b,  90, 125) == 0x0000, "no leak left of the rect", hex(wp(b,90,125)))
ok(wp(b, 350, 200) == 0x07E0, "diamond interior green", hex(wp(b,350,200)))
ok(wp(b, 350, 150) == 0x001F, "diamond boundary kept blue", hex(wp(b,350,150)))
ok(wp(b, 290, 200) == 0x0000, "no escape from the diamond", hex(wp(b,290,200)))
b.gl_line("M -500 0")
b.gl_line("AR")
b.wait_idle(30)
ok(b.drain_errors() == [2], "off-window seed -> error 2")

# ---- 10h: font + TEXT scene (the tb_gl_txx session) ---------------------
print("10h TEXT:")
b.gl_file(ROOT + "/os/font.gl")
b.wait_idle(60)
b.gl_file(ROOT + "/emulator/test/gl_tx.gl")
b.wait_idle(60)
ok(b.drain_errors() == [], "clean run, no GL errors")
ok(wp(b, 20, 200) == 0xFFE0, "H stem base (1x yellow)", hex(wp(b,20,200)))
ok(wp(b, 20, 206) == 0xFFE0, "H stem top", hex(wp(b,20,206)))
ok(wp(b, 19, 203) == 0x0000, "no ink left of the string", hex(wp(b,19,203)))
ok(wp(b, 56, 206) == 0xFFE0, "W after the space advance", hex(wp(b,56,206)))
ok(wp(b, 20, 100) == 0x07FF, "4x B stem base (teal)", hex(wp(b,20,100)))
ok(wp(b, 20, 124) == 0x07FF, "4x B stem top (TSIZE scale)", hex(wp(b,20,124)))
ok(wp(b, 52, 110) == 0x07FF, "lowercase i folded to I", hex(wp(b,52,110)))
n = sum(1 for x in range(280, 340) for wy in range(35, 75)
        if wp(b, x, wy) == 0xF800)
ok(n > 30, "tilted TILT drawn (%d red px)" % n, n)

print("SILICON 10G+10H: %s" % ("PASS" if FAILS == 0 else "%d FAILURES" % FAILS))
sys.exit(1 if FAILS else 0)
