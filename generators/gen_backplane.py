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

# Board size + placement TEMPLATE: single row of ten DIN slots, matching the
# Eagle "rev C compact" placement PDF (hardware/backplane/p8x-backplane-placement.pdf).
#   - 10 vertical DIN41612 sockets J1..J10 in one row across the board
#   - a 100nF cap C1..C10 above each slot, at the top edge
#   - LEFT column: J11 power entry + C11/C12 bulk electrolytics + R1/LED1 power LED
#   - RIGHT column: RN1 pull-up network + R2/R3/R4 + C13/C14 clock termination
#   - 6 mounting holes (3 top, 3 bottom)
BW, BH = 300.0, 128.0
SLOT_X0, SLOT_PITCH, SLOT_CY = 22.0, 25.0, 62.0        # J1 centre, pitch, row centre
footp = {}; missing = []
for ref, spec in bps.items():
    dev, val = spec[0], spec[1]
    x, y = (spec[2], spec[3]) if len(spec) >= 4 else (0, 0)
    ent = FPMAP.get(dev) or FPMAP.get(DEV.get(dev, {}).get("pkg", ""))
    fp = pcbnew.FootprintLoad(FP + "/" + ent[0] + ".pretty", ent[1]) if ent else None
    if fp is None: missing.append("%s(%s)" % (ref, dev)); continue
    fp.SetReference(ref); fp.SetValue(val); fp.Value().SetVisible(False)
    board.Add(fp); footp[ref] = fp

# --- place a footprint so its pad bounding-box centre lands at (x,y) mm ---------
def place(ref, x, y, rot=0):
    if ref not in footp: return
    fp = footp[ref]; fp.SetOrientationDegrees(rot); fp.SetPosition(P(0, 0))
    xs = [p.GetPosition().x for p in fp.Pads()]; ys = [p.GetPosition().y for p in fp.Pads()]
    cx = (min(xs) + max(xs)) // 2; cy = (min(ys) + max(ys)) // 2
    fp.SetPosition(VECTOR2I(mm(x) - cx, mm(y) - cy))

# ten slots in a single row (DIN sockets are natively tall), a 100nF cap above each
for i in range(10):
    sx = SLOT_X0 + SLOT_PITCH * i
    place("J%d" % (i + 1), sx, SLOT_CY)
    place("C%d" % (i + 1), sx, 12.0)                       # decoupling cap, top edge
# left column: power entry + bulk caps, power LED in the bottom-left corner
place("J11", 8.0, 42.0)                                    # PWR-5V header (natively tall)
place("C11", 9.0, 70.0); place("C12", 9.0, 92.0)           # 470uF bulk electrolytics
place("R1", 12.0, 118.0); place("LED1", 26.0, 118.0)       # power-on LED
# right column: wired-OR pull-up array + clock termination
place("RN1", 260.0, 60.0, 90)                              # 8x10K SIP (vertical)
place("R2", 279.0, 40.0); place("R3", 279.0, 60.0); place("R4", 279.0, 80.0)
place("C13", 293.0, 40.0); place("C14", 293.0, 60.0)

# --- silk: SLOT n under each connector (the PDF's slot labels) -----------------
def silk(txt, x, y, size=1.4):
    t = pcbnew.PCB_TEXT(board); t.SetText(txt); t.SetLayer(pcbnew.F_SilkS)
    t.SetPosition(P(x, y)); t.SetTextSize(VECTOR2I(mm(size), mm(size)))
    t.SetTextThickness(mm(size * 0.15)); board.Add(t)
for i in range(10):
    silk("SLOT %d" % (i + 1), SLOT_X0 + SLOT_PITCH * i - 6.0, 116.0)

# --- 6 mounting holes (3 top, 3 bottom), matching the template -----------------
MH = ("MountingHole", "MountingHole_3.2mm_M3")
for hx in (48.0, 150.0, 252.0):
    for hy in (6.0, 122.0):
        h = pcbnew.FootprintLoad(FP + "/" + MH[0] + ".pretty", MH[1])
        if h is None: continue
        h.SetPosition(P(hx, hy)); board.Add(h)

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
