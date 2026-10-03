#!/usr/bin/env python3
"""render_assembly.py -- 3D render of the assembled P8X: the backplane with every
plug-in card standing in its DIN 41612 slot.

Runs under KiCad 10's bundled Python (it imports pcbnew). Driver:
hardware/assembly/build.sh.

    render_assembly.py [--scratch DIR] [--out DIR] [--quality basic|high] [--reuse]

--reuse keeps card STEPs already in the scratch directory (for trying camera
views; drop it after a board changes).

GENERATORS ARE CANON: the real boards are only READ. Every board is copied into
the scratch directory first; all intermediate files (card STEPs, measurement
STLs, the assembly board) live there. Only the finished PNGs are written to the
output directory (default hardware/assembly/).

How the assembly is put together
--------------------------------
1. Each card is exported as a STEP with its component models, silkscreen and
   solder mask (kicad-cli pcb export step --subst-models).
2. A scratch copy of the backplane gets one extra footprint per slot whose only
   content is that card's STEP as a 3D model. The footprint sits at the board
   origin with no rotation, so the model's (offset, rotate) carry the whole
   card-to-backplane transform.
3. The transform is derived, not placed by eye:
   * X/Y come from the pads (pcbnew): the card's J1 pad a1 must land on the
     slot connector's pad a1, its pin rows a..c on the socket's columns a..c,
     and its pins 1..32 along the socket's pins 1..32. The slot is the backplane
     footprint whose value is "SLOT<n>".
   * The insertion depth comes from the two connector models (STL exports of
     J1 alone, measured below): the card sits fully mated, with the top face
     of the female socket against the inner face of the male connector's
     shroud (the face its pins come out of).
   * The rotation is the one proper rotation (no mirroring) that maps the
     card's "away from the connector edge" direction to the backplane's up
     direction, its pin-1 -> pin-32 direction to the socket's, and its
     row-a -> row-c direction (the card's component-side normal; row a is the
     row nearest the card surface) to the socket's. KiCad's 3D-model rotation
     angles are then solved for that matrix.
4. kicad-cli pcb render draws the assembly board from the VIEWS below.
"""
import argparse, collections, itertools, math, os, shutil, struct, subprocess, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
CLI = "/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli"

# Slot order. No card is tied to a slot electrically (every slot sees the same
# bus); this is the order of the CPU data path, peripherals after it, and the
# bring-up bus test card in the last slot.
SLOTS = [
    (1, "control-card"),
    (2, "regbank-card"),
    (3, "alu-card"),
    (4, "memory-card"),
    (5, "io-card"),
    (6, "cf-card"),
    (7, "ps2-card"),
    (8, "bustest-card"),
]

# Camera views: (file name, kicad-cli render arguments). The pivot (the point
# the camera turns about) is set to the middle of the card cage in main().
VIEWS = [
    ("p8x-assembly-render.png",        # 3/4 view from above, onto the component sides
     ["--rotate", "-45,0,-20", "--zoom", "0.68", "--perspective", "--floor",
      "-w", "2400", "-h", "1600"]),
    ("p8x-assembly-render-low.png",    # low view along the slots: connectors and seating
     ["--rotate", "-65,0,-25", "--zoom", "0.72", "--perspective", "-w", "2400", "-h", "1600"]),
    ("p8x-assembly-render-side.png",   # orthographic elevation looking along the sockets
     ["--rotate", "-90,0,0", "--zoom", "0.8", "-w", "1800", "-h", "1600"]),
]
RENDER = ["--background", "opaque"]


def run(*args):
    r = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    if r.returncode != 0:
        sys.exit("command failed: %s\n%s" % (" ".join(args), r.stdout[-2000:]))
    return r.stdout


# ---------------------------------------------------------------- STL geometry
def read_stl(fn):
    """Triangles of an STL file (binary or ASCII) as [(v0, v1, v2), ...]."""
    d = open(fn, "rb").read()
    pts = []
    if d[:5] == b"solid" and b"facet" in d[:400]:
        for line in d.decode().splitlines():
            line = line.strip()
            if line.startswith("vertex"):
                pts.append(tuple(map(float, line.split()[1:4])))
    else:
        n = struct.unpack("<I", d[80:84])[0]
        for i in range(n):
            v = struct.unpack("<12f", d[84 + i * 50:84 + i * 50 + 48])
            pts += [v[3:6], v[6:9], v[9:12]]
    return [pts[i:i + 3] for i in range(0, len(pts), 3)]


def planar_faces(tris, axis):
    """Triangles lying in a plane perpendicular to `axis`, grouped by position."""
    faces = collections.defaultdict(list)
    for t in tris:
        a = [v[axis] for v in t]
        if max(a) - min(a) < 1e-3:
            faces[round(a[0], 3)].append(t)
    return faces


def extent(tris, axis):
    a = [v[axis] for t in tris for v in t]
    return min(a), max(a)


