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

# local copies of the netlist so the power-connector remap below doesn't mutate
# gen_eagle's module-level structures.
bps, bpn, DEV = dict(GE.bps), {k: list(v) for k, v in GE.bpn.items()}, GE.DEV
# device -> footprint (female vertical DIN for the slots; passives as usual)
FPMAP = {
    "DIN96":  ("Connector_DIN", "DIN41612_C_3x32_Female_Vertical_THT"),
    "CAP1":   ("Capacitor_THT", "C_Disc_D5.0mm_W2.5mm_P5.00mm"),
    "CAP":    ("Capacitor_THT", "C_Disc_D5.0mm_W2.5mm_P5.00mm"),
    "CAPP":   ("Capacitor_THT", "CP_Radial_D10.0mm_P5.00mm"),
    "RES":    ("Resistor_THT", "R_Axial_DIN0207_L6.3mm_D2.5mm_P10.16mm_Horizontal"),
    "SIP9":   ("Resistor_THT", "R_Array_SIP9"),
    "LED":    ("LED_THT", "LED_D5.0mm"),
    # Power entry: Phoenix Contact MSTBA 2,5/2-G-5,08 (Digikey 1729128) -- a 2-pos,
    # 5.08mm-pitch pluggable screw terminal block, ~12A. V+ on terminal 1, GND on 2.
    "PWR2":   ("Connector_Phoenix_MSTB",
               "PhoenixContact_MSTBA_2,5_2-G-5,08_1x02_P5.08mm_Horizontal"),
}
# Swap the power connector J11 from the old 4-pin header (TB4) to the 2-terminal
# Phoenix block: keep its placement/value, drop the doubled pins, and re-map its
# bus membership so pad 1 = V+ (VCC) and pad 2 = GND.
bps["J11"] = ("PWR2",) + tuple(bps["J11"][1:])
for _net in bpn: bpn[_net] = [(r, p) for (r, p) in bpn[_net] if r != "J11"]
bpn["VCC"].append(("J11", "1")); bpn["GND"].append(("J11", "2"))
def pad_of(dev, pinname):
    if dev == "DIN96": return pinname.lower()
    if dev not in DEV: return str(pinname)        # local pseudo-devices (e.g. PWR2)
    return str(DEV[dev]["pm"][pinname])

board = pcbnew.BOARD(); board.SetCopperLayerCount(4)
netobj = {}
for n in bpn:
    ni = pcbnew.NETINFO_ITEM(board, n); board.Add(ni); netobj[n] = ni

# Board size + placement: single row of ten DIN slots pushed to the LEFT, with
# ALL the peripheral parts gathered on the RIGHT where there is open room (the
# bulk electrolytics were cramped ~3.5mm from J1 in the old left-column layout).
#   - 10 vertical DIN41612 sockets J1..J10 in one row, hard against the left edge
#   - a 100nF cap C1..C10 above each slot, at the top edge
#   - RIGHT, inner column: RN1 pull-up network + R2/R3/R4 + C13/C14 clock termination
#   - RIGHT, outer column (roomy, by the board edge): J11 power entry, C11/C12
#     bulk electrolytics, R1/LED1 power LED
#   - 6 mounting holes (3 top, 3 bottom)
SLOT_X0, SLOT_PITCH, SLOT_CY = 14.0, 28.0, 62.0        # J1 centre, pitch, row centre
RX = SLOT_X0 + SLOT_PITCH * 9                           # J10 (last slot) centre
RCOL_A, RCOL_B = RX + 16.0, RX + 34.0                  # right inner (pull-ups) / outer (power)
BW, BH = RCOL_B + 18.0, 128.0                           # width leaves the bulk caps room to breathe
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
# right inner column: wired-OR pull-up array + clock termination (small parts)
place("RN1", RCOL_A, 28.0, 90)                             # 8x10K SIP (vertical)
place("R2", RCOL_A, 52.0); place("R3", RCOL_A, 66.0); place("R4", RCOL_A, 80.0)
place("C13", RCOL_A, 98.0); place("C14", RCOL_A, 112.0)
# right outer column (by the board edge, roomy): power entry + bulk caps + power LED
place("J11", RCOL_B + 1.0, 26.0, 90)                       # Phoenix 2-pos terminal block
place("C11", RCOL_B, 56.0); place("C12", RCOL_B, 80.0)     # 470uF bulk electrolytics
place("R1", RCOL_B - 6.0, 108.0); place("LED1", RCOL_B + 8.0, 108.0)   # power-on LED

# --- silk: SLOT n under each connector (the PDF's slot labels) -----------------
def silk(txt, x, y, size=1.4):
    t = pcbnew.PCB_TEXT(board); t.SetText(txt); t.SetLayer(pcbnew.F_SilkS)
    t.SetPosition(P(x, y)); t.SetTextSize(VECTOR2I(mm(size), mm(size)))
    t.SetTextThickness(mm(size * 0.15)); board.Add(t)
for i in range(10):
    silk("SLOT %d" % (i + 1), SLOT_X0 + SLOT_PITCH * i - 6.0, 116.0)

# --- 6 mounting holes (3 top, 3 bottom), matching the template -----------------
MH = ("MountingHole", "MountingHole_3.2mm_M3")
for hx in (BW * 0.15, BW * 0.5, BW * 0.85):
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
