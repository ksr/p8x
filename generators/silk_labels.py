"""silk_labels.py -- the silkscreen labelling pass shared by every board generator.

Board rules (docs/p8x-card-standards.md section 12, 2026-10-24):
  * every reference (U12, R3, ...) stays readable with the parts fitted: printed
    OUTSIDE every part's courtyard, never under a chip, socket or module; an IC
    gets its type (74HCT374, ...) printed beside it;
  * every switch, button and LED carries its function (RESET, STEP, ...), and each
    switch / jumper position what it selects.

label_board() owns the Reference fields (re-placed, horizontal, on F.SilkS), hides
the Value fields, and adds PCB_TEXT items for IC types, passive values, function
labels and position labels. Free silk text a generator already placed is kept and
treated as an obstacle. Each block is tried at candidate spots around the part
(above, below, right, left, then further out, then stacked, then smaller) and the
first spot clear of every courtyard, pad, placed text and the board edge wins.
Returns the refs it could not place cleanly (the caller prints them).
"""
try:
    import pcbnew                    # KiCad's Python; gen_bom.py imports only the type table
except ImportError:
    pcbnew = None

IU = 1000000                                 # internal units per mm
def mm(v): return int(round(v * IU))

# ---- chip types ------------------------------------------------------------
# device -> orderable type (HCT throughout); gen_bom.py prints the same names.
LOGIC = {"74377V2": "74HCT377", "74244": "74HCT244", "74245": "74HCT245",
         "74181": "74HCT181", "74182": "74HCT182", "74157": "74HCT157",
         "74151": "74HCT151", "74138": "74HCT138", "74139": "74HCT139",
         "74161": "74HCT161", "74169": "74HCT169", "74374": "74HCT374",
         "74175": "74HCT175", "74260": "74HCT260", "74257": "74HCT257",
         "74688": "74HCT688", "7430": "74HCT30", "7410": "74HCT10",
         "7402": "74HCT02", "7474": "74HCT74", "HEX14": "74HCT14"}
OTHER = {"28C64": "AT28C64", "6850": "MC6850", "MAX232": "MAX232",
         "DS1302": "DS1302", "MCP23S17": "MCP23S17", "ATMEGA1284": "ATmega1284P",
         "PICO": "Raspberry Pi Pico"}

def chip_type(dev, val):
    """The printed type of an IC, or None for a part that is not a chip."""
    if dev in LOGIC: return LOGIC[dev]
    if dev in OTHER: return OTHER[dev]
    v = (val or "").upper()
    if dev == "GATES14":
        for g in ("00", "08", "32", "86"):
            if "74HCT" + g in v: return "74HCT" + g
        return val
    if dev == "MEM28K8": return "AT28C256" if "28C256" in v else "62256"
    return None

# passive / small parts whose value is worth printing beside the reference
VALUED = {"RES", "RNISO8", "RNISO8D", "SIP9", "CAPP", "OSC", "XTAL32"}

def extra_text(dev, val):
    """Text printed beside the reference: the chip type, or a passive's value."""
    t = chip_type(dev, val)
    if t: return t
    if dev in VALUED and val: return val
    if dev == "CAP" and val and val.lower() not in ("100n", "100nf"): return val
    return None

# ---- geometry --------------------------------------------------------------
def _rect(b): return (b.GetX(), b.GetY(), b.GetRight(), b.GetBottom())
def _grow(r, d): return (r[0] - d, r[1] - d, r[2] + d, r[3] + d)
def _hit(a, b): return a[0] < b[2] and b[0] < a[2] and a[1] < b[3] and b[1] < a[3]

def _courtyard(fp):
    c = fp.GetCourtyard(pcbnew.F_Cu)
    if c.OutlineCount(): return _rect(c.BBox())
    return _rect(fp.GetBoundingBox(False, False))

