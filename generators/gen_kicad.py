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

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
GENE = os.path.join(ROOT, "generators", "gen_eagle.py")
FP   = "/Applications/KiCad/KiCad.app/Contents/SharedSupport/footprints"

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
    "C_DISC1":(("Capacitor_THT", "C_Disc_D5.0mm_W2.5mm_P5.00mm")),
    "C_DISC": (("Capacitor_THT", "C_Disc_D5.0mm_W2.5mm_P5.00mm")),
    "LED5":   ("LED_THT", "LED_D5.0mm"),
    "R_AXIAL":("Resistor_THT", "R_Axial_DIN0207_L6.3mm_D2.5mm_P10.16mm_Horizontal"),
    "HDR3":   ("Connector_PinHeader_2.54mm", "PinHeader_1x03_P2.54mm_Vertical"),
    "HDR4":   ("Connector_PinHeader_2.54mm", "PinHeader_1x04_P2.54mm_Vertical"),
    "HDR10":  ("Connector_PinHeader_2.54mm", "PinHeader_1x10_P2.54mm_Vertical"),
    "MABC96R":("Connector_DIN", "DIN41612_C_3x32_Male_Horizontal_THT"),
    # ---- substitutions (closest standard footprint) ----
    "HDR40":  ("Connector_PinHeader_2.54mm", "PinHeader_2x20_P2.54mm_Vertical", "SUB 2x20 header"),
    "OSC4":   ("Oscillator", "Oscillator_DIP-8", "SUB DIP-8 can oscillator"),
    "SIP9":   ("Resistor_THT", "R_Array_SIP9", "SUB bussed SIP-9 R-network"),
    "SIP16":  ("Connector_PinHeader_2.54mm", "PinHeader_1x16_P2.54mm_Vertical", "SUB 1x16 SIP (isolated R-net)"),
    "CP_RADIAL": ("Capacitor_THT", "CP_Radial_D8.0mm_P3.50mm", "SUB radial electrolytic / coin"),
    "SW2P":   ("Button_Switch_THT", "SW_PUSH_6mm", "SUB 6mm tact switch"),
    "PICO40": ("Connector_PinHeader_2.54mm", "PinHeader_2x20_P2.54mm_Vertical", "SUB 2x20 (Raspberry Pi Pico)"),
}
# device-name overrides where the package alone is ambiguous
DEV_FP = {
    "DIP8SW": ("Button_Switch_THT", "SW_DIP_SPSTx08_Slide_9.78x22.5mm_W7.62mm_P2.54mm", "SUB 8-way DIP switch"),
    "IDE40":  ("Connector_IDC", "IDC-Header_2x20_P2.54mm_Vertical", "SUB 2x20 IDC (40-pin IDE)"),
    "XTAL32": ("Crystal", "Crystal_Round_D3.0mm_Vertical", "SUB 32kHz round crystal"),
    "LEDARR8":("Package_DIP", "DIP-16_W7.62mm", "SUB DIP-16 (8-LED bargraph)"),
    "RNISO8": ("Connector_PinHeader_2.54mm", "PinHeader_1x16_P2.54mm_Vertical", "SUB 1x16 SIP (isolated 8xR)"),
    "RNISO8D":("Package_DIP", "DIP-16_W7.62mm", "SUB DIP-16 isolated R-net"),
    "COIN":   ("Battery", "BatteryHolder_Keystone_3000_1x12mm", "SUB coin-cell holder"),
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
    """(w,h) in mm of the pad bbox after a rotation, without disturbing placement order."""
    fp.SetPosition(P(0, 0))
    if rot: fp.SetOrientationDegrees(rot)
    x0, y0, x1, y1 = pad_bbox(fp)
    return pcbnew.ToMM(x1 - x0), pcbnew.ToMM(y1 - y0)

# ---- the build --------------------------------------------------------------
BH = 100.0
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
        fp = pcbnew.FootprintLoad(FP + "/" + spec[0] + ".pretty", spec[1]) if spec else None
        if fp is None:
            missing.append("%s (%s/%s)" % (ref, dev, DEV[dev]["pkg"])); continue
        fp.SetReference(ref); fp.SetValue(val); board.Add(fp); footp[ref] = fp

    # --- find each LED's series resistor (shared net on the LED anode) --------
    led_res = {}
    for ref in [r for r in parts if cls[r] == "led"]:
        apad = pad_of(ref, parts[ref][0], "A")
        anet = next((n for n, mem in nets.items() if (ref, "A") in mem), None)
        if anet:
            for (r2, pin) in nets[anet]:
                if r2 != ref and cls.get(r2) == "res":
                    led_res[ref] = r2; break
    paired_res = set(led_res.values())

    # --- RIGHT-edge bank: LED(+resistor) pairs, then jumpers/switches ---------
    bank = [(r, led_res.get(r)) for r in parts if cls[r] == "led"]
    jumpers = [r for r in parts if cls[r] in ("jumper",)]
    # place bank down the right edge; resistor inboard, LED at the edge, label between
    BANK_X_LED = None  # decided after we know width; use fixed right positions
    placed = set()

    # --- GRID parts: ICs (+cap above), big connectors, misc, lone resistors ---
    grid = ([r for r in parts if cls[r] == "ic"]
            + [r for r in parts if cls[r] == "bigconn"]
            + [r for r in parts if cls[r] == "misc"]
            + [r for r in parts if cls[r] == "res" and r not in paired_res])

    # board width: flow ICs rot90 into rows in the middle; grow width to fit 100mm
    GX0 = 34.0; GAP = 6.0; CAPH = 7.5
    bankw = 30.0
    def flow(width):
        x1 = width - bankw
        cx = GX0; cyt = 8.0; rowh = 0.0; pos = {}
        for r in grid:
            rot = 90 if cls[r] in ("ic",) else 0
            w, h = size_after(footp[r], rot)
            need_cap = r in capfor
            top = h + (CAPH if need_cap else 0)
            if cx + w > x1 and cx > GX0:
                cx = GX0; cyt += rowh + GAP + 3.0; rowh = 0.0
            pos[r] = (cx + w / 2, cyt + (CAPH if need_cap else 0) + h / 2, rot)
            cx += w + GAP; rowh = max(rowh, top)
        return pos, cyt + rowh
    W = 200.0
    for W in (200, 230, 260, 300, 340, 400):
        pos, bottom = flow(W)
        if bottom <= BH - 6:
            break
    BW = W

    for r, (cxm, cym, rot) in pos.items():
        place_centered(footp[r], cxm, cym, rot); placed.add(r)
        if r in capfor:                                # its cap, hugging the top edge
            c = capfor[r]
            if c in footp:
                x0, y0, x1c, y1c = pad_bbox(footp[r])
                place_centered(footp[c], pcbnew.ToMM((x0 + x1c) // 2), pcbnew.ToMM(y0) - 4.5, 0)
                placed.add(c)

    # bank on the right edge
    yb = 12.0
    for led, res in bank:
        if res and res in footp:
            place_centered(footp[res], BW - 24, yb, 0); placed.add(res)
        if led in footp:
            place_centered(footp[led], BW - 8, yb, 180); placed.add(led)
        yb += 14.0
    for j in jumpers:
        if j in footp:
            place_centered(footp[j], BW - 16, min(yb, BH - 8), 0); placed.add(j); yb += 12.0

    # any decaps whose IC wasn't placed, or leftovers -> park in a bottom row
    px = GX0
    for r in parts:
        if r in placed or r == "J1" or r not in footp: continue
        place_centered(footp[r], px, BH - 6, 0); px += 10.0

    # J1 connector: left edge, rot90, pads centred in 100mm, 4mm from the edge
    if "J1" in footp:
        j = footp["J1"]; j.SetPosition(P(0, 0)); j.SetOrientationDegrees(90)
        x0, y0, x1, y1 = pad_bbox(j)
        j.SetPosition(VECTOR2I(mm(4) - x0, mm(50) - (y0 + y1) // 2))

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
    pcbnew.ZONE_FILLER(board).Fill(board.Zones())

    # --- silkscreen: values + LED/jumper labels ------------------------------
    C_ = pcbnew.GR_TEXT_H_ALIGN_CENTER; L_ = pcbnew.GR_TEXT_H_ALIGN_LEFT
    def txt(field, x, y, just, size=0.9):
        field.SetVisible(True); field.SetLayer(pcbnew.F_SilkS)
        field.SetTextSize(pcbnew.VECTOR2I(mm(size), mm(size)))
        field.SetTextThickness(mm(0.15)); field.SetHorizJustify(just)
        field.SetPosition(VECTOR2I(int(x), int(y)))
    def silk(s, x, y, size=1.2):
        t = pcbnew.PCB_TEXT(board); t.SetText(s); t.SetPosition(P(x, y))
        t.SetLayer(pcbnew.F_SilkS); t.SetTextThickness(mm(0.2))
        t.SetTextSize(pcbnew.VECTOR2I(mm(size), mm(size)))
        t.SetHorizJustify(pcbnew.GR_TEXT_H_ALIGN_CENTER); board.Add(t)
    for ref, fp in footp.items():
        if ref == "J1": fp.Value().SetVisible(False); continue
        x0, y0, x1, y1 = pad_bbox(fp); cx = (x0 + x1) // 2; cy = (y0 + y1) // 2
        v = fp.Value()
        if cls[ref] == "decap":
            txt(v, x1 + mm(1.3), cy, L_)
        elif cls[ref] == "led":
            txt(v, x1 + mm(1.3), cy, L_)
            fp.Reference().SetVisible(False)
            lab = labels.get(ref)
            if lab: silk(lab, pcbnew.ToMM(x0) - 6.0, pcbnew.ToMM(cy) - 1.0, 1.1)
        elif cls[ref] == "res":
            txt(fp.Reference(), cx, cy - mm(3.2), C_); txt(v, cx, cy + mm(3.2), C_)
        else:
            txt(v, cx, y1 + mm(4.6), C_)
        if cls[ref] == "jumper":
            lab = labels.get(ref)
            if lab: silk(lab, pcbnew.ToMM(cx), pcbnew.ToMM(y1) + 2.5, 1.0)

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
    print("wrote", r["out"], "(%dx100mm, %d/%d footprints)" % (r["BW"], r["footprints"], r["parts"]))
    if r["missing"]: print("  MISSING FOOTPRINTS:", r["missing"])
    if r["badpad"]:  print("  PAD MISMATCH (%d):" % len(r["badpad"]), r["badpad"][:12])
    if r["subs"]:    print("  SUBSTITUTIONS:", r["subs"])
