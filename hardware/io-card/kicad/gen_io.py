#!/usr/bin/env python3
"""gen_io.py -- bespoke KiCad board for the P8X I/O CARD rev B (2x ACIA/DB9 +
switches + LEDs + bus monitor). Run with KiCad's bundled Python (needs pcbnew):

    PYK hardware/io-card/kicad/gen_io.py

Edge treatment (matching the PS/2 card's style):
  * the two RS-232 **DB9 sockets** + their RX/TX swap jumpers, the input **DIP
    switch**, and the RTC 3-wire header on the BOTTOM long edge
  * the four **LED bars** (output latch + the A0-7 / A8-15 / D0-7 bus monitors)
    along the TOP edge for visibility; power + I/O-select LEDs on the RIGHT edge
  * the DIN41612 **bus connector J1** on the LEFT edge
  * the ICs (2x 6850, MAX232, decode, buffers, RTC) + caps + R-nets grid-flowed
    in the interior, courtyard-spaced. Reuses gen_kicad's helpers. CANON.
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
# bottom edge: the two DB9 sockets (openings off the edge), the DIP switch, the RTC
# header. The RX/TX swap jumpers JP1/JP2 are set-once config, so they flow in the
# interior near the MAX232 (crowding them onto the bottom edge beside the big
# edge-mount DB9s left the DB9 TXD/RXD pins unroutable). Pads stay inside the edge.
BY = BH - 14.0
place("DB9A", 40.0, BY, 180)
place("DB9B", 95.0, BY, 180)
place("SW1", 155.0, BH - 16.0, 90); place("J3", 214.0, BH - 12.0)
# top edge: the four LED bars (output + A0-7 / A8-15 / D0-7 monitors), pulled down
# far enough that the bar bodies clear the top edge
TY = 24.0
place("LA1", 40.0, TY); place("LM3", 92.0, TY); place("LM1", 144.0, TY); place("LM2", 196.0, TY)
# right edge: power + I/O-select LEDs with their resistors
place("LED3", BW - 8.0, 45.0, 90); place("RP1", BW - 17.0, 45.0, 90)
place("LED4", BW - 8.0, 65.0, 90); place("R4",  BW - 17.0, 65.0, 90)

EDGE_REFS = {"J1", "DB9A", "DB9B", "SW1", "J3",
             "LA1", "LM1", "LM2", "LM3", "LED3", "RP1", "LED4", "R4"}

# --- 2. interior: grid-flow the ICs (+ caps) then remaining passives ----------
IX0, IX1, IY0, IY1, GAP, CAPH = 17.0, BW - 22.0, 34.0, BH - 32.0, 1.8, 4.5
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
pcbnew.SaveBoard(out, board)
print("wrote", out, "(%dx%dmm, %d footprints)" % (BW, BH, len(footp)))
if overflow > IY1: print("  WARNING: interior overflow, bottom=%.0f (need < %.0f)" % (overflow, IY1))
if bad: print("  PAD MISMATCH (%d): %s" % (len(bad), bad[:8]))
