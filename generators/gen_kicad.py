#!/usr/bin/env python3
"""gen_kicad.py -- generic KiCad 4-layer board builder for a gen_eagle card.

    PYK=/Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/3.9/bin/python3
    "$PYK" generators/gen_kicad.py <cardname>

Turns any card defined in generators/gen_eagle.py (its CARDS netlist) into a
KiCad board at hardware/<cardname>/kicad/p8x-<cardname>.kicad_pcb, to the same
standard as the memory card: 210x100mm-class 4-layer (F/B signals, In1=GND,
In2=VCC planes), a bypass cap hugging the top of each IC, a labelled LED /
resistor / jumper bank down the right (top-when-mounted) edge, and part values +
labels on the silkscreen. Routing is done afterwards by Freerouting (see the
per-card route pipeline). GENERATORS ARE CANON.

Footprints for exotic parts are SUBSTITUTED with the closest standard KiCad
footprint and flagged (printed + noted in the per-card README).
"""
import os, sys, math, pcbnew
from pcbnew import VECTOR2I
import silk_labels as SL

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
GENE = os.path.join(ROOT, "generators", "gen_eagle.py")
FP   = "/Applications/KiCad/KiCad.app/Contents/SharedSupport/footprints"
FPLOCAL = os.path.join(os.path.dirname(os.path.abspath(__file__)), "footprints", "p8x.pretty")

def mm(v): return pcbnew.FromMM(float(v))
def P(x, y): return VECTOR2I(mm(x), mm(y))

# ---- load gen_eagle, capturing the per-card labels + IC->cap mapping --------
def load_gene():
    src = open(GENE).read()
    anchor = '    sch={}; order=[r for r in parts if r!="J1"]'
    inject = ('    _CARDLABELS[name]=dict(lab); '
              '_CARDCAPS[name]=dict(zip(icrefs, decap_ref))\n' + anchor)
    assert anchor in src, "gen_eagle card() anchor not found"
    src = src.replace(anchor, inject, 1)
    ns = {"_CARDLABELS": {}, "_CARDCAPS": {}, "__name__": "gen_eagle_kicad"}
    exec(compile(src, GENE, "exec"), ns)
    return ns
GN = load_gene()
DEV = GN["DEV"]; CARDS = GN["CARDS"]
CARDLABELS = GN["_CARDLABELS"]; CARDCAPS = GN["_CARDCAPS"]

