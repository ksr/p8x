#!/usr/bin/env python3
"""Silicon check for stages 10i/10j/10k over the card bridge.

Replays the emulator test scenes' shapes and probes the same golden
pixels with glbridge's PIXELR helper: curves (CIRCLE/ELIPSE; the
retired ARC keyword must error), patterns (LINPAT dashes; the retired
APT keyword must error), and the text completion (TJUST centre, TEXTP,
TEXT from a replayed list).
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
    return b.pixelr(x, 271 - wy)

b = Bridge(SerialXport())
b.resync()
print("card protocol v%d, identity %s" % (b.ping(), b.probe()))
b.drain_errors()

# ---- 10i: curves (CIRCLE/ELIPSE; ARC/SECTOR removed 2026-08-30) ---------
print("10i curves:")
for line in ["RF CLS 0 0 0",
             "WI 0 479 0 271", "VWP 0 479 0 271",
             "C 31 0 0", "M 100 136", "CI 60",
             "C 0 63 0", "PF 1", "M 300 136", "CI 40", "PF 0",
             "C 0 0 31", "M 100 60", "EL 80 30"]:
    b.gl_line(line)
    b.wait_idle(30)
ok(wp(b, 160, 136) == 0xF800, "circle right point", hex(wp(b, 160, 136)))
ok(wp(b, 100, 196) == 0xF800, "circle top point", hex(wp(b, 100, 196)))
ok(wp(b, 100, 136) == 0x0000, "circle hollow", hex(wp(b, 100, 136)))
ok(wp(b, 300, 136) == 0x07E0, "filled circle centre", hex(wp(b, 300, 136)))
ok(wp(b, 180,  60) == 0x001F, "ellipse right point", hex(wp(b, 180, 60)))
# the retired ARC keyword: unknown-keyword error, the stream survives
b.gl_line("ARC 40 0 90")
b.wait_idle(10)
ok(b.drain_errors() != [], "retired ARC keyword errors")
b.gl_line("CI -5")
b.wait_idle(10)
ok(b.drain_errors() == [2], "negative radius -> error 2")

# ---- 10j: patterns (LINPAT; AREAPT removed 2026-08-30) ------------------
print("10j patterns:")
b.gl_line("RF CLS 0 0 0")
b.gl_line("WI 0 479 0 271")
b.gl_line("VWP 0 479 0 271")
b.gl_line("C 31 63 31")
b.gl_line("LPT -3856")                      # $F0F0
b.gl_line("M 10 250 D 200 250")
b.gl_line("LPT -1")
b.gl_line("C 0 63 0 PF 1")
b.gl_line("M 48 48 R 112 112")
b.gl_line("PF 0")
b.wait_idle(30)
ok(wp(b, 10, 250) == 0xFFFF, "dash px0", hex(wp(b, 10, 250)))
ok(wp(b, 14, 250) == 0x0000, "dash gap px4", hex(wp(b, 14, 250)))
ok(wp(b, 50, 51) == 0x07E0, "solid fill px", hex(wp(b, 50, 51)))
ok(wp(b, 51, 50) == 0x07E0, "solid fill px2", hex(wp(b, 51, 50)))
ok(b.drain_errors() == [], "clean pattern run")
b.gl_line("APT 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16")
b.wait_idle(10)
ok(b.drain_errors() != [], "retired APT keyword errors")

# ---- 10k: text completion (font + gl_t2.gl) -----------------------------
print("10k text:")
b.gl_line("RF")
b.gl_file(ROOT + "/os/font.gl")
b.wait_idle(60)
b.gl_file(ROOT + "/emulator/test/gl_t2.gl")
b.wait_idle(60)
ok(b.drain_errors() == [], "clean text run")
ok(wp(b, 222, 200) != 0x0000 or wp(b, 223, 200) != 0x0000,
   "TJUST centre left edge ~222")
ok(wp(b, 219, 203) == 0x0000, "no ink left of centred string",
   hex(wp(b, 219, 203)))
ok(wp(b, 100, 100) == 0x07FF, "LIST replayed from the command list",
   hex(wp(b, 100, 100)))
ok(wp(b, 122, 106) == 0x07FF, "LIST's last char present (T top bar)",
   hex(wp(b, 122, 106)))

print("SILICON 10I/J/K: %s" % ("PASS" if FAILS == 0 else "%d FAILURES" % FAILS))
sys.exit(1 if FAILS else 0)
