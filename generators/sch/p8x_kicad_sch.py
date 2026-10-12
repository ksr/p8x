#!/usr/bin/env python3
"""Write a P8X card netlist (generators/gen_eagle.py) as a KiCad schematic
project (KiCad 8+ format; opened and checked with KiCad 10). Ported from the
P32X schematic toolchain.

Output, in OUTDIR:
  <card>.kicad_sch             root sheet: one block per functional sheet
  <card>-<n>.kicad_sch         sub-sheets (parts + wires/labels)
  p8x.kicad_sym, sym-lib-table generated symbols as an editable project library
  <card>.kicad_pro             minimal project file (shared with the board)

Symbols are generated from the typed pins of p8x_symlib.SYM; every pin gets a
global label with its net name (or a drawn wire on ELK-wired sheets), so nets
connect across sheets exactly as in the canonical netlist. Unused pins get
no-connect flags; two PWR_FLAGs mark VCC and GND as supplied by the backplane.
UUIDs are derived from names, so the files are reproducible.

    python3 p8x_kicad_sch.py CARD OUTDIR [--check]
"""
import os, sys, uuid, json, math

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from p8x_symlib import SYM  # noqa: E402

VERSION = "20231120"
TXT = 9.0
G = 2.54
ETYPE = {"in": "input", "out": "output", "tri": "tri_state", "bidir": "bidirectional",
         "oc": "open_collector", "pwr": "power_in", "gnd": "power_in", "pas": "passive"}

def refdefault(dev):
    if dev in ("DIN96C", "DIN96", "DSUB9F", "IDE40", "HDR3", "HDR4", "HDR10", "JMP2X3",
               "MINIDIN6", "SW2", "DIP8SW", "PICO"):
        return "J"
    if dev in ("LED", "LEDARR8"):
        return "D"
    if dev in ("CAP", "CAP1"):
        return "C"
    if dev in ("RES", "SIP9", "RNISO8", "RNISO8D"):
        return "R"
    return "U"

def U(*names):
    return str(uuid.uuid5(uuid.NAMESPACE_URL, "p8x/" + "/".join(names)))

def q(s):
    return '"%s"' % s.replace("\\", "\\\\").replace('"', '\\"')

def pin_text(name):
    return "~{%s}" % name[1:] if name.startswith("-") else name

def font(hide=False, justify=None):
    j = " (justify %s)" % justify if justify else ""
    return "(effects (font (size 1.27 1.27))%s%s)" % (j, " hide" if hide else "")

def snap(v):
    return round(v / G) * G

def layout_for(dev):
    return SYM[dev]["layout"]