# ---- package -> KiCad footprint (SUB = a flagged substitution) --------------
DIP = "Package_DIP"
FPMAP = {
    "DIP8":   (DIP, "DIP-8_W7.62mm"),   "DIP14": (DIP, "DIP-14_W7.62mm"),
    "DIP16":  (DIP, "DIP-16_W7.62mm"),  "DIP20": (DIP, "DIP-20_W7.62mm"),
    "DIP24N": (DIP, "DIP-24_W7.62mm"),  "DIP24W": (DIP, "DIP-24_W15.24mm"),
    "DIP28N": (DIP, "DIP-28_W7.62mm"),  "DIP28W": (DIP, "DIP-28_W15.24mm"),
    "DIP40":  (DIP, "DIP-40_W15.24mm"),
    "C_DISC1":(("Capacitor_THT", "C_Disc_D5.0mm_W2.5mm_P5.00mm")),
    "C_DISC": (("Capacitor_THT", "C_Disc_D5.0mm_W2.5mm_P5.00mm")),
    "LED5":   ("LED_THT", "LED_D5.0mm"),
    "R_AXIAL":("Resistor_THT", "R_Axial_DIN0207_L6.3mm_D2.5mm_P10.16mm_Horizontal"),
    "HDR3":   ("Connector_PinHeader_2.54mm", "PinHeader_1x03_P2.54mm_Vertical"),
    "HDR4":   ("Connector_PinHeader_2.54mm", "PinHeader_1x04_P2.54mm_Vertical"),
    "HDR10":  ("Connector_PinHeader_2.54mm", "PinHeader_1x10_P2.54mm_Vertical"),
    "MABC96R":("Connector_DIN", "DIN41612_C_3x32_Male_Horizontal_THT"),
    "DSUB9":  ("Connector_Dsub", "DSUB-9_Socket_Horizontal_P2.77x2.54mm_EdgePinOffset9.40mm"),
    "HDR2X3": ("Connector_PinHeader_2.54mm", "PinHeader_2x03_P2.54mm_Vertical"),
    # ---- substitutions (closest standard footprint) ----
    "MINIDIN6":("__LOCAL__", "MiniDIN6_RA_PS2", "custom PS/2 mini-DIN-6 footprint (from vendor drawing -- VERIFY vs part)"),
    "HDR40":  ("Connector_PinHeader_2.54mm", "PinHeader_2x20_P2.54mm_Vertical", "SUB 2x20 header"),
    "OSC4":   ("Oscillator", "Oscillator_DIP-14", "SUB DIP-14 can oscillator"),
    "SIP9":   ("Resistor_THT", "R_Array_SIP9", "SUB bussed SIP-9 R-network"),
    "SIP16":  ("Connector_PinHeader_2.54mm", "PinHeader_1x16_P2.54mm_Vertical", "SUB 1x16 SIP (isolated R-net)"),
    "CP_RADIAL": ("Capacitor_THT", "CP_Radial_D8.0mm_P3.50mm", "SUB radial electrolytic / coin"),
    "SW2P":   ("Button_Switch_THT", "SW_PUSH_6mm", "SUB 6mm tact switch"),
    # the real module footprint (2026-10-24): rows 17.78 mm apart, Pico pin order.
    # The 2x20 header substituted before had rows 2.54 mm apart and odd/even
    # numbering, so a Pico could not have been fitted.
    "PICO40": ("Module", "RaspberryPi_Pico_Common_THT"),
}
# device-name overrides where the package alone is ambiguous
DEV_FP = {
    "DIP8SW": ("Button_Switch_THT", "SW_DIP_SPSTx08_Slide_9.78x22.5mm_W7.62mm_P2.54mm", "SUB 8-way DIP switch"),
    "IDE40":  ("Connector_IDC", "IDC-Header_2x20_P2.54mm_Vertical", "SUB 2x20 IDC (40-pin IDE)"),
    "XTAL32": ("Crystal", "Crystal_Round_D3.0mm_Vertical", "SUB 32kHz round crystal"),
    "LEDARR8":("Package_DIP", "DIP-16_W7.62mm", "SUB DIP-16 (8-LED bargraph)"),
    "RNISO8": ("Connector_PinHeader_2.54mm", "PinHeader_1x16_P2.54mm_Vertical", "SUB 1x16 SIP (isolated 8xR)"),
    "RNISO8D":("Package_DIP", "DIP-16_W7.62mm", "SUB DIP-16 isolated R-net"),
    # CR2032 (20 mm) through-hole holder (2026-10-24; the Keystone 3000 used before
    # holds a 12 mm cell and is surface-mount)
    "COIN":   ("Battery", "BatteryHolder_Keystone_103_1x20mm"),
}
SUBS = []   # collected substitutions to report
def footprint_for(ref, dev):
    if dev in DEV_FP:
        lib, name, *note = DEV_FP[dev]
    else:
        pkg = DEV[dev]["pkg"]
        ent = FPMAP.get(pkg)
        if ent is None:
            return None
        lib, name, *note = ent
    if note:
        SUBS.append("%s (%s): %s -> %s" % (ref, dev, note[0], name))
    return lib, name

# ---- part classification ----------------------------------------------------
def classify(dev):
    pkg = DEV[dev]["pkg"]
    if dev == "DIN96C":            return "conn"
    if dev in ("CAP1",):           return "decap"
    if dev in ("CAP", "CP_RADIAL", "XTAL32"): return "misc"
    if dev == "LED":               return "led"
    if dev == "RES":               return "res"
    if dev.startswith("HDR") or dev == "SW2": return "jumper"
    if dev in ("DIP8SW",):         return "jumper"
    if "DIP" in pkg:               return "ic"
    if pkg in ("IDE40", "HDR40", "PICO40"): return "bigconn"
    return "misc"

def pad_of(ref, dev, pinname):
    if dev == "DIN96C":
        return pinname.lower()
    return str(DEV[dev]["pm"][pinname])

# ---- geometry helpers -------------------------------------------------------
def pad_bbox(fp):
    xs = [p.GetPosition().x for p in fp.Pads()]
    ys = [p.GetPosition().y for p in fp.Pads()]
    return min(xs), min(ys), max(xs), max(ys)

