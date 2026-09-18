#!/usr/bin/env python3
"""gen_backplane.py -- KiCad board for the P8X 10-slot backplane (best-effort).

    PYK generators/gen_backplane.py

The backplane is NOT a plug-in card -- it is ten DIN41612 FEMALE sockets (the bus)
plus power entry, bulk + per-slot decoupling caps, and the wired-OR pull-ups. Its
netlist is the bps/bpn structure in gen_eagle.py. This builds a PLACED KiCad board
(sockets in 2 rows of 5, power + caps, the full bus netlist, GND/VCC planes) --
but it is NOT autorouted: a 10x96-pin parallel bus over a ~520x300mm board is a
large routing job left for later (hand-route or a dedicated Freerouting pass).
GENERATORS ARE CANON.
"""
import os, sys, pcbnew
from pcbnew import VECTOR2I
ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
sys.path.insert(0, os.path.join(ROOT, "generators"))
import gen_eagle as GE
FP = "/Applications/KiCad/KiCad.app/Contents/SharedSupport/footprints"
def mm(v): return pcbnew.FromMM(float(v))
def P(x, y): return VECTOR2I(mm(x), mm(y))

bps, bpn, DEV = GE.bps, GE.bpn, GE.DEV
# device -> footprint (female vertical DIN for the slots; passives as usual)
FPMAP = {
    "DIN96":  ("Connector_DIN", "DIN41612_C_3x32_Female_Vertical_THT"),
    "CAP1":   ("Capacitor_THT", "C_Disc_D5.0mm_W2.5mm_P5.00mm"),
    "CAP":    ("Capacitor_THT", "C_Disc_D5.0mm_W2.5mm_P5.00mm"),
    "CAPP":   ("Capacitor_THT", "CP_Radial_D10.0mm_P5.00mm"),
    "RES":    ("Resistor_THT", "R_Axial_DIN0207_L6.3mm_D2.5mm_P10.16mm_Horizontal"),
    "SIP9":   ("Resistor_THT", "R_Array_SIP9"),
    "LED":    ("LED_THT", "LED_D5.0mm"),
    "TB4":    ("Connector_PinHeader_2.54mm", "PinHeader_1x04_P2.54mm_Vertical"),
}
def pad_of(dev, pinname):
    if dev == "DIN96": return pinname.lower()
    return str(DEV[dev]["pm"][pinname])

board = pcbnew.BOARD(); board.SetCopperLayerCount(4)
netobj = {}
for n in bpn:
    ni = pcbnew.NETINFO_ITEM(board, n); board.Add(ni); netobj[n] = ni

# board size from the slot grid (2 rows of 5, 101.6mm apart), generous margins
BW, BH = 560.0, 320.0
footp = {}; missing = []
for ref, spec in bps.items():
    dev, val = spec[0], spec[1]
    x, y = (spec[2], spec[3]) if len(spec) >= 4 else (0, 0)
    ent = FPMAP.get(dev) or FPMAP.get(DEV.get(dev, {}).get("pkg", ""))
    fp = pcbnew.FootprintLoad(FP + "/" + ent[0] + ".pretty", ent[1]) if ent else None
    if fp is None: missing.append("%s(%s)" % (ref, dev)); continue
    fp.SetReference(ref); fp.SetValue(val); fp.Value().SetVisible(False)
    board.Add(fp); footp[ref] = fp

# --- place: 10 slots in 2 rows of 5, sockets vertical; power + caps below -----
slotx = [40 + 100 * i for i in range(5)]
for i in range(10):
    ref = "J%d" % (i + 1)
    if ref not in footp: continue
    col, row = i % 5, i // 5
    fp = footp[ref]; fp.SetPosition(P(0, 0)); fp.SetOrientationDegrees(0)
    xs = [p.GetPosition().x for p in fp.Pads()]; ys = [p.GetPosition().y for p in fp.Pads()]
    cx = (min(xs) + max(xs)) // 2; cy = (min(ys) + max(ys)) // 2
    fp.SetPosition(VECTOR2I(mm(slotx[col]) - cx, mm(40 + row * 150) - cy))
# power + passives flow along the bottom
px = 30.0
for ref in footp:
    if ref.startswith("J") and ref[1:].isdigit() and int(ref[1:]) <= 10: continue
    fp = footp[ref]; fp.SetPosition(P(0, 0))
    xs = [p.GetPosition().x for p in fp.Pads()]; ys = [p.GetPosition().y for p in fp.Pads()]
    cx = (min(xs) + max(xs)) // 2; cy = (min(ys) + max(ys)) // 2
    fp.SetPosition(VECTOR2I(mm(px) - cx, mm(BH - 20) - cy)); px += 14.0

# --- assign nets ------------------------------------------------------------
bad = []
for net, mem in bpn.items():
    ni = netobj[net]
    for (ref, pin) in mem:
        if ref not in footp: continue
        pad = pad_of(bps[ref][0], pin)
        if not any(p.GetNumber() == pad and (p.SetNet(ni) or True) for p in footp[ref].Pads()):
            bad.append("%s.%s" % (ref, pin))

# outline + planes
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
    for x, y in [(1, 1), (BW - 1, 1), (BW - 1, BH - 1), (1, BH - 1)]: o.Append(mm(x), mm(y))
    board.Add(z)
pcbnew.ZONE_FILLER(board).Fill(board.Zones())

outdir = os.path.join(ROOT, "hardware", "backplane", "kicad"); os.makedirs(outdir, exist_ok=True)
out = os.path.join(outdir, "p8x-backplane.kicad_pcb")
pcbnew.SaveBoard(out, board)
print("wrote", out, "(%dx%dmm, %d/%d footprints)" % (BW, BH, len(footp), len(bps)))
if missing: print("  MISSING:", missing)
if bad: print("  PAD MISMATCH (%d):" % len(bad), bad[:10])
print("  NOTE: placed only -- NOT autorouted (10-slot bus routing is a follow-up).")
