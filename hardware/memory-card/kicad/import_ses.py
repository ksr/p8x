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

# self-heal: Freerouting occasionally leaves a trivial 2-pad net unrouted (e.g. an
# LED-bank resistor->LED at the board edge). Stitch any 2-pad net that has no
# copper AND whose pads are collinear (a clean straight run) with a direct F.Cu
# track, so the board comes out fully connected regardless of the router's whims.
board.BuildConnectivity()
_np = {}
for _fp in board.GetFootprints():
    for _p in _fp.Pads():
        _np.setdefault(_p.GetNetname(), []).append(_p)
_stitched = 0
for _name, _pads in _np.items():
    if _name in ("", "GND", "VCC") or len(_pads) != 2:
        continue
    if any(t.GetNetname() == _name for t in board.GetTracks()):
        continue
    a, b = _pads
    if a.GetPosition().x != b.GetPosition().x and a.GetPosition().y != b.GetPosition().y:
        continue                                   # only stitch straight (collinear) runs
    t = pcbnew.PCB_TRACK(board)
    t.SetStart(a.GetPosition()); t.SetEnd(b.GetPosition())
    # route on B.Cu: the pads are through-hole, so a bottom track connects them
    # while ducking under any F.Cu tracks that block the direct top path.
    t.SetLayer(pcbnew.B_Cu); t.SetWidth(pcbnew.FromMM(0.25)); t.SetNetCode(a.GetNetCode())
    board.Add(t); _stitched += 1
    print("  stitched %s: %s.%s -> %s.%s" % (_name,
          a.GetParentFootprint().GetReference(), a.GetNumber(),
          b.GetParentFootprint().GetReference(), b.GetNumber()))
if _stitched:
    print("stitched %d trivial unrouted 2-pad net(s)" % _stitched)

# re-fill zones (GND pour) after routing
pcbnew.ZONE_FILLER(board).Fill(board.Zones())
pcbnew.SaveBoard(brd, board)
board.BuildConnectivity()
tracks = board.GetTracks()
ntrk = sum(1 for t in tracks if t.Type() == pcbnew.PCB_TRACE_T)
nvia = sum(1 for t in tracks if t.Type() == pcbnew.PCB_VIA_T)
print("routed: %d track segments, %d vias" % (ntrk, nvia))

# regenerate the parts-placement PDF from the finalised board (part of the build)
sys.path.insert(0, HERE)
import gen_placement
gen_placement.build()