def place_centered(fp, x_mm, y_mm, rot=0):
    fp.SetPosition(P(0, 0))
    if rot: fp.SetOrientationDegrees(rot)
    x0, y0, x1, y1 = pad_bbox(fp)
    fp.SetPosition(VECTOR2I(mm(x_mm) - (x0 + x1) // 2, mm(y_mm) - (y0 + y1) // 2))

def size_after(fp, rot):
    """(w,h) in mm for placement spacing -- use the COURTYARD extent (part body),
    not just pads, so wide-body parts (oscillators, connectors) don't overlap."""
    fp.SetPosition(P(0, 0))
    if rot: fp.SetOrientationDegrees(rot)
    try:
        bb = fp.GetCourtyard(pcbnew.F_CrtYd).BBox()
        w, h = pcbnew.ToMM(bb.GetWidth()), pcbnew.ToMM(bb.GetHeight())
        if w > 0.5 and h > 0.5:
            return w, h
    except Exception:
        pass
    x0, y0, x1, y1 = pad_bbox(fp)
    return pcbnew.ToMM(x1 - x0), pcbnew.ToMM(y1 - y0)

# ---- the build --------------------------------------------------------------
BH = 140.0   # connector-edge dimension (the DIN41612 is ~94mm; extra room = more rows)
STD_W = 280.0   # uniform card depth (mm); with BH=140 fits the largest card

# ---- silkscreen labels (silk_labels.py does the placing) ---------------------
# Function labels for the parts that need one (LEDs, switches, buttons, jumpers,
# cable connectors) come from gen_eagle's per-card labels, with the additions and
# corrections below; positions name what each jumper / switch position selects.
LABELLED_DEVS = {"LED", "SW2", "DIP8SW", "LEDARR8", "DSUB9F", "MINIDIN6", "IDE40", "PICO"}
COLOURS = {"GRN", "YEL", "RED"}
# a bar's end bits, printed right of the bar on the rows of anode 1 (top) and
# anode 8 (bottom): each row's right-hand pin is that segment's cathode
_BITS = lambda lo: [(("1", "16"), str(lo), "right"), (("8", "9"), str(lo + 7), "right")]
SILK = {
    "io-card": {
        "labels": {"SW1": "IN $FF00 ON=0", "JP1": "SER1 RX/TX", "JP2": "SER2 RX/TX",
                   "LA1": "OUT $FF02", "LM3": "D0-7", "LM1": "A0-7", "LM2": "A8-15",
                   "DB9A": "SERIAL 1", "DB9B": "SERIAL 2", "LED4": "I/O SEL",
                   "J3": "RTC 3-WIRE"},
        # JP1/JP2: centre pins 3/4 are the MAX232 side; shunts 1-3 + 2-4 = straight
        # (DTE), 3-5 + 4-6 = crossed (null-modem). SW1 switch n drives D(n-1).
        "positions": {"JP1": [(("1", "2"), "DTE"), (("5", "6"), "NULL")],
                      "JP2": [(("1", "2"), "DTE"), (("5", "6"), "NULL")],
                      "SW1": [((str(i),), "D%d" % (i - 1), "left") for i in range(1, 9)],
                      "LA1": _BITS(0), "LM3": _BITS(0), "LM1": _BITS(0), "LM2": _BITS(8)},
    },
    "control-card": {
        # JP1 (2x3): a shunt on 1-2 = 4 MHz, 3-4 = 2 MHz, 5-6 = 1 MHz (even pins = CLKRAW)
        "labels": {"JP1": "CLOCK"},
        "positions": {"JP1": [(("1", "2"), "4M", "above"), (("3", "4"), "2M", "above"),
                              (("5", "6"), "1M", "above")]},
    },
    "bustest-card": {"labels": {"A1": "PICO (USB)"}},
    "ps2-card": {"labels": {"JICSP": "ICSP", "PS2A": "KEYBOARD", "PS2B": "MOUSE"}},
    "cf-card": {"labels": {"J2": "CF 0 $FF10", "J5": "CF 1 $FF18"}},
    "backplane": {"labels": {"LED1": "PWR", "J11": "POWER IN"},
                  "positions": {"J11": [(("1",), "+5V"), (("2",), "GND")]}},
}

def silk_spec(name, parts):
    """-> (labels, positions) for silk_labels.label_board."""
    spec = SILK.get(name, {}); lab = CARDLABELS.get(name, {})
    labels = {}
    for ref, (dev, val) in parts.items():
        if not (dev in LABELLED_DEVS or dev.startswith(("HDR", "JMP")) or ref.startswith(("JP", "SW"))):
            continue
        t = lab.get(ref)
        if t in COLOURS: t = val            # bus test card: function in the value, colour in the label
        if t: labels[ref] = t
    labels.update(spec.get("labels", {}))
    return labels, spec.get("positions", {})

# Parts pinned to a fixed spot instead of the flow: card -> {ref: (x, y, rot)},
# (x, y) = centre of the part's pads in mm. For modules and other parts whose
# position the flow cannot judge.
PINNED = {
    # Pico on the bottom edge, upright and rotated 180 so its USB end (pins 1/40)
    # faces off the board: pad rows 48.26 mm long, pin-1 row 4.5 mm from the edge
    # (~1.4 mm board + ~1.3 mm USB overhang beyond it), clear of the bus edge and
    # of the LED bank on the front edge (2026-10-24; it sat 25 mm in from the top
    # edge beside J1).
    # The probe header (cable to the probe leads) lies along the bottom edge left
    # of the Pico (2026-10-24; it sat mid-board).
    "bustest-card": {"A1": (150.5, BH - 4.5 - 48.26 / 2, 180),
                     "J2": (105.0, BH - 9.0, 90)},
    # Push buttons on the front edge (opposite the bus) under the status LEDs, and
    # the clock-select jumper on the bottom edge below the oscillator X1 (2026-10-24;
    # all four sat mid-board).
    "control-card": {"SWR": (268.0, 52.0, 0), "SWS": (268.0, 68.0, 0),
                     "SWT": (268.0, 84.0, 0), "JP1": (66.0, BH - 10.0, 90)},
}
SCREW_KEEPOUT_R = 4.0   # radius (mm) of the copper keepout around each DIN mounting hole

def add_mounting_keepouts(board, footp, r=SCREW_KEEPOUT_R, layers=None):
    """Ring every DIN-connector mounting hole (NPTH) with a copper keepout so a
    METAL screw can secure the connector without shorting to a trace or a plane.
    Rule area on all copper layers: no fill, no tracks, no vias. Must run BEFORE
    the plane fill and the DSN export so both the pour and Freerouting avoid it."""
    if layers is None:
        layers = (pcbnew.F_Cu, pcbnew.In1_Cu, pcbnew.In2_Cu, pcbnew.B_Cu)
    n = 0
    for fp in (footp.values() if isinstance(footp, dict) else footp):
        # only the DIN edge/socket connectors carry the screw holes we care about
        if "DIN41612" not in str(fp.GetFPIDAsString()): continue
        for p in fp.Pads():
            if p.GetAttribute() != pcbnew.PAD_ATTRIB_NPTH: continue
            cx = pcbnew.ToMM(p.GetPosition().x); cy = pcbnew.ToMM(p.GetPosition().y)
            z = pcbnew.ZONE(board)
            ls = pcbnew.LSET()
            for lyr in layers: ls.AddLayer(lyr)
            z.SetLayerSet(ls)
            z.SetIsRuleArea(True)
            z.SetDoNotAllowZoneFills(True)   # planes pull back from the hole
            z.SetDoNotAllowTracks(True)
            z.SetDoNotAllowVias(True)
            z.SetDoNotAllowPads(False)       # allow the connector's own NPTH hole (no copper) inside
            z.SetDoNotAllowFootprints(False)
            o = z.Outline(); o.NewOutline()
            for i in range(32):
                a = 2 * math.pi * i / 32
                o.Append(mm(cx + r * math.cos(a)), mm(cy + r * math.sin(a)))
            board.Add(z); n += 1
    return n

def build_card(name):
    title, parts, nets = CARDS[name]
    labels = CARDLABELS.get(name, {}); capfor = CARDCAPS.get(name, {})
    invcap = {c: u for u, c in capfor.items()}         # cap_ref -> its IC
    cls = {ref: classify(dev) for ref, (dev, v) in parts.items()}

    board = pcbnew.BOARD(); board.SetCopperLayerCount(4)
    netobj = {}
    for n in nets:
        ni = pcbnew.NETINFO_ITEM(board, n); board.Add(ni); netobj[n] = ni

    footp = {}; missing = []
    for ref, (dev, val) in parts.items():
        spec = footprint_for(ref, dev)
        libdir = FPLOCAL if (spec and spec[0] == "__LOCAL__") else (FP + "/" + spec[0] + ".pretty" if spec else None)
        fp = pcbnew.FootprintLoad(libdir, spec[1]) if spec else None
        if fp is None:
            missing.append("%s (%s/%s)" % (ref, dev, DEV[dev]["pkg"])); continue
        fp.SetReference(ref); fp.SetValue(val); board.Add(fp); footp[ref] = fp

    # --- UNIFIED courtyard-spaced flow for every part (no fragile fixed bank) --
    # ICs rotated 90 with their decoupling cap hugging the top edge; LEDs,
    # resistors, jumpers, switches and misc parts flow inline in the same rows,
    # each spaced by its real courtyard so nothing ever overlaps. Order groups
    # like parts so the LED/jumper cluster stays together (labelled in silk).
    placed = set()
    # STATUS LEDs (+ their series resistors) go in a bank down the RIGHT edge
    # (opposite the bus connector). Find each LED's resistor via its anode net.
    leds = [r for r in parts if cls[r] == "led"]
    led_res = {}; _used = set()
    for led in leds:
        anet = next((n for n, mem in nets.items() if (led, "A") in mem), None)
        if anet:
            for (r2, _p) in nets[anet]:
                if r2 != led and cls.get(r2) == "res" and r2 not in _used:
                    led_res[led] = r2; _used.add(r2); break   # each resistor -> one LED
    bank_res = set(led_res.values())
    # reserve the right strip: compute how many LED columns are needed so the grid
    # never runs into the bank (each column ~20mm; ~12 LEDs fit a 140mm column).
    per_col = max(1, int((BH - 16) / 11))
    ncol = max(1, math.ceil(len(leds) / per_col)) if leds else 0
    BANKW = ncol * 26.0 + 8.0 if leds else 6.0
    # everything else flows in the left area, courtyard-spaced (never overlaps)
    pinned = PINNED.get(name, {})
    for r, (px_, py_, prot) in pinned.items():
        if r in footp: place_centered(footp[r], px_, py_, prot); placed.add(r)
    grid = ([r for r in parts if cls[r] == "ic"]
            + [r for r in parts if cls[r] == "bigconn"]
            + [r for r in parts if cls[r] == "misc"]
            + [r for r in parts if cls[r] == "res" and r not in bank_res]
            + [r for r in parts if cls[r] == "jumper"])
    grid = [r for r in grid if r not in pinned]
    GX0 = 32.0; GAP = 5.0; CAPH = 6.0
    def flow(width):
        x1 = width - BANKW
        cx = GX0; cyt = 8.0; rowh = 0.0; pos = {}
        for r in grid:
            rot = 90 if cls[r] == "ic" else 0
            w, h = size_after(footp[r], rot)
            need_cap = r in capfor
            top = h + (CAPH if need_cap else 0)
            if cx + w > x1 and cx > GX0:
                cx = GX0; cyt += rowh + 3.0; rowh = 0.0
            pos[r] = (cx + w / 2, cyt + (CAPH if need_cap else 0) + h / 2, rot)
            cx += w + GAP; rowh = max(rowh, top)
        return pos, cyt + rowh
    # UNIFORM board size: every card is the same dimensions (Eurocard-style).
    BW = STD_W
    pos, bottom = flow(BW)
    if bottom > BH - 6:
        print("  WARNING: %s overflows %dx%d (bottom=%.0f)" % (name, BW, BH, bottom))
    for r, (cxm, cym, rot) in pos.items():
        place_centered(footp[r], cxm, cym, rot); placed.add(r)
        if r in capfor and capfor[r] in footp:         # cap hugging the IC top edge
            c = capfor[r]; x0, y0, x1c, y1c = pad_bbox(footp[r])
            place_centered(footp[c], pcbnew.ToMM((x0 + x1c) // 2), pcbnew.ToMM(y0) - 4.5, 0)
            placed.add(c)

    # --- status-LED bank down the RIGHT edge (opposite the connector) ---------
    # LEDs near the edge, each series resistor just inboard, courtyard-spaced
    # vertically; wraps to a second column leftward if a card has many LEDs.
    ledx = BW - 9.0; resx = BW - 24.0; by = 10.0
    for led in leds:
        if led not in footp: continue
        lh = size_after(footp[led], 180)[1]
        rr = led_res.get(led)
        rh = size_after(footp[rr], 0)[1] if (rr and rr in footp) else 0
        row = max(lh, rh, 5.0)
        if by + row > BH - 6:                       # column full -> shift left
            ledx -= 26.0; resx -= 26.0; by = 10.0
        place_centered(footp[led], ledx, by + row / 2, 180); placed.add(led)
        if rr and rr in footp:
            place_centered(footp[rr], resx, by + row / 2, 0); placed.add(rr)
        by += row + 4.0

    # any decaps whose IC wasn't placed, or leftovers -> park in a bottom row
    px = GX0
    for r in parts:
        if r in placed or r == "J1" or r not in footp: continue
        place_centered(footp[r], px, BH - 6, 0); px += 10.0

    # J1 connector: left edge, rot90, pads centred in 100mm, 4mm from the edge
    if "J1" in footp:
        j = footp["J1"]; j.SetPosition(P(0, 0)); j.SetOrientationDegrees(90)
        x0, y0, x1, y1 = pad_bbox(j)
        j.SetPosition(VECTOR2I(mm(4) - x0, mm(BH/2) - (y0 + y1) // 2))

    # --- assign pads to nets --------------------------------------------------
    badpad = []
    for net, mem in nets.items():
        ni = netobj[net]
        for (ref, pinname) in mem:
            if ref not in footp: continue
            pad = pad_of(ref, parts[ref][0], pinname)
            hit = False
            for p in footp[ref].Pads():
                if p.GetNumber() == pad: p.SetNet(ni); hit = True
            if not hit: badpad.append("%s.%s(pad %s)" % (ref, pinname, pad))

    # --- board outline + power planes ----------------------------------------
    def edge(x1, y1, x2, y2):
        s = pcbnew.PCB_SHAPE(board); s.SetShape(pcbnew.SHAPE_T_SEGMENT)
        s.SetStart(P(x1, y1)); s.SetEnd(P(x2, y2))
        s.SetLayer(pcbnew.Edge_Cuts); s.SetWidth(mm(0.15)); board.Add(s)
    edge(0, 0, BW, 0); edge(BW, 0, BW, BH); edge(BW, BH, 0, BH); edge(0, BH, 0, 0)
    def plane(layer, netname):
        if netname not in netobj: return
        z = pcbnew.ZONE(board); z.SetLayer(layer); z.SetNet(netobj[netname])
        z.SetIsFilled(True); z.SetPadConnection(pcbnew.ZONE_CONNECTION_FULL)
        z.SetIslandRemovalMode(pcbnew.ISLAND_REMOVAL_MODE_ALWAYS)
        z.SetLocalClearance(mm(0.2)); z.SetMinThickness(mm(0.13))
        o = z.Outline(); o.NewOutline()
        for x, y in [(1, 1), (BW - 1, 1), (BW - 1, BH - 1), (1, BH - 1)]:
            o.Append(mm(x), mm(y))
        board.Add(z)
    plane(pcbnew.In1_Cu, "GND"); plane(pcbnew.In2_Cu, "VCC")
    nk = add_mounting_keepouts(board, footp)   # metal-screw keepouts at DIN holes
    print("  %d DIN mounting-hole keepouts (r=%.1fmm)" % (nk, SCREW_KEEPOUT_R))
    pcbnew.ZONE_FILLER(board).Fill(board.Zones())

    # --- silkscreen: references, chip types, function + position labels -----
    if not SL.title_block(board, SL.card_title(title)): print("  SILK: no clean spot for the title block")
    fails = SL.label_board(board, parts, *silk_spec(name, parts))
    if fails: print("  SILK: no clean spot for %d: %s" % (len(fails), fails[:12]))

    outdir = os.path.join(ROOT, "hardware", name, "kicad")
    os.makedirs(outdir, exist_ok=True)
    out = os.path.join(outdir, "p8x-%s.kicad_pcb" % name)
    pcbnew.SaveBoard(out, board)
    return dict(out=out, BW=BW, parts=len(parts), footprints=len(footp),
                missing=missing, badpad=badpad, subs=list(SUBS))

if __name__ == "__main__":
    name = sys.argv[1]
    SUBS.clear()
    r = build_card(name)
    print("wrote", r["out"], "(%dx%dmm, %d/%d footprints)" % (r["BW"], BH, r["footprints"], r["parts"]))
    if r["missing"]: print("  MISSING FOOTPRINTS:", r["missing"])
    if r["badpad"]:  print("  PAD MISMATCH (%d):" % len(r["badpad"]), r["badpad"][:12])
    if r["subs"]:    print("  SUBSTITUTIONS:", r["subs"])