class Symbol:
    """Geometry of one generated symbol, in symbol coordinates (y up)."""
    def __init__(self, dev):
        self.dev = dev
        pins = SYM[dev]["pins"]
        left, right = layout_for(dev)
        self.power = [(p, t) for p, (n, t) in pins.items() if t in ("pwr", "gnd")]
        rows = max(len(left), len(right))
        names = [p for p in left + right if p]
        longest = max([len(pin_text(p)) for p in names] + [1])
        self.hw = max(2 * G, math.ceil((longest * 1.27 * 0.75 + 2.5) / G) * G)
        if len(left) <= 1 and len(right) <= 1:
            self.hw = 2 * G
        self.top = math.ceil((rows - 1) / 2) * G
        self.pins = {}
        for i, p in enumerate(left):
            if p:
                self.pins[p] = (-(self.hw + G), self.top - i * G, 0)
        for i, p in enumerate(right):
            if p:
                self.pins[p] = (self.hw + G, self.top - i * G, 180)
        self.ytop = self.top + G
        self.ybot = self.top - rows * G
        for k, (p, t) in enumerate(self.power):
            x = snap((k - (len(self.power) - 1) / 2) * 2 * G)
            self.pins[p] = (x, self.ytop + G, 270) if t == "pwr" else (x, self.ybot - G, 90)
        for p in pins:
            assert p in self.pins, (dev, p)
        self.txt = TXT if self.power else 2.0

    def lib(self, libname):
        dev = self.dev
        pins = SYM[dev]["pins"]
        ref = refdefault(dev)
        L = ["  (symbol %s (pin_names (offset 0.762)) (in_bom yes) (on_board yes)" % q(libname),
             "    (property \"Reference\" %s (at 0 %.2f 0) %s)" % (q(ref), self.ytop + 1.5, font()),
             "    (property \"Value\" %s (at 0 %.2f 0) %s)" % (q(dev), self.ybot - 1.5, font()),
             "    (property \"Footprint\" %s (at 0 0 0) %s)" % (q(SYM[dev]["footprint"]), font(True)),
             "    (property \"Datasheet\" \"\" (at 0 0 0) %s)" % font(True),
             "    (symbol %s" % q(libname.split(":")[1] + "_0_1"),
             "      (rectangle (start %.2f %.2f) (end %.2f %.2f) (stroke (width 0.254) (type default)) (fill (type background)))"
             % (-self.hw, self.ytop, self.hw, self.ybot),
             "    )",
             "    (symbol %s" % q(libname.split(":")[1] + "_1_1")]
        for p, (x, y, a) in self.pins.items():
            num, t = pins[p]
            L.append("      (pin %s line (at %.2f %.2f %d) (length %.2f) (name %s %s) (number %s %s))"
                     % (ETYPE[t], x, y, a, G, q("~" if t in ("pwr", "gnd") else pin_text(p)), font(), q(num), font()))
        L += ["    )", "  )"]
        return "\n".join(L)

PWR_FLAG = """  (symbol "p8x:PWR_FLAG" (power) (pin_numbers hide) (pin_names (offset 0) hide) (in_bom yes) (on_board yes)
    (property "Reference" "#FLG" (at 0 1.905 0) %s)
    (property "Value" "PWR_FLAG" (at 0 3.81 0) %s)
    (property "Footprint" "" (at 0 0 0) %s)
    (property "Datasheet" "" (at 0 0 0) %s)
    (symbol "PWR_FLAG_0_0"
      (pin power_out line (at 0 0 90) (length 0) (name "pwr" %s) (number "1" %s))
    )
    (symbol "PWR_FLAG_0_1"
      (polyline (pts (xy 0 0) (xy 0 1.27) (xy -1.016 1.905) (xy 0 2.54) (xy 1.016 1.905) (xy 0 1.27))
        (stroke (width 0) (type default)) (fill (type none)))
    )
  )""" % (font(True), font(), font(True), font(True), font(), font())

def label_len(s):
    return len(s) * 1.27 * 0.8 + 4

