#!/usr/bin/env python3
"""export_dsn.py -- export a Specctra .dsn from the memory-card .kicad_pcb, for
Freerouting. kicad-cli cannot do this; pcbnew.ExportSpecctraDSN can (it needs a
wxApp instance created first). Run with KiCad's bundled python."""
import sys, os, pcbnew
try:
    import wx
    _app = wx.App()                      # ExportSpecctraDSN needs an app instance
except Exception:
    pass
HERE = os.path.dirname(os.path.abspath(__file__))
brd = os.path.join(HERE, "p8x-memory-card.kicad_pcb")
dsn = os.path.join(HERE, "p8x-memory-card.dsn")
board = pcbnew.LoadBoard(brd)
# Unfill the plane zones before export so the DSN carries them as SIMPLE
# rectangles, not the fully-filled copper riddled with anti-pad cutouts -- the
# latter's item count makes Freerouting's optimizer abort ("too many items").
# KiCad re-fills the planes after the SES import.
for z in board.Zones():
    z.UnFill()
ok = pcbnew.ExportSpecctraDSN(board, dsn)
print("ExportSpecctraDSN ->", ok, dsn)

# KiCad exports every layer as (type signal); mark the internal planes as
# (type power) so Freerouting keeps them as GND/VCC planes and routes signals
# ONLY on F.Cu / B.Cu (otherwise it shreds the planes routing signals on them).
txt = open(dsn).read()
for lyr in ("In1.Cu", "In2.Cu"):
    txt = txt.replace("(layer %s\n      (type signal)" % lyr,
                      "(layer %s\n      (type power)" % lyr)
open(dsn, "w").write(txt)
npow = txt.count("(type power)")
print("patched internal layers to power:", npow)
print("exists:", os.path.exists(dsn), os.path.getsize(dsn), "bytes")
import sys as _sys; _sys.stdout.flush(); os._exit(0)   # skip the wx.App exit hang
