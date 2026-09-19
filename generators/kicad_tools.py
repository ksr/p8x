#!/usr/bin/env python3
"""kicad_tools.py -- shared KiCad pipeline steps for the generic card boards
(companion to gen_kicad.py). Run under KiCad's bundled python (needs pcbnew;
some steps shell out to kicad-cli). Subcommands:

    export_dsn  <board.kicad_pcb>          -> <board>.dsn (In1/In2 marked power)
    import_ses  <board.kicad_pcb> <ses>    -> import routing, re-fill planes, save
    placement   <board.kicad_pcb>          -> <dir>/<...>-placement.pdf (centred, B/W)
    finish      <board.kicad_pcb>          -> gerbers zip + top/3d renders + placement

These mirror the memory card's bespoke scripts, generalised to any board path.
"""
import os, sys, subprocess, pcbnew
try:
    import wx; _app = wx.App()
except Exception:
    pass
CLI = "/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli"

def _run(*a):
    subprocess.run(list(a), check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

def _inset_dsn_boundary(t, keep_mm=0.35):
    """Shrink the routing boundary rectangle inward by keep_mm so Freerouting keeps
    all copper back from the board edge -- it otherwise routes to its 0.2mm boundary
    clearance and trips KiCad's 0.5mm copper-to-edge rule (seen as A2 tracks hugging
    the DIN edge on the bustest card). Axis-aligned inset of the outer (path pcb ...)
    rectangle; the plane polygons are already inset, and the units are read from the
    board width so this holds whatever the DSN resolution is."""
    import re
    m = re.search(r'\(boundary\s*\(path pcb 0\s+([\-0-9\s]+?)\)\s*\)', t)
    if not m:
        return t
    nums = [int(v) for v in m.group(1).split()]
    xs = nums[0::2]; ys = nums[1::2]
    if len(xs) < 4:
        return t
    # pcbnew exports the DSN in micrometres ((unit um)); 1000 units == 1 mm
    upm = 1.0 if re.search(r'\(unit mm\)', t) else 1000.0
    d = int(keep_mm * upm)
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    out = []
    for x, y in zip(xs, ys):
        nx = x + d if x == x0 else (x - d if x == x1 else x)
        ny = y + d if y == y0 else (y - d if y == y1 else y)
        out += [nx, ny]
    newpath = "(boundary\n      (path pcb 0  " + "  ".join(
        "%d %d" % (out[i], out[i+1]) for i in range(0, len(out), 2)) + ")\n    )"
    return t[:m.start()] + newpath + t[m.end():]

def export_dsn(brd):
    dsn = brd[:-len(".kicad_pcb")] + ".dsn"
    b = pcbnew.LoadBoard(brd)
    for z in b.Zones():
        z.UnFill()                                   # simple plane rects (optimiser-friendly)
    pcbnew.ExportSpecctraDSN(b, dsn)
    t = open(dsn).read()
    for lyr in ("In1.Cu", "In2.Cu"):
        t = t.replace("(layer %s\n      (type signal)" % lyr,
                      "(layer %s\n      (type power)" % lyr)
    if not os.environ.get("KT_NO_EDGE_INSET"):       # backplane opts out (dense bus needs the room)
        t = _inset_dsn_boundary(t)                   # keep routed copper off the board edge
    open(dsn, "w").write(t)
    print("export_dsn ->", dsn)

def stitch_trivial_nets(b):
    """Self-heal: Freerouting occasionally leaves a trivial 2-pad net unrouted
    (e.g. an LED-bank resistor->LED at the board edge, whose direct top path is
    blocked by another track). Stitch any 2-pad net that has no copper AND whose
    pads are collinear with a straight B.Cu track -- through-hole pads let it duck
    under the F.Cu tracks. Returns the number stitched. Call after ImportSpecctraSES
    and before the zone fill. Shared by every card's import step."""
    b.BuildConnectivity()
    np = {}
    for fp in b.GetFootprints():
        for p in fp.Pads():
            np.setdefault(p.GetNetname(), []).append(p)
    n = 0
    for name, pads in np.items():
        if name in ("", "GND", "VCC") or len(pads) != 2:
            continue
        if any(t.GetNetname() == name for t in b.GetTracks()):
            continue
        a, c = pads
        if a.GetPosition().x != c.GetPosition().x and a.GetPosition().y != c.GetPosition().y:
            continue                                    # only stitch straight (collinear) runs
        t = pcbnew.PCB_TRACK(b)
        t.SetStart(a.GetPosition()); t.SetEnd(c.GetPosition())
        t.SetLayer(pcbnew.B_Cu); t.SetWidth(pcbnew.FromMM(0.25)); t.SetNetCode(a.GetNetCode())
        b.Add(t); n += 1
        print("  stitched %s: %s.%s -> %s.%s" % (name,
              a.GetParentFootprint().GetReference(), a.GetNumber(),
              c.GetParentFootprint().GetReference(), c.GetNumber()))
    if n:
        print("stitched %d trivial unrouted 2-pad net(s)" % n)
    return n

def heal_unconnected(brd):
    """Post-route heal for pads DRC still reports unconnected. The realistic case
    on these boards is a *plane-net orphan*: an SMD pad on GND/VCC (e.g. the DNP
    coin-cell holder BT1, whose Keystone footprint is surface-mount) can't reach
    the In1/In2 plane through a barrel, and the router skipped its F.Cu tie. The
    plane copper is solid a couple mm away, so the fix is a stitching VIA dropped
    into solid plane + a short F.Cu track from the pad to it -- local and clear,
    never a long haul across the board. Only heals when a via site sits on solid
    same-net plane and clear of other pads; anything else it leaves for a human
    (a bad guess would just trade an open for a short). Returns the number healed."""
    import json, re, math
    j = "/tmp/_heal_%d.json" % os.getpid()
    subprocess.run([CLI, "pcb", "drc", "--format", "json", "-o", j, brd],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    unc = json.load(open(j)).get("unconnected_items", [])
    if not unc:
        print("heal: 0 unconnected"); return 0
    b = pcbnew.LoadBoard(brd); mm = pcbnew.ToMM; FM = pcbnew.FromMM
    PLANE = {"GND": pcbnew.In1_Cu, "VCC": pcbnew.In2_Cu}
    # index every pad by (net, rounded pos) so we can recover the actual pad object
    padidx, allpads = {}, []
    for fp in b.GetFootprints():
        for p in fp.Pads():
            allpads.append(p)
            padidx[(p.GetNetname(), round(mm(p.GetPosition().x), 2), round(mm(p.GetPosition().y), 2))] = p
    zone = {}   # net -> filled zone on its plane layer
    for z in b.Zones():
        if z.GetNetname() in PLANE and z.GetLayer() == PLANE[z.GetNetname()]:
            zone[z.GetNetname()] = z
    tracks = [t for t in b.GetTracks() if t.Type() == pcbnew.PCB_TRACE_T]
    def solid(z, x, y):
        return z.GetFilledPolysList(z.GetLayer()).Contains(pcbnew.VECTOR2I(FM(x), FM(y)))
    def clear_of_pads(x, y, skip):
        return all(p is skip or math.hypot(mm(p.GetPosition().x)-x, mm(p.GetPosition().y)-y) > 2.0
                   for p in allpads)
    def _seg_dist(x, y, x1, y1, x2, y2):                 # point->segment distance (mm)
        dx, dy = x2-x1, y2-y1
        L2 = dx*dx + dy*dy
        tt = 0.0 if L2 == 0 else max(0.0, min(1.0, ((x-x1)*dx + (y-y1)*dy)/L2))
        return math.hypot(x-(x1+tt*dx), y-(y1+tt*dy))
    def clear_of_tracks(x, y, netcode):                  # keep a via clear of foreign copper
        for t in tracks:
            if t.GetNetCode() == netcode:                # same-net copper is fine to touch
                continue
            if _seg_dist(x, y, mm(t.GetStart().x), mm(t.GetStart().y),
                         mm(t.GetEnd().x), mm(t.GetEnd().y)) < 1.0:
                return False
        return True
    healed, skipped = 0, 0
    for u in unc:
        its = u.get("items", [])
        nets = [re.search(r'\[([^\]]+)\]', it.get("description", "")) for it in its]
        net = next((mch.group(1) for mch in nets if mch), None)
        if net not in zone:
            skipped += 1; continue                       # not a plane net -> leave to a human
        z = zone[net]
        # find the orphan pad: the reported endpoint that is NOT on the plane layer
        orphan = None
        for it in its:
            if "pos" not in it: continue
            p = padidx.get((net, round(it["pos"]["x"], 2), round(it["pos"]["y"], 2)))
            if p is not None and not p.IsOnLayer(z.GetLayer()):
                orphan = p; break
        if orphan is None:                               # fall back to first plane-net endpoint
            for it in its:
                p = padidx.get((net, round(it["pos"]["x"], 2), round(it["pos"]["y"], 2))) if "pos" in it else None
                if p is not None: orphan = p; break
        if orphan is None:
            skipped += 1; continue
        ox, oy = mm(orphan.GetPosition().x), mm(orphan.GetPosition().y)
        ext = max(mm(orphan.GetSize().x), mm(orphan.GetSize().y)) / 2.0
        # scan compass directions / radii for a via site on solid plane, clear of pads
        site = None
        for r in (ext + 1.0, ext + 1.6, ext + 2.4, ext + 3.2):
            for ang in range(0, 360, 30):
                vx, vy = ox + r*math.cos(math.radians(ang)), oy + r*math.sin(math.radians(ang))
                if (solid(z, vx, vy) and clear_of_pads(vx, vy, orphan)
                        and clear_of_tracks(vx, vy, orphan.GetNetCode())):
                    site = (vx, vy); break
            if site: break
        if not site:
            print("  heal SKIP %s at (%.1f,%.1f): no clear plane via site" % (net, ox, oy))
            skipped += 1; continue
        vx, vy = site
        via = pcbnew.PCB_VIA(b)
        via.SetPosition(pcbnew.VECTOR2I(FM(vx), FM(vy)))
        via.SetDrill(FM(0.4)); via.SetWidth(FM(0.8)); via.SetNetCode(orphan.GetNetCode())
        via.SetLayerPair(pcbnew.F_Cu, pcbnew.B_Cu); b.Add(via)
        t = pcbnew.PCB_TRACK(b)                            # short F.Cu tie pad -> via
        t.SetStart(pcbnew.VECTOR2I(FM(ox), FM(oy))); t.SetEnd(pcbnew.VECTOR2I(FM(vx), FM(vy)))
        t.SetLayer(pcbnew.F_Cu); t.SetWidth(FM(0.4)); t.SetNetCode(orphan.GetNetCode()); b.Add(t)
        healed += 1
        print("  healed %s: %s.%s -> via(%.1f,%.1f) into %s plane" % (net,
              orphan.GetParentFootprint().GetReference(), orphan.GetNumber(), vx, vy, net))
    if healed:
        pcbnew.ZONE_FILLER(b).Fill(b.Zones())             # let the plane take the new vias
        pcbnew.SaveBoard(brd, b)
        print("healed %d plane-net orphan(s)%s" % (healed,
              (", %d left for a human" % skipped) if skipped else ""))
    elif skipped:
        print("heal: %d unconnected left (not auto-healable -- see DRC)" % skipped)
    return healed

def heal_bus_gaps(brd, clear=0.2, cell=0.2, pad_mm=8.0):
    """Finish the backplane bus hops Freerouting converges without completing (it
    logs "autorouter can't improve... finish manually" and leaves ~10 single-pitch
    hops). A path exists -- the router placed the other nine hops of each net -- so
    a focused two-layer A* maze router closes them deterministically. For each
    DRC-reported unconnected pair (non-plane), it rasterises foreign copper (tracks,
    pads, keepout rule-areas) into an F.Cu and a B.Cu occupancy grid over a window
    around the pair, then A*-routes pad->pad on that grid with layer changes via
    stitching vias, and lays the resulting tracks + vias. Same-net copper is
    passable. Anything it can't route it leaves for a human; the final DRC is the
    backstop. Returns the number closed."""
    import json, re, math, heapq
    j = "/tmp/_bus_%d.json" % os.getpid()
    subprocess.run([CLI, "pcb", "drc", "--format", "json", "-o", j, brd],
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    unc = json.load(open(j)).get("unconnected_items", [])
    if not unc:
        print("bus-heal: 0 unconnected"); return 0
    b = pcbnew.LoadBoard(brd); mm = pcbnew.ToMM; FM = pcbnew.FromMM
    plane_nets = set(z.GetNetname() for z in b.Zones()
                     if z.GetLayer() in (pcbnew.In1_Cu, pcbnew.In2_Cu))
    tw = 0.25
    # halo = min centre-to-foreign-edge distance a routed cell centre must keep.
    # Includes the rule clearance, our track half-width, AND a cell/2 margin so a
    # segment drawn between two "free" cell centres can't clip an obstacle that
    # sits between them (the coarse-grid short-circuit bug).
    halo = clear + tw/2.0 + cell/2.0 + 0.05
    # foreign copper as (kind, geom..., layerset, netcode); layerset: 'F','B','FB'
    def lset(item):
        f, bk = item.IsOnLayer(pcbnew.F_Cu), item.IsOnLayer(pcbnew.B_Cu)
        return "FB" if (f and bk) else ("F" if f else "B")
    segs = [(mm(t.GetStart().x), mm(t.GetStart().y), mm(t.GetEnd().x), mm(t.GetEnd().y),
             mm(t.GetWidth())/2.0, lset(t), t.GetNetCode())
            for t in b.GetTracks() if t.Type() == pcbnew.PCB_TRACE_T]
    vias = []
    for t in b.GetTracks():
        if t.Type() != pcbnew.PCB_VIA_T: continue
        try:    vr = mm(t.Cast().GetWidth())/2.0
        except Exception: vr = 0.35
        vias.append((mm(t.GetStart().x), mm(t.GetStart().y), vr, t.GetNetCode()))
    padrects = [(mm(p.GetPosition().x), mm(p.GetPosition().y),
                 max(mm(p.GetSize().x), mm(p.GetSize().y))/2.0, lset(p), p.GetNetCode())
                for fp in b.GetFootprints() for p in fp.Pads()]
    keepz = []                                           # keepout rule-areas (block both signal layers)
    for z in b.Zones():
        if z.GetIsRuleArea():
            bb = z.GetBoundingBox()
            keepz.append((mm(bb.GetLeft()), mm(bb.GetTop()), mm(bb.GetRight()), mm(bb.GetBottom())))
    def _sd(px, py, x1, y1, x2, y2):
        dx, dy = x2-x1, y2-y1; L2 = dx*dx+dy*dy
        tt = 0.0 if L2 == 0 else max(0.0, min(1.0, ((px-x1)*dx+(py-y1)*dy)/L2))
        return math.hypot(px-(x1+tt*dx), py-(y1+tt*dy))
    def blocked(x, y, layer, nc):
        for (a, c, e, f, hw, ls, snc) in segs:
            if snc == nc or layer not in ls: continue
            if _sd(x, y, a, c, e, f) < halo + hw: return True
        for (a, c, r, snc) in vias:
            if snc == nc: continue
            if math.hypot(x-a, y-c) < halo + r: return True
        for (a, c, r, ls, snc) in padrects:
            if snc == nc or layer not in ls: continue
            if abs(x-a) < halo + r and abs(y-c) < halo + r: return True
        for (x0, y0, x1, y1) in keepz:
            if x0-halo < x < x1+halo and y0-halo < y < y1+halo: return True
        return False
    def astar(ax, ay, cx, cy, nc):
        x0, x1 = min(ax, cx)-pad_mm, max(ax, cx)+pad_mm
        y0, y1 = min(ay, cy)-pad_mm, max(ay, cy)+pad_mm
        W = int((x1-x0)/cell)+1; H = int((y1-y0)/cell)+1
        def gx(x): return min(W-1, max(0, int(round((x-x0)/cell))))
        def gy(y): return min(H-1, max(0, int(round((y-y0)/cell))))
        sx, sy, tx, ty = gx(ax), gy(ay), gx(cx), gy(cy)
        LC = ("F", "B")                                  # layer code for blocked()
        occ = {}                                         # memoised blocked() per (i,j,layer)
        def free(i, j, l):
            k = (i, j, l)
            if k not in occ:
                occ[k] = not blocked(x0+i*cell, y0+j*cell, LC[l], nc)
            return occ[k]
        start = (sx, sy, 0)
        goals = {(tx, ty, 0), (tx, ty, 1)}
        h = lambda i, j: (abs(i-tx)+abs(j-ty))
        openq = [(h(sx, sy), 0, start)]; came = {start: None}; g = {start: 0}
        VIA = 8                                          # via cost (grid steps)
        seen = 0
        while openq and seen < 200000:
            seen += 1
            _, gc, cur = heapq.heappop(openq)
            if cur in goals:
                path = []
                while cur is not None: path.append(cur); cur = came[cur]
                return [(x0+i*cell, y0+j*cell, l) for (i, j, l) in reversed(path)]
            ci, cj, cl = cur
            nbrs = [(ci+1, cj, cl, 1), (ci-1, cj, cl, 1), (ci, cj+1, cl, 1), (ci, cj-1, cl, 1),
                    (ci, cj, 1-cl, VIA)]
            for ni, nj, nl, cost in nbrs:
                if not (0 <= ni < W and 0 <= nj < H): continue
                if not free(ni, nj, nl): continue
                if nl != cl and not free(ni, nj, cl): continue   # via needs both layers clear
                nn = (ni, nj, nl); ng = gc+cost
                if ng < g.get(nn, 1e9):
                    g[nn] = ng; came[nn] = cur
                    heapq.heappush(openq, (ng+h(ni, nj), ng, nn))
        return None
    def add_track(x1, y1, x2, y2, layer, nc):
        t = pcbnew.PCB_TRACK(b); t.SetStart(pcbnew.VECTOR2I(FM(x1), FM(y1)))
        t.SetEnd(pcbnew.VECTOR2I(FM(x2), FM(y2)))
        t.SetLayer(layer); t.SetWidth(FM(tw)); t.SetNetCode(nc); b.Add(t)
    def add_via(x, y, nc):
        v = pcbnew.PCB_VIA(b); v.SetPosition(pcbnew.VECTOR2I(FM(x), FM(y)))
        v.SetDrill(FM(0.4)); v.SetWidth(FM(0.7)); v.SetNetCode(nc)
        v.SetLayerPair(pcbnew.F_Cu, pcbnew.B_Cu); b.Add(v)
    LY = (pcbnew.F_Cu, pcbnew.B_Cu)
    healed, skipped = 0, 0
    for u in unc:
        its = [it for it in u.get("items", []) if "pos" in it]
        if len(its) < 2: continue
        m = next((re.search(r'\[([^\]]+)\]', it.get("description", "")) for it in its
                  if re.search(r'\[([^\]]+)\]', it.get("description", ""))), None)
        net = m.group(1) if m else None
        if net in plane_nets or net is None:
            continue
        nc = b.FindNet(net).GetNetCode()
        ax, ay = its[0]["pos"]["x"], its[0]["pos"]["y"]
        cx, cy = its[1]["pos"]["x"], its[1]["pos"]["y"]
        path = astar(ax, ay, cx, cy, nc)
        if not path:
            skipped += 1
            print("  bus-heal SKIP %-7s (%.1f,%.1f)->(%.1f,%.1f): no maze route" % (net, ax, ay, cx, cy))
            continue
        # emit: collapse collinear runs per layer, drop a via at each layer change
        run = [path[0]]
        for p in path[1:]:
            if p[2] != run[-1][2]:                       # layer change -> via at the switch point
                for a, c in zip(run, run[1:]):
                    add_track(a[0], a[1], c[0], c[1], LY[a[2]], nc)
                add_via(run[-1][0], run[-1][1], nc)
                # register the new via as an obstacle for later gaps
                vias.append((run[-1][0], run[-1][1], 0.35, nc))
                run = [p]
            else:
                run.append(p)
        for a, c in zip(run, run[1:]):
            add_track(a[0], a[1], c[0], c[1], LY[a[2]], nc)
        # register new tracks as obstacles for later gaps in this pass
        for a, c in zip(path, path[1:]):
            if a[2] == c[2]:
                segs.append((a[0], a[1], c[0], c[1], tw/2.0, "F" if a[2]==0 else "B", nc))
        healed += 1
        print("  bus-healed %-7s (%.1f,%.1f)->(%.1f,%.1f) via maze (%d pts)" % (net, ax, ay, cx, cy, len(path)))
    if not healed:
        if skipped: print("bus-heal: %d gap(s) left (none maze-routable)" % skipped)
        return 0
    # SAFETY: never ship maze copper that shorts or crowds. Save to a temp, DRC it,
    # and only overwrite the real board if we added ZERO blocking violations.
    COSMETIC = {"silk_overlap", "silk_edge_clearance", "silk_over_copper"}
    def _blocking(path_):
        jj = "/tmp/_bus_chk_%d.json" % os.getpid()
        subprocess.run([CLI, "pcb", "drc", "--format", "json", "-o", jj, path_],
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        dd = json.load(open(jj))
        return sum(1 for v in dd.get("violations", []) if v["type"] not in COSMETIC)
    base_block = _blocking(brd)
    tmp = "/tmp/_bus_try_%d.kicad_pcb" % os.getpid()
    pcbnew.SaveBoard(tmp, b)
    new_block = _blocking(tmp)
    if new_block > base_block:
        print("bus-heal: REJECTED -- maze routing added %d blocking DRC (was %d); board unchanged"
              % (new_block - base_block, base_block))
        return 0
    pcbnew.SaveBoard(brd, b)
    print("bus-healed %d gap(s)%s (0 new blocking DRC)" %
          (healed, (", %d left for a human" % skipped) if skipped else ""))
    return healed

def heal_edge_clearance(brd, clear=0.5, margin=0.06):
    """Post-route heal: Freerouting occasionally lays a track segment a hair too
    close to the board edge (e.g. an A2 bus track hugging the left edge by the DIN
    connector at 0.468mm vs the 0.5mm rule). These boards are rectangular, so pull
    any copper vertex that sits inside clear+halfwidth of an edge straight back in,
    perpendicular to that edge, moving every coincident endpoint together so the
    net stays whole. A ~0.05mm nudge fixes the clearance without disturbing routing.
    Returns the number of vertices moved."""
    b = pcbnew.LoadBoard(brd); mm = pcbnew.ToMM; FM = pcbnew.FromMM
    # true board edge = the Edge.Cuts *centreline* (what DRC measures to); the
    # board bbox instead includes the cut line's half-width, so read the drawings.
    xs, ys = [], []
    for d in b.GetDrawings():
        if d.GetLayer() == pcbnew.Edge_Cuts:
            bx = d.GetBoundingBox()
            hw = mm(d.GetWidth()) / 2.0
            xs += [mm(bx.GetLeft()) + hw, mm(bx.GetRight()) - hw]
            ys += [mm(bx.GetTop()) + hw, mm(bx.GetBottom()) - hw]
    if not xs:
        bb = b.GetBoardEdgesBoundingBox()
        xs = [mm(bb.GetLeft()), mm(bb.GetRight())]; ys = [mm(bb.GetTop()), mm(bb.GetBottom())]
    x0, x1, y0, y1 = min(xs), max(xs), min(ys), max(ys)
    tracks = [t for t in b.GetTracks() if t.Type() == pcbnew.PCB_TRACE_T]
    # gather endpoints that need a push: {(rounded old pos): new pos}
    moves = {}
    for t in tracks:
        hw = mm(t.GetWidth()) / 2.0
        need = clear + hw
        for get in (t.GetStart, t.GetEnd):
            px, py = mm(get().x), mm(get().y)
            nx, ny = px, py
            if px - x0 < need: nx = x0 + need + margin
            if x1 - px < need: nx = x1 - need - margin
            if py - y0 < need: ny = y0 + need + margin
            if y1 - py < need: ny = y1 - need - margin
            if (nx, ny) != (px, py):
                moves[(round(px, 4), round(py, 4))] = (nx, ny)
    if not moves:
        print("heal_edge: 0 edge-hugging vertices"); return 0
    moved = 0
    for t in tracks:
        for setp, getp in ((t.SetStart, t.GetStart), (t.SetEnd, t.GetEnd)):
            key = (round(mm(getp().x), 4), round(mm(getp().y), 4))
            if key in moves:
                nx, ny = moves[key]
                setp(pcbnew.VECTOR2I(FM(nx), FM(ny))); moved += 1
    pcbnew.SaveBoard(brd, b)
    print("heal_edge: pulled %d vertex/segment endpoint(s) back from the board edge" % moved)
    return moved

def import_ses(brd, ses):
    b = pcbnew.LoadBoard(brd)
    pcbnew.ImportSpecctraSES(b, ses)
    stitch_trivial_nets(b)                              # finish any net the router missed
    pcbnew.ZONE_FILLER(b).Fill(b.Zones())
    pcbnew.SaveBoard(brd, b)
    b.BuildConnectivity()
    ntrk = sum(1 for t in b.GetTracks() if t.Type() == pcbnew.PCB_TRACE_T)
    nvia = sum(1 for t in b.GetTracks() if t.Type() == pcbnew.PCB_VIA_T)
    print("import_ses: %d tracks, %d vias" % (ntrk, nvia))
    heal_edge_clearance(brd)                            # pull any edge-hugging track back inside
    heal_unconnected(brd)                               # DRC-driven heal for what the router+stitch left

def placement(brd):
    b = pcbnew.LoadBoard(brd)
    bb = b.GetBoardEdgesBoundingBox()
    bw = pcbnew.ToMM(bb.GetWidth())
    paper, pw, ph = ("A4", 297.0, 210.0) if bw <= 280 else ("A3", 420.0, 297.0)
    c = bb.GetCenter()
    shift = pcbnew.VECTOR2I(pcbnew.FromMM(pw) // 2 - c.x, pcbnew.FromMM(ph) // 2 - c.y)
    for it in (list(b.GetFootprints()) + list(b.GetTracks())
               + list(b.GetDrawings()) + list(b.Zones())):
        it.Move(shift)
    name = os.path.basename(brd)[:-len(".kicad_pcb")]
    tmp = "/tmp/%s-placement.kicad_pcb" % name
    pcbnew.SaveBoard(tmp, b)
    tb = ('  (title_block\n    (title "%s -- Parts Placement")\n'
          '    (company "P8X")\n  )\n' % name)
    t = open(tmp).read()
    if paper == "A3":
        t = t.replace('(paper "A4")', '(paper "A3")', 1)
    t = t.replace('(paper "%s")\n' % paper, '(paper "%s")\n' % paper + tb, 1)
    open(tmp, "w").write(t)
    out = os.path.join(os.path.dirname(brd), name + "-placement.pdf")
    _run(CLI, "pcb", "export", "pdf", "--layers", "F.Silkscreen,F.Fab,Edge.Cuts",
         "--black-and-white", "--include-border-title", "-o", out, tmp)
    os.remove(tmp)
    print("placement ->", out)

def _boilerplate(d, name):
    gi=os.path.join(d,".gitignore")
    open(gi,"w").write("gerbers/\n*.dsn\n*.kicad_prl\n*.rpt\nfr.log\nlogs/\n")
    rd=os.path.join(d,"README.md")
    if not os.path.exists(rd):
        card=name.replace("p8x-","")
        open(rd,"w").write(
"# %s -- KiCad\n\n"
"Generated by `generators/gen_kicad.py` from the canonical gen_eagle netlist\n"
"(`CARDS[\"%s\"]`), same standard as the memory card: 4-layer (F/B signals,\n"
"In1=GND, In2=VCC planes), a bypass cap above each IC, a labelled LED/jumper bank,\n"
"part values on silk. Routed with Freerouting. GENERATORS ARE CANON -- edit\n"
"`gen_kicad.py` and re-run `generators/build_kicad_card.sh %s`.\n\n"
"| File | What |\n|------|------|\n"
"| `p8x-%s.kicad_pcb` | the board |\n"
"| `p8x-%s.ses` | the Freerouting routing |\n"
"| `p8x-%s-gerbers.zip` | orderable gerbers |\n"
"| `p8x-%s-placement.pdf` | parts placement (refs+values) |\n"
"| `p8x-%s-render-top.png` / `-3d.png` | renders |\n\n"
"Exotic parts use the closest standard KiCad footprint (flagged when built).\n"
% (card,card,card,card,card,card,card,card))

def finish(brd):
    d = os.path.dirname(brd); name = os.path.basename(brd)[:-len(".kicad_pcb")]
    ger = os.path.join(d, "gerbers"); zipf = os.path.join(d, name + "-gerbers.zip")
    if os.path.isdir(ger):
        for f in os.listdir(ger): os.remove(os.path.join(ger, f))
    _run(CLI, "pcb", "export", "gerbers", "--no-protel-ext", "-o", ger + "/", brd)
    _run(CLI, "pcb", "export", "drill", "--format", "excellon", "--excellon-units", "mm", "-o", ger + "/", brd)
    if os.path.exists(zipf): os.remove(zipf)
    import glob, zipfile
    with zipfile.ZipFile(zipf, "w", zipfile.ZIP_DEFLATED) as z:
        for f in sorted(glob.glob(ger + "/*.gbr") + glob.glob(ger + "/*.gbrjob") + glob.glob(ger + "/*.drl")):
            z.write(f, os.path.basename(f))
    _run(CLI, "pcb", "render", "--side", "top", "--quality", "high", "--floor",
         "-w", "1800", "-h", "1000", "-o", os.path.join(d, name + "-render-top.png"), brd)
    _run(CLI, "pcb", "render", "--rotate", "-25,0,22", "--perspective", "--quality", "high", "--floor",
         "-w", "1800", "-h", "1100", "-o", os.path.join(d, name + "-render-3d.png"), brd)
    placement(brd)
    _boilerplate(d, name)
    print("finish: gerbers + renders + placement for", name)

if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "export_dsn": export_dsn(sys.argv[2])
    elif cmd == "import_ses": import_ses(sys.argv[2], sys.argv[3])
    elif cmd == "heal": heal_unconnected(sys.argv[2])
    elif cmd == "heal_bus": heal_bus_gaps(sys.argv[2])
    elif cmd == "heal_edge": heal_edge_clearance(sys.argv[2])
    elif cmd == "placement": placement(sys.argv[2])
    elif cmd == "finish": finish(sys.argv[2])
    else: sys.exit("unknown cmd " + cmd)
    sys.stdout.flush(); os._exit(0)   # skip the wx.App event-loop exit hang (work is saved)
