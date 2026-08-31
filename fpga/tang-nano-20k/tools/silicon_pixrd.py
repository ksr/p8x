#!/usr/bin/env python3
"""Silicon check for PIXRD over the card bridge: the single-interface
migration's first verb. Draws with GL, reads back with PIXRD through
the RB FIFO, and cross-checks against the device PIXELR the bridge
helper still speaks."""
import sys, os, time
sys.path.insert(0, os.path.expanduser(
    "~/Documents/Projects/p8x/fpga/tang-nano-20k/tools"))
from glbridge import Bridge, SerialXport

IDX_GLSTAT, IDX_GLRB = 0x31, 0x32
FAILS = 0

def ok(cond, what, got=None):
    global FAILS
    if cond: print("  ok  %s" % what)
    else:
        FAILS += 1
        print("  FAIL %s (got %s)" % (what, got))

def rbw(b, timeout=3.0):
    """Pop one int16 read-back word (low byte first) via GLRB."""
    out = []
    t0 = time.time()
    while len(out) < 2:
        if b.rdreg(IDX_GLSTAT) & 1:
            out.append(b.rdreg(IDX_GLRB))
        elif time.time() - t0 > timeout:
            raise TimeoutError("RB word timed out at %d bytes" % len(out))
    return out[0] | (out[1] << 8)

b = Bridge(SerialXport())
b.resync()
print("card protocol v%d, identity %s" % (b.ping(), b.probe()))
b.drain_errors()

print("PIXRD:")
for line in ["RF CLS 0 0 0",
             "WI 0 479 0 271", "VWP 0 479 0 271",
             "C 31 63 0", "M 100 50", "POINT"]:
    b.gl_line(line)
    b.wait_idle(30)
b.gl_line("PXR 100 50")
ok(rbw(b) == 0xFFE0, "identity hit reads yellow")
b.gl_line("PXR 101 50")
ok(rbw(b) == 0x0000, "neighbour reads 0")
b.gl_line("PXR -5 50")
ok(rbw(b) == 0x0000, "off-window reads 0")
ok(b.pixelr(100, 221) == 0xFFE0, "device PIXELR agrees at screen (100,221)")
# the mapped window
for line in ["WI -120 120 -120 120", "VWP 104 375 0 271",
             "C 0 63 31", "M 60 60", "POINT"]:
    b.gl_line(line)
    b.wait_idle(30)
b.gl_line("PXR 60 60")
ok(rbw(b) == 0x07FF, "mapped-window hit reads teal")
b.gl_line("PXR 0 0")
ok(rbw(b) == 0x0000, "mapped origin reads 0")
# recorded in a list, read at replay
b.gl_line("CLBEG 5 PXR 60 60 CLEND")
b.gl_line("CLRUN 5")
ok(rbw(b) == 0x07FF, "list replay reads teal")
ok(b.drain_errors() == [], "clean run, no GL errors")

print("SILICON PIXRD: %s" % ("PASS" if FAILS == 0 else "%d FAILURES" % FAILS))
sys.exit(1 if FAILS else 0)
