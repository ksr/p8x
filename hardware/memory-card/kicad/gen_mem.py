#!/usr/bin/env python3
"""gen_mem.py -- generate the P8X MEMORY CARD as a KiCad PCB (rev F, 6K decode).

Run with KiCad's bundled Python (needs pcbnew):

  PYK=/Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/3.9/bin/python3
  "$PYK" hardware/memory-card/kicad/gen_mem.py

GENERATORS ARE CANON -- edit here and re-run, never hand-edit the .kicad_pcb.

NETLIST SOURCE. The functional netlist is the canonical one in
generators/gen_eagle.py (the `# MEMORY CARD rev E` section, built through the
shared card() helper -- connector J1, per-IC decoupling caps, IC power pins,
and the J1 bus wiring). We import that module (its EMIT guard means importing it
writes no files) and read CARDS["memory-card"].

REV F -- THE 6 KB ROM DECODE. The rev-E CAD decodes an 8 KB ROM ($0000-$1FFF),
which maps $1800-$1FFF to the (unwritable) ROM chip -- a build blocker once the
OS touches its scratch there (see the theory doc's ⚠ note). rev F corrects the
decode to a 6 KB ROM ($0000-$17FF) with $1800-$1FFF as RAM, matching the
emulator/OS. It adds NO new chips -- it rewires three spare gates:
    P      = AND(A11,A12)           on U9.4  (spare 74HCT08 gate)
    ROM!CE = OR(A13|A14|A15, P)     on U11.2 (spare 74HCT32 gate)
    S      = OR(A13|A14, P)         on U11.3 (spare 74HCT32 gate)
    -RAM2CE= NAND(!A15, S)          on U7.3  (its B input moves from Q to S)
so ROM answers only $0000-$17FF and U10 (low RAM) widens to $1800-$7FFF. The
transform is applied to the imported netlist below and asserted for sanity.

This script builds the board (footprints, nets, placement, GND pour, outline).
Routing is done afterwards by Freerouting via a Specctra DSN/SES round-trip
(see route.sh) -- neither kicad-cli nor the Eagle flow autoroutes.
"""
import os, sys, copy, pcbnew
from pcbnew import VECTOR2I

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
FP   = "/Applications/KiCad/KiCad.app/Contents/SharedSupport/footprints"
OUT  = os.path.join(HERE, "p8x-memory-card.kicad_pcb")
sys.path.insert(0, os.path.join(ROOT, "generators"))
import gen_eagle as GE

def mm(v): return pcbnew.FromMM(v)
def P(x, y): return VECTOR2I(mm(x), mm(y))

# ---- 1. pull the canonical netlist + apply the rev-F decode transform ------
_title, PARTS, NETS = GE.CARDS["memory-card"]
PARTS = copy.deepcopy(PARTS); NETS = copy.deepcopy(NETS)
DEV = GE.DEV

def _rm(net, *items): NETS[net] = [p for p in NETS[net] if p not in items]
def _add(net, *items): NETS.setdefault(net, []).extend(items)

def apply_revF():
    # untie the spare gates we are about to use from GND
    _rm("GND", ("U9","4A"),("U9","4B"),
               ("U11","2A"),("U11","2B"),("U11","3A"),("U11","3B"))
    _add("A11", ("U9","4A")); _add("A12", ("U9","4B"))     # AND inputs
    NETS["P"]      = [("U9","4Y"),("U11","2B"),("U11","3B")]   # A11*A12
    _rm("Q", ("U7","3B")); _add("Q", ("U11","3A"))            # Q -> OR3 too
    NETS["ROMOR3"] = [("U11","1Y"),("U11","2A")]              # A13|A14|A15 (was ROM8CE)
    del NETS["ROM8CE"]
    NETS["ROMCE"]  = [("U11","2Y"),("U1","!CE"),("U8","3A")]  # 6K ROM !CE (+ ROM LED sel)
    NETS["S"]      = [("U11","3Y"),("U7","3B")]               # A13|A14|(A11*A12) -> RAM2 NAND
apply_revF()

# sanity: no pad assigned to two nets; only the spare U11.4Y output floats
_owner = {}
for _net, _mem in NETS.items():
    for _k in _mem:
        assert _k not in _owner, "pad %s in two nets (%s,%s)" % (_k, _owner[_k], _net)
        _owner[_k] = _net
for _u in ("U7","U8","U9","U11"):
    _dev = PARTS[_u][0]
    _un = [pn for pn in DEV[_dev]["L"]+DEV[_dev]["R"] if (_u,pn) not in _owner]
    assert _un == (["4Y"] if _u == "U11" else []), "%s unexpected floats %s" % (_u, _un)

