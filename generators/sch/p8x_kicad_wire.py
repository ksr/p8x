#!/usr/bin/env python3
"""ELK-wired schematic sheets for the P8X KiCad export (ported from P32X).

ELK (elk_layout.js, elkjs) places the parts on a sheet and routes the nets local
to that sheet as orthogonal wires; power, backplane signals and nets shared with
other sheets keep their labels, as a hand-drawn schematic would. Everything is on
the 2.54 mm KiCad grid, so after ELK the coordinates round to the grid and every
wire end still lands on its pin. Junction dots go where >=3 wire/pin ends meet.

Connectivity is not trusted to the layout: p8x_kicad_sch.verify() compares
KiCad's own netlist of the result with the canonical one, so any short or break
from routing or rounding shows up there.
"""
import os, sys, json, math, subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from p8x_symlib import SYM  # noqa: E402
from p8x_card import SIGNALS  # noqa: E402
import p8x_kicad_sch as KS  # noqa: E402

G = KS.G
SIDE = {0: "WEST", 180: "EAST", 270: "NORTH", 90: "SOUTH"}

def nets_of(card):
    m = {}
    for n, pins in card.nets.items():
        for rp in pins:
            m[rp] = n
    return m

def wired_nets(card, refs):
    """Nets drawn as wires on this sheet: not power, not a backplane signal, at
    least two pins on this sheet, not a chain between identical chips. A net that
    also reaches other sheets is wired between its pins here and carries its name
    label (a global label) to the rest, as a hand-drawn sheet does (2026-10-24;
    before, only nets wholly on one sheet were wired)."""
    on = set(refs)
    out = {}
    for n, pins in card.nets.items():
        if n in ("VCC", "GND") or n in SIGNALS:
            continue
        pins = [(r, p) for r, p in pins if r in on]
        if len(pins) < 2:
            continue
        # a long chain through many identical chips (e.g. a shared enable to every
        # counter) would make ELK step each chip into its own column; a short chain
        # (a carry RC into the next slice) is the natural left-to-right flow, so wire
        # it. Threshold: skip only when it spans more than 3 like chips.
        if len({card.parts[r][0] for r, p in pins}) == 1 and len({r for r, p in pins}) > 3:
            continue
        out[n] = pins
    return out

def driver_first(card, pins):
    rank = {"out": 0, "tri": 1, "oc": 1, "bidir": 2}
    return sorted(pins, key=lambda rp: rank.get(SYM[card.parts[rp[0]][0]]["pins"][rp[1]][1], 3))

# Each wire is oriented by drawing side, not by electrical direction (2026-10-24):
# a pin on a symbol's right edge feeds one on a left edge, so ELK lays the sheet
# out in the drawn left-to-right flow. Electrical direction loops back on a round
# trip such as ACIA TXD -> MAX232 -> RXD, and ELK then breaks the cycle by pushing
# one ACIA to the far side of the sheet.
def side_first(card, pins):
    def east(rp):
        return SIDE[KS.Symbol(card.parts[rp[0]][0]).pins[rp[1]][2]] == "EAST"
    ranked = driver_first(card, pins)
    return sorted(ranked, key=lambda rp: not east(rp))   # stable: drivers first among equals

def build_graph(card, refs, wired, label_room, edge_space):
    children, edges = [], []
    for ref in refs:
        sym = KS.Symbol(card.parts[ref][0])
        w = round(2 * (sym.hw + G) / G)
        h = round((sym.ytop + G - (sym.ybot - G)) / G)
        ports = []
        for p, (px, py, a) in sym.pins.items():
            ports.append({"id": "%s.%s" % (ref, p),
                          "x": round((px + sym.hw + G) / G), "y": round((sym.ytop + G - py) / G),
                          "width": 0, "height": 0,
                          "layoutOptions": {"elk.port.side": SIDE[a]}})
        children.append({"id": ref, "width": w, "height": h, "ports": ports,
                         "layoutOptions": {"elk.portConstraints": "FIXED_POS"}})
    for n, pins in wired.items():
        d, *rest = side_first(card, pins)
        for k, (r, p) in enumerate(rest):
            edges.append({"id": "%s#%d" % (n, k), "sources": ["%s.%s" % d], "targets": ["%s.%s" % (r, p)]})
    return {"id": "sheet", "children": children, "edges": edges,
            "layoutOptions": {"elk.spacing.edgeNode": str(label_room),
                              "elk.spacing.edgeEdge": str(edge_space),
                              "elk.layered.spacing.edgeEdgeBetweenLayers": str(edge_space),
                              "elk.spacing.nodeNode": str(label_room + 2),
                              "elk.layered.spacing.nodeNodeBetweenLayers": str(2 * label_room + 4)}}

def run_elk(graph):
    r = subprocess.run(["node", os.path.join(HERE, "elk_layout.js")], input=json.dumps(graph),
                       capture_output=True, text=True, cwd=HERE)
    if r.returncode:
        raise SystemExit("ELK failed: " + r.stderr)
    return json.loads(r.stdout)