class Labeler:
    def __init__(self, board):
        self.board = board
        e = board.GetBoardEdgesBoundingBox()
        self.inside = _grow(_rect(e), -mm(0.6))
        self.fps = [f for f in board.GetFootprints()]
        self.crt = [_grow(_courtyard(f), mm(0.15)) for f in self.fps]
        self.pads = [_grow(_rect(p.GetBoundingBox()), mm(0.15))
                     for f in self.fps for p in f.Pads()]
        self.texts = [_grow(_rect(t.GetBoundingBox()), mm(0.25))
                      for t in board.GetDrawings()
                      if isinstance(t, pcbnew.PCB_TEXT) and t.GetLayer() == pcbnew.F_SilkS]
        self.failed = []

    # a "piece" is a text object (Reference field or a new PCB_TEXT) set up
    # LEFT/TOP justified; measure its box with the anchor at (0, 0)
    def _style(self, t, size):
        t.SetLayer(pcbnew.F_SilkS); t.SetVisible(True)
        t.SetTextSize(pcbnew.VECTOR2I(mm(size), mm(size)))
        t.SetTextThickness(mm(max(0.1, size * 0.15)))
        t.SetHorizJustify(pcbnew.GR_TEXT_H_ALIGN_LEFT)
        t.SetVertJustify(pcbnew.GR_TEXT_V_ALIGN_TOP)
        t.SetTextAngle(pcbnew.EDA_ANGLE(0, pcbnew.DEGREES_T))
        t.SetPosition(pcbnew.VECTOR2I(0, 0))
        r = _rect(t.GetBoundingBox())
        return r[0], r[1], r[2] - r[0], r[3] - r[1]      # offset x, y, width, height

    def _fits(self, r):
        if not (r[0] >= self.inside[0] and r[1] >= self.inside[1] and
                r[2] <= self.inside[2] and r[3] <= self.inside[3]): return False
        return not (any(_hit(r, c) for c in self.crt) or any(_hit(r, p) for p in self.pads)
                    or any(_hit(r, t) for t in self.texts))

    def _candidates(self, box, w, h, toward=None):
        """Top-left corners around box for a w x h block, nearest first."""
        x0, y0, x1, y1 = box; out = []
        for d in (0.35, 1.3, 2.6, 4.0):
            g = mm(d)
            above = [(x, y0 - g - h) for x in (x0, (x0 + x1 - w) // 2, x1 - w)]
            below = [(x, y1 + g) for x in (x0, (x0 + x1 - w) // 2, x1 - w)]
            right = [(x1 + g, y) for y in ((y0 + y1 - h) // 2, y0, y1 - h)]
            left = [(x0 - g - w, y) for y in ((y0 + y1 - h) // 2, y0, y1 - h)]
            sides = {"above": above, "below": below, "right": right, "left": left}
            order = ["above", "below", "right", "left"]
            if toward in sides: order.remove(toward); order.insert(0, toward)
            for s in order: out += sides[s]
        return out

    def place(self, box, pieces, toward=None, key=""):
        """Place a block of (text-object, size) pieces next to box. Tries one
        line, then stacked lines, at each size step. Returns True if clean."""
        for shrink in (1.0, 0.85, 0.7):
            for stacked in (False, True):
                ms = [self._style(t, s * shrink) for t, s in pieces]
                gap = mm(0.8)
                if stacked:
                    w = max(m[2] for m in ms); h = sum(m[3] for m in ms) + mm(0.2) * (len(ms) - 1)
                else:
                    w = sum(m[2] for m in ms) + gap * (len(ms) - 1); h = max(m[3] for m in ms)
                for (bx, by) in self._candidates(box, w, h, toward):
                    r = (bx, by, bx + w, by + h)
                    if not self._fits(r): continue
                    cx, cy = bx, by
                    for (t, _s), m in zip(pieces, ms):
                        t.SetPosition(pcbnew.VECTOR2I(cx - m[0], cy - m[1]))
                        if stacked: cy += m[3] + mm(0.2)
                        else: cx += m[2] + gap
                    self.texts.append(_grow(r, mm(0.25)))
                    return True
                if len(pieces) == 1: break           # stacking one piece changes nothing
        # nothing clean: leave it above the part at the smallest size and report
        ms = [self._style(t, s * 0.7) for t, s in pieces]
        cx, cy = box[0], box[1] - mm(0.3) - max(m[3] for m in ms)
        for (t, _s), m in zip(pieces, ms):
            t.SetPosition(pcbnew.VECTOR2I(cx - m[0], cy - m[1])); cx += m[2] + mm(0.8)
        self.failed.append(key)
        return False

    def new_text(self, s):
        t = pcbnew.PCB_TEXT(self.board); t.SetText(s); self.board.Add(t); return t

def _order(ref, dev, ctype):
    if ctype: return 0                               # ICs first: tightest spots
    if dev in ("LED", "SW2", "DIP8SW", "LEDARR8") or ref.startswith(("JP", "SW")): return 1
    return 2

def label_board(board, parts, labels=None, positions=None, skip=()):
    """Label every footprint on board.
    parts: ref -> (device, value).  labels: ref -> function label.
    positions: ref -> [(pad numbers, text[, side]), ...] -- each text printed
    beside the named pads (a jumper or switch position, a bar's end bit), on the
    side facing away from the part's centre unless side names one.
    skip: refs left unlabelled."""
    labels = labels or {}; positions = positions or {}
    L = Labeler(board)
    fps = {f.GetReference(): f for f in board.GetFootprints()}
    refs = sorted((r for r in fps if r in parts and r not in skip),
                  key=lambda r: (_order(r, parts[r][0], chip_type(*parts[r])), r))
    for r in skip:
        if r in fps: fps[r].Reference().SetVisible(False)
    for r in refs:
        f = fps[r]; dev, val = parts[r]
        f.Value().SetVisible(False)
        box = _courtyard(f)
        pieces = [(f.Reference(), 1.0)]
        ex = extra_text(dev, val)
        if ex: pieces.append((L.new_text(ex), 0.8))
        if r in labels:                              # the function label rides in the
            pieces.append((L.new_text(labels[r]), 1.0))  # same block, so it stays with its part
        L.place(box, pieces, key=r)
        for pos in positions.get(r, []):
            pads, txt = pos[0], pos[1]
            ps = [p for p in f.Pads() if p.GetNumber() in pads]
            if not ps: continue
            pb = _rect(ps[0].GetBoundingBox())
            for p in ps[1:]:
                q = _rect(p.GetBoundingBox())
                pb = (min(pb[0], q[0]), min(pb[1], q[1]), max(pb[2], q[2]), max(pb[3], q[3]))
            # face away from the part's centre
            cb = _courtyard(f); pcx = (pb[0] + pb[2]) // 2; pcy = (pb[1] + pb[3]) // 2
            ccx = (cb[0] + cb[2]) // 2; ccy = (cb[1] + cb[3]) // 2
            dx, dy = pcx - ccx, pcy - ccy
            toward = pos[2] if len(pos) > 2 else (
                ("right" if dx > 0 else "left") if abs(dx) > abs(dy)
                else ("below" if dy > 0 else "above"))
            # reach out to the courtyard edge on that side, so the text clears it
            pb = {"right": (pb[0], pb[1], cb[2], pb[3]), "left": (cb[0], pb[1], pb[2], pb[3]),
                  "below": (pb[0], pb[1], pb[2], cb[3]), "above": (pb[0], cb[1], pb[2], pb[3])}[toward]
            L.place(pb,[(L.new_text(txt), 0.8)], toward=toward, key="%s pos %s" % (r, txt))
    return L.failed