def export_j1_stl(pcb, out):
    run(CLI, "pcb", "export", "stl", "--subst-models", "--no-board-body",
        "--component-filter", "J1", "-f", "-o", out, pcb)
    return read_stl(out)


def measure_male(tris, edge_x):
    """Male right-angle DIN 41612 on a card (STL frame: x = card x, y = -card y,
    z up from the card's underside). Returns (z of the row-a pin axis, x of the
    shroud's inner face)."""
    # Mating pins: the only geometry strictly inside the shroud, between its
    # front face and the face the pins come out of.
    xf = planar_faces(tris, 0)
    beyond = {x: ts for x, ts in xf.items() if x < edge_x + 0.5}
    front = min(beyond)
    # the inner face is pierced by all 96 pins: the most finely meshed one
    inner = max((x for x in beyond if x != front), key=lambda x: len(beyond[x]))
    pinz = [v[2] for t in tris for v in t if front + 0.2 < v[0] < inner - 0.2]
    zmin = min(pinz)
    row_a = [z for z in pinz if z < zmin + 1.0]       # the lowest pin row
    return (min(row_a) + max(row_a)) / 2.0, inner


def measure_female(tris):
    """Vertical female DIN 41612 on the backplane (STL frame). Returns the
    height of its top face above its seating plane (the underside of the
    housing: the lowest horizontal face as wide as the whole housing)."""
    x0, x1 = extent(tris, 0)
    zf = planar_faces(tris, 2)
    seat = min(z for z, ts in zf.items()
               if abs(extent(ts, 0)[0] - x0) < 0.05 and abs(extent(ts, 0)[1] - x1) < 0.05)
    return extent(tris, 2)[1] - seat


# ---------------------------------------------------------------- rotations
def mat_mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]


def rot(axis, deg):
    c, s = round(math.cos(math.radians(deg))), round(math.sin(math.radians(deg)))
    if axis == 0:
        return [[1, 0, 0], [0, c, -s], [0, s, c]]
    if axis == 1:
        return [[c, 0, s], [0, 1, 0], [-s, 0, c]]
    return [[c, -s, 0], [s, c, 0], [0, 0, 1]]


def kicad_model_matrix(rx, ry, rz):
    """KiCad's 3D viewer applies a model's (rotate rx ry rz) as
    Rz(-rz) * Ry(-ry) * Rx(-rx) (right-handed, Y up)."""
    return mat_mul(rot(2, -rz), mat_mul(rot(1, -ry), rot(0, -rx)))


def solve_rotation(R):
    for rx, ry, rz in itertools.product((0, 90, 180, 270), repeat=3):
        if kicad_model_matrix(rx, ry, rz) == R:
            return rx, ry, rz
    sys.exit("no KiCad rotation for %r" % (R,))


def unit(v):
    m = math.sqrt(sum(c * c for c in v))
    return [round(c / m) for c in v]


