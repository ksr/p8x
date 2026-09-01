#!/usr/bin/env python3
"""Silicon check for BLIT over the card bridge -- plus the number the
whole rung was chasing: the WALL-CLOCK time to stream a full 256x256
P8I (the mandrill) to the panel, versus the minutes the per-pixel
device path used to take."""
import sys, os, time, struct
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from glbridge import Bridge, SerialXport

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))
FAILS = 0

def ok(cond, what, got=None):
    global FAILS
    if cond: print("  ok  %s" % what)
    else:
        FAILS += 1
        print("  FAIL %s (got %s)" % (what, got))

def rbw(b, timeout=3.0):
    out = []
    t0 = time.time()
    while len(out) < 2:
        if b.rdreg(0x31) & 1:
            out.append(b.rdreg(0x32))
        elif time.time() - t0 > timeout:
            raise TimeoutError("RB word timed out")
    return out[0] | (out[1] << 8)

def prd(b, x, y):
    b.burst(bytes([0x63, x & 255, (x >> 8) & 255, y & 255, (y >> 8) & 255]))
    return rbw(b)

b = Bridge(SerialXport())
b.resync()
print("card protocol v%d, identity %s" % (b.ping(), b.probe()))
b.drain_errors()

print("BLIT:")
b.gl_line("RF PROJCT 0 CLS 0 0 0")
b.gl_line("WI 0 479 0 271"); b.gl_line("VWP 0 479 0 271")
b.wait_idle(30)
# the golden 4x3 at (100,50), payload 1000..1011
pay = b"".join(struct.pack("<H", 1000 + i) for i in range(12))
b.burst(bytes([0x64, 100, 0, 50, 0, 4, 0, 3, 0]) + pay)
b.wait_idle(10)
ok(prd(b, 100, 52) == 1000, "top-left of the 4x3")
ok(prd(b, 103, 50) == 1011, "bottom-right of the 4x3")
ok(prd(b, 104, 51) == 0, "right border clean")
# retired CLMOD: err1, stream lives
b.burst(bytes([0x78]))
b.wait_idle(5)
ok(b.drain_errors() == [1], "retired CLMOD -> err1")
ok(prd(b, 100, 52) == 1000, "stream alive after the skip")

# ---- the timed mandrill ------------------------------------------------
img = open(ROOT + "/os/mandrill.p8i", "rb").read()
w, h = struct.unpack("<HH", img[4:8])
payload = img[10:10 + 2*w*h]
print("mandrill: %dx%d, %d payload bytes" % (w, h, len(payload)))
hdr = bytes([0x64, 112 & 255, 0, 8, 0, w & 255, w >> 8, h & 255, h >> 8])
t0 = time.time()
b.burst(hdr + payload)
b.wait_idle(60)
dt = time.time() - t0
print("  streamed + drawn in %.1f s  (%.0f bytes/s effective)"
      % (dt, len(payload) / dt))
# spot-check four pixels against the file (rows top-down from window 8+h-1)
def filepx(px, py_top):
    i = 10 + 2 * (py_top * w + px)
    return img[i] | (img[i+1] << 8)
ok(prd(b, 112, 8 + h - 1) == filepx(0, 0), "top-left pixel matches the file")
ok(prd(b, 112 + w - 1, 8) == filepx(w - 1, h - 1), "bottom-right matches")
ok(prd(b, 112 + w // 2, 8 + h // 2) == filepx(w // 2, h // 2 - 1),
   "an interior pixel matches")
ok(b.drain_errors() == [], "clean run, no GL errors")

print("SILICON BLIT: %s" % ("PASS" if FAILS == 0 else "%d FAILURES" % FAILS))
sys.exit(1 if FAILS else 0)
