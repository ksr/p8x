#!/usr/bin/env python3
# Author: Claude (Anthropic) for Ken Rother, 2026
"""The 3D model of the PS/2 socket (a right-angle mini-DIN-6) for the boards' pictures: KiCad's library has none, so the
sockets showed as bare pads (Ken, 2026-11-23: new renders include the PS/2 connectors). Needs only Python:

    python3 tools/models/gen_minidin6.py        writes the two .step files beside this script

  MiniDIN6_MD-60SM.step       Same Sky MD-60SM with its pins; its origin is pad 1 of the MD-60SM footprints (elf, YACC1-D,
                              ELFII-VIDEO, P32W: mating face 8.5 mm in front of the row of four)
  MiniDIN6_RA_PS2-body.step   the same body without pins, for P8X's MiniDIN6_RA_PS2 footprint (another pin pattern,
                              origin its pad 1), the mating face on the side that footprint marks

From the data sheet (MD-SM rev 1.09, as recorded with YACC1's footprint, gen_v40.py): the body 14.0 x 13.0 x 12.8 mm, the
pins, the earth terminal and the two side legs (0.54 thick, centres 13.5 apart). NOT from it, only for the look: the
height of the opening, the contacts in it, the colours and how far the pins go down. A picture, not a part to measure.
"""
import math, os

HERE = os.path.dirname(os.path.abspath(__file__))
BLACK, TIN = (0.06, 0.06, 0.07), (0.78, 0.78, 0.76)


class Step:
    """a STEP file of solids, each a polygon (with holes) pushed along an axis"""
    def __init__(self, name):
        self.name, self.L, self.solids = name, [], []

    def e(self, s):
        self.L.append(s); return "#%d" % len(self.L)

    def vec(self, kind, v):
        return self.e("%s('',(%s))" % (kind, ",".join("%.5f" % (c + 0.0) for c in v)))

    def solid(self, outer, holes, axis, a, b, colour):
        """outer, holes: lists of (u, v); axis 'z': (u, v) = (x, y); axis 'x': (u, v) = (y, z). From a to b."""
        def area(p): return sum(p[i-1][0] * p[i][1] - p[i][0] * p[i-1][1] for i in range(len(p))) / 2
        loops = [outer if area(outer) > 0 else outer[::-1]] + [h if area(h) < 0 else h[::-1] for h in holes]
        at = (lambda p, w: (p[0], p[1], w)) if axis == "z" else (lambda p, w: (w, p[0], p[1]))
        up = (0, 0, 1) if axis == "z" else (1, 0, 0)
        verts, edges = {}, {}
        def vertex(p):
            if p not in verts:
                c = self.vec("CARTESIAN_POINT", p); verts[p] = (self.e("VERTEX_POINT('',%s)" % c), c)
            return verts[p]
        def oriented(p, q):
            if (q, p) in edges: return self.e("ORIENTED_EDGE('',*,*,%s,.F.)" % edges[(q, p)])
            if (p, q) not in edges:
                n = math.dist(p, q)
                d = self.vec("DIRECTION", [(q[i] - p[i]) / n for i in range(3)])
                line = self.e("LINE('',%s,%s)" % (vertex(p)[1], self.e("VECTOR('',%s,1.)" % d)))
                edges[(p, q)] = self.e("EDGE_CURVE('',%s,%s,%s,.T.)" % (vertex(p)[0], vertex(q)[0], line))
            return self.e("ORIENTED_EDGE('',*,*,%s,.T.)" % edges[(p, q)])
        def face(rings, normal, ref):
            bounds = []
            for i, r in enumerate(rings):
                loop = self.e("EDGE_LOOP('',(%s))" % ",".join(oriented(r[j], r[(j + 1) % len(r)]) for j in range(len(r))))
                bounds.append(self.e("%s('',%s,.T.)" % ("FACE_OUTER_BOUND" if i == 0 else "FACE_BOUND", loop)))
            ax = self.e("AXIS2_PLACEMENT_3D('',%s,%s,%s)" % (vertex(rings[0][0])[1], self.vec("DIRECTION", normal),
                                                             self.vec("DIRECTION", ref)))
            return self.e("ADVANCED_FACE('',(%s),%s,.T.)" % (",".join(bounds), self.e("PLANE('',%s)" % ax)))
        low = [[at(p, a) for p in l] for l in loops]
        high = [[at(p, b) for p in l] for l in loops]
        ref = (1, 0, 0) if axis == "z" else (0, 1, 0)
        faces = [face(high, up, ref), face([l[::-1] for l in low], tuple(-c for c in up), ref)]
        for l, h in zip(low, high):
            for j in range(len(l)):
                k = (j + 1) % len(l)
                n = math.dist(l[j], l[k]); d = [(l[k][i] - l[j][i]) / n for i in range(3)]
                normal = (d[1]*up[2] - d[2]*up[1], d[2]*up[0] - d[0]*up[2], d[0]*up[1] - d[1]*up[0])
                faces.append(face([[l[j], l[k], h[k], h[j]]], normal, d))
        s = self.e("MANIFOLD_SOLID_BREP('',%s)" % self.e("CLOSED_SHELL('',(%s))" % ",".join(faces)))
        self.solids.append((s, colour))

    def box(self, x0, x1, y0, y1, z0, z1, colour):
        self.solid([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], [], "z", z0, z1, colour)

    def write(self, path):
        e = self.e
        app = e("APPLICATION_CONTEXT('core data for automotive mechanical design processes')")
        e("APPLICATION_PROTOCOL_DEFINITION('international standard','automotive_design',2000,%s)" % app)
        prod = e("PRODUCT('%s','%s','',(%s))" % (self.name, self.name, e("PRODUCT_CONTEXT('',%s,'mechanical')" % app)))
        form = e("PRODUCT_DEFINITION_FORMATION('','',%s)" % prod)
        pdef = e("PRODUCT_DEFINITION('design','',%s,%s)" % (form, e("PRODUCT_DEFINITION_CONTEXT('part definition',%s,'design')" % app)))
        shape = e("PRODUCT_DEFINITION_SHAPE('','',%s)" % pdef)
        mm = e("(LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(.MILLI.,.METRE.))")
        rad = e("(NAMED_UNIT(*) PLANE_ANGLE_UNIT() SI_UNIT($,.RADIAN.))")
        ster = e("(NAMED_UNIT(*) SI_UNIT($,.STERADIAN.) SOLID_ANGLE_UNIT())")
        unc = e("UNCERTAINTY_MEASURE_WITH_UNIT(LENGTH_MEASURE(1.E-05),%s,'distance_accuracy_value','')" % mm)
        ctx = e("(GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNCERTAINTY_ASSIGNED_CONTEXT((%s)) "
                "GLOBAL_UNIT_ASSIGNED_CONTEXT((%s,%s,%s)) REPRESENTATION_CONTEXT('',''))" % (unc, mm, rad, ster))
        org = e("AXIS2_PLACEMENT_3D('',%s,%s,%s)" % (self.vec("CARTESIAN_POINT", (0, 0, 0)), self.vec("DIRECTION", (0, 0, 1)),
                                                     self.vec("DIRECTION", (1, 0, 0))))
        rep = e("ADVANCED_BREP_SHAPE_REPRESENTATION('%s',(%s),%s)" % (self.name, ",".join([org] + [s for s, _ in self.solids]), ctx))
        e("SHAPE_DEFINITION_REPRESENTATION(%s,%s)" % (shape, rep))
        styled = []
        for s, c in self.solids:
            rgb = e("COLOUR_RGB('',%.3f,%.3f,%.3f)" % c)
            fill = e("FILL_AREA_STYLE('',(%s))" % e("FILL_AREA_STYLE_COLOUR('',%s)" % rgb))
            side = e("SURFACE_SIDE_STYLE('',(%s))" % e("SURFACE_STYLE_FILL_AREA(%s)" % fill))
            psa = e("PRESENTATION_STYLE_ASSIGNMENT((%s))" % e("SURFACE_STYLE_USAGE(.BOTH.,%s)" % side))
            styled.append(e("STYLED_ITEM('',(%s),%s)" % (psa, s)))
        e("MECHANICAL_DESIGN_GEOMETRIC_PRESENTATION_REPRESENTATION('',(%s),%s)" % (",".join(styled), ctx))
        with open(path, "w") as f:
            f.write("ISO-10303-21;\nHEADER;\nFILE_DESCRIPTION(('%s'),'2;1');\nFILE_NAME('%s','2026-11-24',('Claude for Ken Rother'),"
                    "(''),'gen_minidin6.py','','');\nFILE_SCHEMA(('AUTOMOTIVE_DESIGN { 1 0 10303 214 1 1 1 1 }'));\nENDSEC;\nDATA;\n"
                    % (self.name, self.name))
            f.writelines("#%d=%s;\n" % (i + 1, s) for i, s in enumerate(self.L))
            f.write("ENDSEC;\nEND-ISO-10303-21;\n")
        print("wrote", path)


