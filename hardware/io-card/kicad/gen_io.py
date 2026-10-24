#!/usr/bin/env python3
"""gen_io.py -- bespoke KiCad board for the P8X I/O CARD rev B (2x ACIA/DB9 +
switches + LEDs + bus monitor). Run with KiCad's bundled Python (needs pcbnew):

    PYK hardware/io-card/kicad/gen_io.py

Edge treatment (front edge = RIGHT, opposite the bus; rules of 2026-10-24):
  * at the right edge: the power + I/O-select LEDs, the input **DIP switch** and
    the two RS-232 **DB9 sockets**, facing out of the edge
  * just inboard of them, the four **LED bars** (output latch + the D0-7 / A0-7
    / A8-15 bus monitors), each with its DIP-16 resistor network
  * on the bottom edge: the RX/TX swap jumpers, the RTC 3-wire header and the
    RTC's CR2032 holder
  * the DIN41612 **bus connector J1** on the LEFT edge
  * the ICs (2x 6850, MAX232, decode, buffers, RTC) + caps grid-flowed in the
    interior, courtyard-spaced. Reuses gen_kicad's helpers. CANON.
"""
import os, sys
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "generators"))
import pcbnew
import gen_kicad as GK
from pcbnew import VECTOR2I
mm, P = GK.mm, GK.P
CARD = "io-card"
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
# J1 DIN bus: left edge, vertical, pads 4mm in, centred on the 140mm edge
if "J1" in footp:
    j = footp["J1"]; j.SetOrientationDegrees(90); j.SetPosition(P(0, 0))
    x0, y0, x1, y1 = GK.pad_bbox(j)
    j.SetPosition(VECTOR2I(mm(4) - x0, mm(BH/2) - (y0 + y1)//2))
# FRONT edge = the RIGHT edge, opposite the bus connector (layout rules
# 2026-10-24: switches, LEDs and outside-cable connectors at the front edge;
# jumper blocks and cable headers near an edge). Two columns:
#   * at the edge, top to bottom: the input DIP switch, the two RS-232 DB9
#     sockets facing OUT of the edge, then the power + I/O-select LEDs;
#   * just inboard: the four LED bars (output latch, D0-7, A0-7, A8-15), each with
#     its DIP-16 current-limit network on its left -- resistor pins 16..9
#     (B1..B8) face the bar's anodes 1..8 straight across.
# Below the bars, by the DB9s: the RX/TX swap jumpers on the bottom edge; the RTC
# header and its CR2032 holder further along the bottom edge.
EX = BW - 8.0                       # edge column centre line
place("SW1", BW - 7.0, 38.0, 0)
# The DB9s face OUT: rotation 90 turns the socket's mating face (+y at rotation 0)
# toward +x. The footprint's board-edge offset puts pin 1 9.40 mm in from the
# edge, so the shell overhangs the right edge for a cable. Origin = pad 1; pins
# 1-5 then run +y, so pad 1 sits 5.54 mm above the pin-row centre.
def place_db9(ref, cy):
    if ref not in footp: return
    f = footp[ref]; f.SetOrientationDegrees(90); f.SetPosition(P(BW - 9.40, cy - 5.54))
place_db9("DB9A", 72.0)
place_db9("DB9B", 108.0)
# power + I/O-select LEDs below the DB9s, each resistor lying flat to its left
place("LED3", BW - 6.0, 128.0, 90); place("RP1", BW - 17.0, 128.0, 0)
place("LED4", BW - 6.0, 135.5, 90); place("R4",  BW - 17.0, 135.5, 0)
BX = BW - 25.0                      # bar column; resistor network 12 mm left of it
for i, (bar, rnet) in enumerate([("LA1", "RL1"), ("LM3", "RM3"),
                                 ("LM1", "RM1"), ("LM2", "RM2")]):
    place(bar, BX, 15.0 + 27.0 * i); place(rnet, BX - 12.0, 15.0 + 27.0 * i)
place("JP1", BW - 44.0, BH - 9.0, 90); place("JP2", BW - 32.0, BH - 9.0, 90)
place("J3", BW - 95.0, BH - 6.0)
place("BT1", BW - 72.0, BH - 17.0)

EDGE_REFS = {"J1", "DB9A", "DB9B", "SW1", "J3", "BT1", "JP1", "JP2",
             "LA1", "LM1", "LM2", "LM3", "RL1", "RM1", "RM2", "RM3",
             "LED3", "RP1", "LED4", "R4"}

# --- 2. interior: grid-flow the ICs (+ caps) then remaining passives ----------
IX0, IX1, IY0, IY1, GAP, CAPH = 17.0, BW - 47.0, 8.0, BH - 32.0, 1.8, 4.5
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

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "p8x-io-card.kicad_pcb")
# silkscreen: references outside every part, IC types, function + position labels
_fails = GK.SL.label_board(board, parts, *GK.silk_spec(CARD, parts))
if _fails: print("  SILK: no clean spot for %d: %s" % (len(_fails), _fails[:12]))

pcbnew.SaveBoard(out, board)
print("wrote", out, "(%dx%dmm, %d footprints)" % (BW, BH, len(footp)))
if overflow > IY1: print("  WARNING: interior overflow, bottom=%.0f (need < %.0f)" % (overflow, IY1))
if bad: print("  PAD MISMATCH (%d): %s" % (len(bad), bad[:8]))