class SheetWriter:
    def __init__(self, card, root_uuid, block_uuid, title, rows, page, net, power_nets=("VCC", "GND"), proj=None):
        self.card, self.title, self.rows, self.page, self.net = card, title, rows, page, net
        self.root, self.block = root_uuid, block_uuid
        self.items, self.libs, self.labels = [], {}, 0
        self.wired_pins = set()
        self.wired = False
        self.power_nets = list(power_nets)
        self.proj = proj or card.name        # KiCad project name (matches the .kicad_pro basename)

    def place(self, ref, X, Y):
        dev, func, value = self.card.parts[ref]
        sym = Symbol(dev)
        libname = "p8x:" + dev
        self.libs[libname] = sym.lib(libname)
        path = "/%s/%s" % (self.root, self.block)
        L = ["  (symbol (lib_id %s) (at %.2f %.2f 0) (unit 1) (in_bom yes) (on_board yes) (dnp no)"
             % (q(libname), X, Y),
             "    (uuid %s)" % q(U(self.card.name, "sym", ref)),
             "    (property \"Reference\" %s (at %.2f %.2f 0) %s)" % (q(ref), X - sym.hw, Y - sym.ytop - sym.txt, font(justify="left")),
             "    (property \"Value\" %s (at %.2f %.2f 0) %s)" % (q(value), X - sym.hw, Y - sym.ybot + sym.txt, font(justify="left")),
             "    (property \"Footprint\" %s (at %.2f %.2f 0) %s)" % (q(SYM[dev]["footprint"]), X, Y, font(True)),
             "    (property \"Datasheet\" \"\" (at %.2f %.2f 0) %s)" % (X, Y, font(True))]
        for p, (num, t) in SYM[dev]["pins"].items():
            L.append("    (pin %s (uuid %s))" % (q(num), q(U(self.card.name, "pin", ref, p))))
        L += ["    (instances (project %s (path %s (reference %s) (unit 1))))" % (q(self.proj), q(path), q(ref)),
              "  )"]
        self.items.append("\n".join(L))
        for p, (px, py, a) in sym.pins.items():
            x, y = X + px, Y - py
            net = self.net.get((ref, p))
            if (ref, p) in self.wired_pins:
                continue
            if net is None:
                self.items.append("  (no_connect (at %.2f %.2f) (uuid %s))" % (x, y, q(U(self.card.name, "nc", ref, p))))
                continue
            la = {0: 180, 180: 0, 270: 90, 90: 270}[a]
            just = "right" if la in (180, 270) else "left"
            self.items.append(
                "  (global_label %s (shape passive) (at %.2f %.2f %d) (fields_autoplaced yes) %s (uuid %s)\n"
                "    (property \"Intersheetrefs\" \"${INTERSHEET_REFS}\" (at %.2f %.2f 0) %s))"
                % (q(net), x, y, la, font(justify=just), q(U(self.card.name, "lbl", ref, p)), x, y, font(True)))
            self.labels += 1
        return sym

    def size(self, ref):
        dev = self.card.parts[ref][0]
        sym = Symbol(dev)
        left, right = layout_for(dev)
        lw = max([label_len(self.net.get((ref, p), "")) for p in left if p] + [4])
        rw = max([label_len(self.net.get((ref, p), "")) for p in right if p] + [4])
        return lw + sym.hw + G, sym.hw + G + rw, sym.ytop + sym.txt + 3, -sym.ybot + sym.txt + 3

    def flags(self, y):
        fl = []
        for k, n in enumerate(self.power_nets):
            x = 15.24 + 15.24 * k
            fl.append("  (symbol (lib_id \"p8x:PWR_FLAG\") (at %.2f %.2f 0) (unit 1) (in_bom yes) (on_board yes) (dnp no)\n"
                      "    (uuid %s)\n"
                      "    (property \"Reference\" \"#FLG0%d\" (at %.2f %.2f 0) %s)\n"
                      "    (property \"Value\" \"PWR_FLAG\" (at %.2f %.2f 0) %s)\n"
                      "    (property \"Footprint\" \"\" (at %.2f %.2f 0) %s)\n"
                      "    (property \"Datasheet\" \"\" (at %.2f %.2f 0) %s)\n"
                      "    (pin \"1\" (uuid %s))\n"
                      "    (instances (project %s (path %s (reference \"#FLG0%d\") (unit 1))))\n  )\n"
                      "  (global_label %s (shape passive) (at %.2f %.2f 270) (fields_autoplaced yes) %s (uuid %s)\n"
                      "    (property \"Intersheetrefs\" \"${INTERSHEET_REFS}\" (at %.2f %.2f 0) %s))"
                      % (x, y, q(U(self.card.name, "flag", n)), k + 1, x, y - 2, font(True), x, y - 4, font(),
                         x, y, font(True), x, y, font(True), q(U(self.card.name, "flagpin", n)), q(self.proj),
                         q("/%s/%s" % (self.root, self.block)), k + 1, q(n), x, y, font(justify="right"),
                         q(U(self.card.name, "flaglbl", n)), x, y, font(True)))
        return "\n".join(fl)

    def write(self, path, flags=False):
        if self.wired:
            try:
                return self.write_wired(path, flags)
            except SystemExit as e:        # ELK could not route this sheet cleanly: fall back to labels
                sys.stderr.write("  sheet %d: %s -- falling back to label style\n" % (self.page, e))
                self.items, self.libs, self.wired_pins = [], {}, set()
        layout, y, width = [], 25.4, 0
        for row in self.rows:
            x = 15.24
            up = max(self.size(r)[2] for r in row)
            down = max(self.size(r)[3] for r in row)
            Y = snap(y + up)
            for ref in row:
                lw, rw, _, _ = self.size(ref)
                X = snap(x + lw)
                layout.append((ref, X, Y))
                x = X + rw + 5.08
            width = max(width, x)
            y = Y + down + 7.62
        paper = next(p for p, (w, h) in (("A4", (297, 210)), ("A3", (420, 297)), ("A2", (594, 420)),
                                         ("A1", (841, 594)), ("A0", (1189, 841)))
                     if width <= w - 10 and y <= h - 30)
        for ref, X, Y in layout:
            self.place(ref, X, Y)
        extra = self.flags(snap(y + 2.54)) if flags else ""
        self.emit(path, paper, extra)

    def write_wired(self, path, flags):
        import p8x_kicad_wire
        refs = [r for row in self.rows for r in row]
        pos, wires, junctions, labels, self.wired_pins, (w, h) = p8x_kicad_wire.layout_sheet(self.card, refs)
        for ref in refs:
            self.place(ref, *pos[ref])
        for k, (n, (x1, y1), (x2, y2)) in enumerate(wires):
            self.items.append("  (wire (pts (xy %.2f %.2f) (xy %.2f %.2f)) (stroke (width 0) (type default)) (uuid %s))"
                              % (x1, y1, x2, y2, q(U(self.card.name, "wire", str(self.page), str(k)))))
        for net, x1, y1, horiz in labels:
            ang = 180 if horiz else 90
            self.items.append("  (global_label %s (shape passive) (at %.2f %.2f %d) (fields_autoplaced yes) %s (uuid %s)\n"
                              "    (property \"Intersheetrefs\" \"${INTERSHEET_REFS}\" (at %.2f %.2f 0) %s))"
                              % (q(net), x1, y1, ang, font(justify="right" if horiz else "left"),
                                 q(U(self.card.name, "netlabel", str(self.page), net)), x1, y1, font(True)))
        for k, (x, y) in enumerate(junctions):
            self.items.append("  (junction (at %.2f %.2f) (diameter 0) (color 0 0 0 0) (uuid %s))"
                              % (x, y, q(U(self.card.name, "junction", str(self.page), str(k)))))
        paper = next(p for p, (pw, ph) in (("A4", (297, 210)), ("A3", (420, 297)), ("A2", (594, 420)),
                                           ("A1", (841, 594)), ("A0", (1189, 841)))
                     if w <= pw - 10 and h <= ph - 30)
        extra = self.flags(snap(h - 10)) if flags else ""
        self.emit(path, paper, extra)

    def emit(self, path, paper, extra):
        out = ["(kicad_sch (version %s) (generator \"p8x_kicad_sch\")" % VERSION,
               "  (uuid %s)" % q(U(self.card.name, "file", str(self.page))),
               "  (paper %s)" % q(paper),
               "  (title_block (title %s) (company \"P8X\") (comment 1 %s) (comment 2 %s))"
               % (q(self.card.title), q(self.title),
                  q("Generated by generators/sch/p8x_kicad_sch.py from gen_eagle.py - do not edit")),
               "  (lib_symbols", *sorted(self.libs.values()), *([PWR_FLAG] if extra else []), "  )",
               *self.items, extra, ")"]
        with open(path, "w") as fh:
            fh.write("\n".join(s for s in out if s) + "\n")

