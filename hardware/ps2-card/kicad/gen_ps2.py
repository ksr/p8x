#!/usr/bin/env python3
"""gen_ps2.py -- bespoke KiCad board for the P8X PS/2 CARD (keyboard + mouse).
Run with KiCad's bundled Python (needs pcbnew):

    PYK hardware/ps2-card/kicad/gen_ps2.py

Placement is bespoke so the external parts land where the user wants them:
  * the two PS/2 mini-DIN-6 sockets on the BOTTOM long edge (openings facing off
    the edge for cable access), with the ICSP header + reset pull-ups beside them
  * the four status LEDs (power, kbd-read, mouse-read, keystroke-available) on the
    RIGHT edge, opposite the bus connector
  * the DIN41612 bus edge connector J1 on the LEFT edge
  * the ICs (ATmega1284 + the decode/latch bridge) + their decoupling caps and the
    PS/2 pull-up SIP grid-flowed in the interior, courtyard-spaced so nothing overlaps
It reuses gen_kicad's footprint map / helpers (including the custom mini-DIN-6
footprint via the __LOCAL__ library) so footprints stay consistent. CANON.
"""
import os, sys
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "generators"))
import pcbnew
import gen_kicad as GK
from pcbnew import VECTOR2I
mm, P = GK.mm, GK.P
CARD = "ps2-card"
BW, BH = 280.0, 140.0

title, parts, nets = GK.CARDS[CARD]
board = pcbnew.BOARD(); board.SetCopperLayerCount(4)
netobj = {}
for n in nets:
    ni = pcbnew.NETINFO_ITEM(board, n); board.Add(ni); netobj[n] = ni

# --- load footprints (handle the __LOCAL__ p8x library for the mini-DIN-6) ----
footp = {}
for ref, (dev, val) in parts.items():
    lib, name = GK.footprint_for(ref, dev)[:2]
    libdir = GK.FPLOCAL if lib == "__LOCAL__" else (GK.FP + "/%s.pretty" % lib)
    fp = pcbnew.FootprintLoad(libdir, name)
    fp.SetReference(ref); fp.SetValue(val); fp.Value().SetVisible(False)
    board.Add(fp); footp[ref] = fp

def place(ref, x, y, rot=0):
    if ref in footp: GK.place_centered(footp[ref], x, y, rot)

# --- 1. edge parts (hand-placed) ---------------------------------------------
# J1 DIN bus: left edge, vertical, pads 4mm in, centred on the 140mm edge
if "J1" in footp:
    j = footp["J1"]; j.SetOrientationDegrees(90); j.SetPosition(P(0, 0))
    x0, y0, x1, y1 = GK.pad_bbox(j)
    j.SetPosition(VECTOR2I(mm(4) - x0, mm(BH/2) - (y0 + y1)//2))
# bottom edge: the two PS/2 sockets (rot 180 so the footprint's -Y opening faces
# +Y = off the bottom edge), then the ICSP header + reset pull-ups beside them
BY = BH - 9.0
place("PS2A", 92.0, BY, 180); place("PS2B", 132.0, BY, 180)   # keyboard, mouse
place("JICSP", 172.0, BH - 7.0); place("RRST", 192.0, BH - 6.0); place("RRB", 210.0, BH - 6.0)
# right edge (opposite J1): the four status LEDs, each with its series resistor
LX, RX = BW - 6.0, BW - 15.0
for ref, rref, yy in (("LEDPWR", "RPWR", 30.0), ("LEDKR", "RKR", 55.0),
                      ("LEDMR", "RMR", 80.0), ("LEDKA", "RKA", 105.0)):
    place(ref, LX, yy, 90); place(rref, RX, yy, 90)

EDGE_REFS = {"J1", "PS2A", "PS2B", "JICSP", "RRST", "RRB",
             "LEDPWR", "RPWR", "LEDKR", "RKR", "LEDMR", "RMR", "LEDKA", "RKA"}

# --- 2. interior: grid-flow the ICs (+ their caps) then the passives ----------
IX0, IX1, IY0, IY1, GAP, CAPH = 17.0, BW - 22.0, 5.0, BH - 18.0, 1.8, 4.5
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

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "p8x-ps2-card.kicad_pcb")
pcbnew.SaveBoard(out, board)
print("wrote", out, "(%dx%dmm, %d footprints)" % (BW, BH, len(footp)))
if overflow > IY1: print("  WARNING: interior overflow, bottom=%.0f (need < %.0f)" % (overflow, IY1))
if bad: print("  PAD MISMATCH (%d): %s" % (len(bad), bad[:8]))