# ---- 2. device -> KiCad footprint, and pin-name -> pad-number --------------
FPMAP = {
    "MEM28K8": ("Package_DIP", "DIP-28_W15.24mm"),
    "74245":   ("Package_DIP", "DIP-20_W7.62mm"),
    "74138":   ("Package_DIP", "DIP-16_W7.62mm"),
    "7430":    ("Package_DIP", "DIP-14_W7.62mm"),
    "GATES14": ("Package_DIP", "DIP-14_W7.62mm"),
    "CAP1":    ("Capacitor_THT", "C_Disc_D5.0mm_W2.5mm_P5.00mm"),
    "LED":     ("LED_THT", "LED_D5.0mm"),
    "RES":     ("Resistor_THT", "R_Axial_DIN0207_L6.3mm_D2.5mm_P10.16mm_Horizontal"),
    "HDR3":    ("Connector_PinHeader_2.54mm", "PinHeader_1x03_P2.54mm_Vertical"),
    "DIN96C":  ("Connector_DIN", "DIN41612_C_3x32_Male_Horizontal_THT"),
}
def pad_of(ref, pinname):
    dev = PARTS[ref][0]
    if dev == "DIN96C":                 # footprint pads are lowercase a1..c32
        return pinname.lower()
    return str(DEV[dev]["pm"][pinname])

# ---- 3. board, nets, footprints -------------------------------------------
board = pcbnew.BOARD()
board.SetCopperLayerCount(4)              # 4-layer: F.Cu / In1(GND) / In2(VCC) / B.Cu
netobj = {}
for n in NETS:
    ni = pcbnew.NETINFO_ITEM(board, n); board.Add(ni); netobj[n] = ni

def load_fp(ref):
    lib, name = FPMAP[PARTS[ref][0]]
    fp = pcbnew.FootprintLoad(FP + "/" + lib + ".pretty", name)
    if fp is None:
        sys.exit("footprint missing: %s:%s (for %s)" % (lib, name, ref))
    fp.SetReference(ref)
    fp.SetValue(PARTS[ref][1])
    return fp

# The card is a Eurocard: its HEIGHT is fixed at 100mm by the DIN41612 connector
# and the backplane slot. The WIDTH (the card's depth, projecting out from the
# backplane) is free -- widened to 200mm here for routing headroom on this dense
# bus board (the user opted for the larger card; it does not affect slot pitch).
BW, BH = 280.0, 140.0   # uniform card size (matches the generic cards)

# Explicit placement (mm centre, rotation) for EVERY part, laid out in clear
# lanes so nothing overlaps (final fine-layout is the router's/human's job, but
# the parts must not collide):
#   - J1 (DIN41612) rotated 90 deg at the left edge, pins into the board;
#   - the three memories in a vertical-DIP row across the middle so the shared
#     A0-A14 bus runs straight past them;
#   - the data buffer + the two DOE/DLD decoders in a column by the connector;
#   - the gate chips in a row along the bottom;
#   - each IC's 100nF cap in the open lane just below the memories / above the
#     gates; the LED bank (resistor + LED pairs) + WP jumper along the top edge.
# the DIP chips are rotated 90 deg (long axis horizontal) so they are only ~17mm
# tall -- three rows (memories / buffer+decoders / gates) then fit with a clear
# cap lane, instead of the 39mm-tall vertical DIP-28s crowding everything.
# ORIENTATION: the card plugs into a table-parallel backplane, so the connector
# edge (left, x=0) is the BOTTOM when mounted and the OPPOSITE edge (right,
# x=200) is the TOP. The status LEDs therefore run down the RIGHT edge so they
# sit across the top of the mounted card. Signal flow: connector (left) ->
# buffer/decoders -> memories -> gates, with the LED bank at the far right.
# NOTE: DIP footprints anchor at pin 1, not their centre, so all coordinates
# below are TRUE CENTRES and place_centered() compensates for each footprint's
# pad-bbox offset. Rows: memories / buffer+decoders / gates, connector left,
# LEDs down the right (top-when-mounted) edge.
PLACE = {
    # memory row (rot 90): ROM, low-RAM, high-RAM share A0-A14 straight across
    "U1":  (52,  26, 90), "U10": (96,  26, 90), "U2":  (140, 26, 90),
    # buffer + decoders row
    "U3":  (52,  54, 90),  # 74245 data buffer (near connector data bus)
    "U5":  (98,  54, 90),  # 74138 DOE decode
    "U6":  (140, 54, 90),  # 74138 DLD decode
    # gate row
    "U4":  (48,  82, 90),  # 7430 I/O-page NAND
    "U7":  (76,  82, 90),  # 74HC00
    "U8":  (104, 82, 90),  # 74HC32
    "U9":  (132, 82, 90),  # 74HC08
    "U11": (158, 82, 90),  # 74HC32 (rev E/F decode)
    # write-protect jumper -- clear area near the ROM, above the gate row
    "JWP": (162, 62, 90),
}
# Each 100nF decoupling cap sits just ABOVE its own IC (house convention: cap at
# the top of the chip, horizontal / parallel to the chip's top edge, right next to
# it). Positions are computed after placement from each chip's top pad edge.
CAPFOR = {"C1":"U1", "C2":"U2", "C3":"U3", "C4":"U4", "C5":"U5", "C6":"U6",
          "C7":"U7", "C8":"U8", "C9":"U9", "C10":"U10", "C11":"U11"}