def write_project(card, sheets, outdir, wired=(), proj=None):
    proj = proj or card.name                  # .kicad_sch / .kicad_pro basename
    os.makedirs(outdir, exist_ok=True)
    net = {}
    for n, pins in card.nets.items():
        for rp in pins:
            net[rp] = n
    # every net that carries a power/ground pin needs a PWR_FLAG (backplane supplies it)
    seen = set()
    for n, pins in card.nets.items():
        for r, p in pins:
            dev = card.parts[r][0]
            if dev in SYM and SYM[dev]["pins"].get(p, ("", ""))[1] in ("pwr", "gnd"):
                seen.add(n)
                break
    power_nets = [x for x in ("VCC", "GND") if x in seen] + sorted(seen - {"VCC", "GND"})
    root = U(card.name, "root")
    blocks = []
    for i, (title, rows) in enumerate(sheets, 1):
        fname = "%s-%d.kicad_sch" % (proj, i)
        bu = U(card.name, "block", str(i))
        sw = SheetWriter(card, root, bu, title, rows, i + 1, net, power_nets=power_nets, proj=proj)
        sw.wired = i in wired
        sw.write(os.path.join(outdir, fname), flags=(i == len(sheets)))
        blocks.append((title, fname, bu, i + 1))
    L = ["(kicad_sch (version %s) (generator \"p8x_kicad_sch\")" % VERSION,
         "  (uuid %s)" % q(root), "  (paper \"A4\")",
         "  (title_block (title %s) (company \"P8X\") (comment 1 \"Root sheet: one block per functional sheet\")"
         " (comment 2 \"Generated by generators/sch/p8x_kicad_sch.py - do not edit\"))" % q(card.title),
         "  (lib_symbols)"]
    for k, (title, fname, bu, page) in enumerate(blocks):
        x, y = 25.4, 30.48 + k * 30.48
        L += ["  (sheet (at %.2f %.2f) (size 101.6 20.32) (fields_autoplaced yes)" % (x, y),
              "    (stroke (width 0.1524) (type solid)) (fill (color 0 0 0 0.0000))",
              "    (uuid %s)" % q(bu),
              "    (property \"Sheetname\" %s (at %.2f %.2f 0) %s)" % (q(title[:60]), x, y - 0.7, font(justify="left bottom")),
              "    (property \"Sheetfile\" %s (at %.2f %.2f 0) %s)" % (q(fname), x, y + 20.9, font(justify="left top")),
              "    (instances (project %s (path %s (page %s))))" % (q(proj), q("/" + root), q(str(page))),
              "  )"]
    L += ["  (sheet_instances (path \"/\" (page \"1\")))", ")"]
    with open(os.path.join(outdir, proj + ".kicad_sch"), "w") as fh:
        fh.write("\n".join(L) + "\n")
    libs = {}
    for ref, (dev, f, v) in card.parts.items():
        libs[dev] = Symbol(dev).lib("p8x:" + dev).replace('(symbol "p8x:', '(symbol "', 1)
    with open(os.path.join(outdir, "p8x.kicad_sym"), "w") as fh:
        fh.write('(kicad_symbol_lib (version %s) (generator "p8x_kicad_sch")\n' % VERSION)
        fh.write("\n".join(libs[d] for d in sorted(libs)) + "\n")
        fh.write(PWR_FLAG.replace('(symbol "p8x:PWR_FLAG"', '(symbol "PWR_FLAG"', 1) + "\n)\n")
    with open(os.path.join(outdir, "sym-lib-table"), "w") as fh:
        fh.write('(sym_lib_table\n  (version 7)\n  (lib (name "p8x") (type "KiCad") (uri "${KIPRJMOD}/p8x.kicad_sym")'
                 ' (options "") (descr "P8X generated symbols"))\n)\n')
    pro = os.path.join(outdir, proj + ".kicad_pro")
    if not os.path.exists(pro):
        with open(pro, "w") as fh:
            json.dump({"meta": {"filename": card.name + ".kicad_pro", "version": 1}}, fh, indent=2)
            fh.write("\n")