# ---------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--scratch", default=os.path.join(os.environ.get("TMPDIR", "/tmp"), "p8x-assembly"))
    ap.add_argument("--out", default=os.path.join(ROOT, "hardware", "assembly"))
    ap.add_argument("--quality", default="high")
    ap.add_argument("--reuse", action="store_true", help="reuse card STEPs already in scratch")
    a = ap.parse_args()

    import pcbnew
    scratch = os.path.abspath(a.scratch)
    os.makedirs(scratch, exist_ok=True)
    os.makedirs(a.out, exist_ok=True)

    def copy_board(board):
        """Copy hardware/<board>/kicad/p8x-<board>.kicad_pcb (+ .kicad_pro) to scratch."""
        src = os.path.join(ROOT, "hardware", board, "kicad", "p8x-%s" % board)
        dst_dir = os.path.join(scratch, board)
        os.makedirs(dst_dir, exist_ok=True)
        dst = os.path.join(dst_dir, "p8x-%s" % board)
        for ext in (".kicad_pcb", ".kicad_pro"):
            if os.path.exists(src + ext):
                shutil.copyfile(src + ext, dst + ext)
        return dst + ".kicad_pcb"

    def xy(p):              # pcbnew position -> 3D frame (mm, Y up)
        return p.x / 1e6, -p.y / 1e6

    # --- backplane copy: slot sockets and the socket height
    bp_pcb = copy_board("backplane")
    female_h = measure_female(export_j1_stl(bp_pcb, os.path.join(scratch, "backplane", "J1.stl")))
    bp = pcbnew.LoadBoard(bp_pcb)
    sockets = {}
    for fp in bp.GetFootprints():
        val = fp.GetValue()
        if val.startswith("SLOT"):
            pads = {p.GetNumber(): xy(p.GetPosition()) for p in fp.Pads()}
            sockets[int(val[4:])] = pads
    print("socket top face %.2f mm above the backplane; %d slots" % (female_h, len(sockets)))

    offsets = []
    for slot, card in SLOTS:
        pcb = copy_board(card)
        step = pcb[:-len(".kicad_pcb")] + ".step"
        cb = pcbnew.LoadBoard(pcb)
        cbb = cb.GetBoardEdgesBoundingBox()
        edge_x, card_h = cbb.GetX() / 1e6, cbb.GetWidth() / 1e6
        j1 = [fp for fp in cb.GetFootprints() if fp.GetReference() == "J1"][0]
        assert "DIN41612" in j1.GetFPIDAsString(), card
        cp = {p.GetNumber(): xy(p.GetPosition()) for p in j1.Pads()}
        row_a_z, inner_x = measure_male(export_j1_stl(pcb, os.path.join(scratch, card, "J1.stl")), edge_x)
        if not (a.reuse and os.path.exists(step)):
            run(CLI, "pcb", "export", "step", "--subst-models", "--include-silkscreen",
                "--include-soldermask", "-f", "-o", step, pcb)

        bs = sockets[slot]
        # card axes (3D frame: x, y = -kicad y, z = card normal) -> backplane axes
        c_pins = unit([cp["a32"][0] - cp["a1"][0], cp["a32"][1] - cp["a1"][1], 0])
        b_pins = unit([bs["a32"][0] - bs["a1"][0], bs["a32"][1] - bs["a1"][1], 0])
        c_rows = unit([cp["c1"][0] - cp["a1"][0], cp["c1"][1] - cp["a1"][1], 0])
        b_rows = unit([bs["c1"][0] - bs["a1"][0], bs["c1"][1] - bs["a1"][1], 0])
        # On the card the PCB tails of rows a..c step away from the connector
        # edge, and the mating pins of rows a..c step up off the card surface.
        # So: card "rows" direction (in-plane) -> backplane up (+Z);
        #     card normal (+Z, the row a->c mating stack) -> socket rows a->c;
        #     card pins 1->32 -> socket pins 1->32.
        R = [[0] * 3 for _ in range(3)]
        for src, dst in ((c_rows, [0, 0, 1]), ([0, 0, 1], b_rows), (c_pins, b_pins)):
            for i in range(3):
                for j in range(3):
                    R[i][j] += dst[i] * src[j]
        det = (R[0][0] * (R[1][1] * R[2][2] - R[1][2] * R[2][1])
               - R[0][1] * (R[1][0] * R[2][2] - R[1][2] * R[2][0])
               + R[0][2] * (R[1][0] * R[2][1] - R[1][1] * R[2][0]))
        assert det == 1, "mirrored mapping for %s" % card
        rx, ry, rz = solve_rotation(R)
        # anchor: card pin a1 on the inner shroud face -> socket a1 at its top face
        p_card = [inner_x, cp["a1"][1], row_a_z]
        p_bp = [bs["a1"][0], bs["a1"][1], female_h]
        Rp = [sum(R[i][k] * p_card[k] for k in range(3)) for i in range(3)]
        off = [p_bp[i] - Rp[i] for i in range(3)]
        offsets.append(off)
        print("slot %d %-13s rotate (%d %d %d) offset (%.3f %.3f %.3f)" % ((slot, card, rx, ry, rz) + tuple(off)))

        fp = pcbnew.FOOTPRINT(bp)
        fp.SetReference("ASSY%d" % slot)
        fp.SetValue(card)
        fp.Reference().SetVisible(False)
        fp.Value().SetVisible(False)
        m = pcbnew.FP_3DMODEL()
        m.m_Filename = step
        m.m_Offset = pcbnew.VECTOR3D(*off)
        m.m_Rotation = pcbnew.VECTOR3D(rx, ry, rz)
        m.m_Scale = pcbnew.VECTOR3D(1, 1, 1)
        fp.Add3DModel(m)
        bp.Add(fp)
        fp.SetPosition(pcbnew.VECTOR2I(0, 0))

    assy = os.path.join(scratch, "p8x-assembly.kicad_pcb")
    shutil.copyfile(os.path.join(scratch, "backplane", "p8x-backplane.kicad_pro"),
                    os.path.join(scratch, "p8x-assembly.kicad_pro"))
    pcbnew.SaveBoard(assy, bp)
    print("assembly board:", assy)

    # pivot: the middle of the cage, relative to the backplane centre, in cm
    bb = bp.GetBoardEdgesBoundingBox()
    cx = (min(o[0] for o in offsets) + max(o[0] for o in offsets)) / 2 + 10   # cards ~20 mm deep
    top = max(o[2] for o in offsets) + card_h
    pivot = "%.1f,0,%.1f" % ((cx - bb.GetCenter().x / 1e6) / 10, top / 2 / 10)
    for name, args in VIEWS:
        out = os.path.join(a.out, name)
        run(CLI, "pcb", "render", "--quality", a.quality, *args, *RENDER,
            "--pivot", pivot, "-o", out, assy)
        print("wrote", out)


if __name__ == "__main__":
    main()
    sys.stdout.flush()
    os._exit(0)          # skip the wx.App exit hang
