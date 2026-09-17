#!/usr/bin/env python3
"""gen_xor.py -- generate the XOR trial board's KiCad PCB from scratch.

Run with KiCad's bundled Python (it imports pcbnew):

  PYK=/Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/3.9/bin/python3
  "$PYK" hardware/xor-trial/kicad/gen_xor.py

Emits xor_trial.kicad_pcb next to this file: one 74HC86 (gate 1 used), two
push-buttons with 10k pull-downs, an LED through 330R on the output, a 100nF
decoupling cap, and a 2-pin power header. Ground is a bottom-layer copper pour;
VCC and the signal nets are routed as top-layer tracks. GENERATORS ARE CANON --
edit here and re-run, do not hand-edit the .kicad_pcb.
"""
import os, sys, pcbnew
from pcbnew import VECTOR2I, wxPoint

HERE = os.path.dirname(os.path.abspath(__file__))
FP   = "/Applications/KiCad/KiCad.app/Contents/SharedSupport/footprints"
OUT  = os.path.join(HERE, "xor_trial.kicad_pcb")

def mm(v): return pcbnew.FromMM(v)
def P(x, y): return VECTOR2I(mm(x), mm(y))

board = pcbnew.BOARD()

# ---- nets -----------------------------------------------------------------
netnames = ["GND", "VCC", "N1A", "N1B", "N1Y", "NLED"]
nets = {}
for n in netnames:
    net = pcbnew.NETINFO_ITEM(board, n)
    board.Add(net)
    nets[n] = net

# ---- footprints: (ref, lib, name, x, y, rot, value) -----------------------
# positions place the footprint ANCHOR (pin 1 for the DIP / header) in mm.
PARTS = [
    ("U1",  "Package_DIP",               "DIP-14_W7.62mm",                                  27, 15,   0, "74HC86"),
    ("J1",  "Connector_PinHeader_2.54mm","PinHeader_1x02_P2.54mm_Vertical",                  6, 20,   0, "+5V/GND"),
    ("SW1", "Button_Switch_THT",         "SW_PUSH_6mm",                                     11,  4,   0, "PUSH"),
    ("SW2", "Button_Switch_THT",         "SW_PUSH_6mm",                                     41,  4,   0, "PUSH"),
    ("R1",  "Resistor_THT",              "R_Axial_DIN0207_L6.3mm_D2.5mm_P10.16mm_Horizontal",11, 12,  0, "10k"),
    ("R2",  "Resistor_THT",              "R_Axial_DIN0207_L6.3mm_D2.5mm_P10.16mm_Horizontal",41, 12,  0, "10k"),
    ("R3",  "Resistor_THT",              "R_Axial_DIN0207_L6.3mm_D2.5mm_P10.16mm_Horizontal",40, 24,  0, "330"),
    ("LED1","LED_THT",                   "LED_D5.0mm",                                      56, 24,  90, "LED"),
    ("C1",  "Capacitor_THT",             "C_Disc_D5.0mm_W2.5mm_P5.00mm",                    28,  9,   0, "100nF"),
]
fps = {}
for ref, lib, name, x, y, rot, val in PARTS:
    fp = pcbnew.FootprintLoad(FP + "/" + lib + ".pretty", name)
    if fp is None:
        sys.exit("could not load footprint %s:%s" % (lib, name))
    fp.SetReference(ref)
    fp.SetValue(val)
    fp.Value().SetVisible(False)               # keep silk to references only
    fp.SetPosition(P(x, y))
    if rot:
        fp.SetOrientationDegrees(rot)
    if ref in ("R1", "R2", "R3"):              # ref text below the body (clear of SW*)
        fp.Reference().SetPosition(P(x + 5, y + 3))
    board.Add(fp)
    fps[ref] = fp

# ---- assign pads to nets: (ref, pad-number, net) --------------------------
CONN = [
    ("J1","1","VCC"), ("J1","2","GND"),
    ("U1","14","VCC"), ("U1","7","GND"),
    ("U1","1","N1A"), ("U1","2","N1B"), ("U1","3","N1Y"),
    ("U1","4","GND"), ("U1","5","GND"), ("U1","9","GND"),
    ("U1","10","GND"), ("U1","12","GND"), ("U1","13","GND"),
    ("SW1","1","VCC"), ("SW1","2","N1A"),
    ("SW2","1","VCC"), ("SW2","2","N1B"),
    ("R1","1","N1A"), ("R1","2","GND"),
    ("R2","1","N1B"), ("R2","2","GND"),
    ("R3","1","N1Y"), ("R3","2","NLED"),
    ("LED1","2","NLED"), ("LED1","1","GND"),
    ("C1","1","VCC"), ("C1","2","GND"),
]
for ref, padnum, netname in CONN:
    net = nets[netname]
    hit = False
    for pad in fps[ref].Pads():
        if pad.GetNumber() == padnum:
            pad.SetNet(net); hit = True
    if not hit:
        sys.exit("no pad %s on %s" % (padnum, ref))