def layout_sheet(card, refs):
    for space in (2, 3, 4, 6):
        result, conflicts = _layout(card, refs, space)
        if not conflicts:
            return result
    raise SystemExit("schematic wiring: nets still touch after rounding: %s" % conflicts[:3])

def _layout(card, refs, edge_space):
    net = nets_of(card)
    wired = wired_nets(card, refs)
    labels = [n for (r, p), n in net.items() if r in refs and n not in wired]
    room = max(4, math.ceil(max([KS.label_len(n) for n in labels] + [0]) / G) + 1)
    out = run_elk(build_graph(card, refs, wired, room, edge_space))
    ox, oy = 6 + room, 8
    pos = {}
    for ch in out["children"]:
        sym = KS.Symbol(card.parts[ch["id"]][0])
        nx, ny = round(ch["x"]) + ox, round(ch["y"]) + oy
        pos[ch["id"]] = (nx * G + sym.hw + G, ny * G + sym.ytop + G)
    segs = set()
    for e in out.get("edges", []):
        n = e["id"].rsplit("#", 1)[0]
        for sec in e.get("sections", []):
            pts = [sec["startPoint"]] + sec.get("bendPoints", []) + [sec["endPoint"]]
            pts = [(round(p["x"]) + ox, round(p["y"]) + oy) for p in pts]
            for a, b in zip(pts, pts[1:]):
                if a != b:
                    segs.add((n, min(a, b), max(a, b)))
    pin_pts = {}
    for ref in refs:
        sym = KS.Symbol(card.parts[ref][0])
        X, Y = pos[ref]
        for p, (px, py, a) in sym.pins.items():
            if (ref, p) in net and net[(ref, p)] in wired:
                pin_pts[(round((X + px) / G), round((Y - py) / G))] = net[(ref, p)]
    junctions, ends = [], {}
    for n, a, b in segs:
        for qq in (a, b):
            ends.setdefault((n, qq), 0)
            ends[(n, qq)] += 1
    for (n, qq), k in ends.items():
        k += 1 if pin_pts.get(qq) == n else 0
        on_mid = any(m == n and qq not in (a, b) and _on(qq, a, b) for m, a, b in segs)
        if k >= 3 or on_mid:
            junctions.append(qq)
    all_pins = {}
    for ref in refs:
        sym = KS.Symbol(card.parts[ref][0])
        X, Y = pos[ref]
        for p, (px, py, a) in sym.pins.items():
            all_pins[(round((X + px) / G), round((Y - py) / G))] = net.get((ref, p), "nc:%s.%s" % (ref, p))
    conflicts = []
    seglist = sorted(segs)
    for n, a, b in seglist:
        for qq, other in all_pins.items():
            if other != n and _on(qq, a, b):
                conflicts.append((n, other, qq))
        for m, c, d in seglist:
            if m != n and _touch(a, b, c, d):
                conflicts.append((n, m, a))
    labels = []
    for n in sorted({n for n, a, b in seglist}):
        runs = sorted(((abs(a[0] - b[0]) + abs(a[1] - b[1]), a, b) for m, a, b in seglist if m == n), reverse=True)
        spot = None
        for ln, a, b in runs:
            pts = [(x, a[1]) for x in range(a[0], b[0] + 1)] if a[1] == b[1] else [(a[0], y) for y in range(a[1], b[1] + 1)]
            pts.sort(key=lambda qq: abs(qq[0] - (a[0] + b[0]) / 2) + abs(qq[1] - (a[1] + b[1]) / 2))
            for qq in pts:
                if all(not (m != n and _on(qq, c, d)) for m, c, d in seglist) and \
                   all(o == n for pq, o in all_pins.items() if pq == qq):
                    spot = (qq, a[1] == b[1]); break
            if spot:
                break
        if spot is None:
            conflicts.append((n, "no free spot for its name label", None))
        else:
            labels.append((n, spot[0][0] * G, spot[0][1] * G, spot[1]))
    wires = [(n, (a[0] * G, a[1] * G), (b[0] * G, b[1] * G)) for n, a, b in seglist]
    w = (max(ch["x"] + ch["width"] for ch in out["children"]) + ox + room + 6) * G
    h = (max(ch["y"] + ch["height"] for ch in out["children"]) + oy + 10) * G
    return (pos, wires, [(x * G, y * G) for x, y in sorted(set(junctions))], labels,
            {rp for rp, n in net.items() if n in wired and rp[0] in refs}, (w, h)), conflicts

def _touch(a, b, c, d):
    return _on(a, c, d) or _on(b, c, d) or _on(c, a, b) or _on(d, a, b)

def _on(q, a, b):
    (x, y), (x1, y1), (x2, y2) = q, a, b
    return (x1 == x2 == x and min(y1, y2) <= y <= max(y1, y2)) or \
           (y1 == y2 == y and min(x1, x2) <= x <= max(x1, x2))