# LED bank down the RIGHT (top-when-mounted) edge: each series resistor
# (horizontal, inboard) feeds an LED near the edge, rotated 180 so its anode
# (pad 2) faces the resistor's pad 2 (same net). A silk label sits between the
# resistor and the LED. 14mm vertical pitch.
LEDPAIR = [("RP1","LED3","PWR"), ("RS1","LED2","ROM"), ("RS2","LED4","RAMH"),
           ("RS3","LED5","RD"),  ("RS4","LED6","WR"),  ("RS5","LED7","RAML")]
for i, (rs, led, _lbl) in enumerate(LEDPAIR):
    yr = 30 + i*14
    PLACE[rs]  = (250, yr,   0)
    PLACE[led] = (271, yr, 180)

footp = {}
for ref in PARTS:
    fp = load_fp(ref); board.Add(fp); footp[ref] = fp
missing = [r for r in PARTS if r not in PLACE and r != "J1" and r not in CAPFOR]
assert not missing, "unplaced parts: %s" % missing

def place_centered(fp, x, y, rot):
    """Place so the footprint's pad-bbox CENTRE lands at (x,y) mm, after rot."""
    fp.SetPosition(P(0, 0))
    if rot: fp.SetOrientationDegrees(rot)
    xs = [p.GetPosition().x for p in fp.Pads()]
    ys = [p.GetPosition().y for p in fp.Pads()]
    cx = (min(xs) + max(xs)) // 2; cy = (min(ys) + max(ys)) // 2
    fp.SetPosition(VECTOR2I(mm(x) - cx, mm(y) - cy))

for ref, (x, y, rot) in PLACE.items():
    place_centered(footp[ref], x, y, rot)