# ---- board outline (Edge.Cuts rectangle) ----------------------------------
def edge(x1, y1, x2, y2):
    seg = pcbnew.PCB_SHAPE(board)
    seg.SetShape(pcbnew.SHAPE_T_SEGMENT)
    seg.SetStart(P(x1, y1)); seg.SetEnd(P(x2, y2))
    seg.SetLayer(pcbnew.Edge_Cuts)
    seg.SetWidth(mm(0.15))
    board.Add(seg)
BX0, BY0, BX1, BY1 = 0, 0, 62, 44
edge(BX0, BY0, BX1, BY0); edge(BX1, BY0, BX1, BY1)
edge(BX1, BY1, BX0, BY1); edge(BX0, BY1, BX0, BY0)

# ---- routing: VCC + signals on top; GND is the bottom pour (THT pads reach it)
TRACK_W = mm(0.4)
def padpos(ref, num, idx=0):
    ps = [p for p in fps[ref].Pads() if p.GetNumber() == num]
    return ps[idx].GetPosition()
def trk(net, layer, *pts):                    # a polyline of tracks on one layer
    for a, b in zip(pts, pts[1:]):
        t = pcbnew.PCB_TRACK(board)
        t.SetStart(a if isinstance(a, pcbnew.VECTOR2I) else P(*a))
        t.SetEnd(b if isinstance(b, pcbnew.VECTOR2I) else P(*b))
        t.SetWidth(TRACK_W); t.SetLayer(layer); t.SetNet(net)
        board.Add(t)
def via(net, x, y):
    v = pcbnew.PCB_VIA(board)
    v.SetPosition(P(x, y)); v.SetDrill(mm(0.4)); v.SetWidth(mm(0.8))
    v.SetNet(net); board.Add(v)
    return v.GetPosition()

F = pcbnew.F_Cu; B = pcbnew.B_Cu
# VCC (top): J1.1 up the left edge, across the top (through SW1.1 & SW2.1 pads),
# with branches down to U1.14 and down to C1.1 -- all above U1's body, no pads crossed.
trk(nets["VCC"], F, padpos("J1","1"), P(6,4), P(11,4), P(17.5,4), P(41,4), P(47.5,4))
trk(nets["VCC"], F, P(34.6,4), padpos("U1","14"))          # branch down to pin 14
trk(nets["VCC"], F, P(30,4), padpos("C1","1"))             # branch down to C1
# the two same-number button pads are one net but not linked in the footprint --
# jumper them (SW*.1 VCC pads are already bridged by the VCC track above).
trk(nets["N1A"], F, padpos("SW1","2",0), padpos("SW1","2",1))
trk(nets["N1B"], F, padpos("SW2","2",0), padpos("SW2","2",1))
# N1A (top): SW1.2 down to R1.1, then out the LEFT of R1 (away from R1.2=GND) to U1.1
trk(nets["N1A"], F, padpos("SW1","2"), padpos("R1","1"))
trk(nets["N1A"], F, padpos("R1","1"), P(11,15), padpos("U1","1"))
# N1B: SW2.2 -> R2.1 (top); then a BOTTOM track (THT pads reach it, no vias) left of
# U1 to pin 2 -- avoids the GND pads and does not cross the top N1A track.
trk(nets["N1B"], F, padpos("SW2","2"), padpos("R2","1"))
trk(nets["N1B"], B, padpos("R2","1"), P(24,12), P(24,17.5), padpos("U1","2"))
# N1Y: U1.3 out the LEFT on the BOTTOM, then AROUND the bottom of U1 (not between
# the pin rows -- that skimmed the GND pins) up to R3.1.
trk(nets["N1Y"], B, padpos("U1","3"), P(24,20.1), P(24,32), P(40,32), padpos("R3","1"))
# NLED (top): R3.2 -> LED1.2 (anode), routed around LED1.1 (=GND) at (56,24)
trk(nets["NLED"], F, padpos("R3","2"), P(53,24), P(53,21.5), padpos("LED1","2"))

# ---- ground pour: a bottom-layer zone over the whole board ----------------
zone = pcbnew.ZONE(board)
zone.SetLayer(pcbnew.B_Cu)
zone.SetNet(nets["GND"])
zone.SetIsFilled(True)
outline = zone.Outline()
outline.NewOutline()
for x, y in [(0.5,0.5),(61.5,0.5),(61.5,43.5),(0.5,43.5)]:
    outline.Append(mm(x), mm(y))
board.Add(zone)

# fill the GND zone (clears around VCC/signal copper on the bottom)
filler = pcbnew.ZONE_FILLER(board)
filler.Fill(board.Zones())

pcbnew.SaveBoard(OUT, board)
# report unrouted (ratsnest) count via the connectivity engine
board.BuildConnectivity()
print("wrote", OUT)
print("footprints:", board.GetFootprints().GetCount() if hasattr(board.GetFootprints(),'GetCount') else len(list(board.GetFootprints())))
print("nets:", board.GetNetCount())