def verify(card, netfile):
    """Compare a netlist exported by KiCad with the canonical one."""
    import re
    text = open(netfile).read()
    text = text[text.index("(nets"):]
    kc = {}
    for chunk in re.split(r"\(net\s", text)[1:]:
        name = re.search(r'\(name\s+"([^"]*)"\)', chunk).group(1).lstrip("/")
        nodes = set(re.findall(r'\(ref\s+"([^"]+)"\)\s*\(pin\s+"([^"]+)"\)', chunk))
        nodes = {n for n in nodes if not n[0].startswith("#")}
        if nodes:
            kc[name] = nodes
    ours = {}
    for net, pins in card.nets.items():
        ours[net] = {(r, SYM[card.parts[r][0]]["pins"][p][0]) for r, p in pins}
    problems = []
    nc = {(r, SYM[card.parts[r][0]]["pins"][p][0]) for r, p in card.nc}
    for net in [n for n in kc if n.startswith("unconnected-")]:
        if len(kc[net]) != 1 or not kc[net] <= nc:
            problems.append("%s: %s is not a declared unused pin" % (net, sorted(kc[net])))
        del kc[net]
    for net in sorted(set(kc) | set(ours)):
        a, b = ours.get(net, set()), kc.get(net, set())
        if a != b:
            problems.append("%s: only in Python %s, only in KiCad %s" % (net, sorted(a - b)[:4], sorted(b - a)[:4]))
    return problems, len(kc), sum(len(v) for v in kc.values())

