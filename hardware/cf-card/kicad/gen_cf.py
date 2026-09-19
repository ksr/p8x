#!/usr/bin/env python3
"""gen_cf.py -- bespoke KiCad board for the P8X CF-IDE CARD rev B (two 8-bit True
IDE drives: drive 0 $FF10-17, drive 1 $FF18-1F). Run with KiCad's bundled Python:

    PYK hardware/cf-card/kicad/gen_cf.py

Placement is bespoke so two CF-to-IDE adapters physically fit: a CF adapter sits
ON its 40-pin header and projects a ~43x50mm body over the board, so the two
headers J2 (drive 0) and J5 (drive 1) are placed on the RIGHT, ~70mm apart in Y,
with the whole right column kept clear of ICs. The DIN41612 bus is on the LEFT,
the activity/status LEDs on the far-right edge, and the decode + data buffers +
pull-ups grid-flowed in the left interior. Reuses gen_kicad's helpers. CANON.
"""
import os, sys
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "generators"))
import pcbnew
import gen_kicad as GK
from pcbnew import VECTOR2I
mm, P = GK.mm, GK.P
CARD = "cf-card"
BW, BH = 280.0, 140.0

title, parts, nets = GK.CARDS[CARD]
board = pcbnew.BOARD(); board.SetCopperLayerCount(4)
netobj = {}
for nn in nets:
    ni = pcbnew.NETINFO_ITEM(board, nn); board.Add(ni); netobj[nn] = ni

footp = {}
for ref, (dev, val) in parts.items():
    lib, name = GK.footprint_for(ref, dev)[:2]
    libdir = GK.FPLOCAL if lib == "__LOCAL__" else (GK.FP + "/%s.pretty" % lib)
    fp = pcbnew.FootprintLoad(libdir, name)
    fp.SetReference(ref); fp.SetValue(val); fp.Value().SetVisible(False)
    board.Add(fp); footp[ref] = fp

def place(ref, x, y, rot=0):
    if ref in footp: GK.place_centered(footp[ref], x, y, rot)

# --- 1. edge parts -----------------------------------------------------------
# J1 DIN bus: left edge
if "J1" in footp:
    j = footp["J1"]; j.SetOrientationDegrees(90); j.SetPosition(P(0, 0))
    x0, y0, x1, y1 = GK.pad_bbox(j)
    j.SetPosition(VECTOR2I(mm(4) - x0, mm(BH/2) - (y0 + y1)//2))
# two IDE-40 headers on the RIGHT, ~70mm apart in Y (a CF adapter projects ~43x50mm
# over each header; keep the right column clear so the two adapters don't collide)
IDEX = 205.0
place("J2", IDEX, 34.0);  place("RN1", 176.0, 34.0, 90)   # drive 0 + its pull-ups
place("J5", IDEX, 105.0); place("RN3", 176.0, 105.0, 90)  # drive 1 + its pull-ups
# far-right edge: power + per-drive activity + disk-active LEDs with resistors
for ref, rref, yy in (("LED3", "RP1", 20.0), ("LED4", "R4", 55.0),
                      ("LED6", "R6", 90.0), ("LED5", "R5", 125.0)):
    place(ref, BW - 7.0, yy, 90); place(rref, BW - 16.0, yy, 90)

EDGE_REFS = {"J1", "J2", "J5", "RN1", "RN3",
             "LED3", "RP1", "LED4", "R4", "LED5", "R5", "LED6", "R6"}

# --- 2. interior: left zone (clear of the IDE headers/adapters on the right) --
IX0, IX1, IY0, IY1, GAP, CAPH = 17.0, 158.0, 6.0, BH - 8.0, 1.8, 4.5
capfor = GK.CARDCAPS.get(CARD, {})
caprefs = set(capfor.values())
cx = [IX0]; cyt = [IY0]; rowh = [0.0]; overflow = [0.0]
def flow_one(ref, rot, cap=None):
    if ref not in footp: return
    w, h = GK.size_after(footp[ref], rot)
    band = CAPH if cap else 0.0
    if cx[0] + w > IX1 and cx[0] > IX0:
        cx[0] = IX0; cyt[0] += rowh[0] + GAP; rowh[0] = 0.0
    place(ref, cx[0] + w/2, cyt[0] + band + h/2, rot)
    if cap and cap in footp: place(cap, cx[0] + w/2, cyt[0] + band/2, 0)
    cx[0] += w + GAP; rowh[0] = max(rowh[0], h + band)
    overflow[0] = max(overflow[0], cyt[0] + band + h)
for ref in [r for r in parts if r.startswith("U")]:
    rot = 0 if GK.size_after(footp[ref], 0)[0] <= GK.size_after(footp[ref], 90)[0] else 90
    flow_one(ref, rot, capfor.get(ref))
for ref in [r for r in parts if r not in EDGE_REFS and r not in caprefs and not r.startswith("U")]:
    if ref not in footp: continue
    rot = 0 if GK.size_after(footp[ref], 0)[1] <= GK.size_after(footp[ref], 90)[1] else 90
    flow_one(ref, rot)
overflow = overflow[0]

# --- 3. assign nets ----------------------------------------------------------
bad = []
for net, mem in nets.items():
    ni = netobj[net]
    for (ref, pin) in mem:
        if ref not in footp: continue
        pad = GK.pad_of(ref, parts[ref][0], pin)
        if not any(p.GetNumber() == pad and (p.SetNet(ni) or True) for p in footp[ref].Pads()):
            bad.append("%s.%s" % (ref, pin))

# --- 4. outline + planes + keepouts ------------------------------------------
def edge(x1, y1, x2, y2):
    s = pcbnew.PCB_SHAPE(board); s.SetShape(pcbnew.SHAPE_T_SEGMENT)
    s.SetStart(P(x1, y1)); s.SetEnd(P(x2, y2)); s.SetLayer(pcbnew.Edge_Cuts)
    s.SetWidth(mm(0.15)); board.Add(s)
edge(0, 0, BW, 0); edge(BW, 0, BW, BH); edge(BW, BH, 0, BH); edge(0, BH, 0, 0)
for layer, nn in [(pcbnew.In1_Cu, "GND"), (pcbnew.In2_Cu, "VCC")]:
    if nn not in netobj: continue
    z = pcbnew.ZONE(board); z.SetLayer(layer); z.SetNet(netobj[nn]); z.SetIsFilled(True)
    z.SetPadConnection(pcbnew.ZONE_CONNECTION_FULL)
    z.SetIslandRemovalMode(pcbnew.ISLAND_REMOVAL_MODE_ALWAYS)
    z.SetLocalClearance(mm(0.2)); z.SetMinThickness(mm(0.13))
    o = z.Outline(); o.NewOutline()
    for x, y in [(1, 1), (BW-1, 1), (BW-1, BH-1), (1, BH-1)]: o.Append(mm(x), mm(y))
    board.Add(z)
GK.add_mounting_keepouts(board, footp)
pcbnew.ZONE_FILLER(board).Fill(board.Zones())

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "p8x-cf-card.kicad_pcb")
pcbnew.SaveBoard(out, board)
print("wrote", out, "(%dx%dmm, %d footprints)" % (BW, BH, len(footp)))
if overflow > IY1: print("  WARNING: interior overflow, bottom=%.0f (need < %.0f)" % (overflow, IY1))
if bad: print("  PAD MISMATCH (%d): %s" % (len(bad), bad[:8]))