# decoupling caps: horizontal, centred on their IC's x, 4mm above the IC's top
# pad row (cap parallel to the chip's top edge, hugging it -- house convention).
for cap, chip in CAPFOR.items():
    cfp = footp[chip]
    cxs = [p.GetPosition().x for p in cfp.Pads()]
    cys = [p.GetPosition().y for p in cfp.Pads()]
    ic_cx = pcbnew.ToMM((min(cxs) + max(cxs)) // 2)
    ic_top = pcbnew.ToMM(min(cys))          # smallest y = top edge in layout
    place_centered(footp[cap], ic_cx, ic_top - 4.5, 0)

# J1 (DIN41612) hugs the left edge: rot 90, its left pad column 4mm from the edge
# (the connector body overhangs the edge, as a card edge connector should) and
# its pads centred in the 100mm height.
_pj = footp["J1"]
_pj.SetPosition(P(0, 0)); _pj.SetOrientationDegrees(90)
_xs = [p.GetPosition().x for p in _pj.Pads()]
_ys = [p.GetPosition().y for p in _pj.Pads()]
_pj.SetPosition(VECTOR2I(mm(4) - min(_xs), mm(BH/2) - (min(_ys) + max(_ys)) // 2))

# ---- 3b. put each part's VALUE on the silkscreen ---------------------------
# There is plenty of room, so show values (the ICs' part numbers differ; the
# passives are uniform but shown anyway). Reference stays where KiCad put it; the
# value goes to a clear spot: below the ICs, right of the caps (open lane there),
# below the resistors. J1/JWP values are left off (ref + the pin silk say enough).
def _txt(field, x, y, just, size=0.9):
    field.SetVisible(True); field.SetLayer(pcbnew.F_SilkS)
    field.SetTextSize(pcbnew.VECTOR2I(mm(size), mm(size)))
    field.SetTextThickness(mm(0.15)); field.SetHorizJustify(just)
    field.SetPosition(VECTOR2I(x, y))
C_ = pcbnew.GR_TEXT_H_ALIGN_CENTER; L_ = pcbnew.GR_TEXT_H_ALIGN_LEFT
for ref in PARTS:
    if ref in ("J1", "JWP"):
        footp[ref].Value().SetVisible(False); continue
    fp = footp[ref]
    xs = [p.GetPosition().x for p in fp.Pads()]; ys = [p.GetPosition().y for p in fp.Pads()]
    cx = (min(xs) + max(xs)) // 2; cy = (min(ys) + max(ys)) // 2
    if ref.startswith("C"):                        # cap: value to the right (open lane)
        _txt(fp.Value(), max(xs) + mm(1.5), cy, L_)
    elif ref.startswith("U"):                      # IC: part number below the body
        _txt(fp.Value(), cx, max(ys) + mm(4.6), C_)
    elif ref.startswith("LED"):                    # LED: colour to the right; the
        _txt(fp.Value(), max(xs) + mm(1.3), cy, L_)   # function label (PWR/ROM/..) is
        fp.Reference().SetVisible(False)              # a better ID than "LEDn" here
    else:                                          # resistor: ref above, value below
        _txt(fp.Reference(), cx, cy - mm(3.2), C_)
        _txt(fp.Value(), cx, cy + mm(3.2), C_)

# ---- 4. assign pads to nets ------------------------------------------------
for net, mem in NETS.items():
    ni = netobj[net]
    for (ref, pinname) in mem:
        pad = pad_of(ref, pinname)
        hit = False
        for p in footp[ref].Pads():
            if p.GetNumber() == pad:
                p.SetNet(ni); hit = True
        if not hit:
            sys.exit("no pad %r on %s (net %s)" % (pad, ref, net))

# ---- 5. board outline (Edge.Cuts rectangle) --------------------------------
def edge(x1, y1, x2, y2):
    s = pcbnew.PCB_SHAPE(board); s.SetShape(pcbnew.SHAPE_T_SEGMENT)
    s.SetStart(P(x1, y1)); s.SetEnd(P(x2, y2))
    s.SetLayer(pcbnew.Edge_Cuts); s.SetWidth(mm(0.15)); board.Add(s)
edge(0, 0, BW, 0); edge(BW, 0, BW, BH); edge(BW, BH, 0, BH); edge(0, BH, 0, 0)

# ---- 5b. silkscreen LED labels (between each resistor and its LED) ----------
def silk(s, x, y, size=1.4):
    t = pcbnew.PCB_TEXT(board)
    t.SetText(s); t.SetPosition(P(x, y)); t.SetLayer(pcbnew.F_SilkS)
    t.SetTextThickness(mm(0.25))
    t.SetTextSize(pcbnew.VECTOR2I(mm(size), mm(size)))
    t.SetHorizJustify(pcbnew.GR_TEXT_H_ALIGN_CENTER)
    board.Add(t)
for i, (_rs, _led, label) in enumerate(LEDPAIR):
    silk(label, 262, 30 + i*14 - 2.0)      # just above each LED, inboard of the edge

# JWP ROM write-protect jumper: mark the two shunt positions. Pins (row): 1=-WE,
# 2=ROMWE (common, to U1 !WE), 3=VCC. Shunt 1-2 = ROM WRITABLE; 2-3 = PROTECTED.
_jp = {p.GetNumber(): p.GetPosition() for p in footp["JWP"].Pads()}
silk("WR", pcbnew.ToMM(_jp["1"].x), pcbnew.ToMM(_jp["1"].y) + 3.3, size=1.0)  # 1-2
silk("WP", pcbnew.ToMM(_jp["3"].x), pcbnew.ToMM(_jp["3"].y) + 3.3, size=1.0)  # 2-3

# ---- 6. internal power planes: In1.Cu = GND, In2.Cu = VCC ------------------
# THT pads penetrate every layer, so each GND/VCC pin connects to its plane with
# no routing at all -- which is why this board goes to 4 layers. Freerouting then
# only has to route the signal nets, on the two full outer layers.
def plane(layer, net):
    z = pcbnew.ZONE(board); z.SetLayer(layer); z.SetNet(netobj[net])
    z.SetIsFilled(True)
    z.SetPadConnection(pcbnew.ZONE_CONNECTION_FULL)   # solid bond -- it's a plane
    z.SetIslandRemovalMode(pcbnew.ISLAND_REMOVAL_MODE_ALWAYS)  # drop orphan slivers
    z.SetLocalClearance(mm(0.2))   # tight, so the pour threads into pad pockets
    z.SetMinThickness(mm(0.13))    # thin necks survive -> plane stays one piece
    o = z.Outline(); o.NewOutline()
    for x, y in [(1, 1), (BW-1, 1), (BW-1, BH-1), (1, BH-1)]:
        o.Append(mm(x), mm(y))
    board.Add(z)
plane(pcbnew.In1_Cu, "GND")
plane(pcbnew.In2_Cu, "VCC")
pcbnew.ZONE_FILLER(board).Fill(board.Zones())

pcbnew.SaveBoard(OUT, board)
board.BuildConnectivity()
print("wrote", OUT)
print("footprints:", len(list(board.GetFootprints())), " nets:", board.GetNetCount())