KICAD_CLI = "/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli"

def kicad_check(card, outdir, proj=None):
    import subprocess, shutil
    cli = shutil.which("kicad-cli") or (KICAD_CLI if os.path.exists(KICAD_CLI) else None)
    if not cli:
        return True, "KiCad not installed: ERC and netlist comparison skipped"
    root = os.path.join(outdir, (proj or card.name) + ".kicad_sch")
    rpt, net = os.path.join(outdir, "erc.rpt"), os.path.join(outdir, "kicad.net")
    subprocess.run([cli, "sch", "erc", "-o", rpt, root], capture_output=True)
    subprocess.run([cli, "sch", "export", "netlist", "--format", "kicadsexpr", "-o", net, root],
                   capture_output=True)
    lines = open(rpt).read().splitlines() if os.path.exists(rpt) else []
    errs = warns = 0
    for i, l in enumerate(lines):
        if l.startswith("["):
            sev = "".join(lines[i + 1:i + 3])
            if "; error" in sev:
                errs += 1
            elif "; warning" in sev:
                warns += 1
    problems, n, pins = verify(card, net)
    for f in (rpt, net):
        if os.path.exists(f):
            os.remove(f)
    if errs or problems:
        return False, "KiCad ERC: %d error(s), %d warning(s); netlist differences: %s" % (errs, warns, problems[:3])
    return True, "KiCad ERC 0 errors (%d warning(s)); KiCad netlist = ours (%d nets, %d pins)" % (warns, n, pins)

def main():
    import argparse
    import p8x_card, p8x_sheets
    ap = argparse.ArgumentParser()
    ap.add_argument("card")
    ap.add_argument("outdir")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--proj", default=None, help="project basename (default: card name); use to unify with the board")
    args = ap.parse_args()
    card = p8x_card.load(args.card)
    sheets, wired = p8x_sheets.sheets_for(card)
    write_project(card, sheets, args.outdir, wired=wired, proj=args.proj)
    msg = "%s: KiCad schematic written to %s (%d sheets, wired %s)" % (args.card, args.outdir, len(sheets), sorted(wired))
    if args.check:
        ok, m = kicad_check(card, args.outdir, proj=args.proj)
        print(msg + "; " + m)
        sys.exit(0 if ok else 1)
    print(msg)

if __name__ == "__main__":
    main()