def circle(cy, cz, r, n=40):
    return [(cy + r * math.cos(2 * math.pi * i / n), cz + r * math.sin(2 * math.pi * i / n)) for i in range(n)]


def socket(name, face, mid, pins):
    """face: the mating face's x; mid: the centre line's y (y up), both from the origin pad. Opening towards +x."""
    s = Step(name)
    X = lambda x: face + x                              # x measured from the mating face, negative behind it
    W, D, H, CZ, DEEP = 7.0, 13.0, 12.8, 6.6, 8.0       # half width, depth, height; opening's centre and depth
    rect = [(mid - W, 0.0), (mid + W, 0.0), (mid + W, H), (mid - W, H)]
    s.solid(rect, [], "x", X(-D), X(-DEEP), BLACK)
    s.solid(rect, [circle(mid, CZ, 5.0)], "x", X(-DEEP), X(0), BLACK)
    s.solid(circle(mid, CZ, 5.0), [circle(mid, CZ, 4.75)], "x", X(-DEEP), X(0.02), TIN)       # the shell's ring
    contacts = [circle(mid + y, CZ + z, 0.5, 12) for y, z in ((1.3, -2.4), (-1.3, -2.4), (2.9, 0), (-2.9, 0), (2.2, 2.2), (-2.2, 2.2))]
    s.solid(circle(mid, CZ, 3.9), contacts, "x", X(-DEEP), X(-1.2), BLACK)                    # the insert, its six contacts
    for sign in (1, -1):                                                                      # the shield's side legs
        lo, hi = sorted((mid + sign * 6.49, mid + sign * 7.03))
        s.box(X(-6.4), X(-4.6), lo, hi, -3.2 if pins else 0.0, 5.5, TIN)
    if pins:
        s.box(X(-4.95), X(-4.45), mid - 0.9, mid + 0.9, -3.2, 0.0, TIN)                       # the earth terminal
        for x, y in ((-8.5, 1.3), (-8.5, -1.3), (-8.5, 3.4), (-8.5, -3.4), (-11.0, 3.4), (-11.0, -3.4)):
            s.box(X(x - 0.3), X(x + 0.3), mid + y - 0.3, mid + y + 0.3, -3.2, 0.0, TIN)
    s.write(os.path.join(HERE, name + ".step"))


if __name__ == "__main__":
    socket("MiniDIN6_MD-60SM", 8.5, -1.3, True)
    socket("MiniDIN6_RA_PS2-body", 4.0, 1.3, False)
