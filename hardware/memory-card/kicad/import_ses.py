#!/usr/bin/env python3
"""import_ses.py -- import the Freerouting .ses back into the .kicad_pcb, re-fill
the GND zone, and save. Run with KiCad's bundled python."""
import sys, os, pcbnew
try:
    import wx; _app = wx.App()
except Exception:
    pass
HERE = os.path.dirname(os.path.abspath(__file__))
brd = os.path.join(HERE, "p8x-memory-card.kicad_pcb")
ses = os.path.join(HERE, "p8x-memory-card.ses")
board = pcbnew.LoadBoard(brd)
ok = pcbnew.ImportSpecctraSES(board, ses)
print("ImportSpecctraSES ->", ok)
# re-fill zones (GND pour) after routing
pcbnew.ZONE_FILLER(board).Fill(board.Zones())
pcbnew.SaveBoard(brd, board)
board.BuildConnectivity()
tracks = board.GetTracks()
ntrk = sum(1 for t in tracks if t.Type() == pcbnew.PCB_TRACE_T)
nvia = sum(1 for t in tracks if t.Type() == pcbnew.PCB_VIA_T)
print("routed: %d track segments, %d vias" % (ntrk, nvia))
