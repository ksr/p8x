#!/usr/bin/env python3
"""gen_periph.py -- bespoke KiCad board for the P8X PERIPHERAL CARD (I/O + CF +
PS/2). Run with KiCad's bundled Python (needs pcbnew):

    PYK hardware/peripheral-card/kicad/gen_periph.py

This card is far denser than the auto-flow cards (33 ICs + a connector row), so
placement is bespoke, per the user's rules:
  * all EXTERNAL connectors along the BOTTOM long edge (2x DB9, 2x PS/2, the
    serial swap jumpers, the ICSP header)
  * the DIN41612 bus edge connector J1 on the LEFT edge
  * the IDE-40 header J4 near the RIGHT edge (mates the CF-to-IDE adapter)
  * everything else (33 ICs + decoupling caps + LED bars + DIP switch + RTC +
    passives) grid-flowed in the interior, courtyard-spaced so nothing overlaps
It reuses gen_kicad's footprint map / helpers so footprints + substitutions stay
consistent with the other cards. GENERATORS ARE CANON.
"""
import os, sys
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "generators"))
import pcbnew
import gen_kicad as GK        # footprint_for, place_centered, size_after, pad_of, FPMAP, CARDS, DEV, keepouts
from pcbnew import VECTOR2I
mm, P = GK.mm, GK.P
CARD = "peripheral-card"
BW, BH = 280.0, 140.0

title, parts, nets = GK.CARDS[CARD]
board = pcbnew.BOARD(); board.SetCopperLayerCount(4)
netobj = {}
for n in nets:
    ni = pcbnew.NETINFO_ITEM(board, n); board.Add(ni); netobj[n] = ni

# --- load footprints ---------------------------------------------------------
footp = {}
for ref, (dev, val) in parts.items():
    lib, name = GK.footprint_for(ref, dev)[:2]
    fp = pcbnew.FootprintLoad(GK.FP_DIR if hasattr(GK, "FP_DIR") else
        "/Applications/KiCad/KiCad.app/Contents/SharedSupport/footprints/%s.pretty" % lib, name)
    if fp is None:
        fp = pcbnew.FootprintLoad(
            "/Applications/KiCad/KiCad.app/Contents/SharedSupport/footprints/%s.pretty" % lib, name)
    fp.SetReference(ref); fp.SetValue(val); fp.Value().SetVisible(False)
    board.Add(fp); footp[ref] = fp

def place(ref, x, y, rot=0):
    if ref in footp: GK.place_centered(footp[ref], x, y, rot)   # place_centered takes mm floats

# --- 1. edge connectors (hand-placed) ----------------------------------------
# J1 DIN bus: left edge, vertical, pads 4mm in, centred on the 140mm edge
if "J1" in footp:
    j = footp["J1"]; j.SetOrientationDegrees(90); j.SetPosition(P(0, 0))
    x0, y0, x1, y1 = GK.pad_bbox(j)
    j.SetPosition(VECTOR2I(mm(4) - x0, mm(BH/2) - (y0 + y1)//2))
# J4 IDE-40: right edge, natively tall (2x20 vertical = ~50mm along Y), pads
# clear of the edge; the CF-to-IDE adapter plugs on and sits off to the right.
place("J4", BW - 8.0, BH/2, 0)
# bottom connector row (bodies overhang the bottom edge; pads on-board), left-to-right
BY = BH - 7.0
place("DB9A", 34.0, BY - 2.0); place("DB9B", 66.0, BY - 2.0)   # serial DB9 sockets
place("JP1", 96.0, BY);       place("JP2", 112.0, BY)          # RX/TX swap jumpers
place("PS2A", 140.0, BY - 2.0); place("PS2B", 172.0, BY - 2.0) # PS/2 kbd + mouse
place("JICSP", 200.0, BY);    place("RRST", 214.0, BY)         # ATmega ICSP + reset pull-up

EDGE_REFS = {"J1", "J4", "DB9A", "DB9B", "JP1", "JP2", "PS2A", "PS2B", "JICSP", "RRST"}

# --- 2. interior: grid-flow, courtyard-spaced; each decap hugs its IC ---------
# interior box (clear of J1 on the left, J4 on the right, the connector row below)
IX0, IX1, IY0, IY1, GAP, CAPH = 17.0, 246.0, 5.0, BH - 18.0, 1.8, 4.5
capfor = GK.CARDCAPS.get(CARD, {})                    # IC -> its decoupling cap
caprefs = set(capfor.values())
cx = [IX0]; cyt = [IY0]; rowh = [0.0]; overflow = [0.0]
def flow_one(ref, rot, cap=None):
    if ref not in footp: return
    w, h = GK.size_after(footp[ref], rot)
    band = CAPH if cap else 0.0
    if cx[0] + w > IX1 and cx[0] > IX0:               # wrap to next row
        cx[0] = IX0; cyt[0] += rowh[0] + GAP; rowh[0] = 0.0
    place(ref, cx[0] + w/2, cyt[0] + band + h/2, rot)
    if cap and cap in footp: place(cap, cx[0] + w/2, cyt[0] + band/2, 0)  # cap in the band above
    cx[0] += w + GAP; rowh[0] = max(rowh[0], h + band)
    overflow[0] = max(overflow[0], cyt[0] + band + h)
# ICs first (with their caps hugged), then LED bars / R-nets / switch / passives.
# orient each IC NARROW (min width) so more fit per row -> fewer, taller rows,
# which totals LESS height than many short-wide rows.
for ref in [r for r in parts if r.startswith("U")]:
    rot = 0 if GK.size_after(footp[ref], 0)[0] <= GK.size_after(footp[ref], 90)[0] else 90
    flow_one(ref, rot, capfor.get(ref))
for ref in [r for r in parts if r not in EDGE_REFS and r not in caprefs and not r.startswith("U")]:
    if ref not in footp: continue
    rot = 0 if GK.size_after(footp[ref], 0)[1] <= GK.size_after(footp[ref], 90)[1] else 90
    flow_one(ref, rot)                                # lay each passive/bar flat (min height)
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

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "p8x-peripheral-card.kicad_pcb")
pcbnew.SaveBoard(out, board)
print("wrote", out, "(%dx%dmm, %d footprints)" % (BW, BH, len(footp)))
if overflow: print("  WARNING: interior overflow, bottom=%.0f (need < %.0f)" % (overflow, IY1))
if bad: print("  PAD MISMATCH (%d): %s" % (len(bad), bad[:8]))
