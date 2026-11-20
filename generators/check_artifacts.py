#!/usr/bin/env python3
"""Freshness gate for the KiCad flow: fail if a committed board artifact no longer
matches what its source makes. It only reads the repository: every build runs in a
temporary copy of the working tree (the tracked files as they are on disk now, so
uncommitted edits count), and the copy is removed at the end.

    python3 generators/check_artifacts.py              # all nine boards
    python3 generators/check_artifacts.py io-card cf-card
    python3 generators/check_artifacts.py --keep       # keep the copy to look at

Exit 0 = every artifact is fresh, 1 = something is stale or a check could not run
(a SKIP is not a pass), 2 = nothing could run (no KiCad, an unknown board).

Per board (hardware/<board>/kicad/), five checks:

  schematic   generators/sch/p8x_kicad_sch.py --check makes the schematic again;
              every .kicad_sch, p8x.kicad_sym and sym-lib-table must match the
              committed files byte for byte, with no committed sheet left over.
              --check also runs KiCad's ERC and compares KiCad's netlist with the
              generator's. (Needs generators/sch/node_modules: `npm install` there.)
  sch-pdf     kicad-cli exports the committed schematic to PDF again; it must
              match <board>-schematic.pdf apart from the dates and the PDF /ID.
  board       the board's placement generator (gen_kicad.py, or the card's own
              gen_*.py) makes the unrouted board again; every part must match the
              committed routed board: reference, footprint, value, position,
              rotation, side, the net on every pad, the board outline, and every
              silkscreen text (to 0.02 mm: the round trip through routing moves a
              text by 0.01 mm).
  gerbers     kicad-cli exports the gerbers and drill files from the committed
              board again, as kicad_tools.order_files does; they must match the
              files in <board>-gerbers.zip apart from the date lines. This is the
              check that the zip a fab gets is the board in the repo.
  placement   kicad_tools.py placement (the memory card: its own gen_placement.py)
              draws <board>-placement.pdf again from the committed board; it must
              match apart from the dates and the /ID.

Not checked, because no build reproduces them exactly: the routing itself (the
.ses and the tracks: Freerouting gives a different route each run; the DRC in
check_card.sh is what proves a route), and the ray-traced renders (*-render-*.png).

Before 2026-11-20 this script ran build_all.py, the Eagle-era flow, and asked git
whether hardware/ had changed. That flow's outputs are no longer tracked (the Eagle
files are frozen in eagle-deprecated/), so it compared nothing, and it stopped with
a FileNotFoundError on the deprecated led-card.
"""
import difflib, json, os, re, shutil, subprocess, sys, tempfile, zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
PYK = "/Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/3.9/bin/python3"
CLI = "/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli"

# The nine boards, as in generators/sch/build_sch.sh.
BOARDS = ["control-card", "regbank-card", "alu-card", "io-card", "cf-card",
          "ps2-card", "memory-card", "bustest-card", "backplane"]

# Each board's placement generator, as generators/build.sh dispatches it:
# (script relative to the repo, its arguments). The script runs from its own folder.
def generator(board):
    own = {"memory-card": "hardware/memory-card/kicad/gen_mem.py",
           "io-card":     "hardware/io-card/kicad/gen_io.py",
           "cf-card":     "hardware/cf-card/kicad/gen_cf.py",
           "ps2-card":    "hardware/ps2-card/kicad/gen_ps2.py",
           "backplane":   "generators/gen_backplane.py"}
    if board in own:
        return own[board], []
    return "generators/gen_kicad.py", [board]

SILK_TOL = 0.02   # mm

# ---------------------------------------------------------------------------
# --dump-board: runs under KiCad's python (pcbnew), writes a board's parts as JSON
def dump_board(brd, out):
    import pcbnew
    b = pcbnew.LoadBoard(brd)
    parts, silk = {}, []
    for f in b.GetFootprints():
        p = f.GetPosition()
        parts[f.GetReference()] = dict(
            footprint=str(f.GetFPID().GetLibItemName()), value=f.GetValue(),
            x=round(p.x / 1e6, 3), y=round(p.y / 1e6, 3),
            rotation=round(f.GetOrientationDegrees(), 1), side=f.GetLayerName(),
            pads=sorted([pd.GetNumber(), pd.GetNetname()] for pd in f.Pads()))
        for fl in (f.Reference(), f.Value()):
            if fl.IsVisible() and "Silk" in fl.GetLayerName():
                q = fl.GetPosition()
                silk.append([f.GetReference(), fl.GetText(), fl.GetLayerName(),
                             q.x / 1e6, q.y / 1e6, round(fl.GetTextAngleDegrees(), 1)])
    for d in b.GetDrawings():
        if d.GetClass() in ("PCB_TEXT", "PCB_TEXTBOX") and "Silk" in d.GetLayerName():
            q = d.GetPosition()
            silk.append(["", d.GetText(), d.GetLayerName(),
                         q.x / 1e6, q.y / 1e6, round(d.GetTextAngleDegrees(), 1)])
    bb = b.GetBoardEdgesBoundingBox()
    outline = [round(bb.GetX() / 1e6, 3), round(bb.GetY() / 1e6, 3),
               round(bb.GetWidth() / 1e6, 3), round(bb.GetHeight() / 1e6, 3)]
    with open(out, "w") as fh:
        json.dump(dict(parts=parts, silk=sorted(silk), outline=outline), fh)

# ---------------------------------------------------------------------------
def run(argv, cwd=None):
    return subprocess.run(argv, cwd=cwd, capture_output=True, text=True)

def tail(r, n=3):
    lines = [l for l in (r.stdout + r.stderr).splitlines()
             if l.strip() and not re.search(r"Fontconfig|Debug:|traits|wxApp", l)]
    return " | ".join(lines[-n:])

def copy_tree(dst):
    """The tracked files as they are on disk now (deleted ones skipped), plus the
    schematic generator's node_modules, which is not tracked."""
    r = run(["git", "ls-files", "-z"], cwd=ROOT)
    if r.returncode != 0:
        sys.exit("check-artifacts: git ls-files failed: " + r.stderr.strip())
    for rel in r.stdout.split("\0"):
        src = os.path.join(ROOT, rel)
        if not rel or not os.path.isfile(src):
            continue
        out = os.path.join(dst, rel)
        os.makedirs(os.path.dirname(out), exist_ok=True)
        shutil.copy2(src, out)
    nm = os.path.join(HERE, "sch", "node_modules")
    if os.path.isdir(nm):
        shutil.copytree(nm, os.path.join(dst, "generators", "sch", "node_modules"), symlinks=True)

PDF_VOLATILE = re.compile(rb"(/(?:CreationDate|ModDate) *\()[^)]*(\))|(/ID *\[)[^\]]*(\])"
                          rb"|(<xmp:(?:CreateDate|ModifyDate|MetadataDate)>)[^<]*")
def pdf_norm(path):
    with open(path, "rb") as fh:
        return PDF_VOLATILE.sub(lambda m: b"".join(g for g in m.groups() if g), fh.read())

GERBER_DATE = re.compile(r"CreationDate|Created by KiCad|^; *DRILL file .* date")
def gerber_norm(data):
    return [l for l in data.decode("latin1").splitlines() if not GERBER_DATE.search(l)]

def first_diff(a, b, n=2):
    d = [l for l in difflib.unified_diff(a, b, lineterm="", n=0)
         if l[:1] in "+-" and l[:3] not in ("+++", "---")]
    return "%d lines differ, first: %s" % (len(d), "; ".join(x[:70] for x in d[:n]))

# ---------------------------------------------------------------------------
def check_schematic(tmp, board, kd):
    if not os.path.isdir(os.path.join(tmp, "generators", "sch", "node_modules", "elkjs")):
        return "SKIP", ["generators/sch/node_modules is missing: cd generators/sch && npm install"]
    out = tempfile.mkdtemp(dir=tmp, prefix="sch-")
    r = run([sys.executable, os.path.join(tmp, "generators", "sch", "p8x_kicad_sch.py"),
             board, out, "--proj", "p8x-" + board, "--check"], cwd=os.path.join(tmp, "generators", "sch"))
    if r.returncode != 0 or "KiCad schematic written" not in r.stdout + r.stderr:
        return "FAIL", ["the generator failed: " + tail(r)]
    probs = []
    summary = [l for l in (r.stdout + r.stderr).splitlines() if "KiCad schematic written" in l]
    if summary and not re.search(r"ERC 0 errors.*netlist = ours", summary[0]):
        probs.append("generator check: " + summary[0].split("; ", 1)[-1])
    fresh = sorted(f for f in os.listdir(out)
                   if f.endswith((".kicad_sch", ".kicad_sym")) or f == "sym-lib-table")
    for f in fresh:
        mine = os.path.join(kd, f)
        if not os.path.exists(mine):
            probs.append("%s: made by the generator, not committed" % f)
        elif open(mine, "rb").read() != open(os.path.join(out, f), "rb").read():
            a = open(mine, encoding="utf-8", errors="replace").read().splitlines()
            b = open(os.path.join(out, f), encoding="utf-8", errors="replace").read().splitlines()
            probs.append("%s: %s" % (f, first_diff(a, b)))
    for f in sorted(os.listdir(kd)):
        if re.fullmatch(r"p8x-%s(-\d+)?\.kicad_sch" % re.escape(board), f) and f not in fresh:
            probs.append("%s: committed, but the generator no longer makes it" % f)
    return ("STALE" if probs else "OK"), probs

def check_sch_pdf(tmp, board, kd):
    pdf = os.path.join(kd, "p8x-%s-schematic.pdf" % board)
    if not os.path.exists(pdf):
        return "STALE", ["p8x-%s-schematic.pdf is not committed" % board]
    new = os.path.join(tmp, "sch-%s.pdf" % board)
    r = run([CLI, "sch", "export", "pdf", "-o", new, os.path.join(kd, "p8x-%s.kicad_sch" % board)])
    if r.returncode != 0 or not os.path.exists(new):
        return "FAIL", ["kicad-cli sch export pdf failed: " + tail(r)]
    if pdf_norm(pdf) != pdf_norm(new):
        return "STALE", ["the PDF is not the committed schematic: run generators/sch/build_sch.sh " + board]
    return "OK", []

def check_gerbers(tmp, board, kd):
    brd = os.path.join(kd, "p8x-%s.kicad_pcb" % board)
    zp = os.path.join(kd, "p8x-%s-gerbers.zip" % board)
    if not os.path.exists(zp):
        return "STALE", ["p8x-%s-gerbers.zip is not committed" % board]
    out = tempfile.mkdtemp(dir=tmp, prefix="ger-") + "/"
    r1 = run([CLI, "pcb", "export", "gerbers", "--no-protel-ext", "-o", out, brd])
    r2 = run([CLI, "pcb", "export", "drill", "--format", "excellon", "--excellon-units", "mm",
              "--excellon-separate-th", "-o", out, brd])
    if r1.returncode or r2.returncode:
        return "FAIL", ["kicad-cli export failed: " + tail(r1 if r1.returncode else r2)]
    new = {f for f in os.listdir(out) if f.endswith((".gbr", ".gbrjob", ".drl"))}
    z = zipfile.ZipFile(zp)
    inzip = {os.path.basename(n): n for n in z.namelist() if not n.endswith("/")}
    probs = []
    if set(inzip) - new: probs.append("only in the zip: " + ", ".join(sorted(set(inzip) - new)))
    if new - set(inzip): probs.append("missing from the zip: " + ", ".join(sorted(new - set(inzip))))
    for f in sorted(new & set(inzip)):
        a = gerber_norm(z.read(inzip[f]))
        b = gerber_norm(open(os.path.join(out, f), "rb").read())
        if a != b:
            probs.append("%s: %s" % (f, first_diff(a, b)))
    return ("STALE" if probs else "OK"), probs

def check_placement(tmp, board, kd):
    pdf = os.path.join(kd, "p8x-%s-placement.pdf" % board)
    if not os.path.exists(pdf):
        return "STALE", ["p8x-%s-placement.pdf is not committed" % board]
    keep = os.path.join(tmp, "placement-%s.pdf" % board)
    shutil.copy2(pdf, keep)                       # the drawing is made in place
    own = os.path.join(kd, "gen_placement.py")   # the memory card draws its own (titled, A4)
    if os.path.exists(own):
        r = run([PYK, own], cwd=kd)
    else:
        r = run([PYK, os.path.join(tmp, "generators", "kicad_tools.py"), "placement",
                 os.path.join(kd, "p8x-%s.kicad_pcb" % board)])
    new = os.path.join(tmp, "placement-%s-new.pdf" % board)
    shutil.copy2(pdf, new); shutil.copy2(keep, pdf)
    if r.returncode != 0:
        return "FAIL", ["kicad_tools.py placement failed: " + tail(r)]
    if pdf_norm(keep) != pdf_norm(new):
        return "STALE", ["the PDF is not the committed board: draw it again (%s)"
                         % ("gen_placement.py" if os.path.exists(own) else "kicad_tools.py placement")]
    return "OK", []

def check_board(tmp, board, kd):
    brd = os.path.join(kd, "p8x-%s.kicad_pcb" % board)
    old_j, new_j = os.path.join(tmp, "old-%s.json" % board), os.path.join(tmp, "new-%s.json" % board)
    me = os.path.abspath(__file__)
    r = run([PYK, me, "--dump-board", brd, old_j])
    if not os.path.exists(old_j):
        return "FAIL", ["could not read the committed board: " + tail(r)]
    keep = os.path.join(tmp, "committed-%s.kicad_pcb" % board)
    shutil.copy2(brd, keep)
    script, args = generator(board)
    sp = os.path.join(tmp, script)
    r = run([PYK, sp] + args, cwd=os.path.dirname(sp))
    made = os.path.getmtime(brd) > os.path.getmtime(keep) or open(brd, "rb").read() != open(keep, "rb").read()
    if r.returncode != 0 or not made:
        shutil.copy2(keep, brd)
        return "FAIL", ["%s failed: %s" % (script, tail(r))]
    r = run([PYK, me, "--dump-board", brd, new_j])
    shutil.copy2(keep, brd)                       # later checks see the committed board
    if not os.path.exists(new_j):
        return "FAIL", ["could not read the fresh board: " + tail(r)]
    a, b = json.load(open(old_j)), json.load(open(new_j))
    probs = []
    for ref in sorted(set(a["parts"]) - set(b["parts"])):
        probs.append("%s: on the committed board, not made by the generator" % ref)
    for ref in sorted(set(b["parts"]) - set(a["parts"])):
        probs.append("%s: made by the generator, not on the committed board" % ref)
    for ref in sorted(set(a["parts"]) & set(b["parts"])):
        for k, v in a["parts"][ref].items():
            if v != b["parts"][ref][k]:
                probs.append("%s %s: committed %s, generator %s" % (ref, k, str(v)[:60], str(b["parts"][ref][k])[:60]))
    if a["outline"] != b["outline"]:
        probs.append("outline: committed %s, generator %s" % (a["outline"], b["outline"]))
    def unmatched(xs, ys):
        left = list(ys); out = []
        for t in xs:
            hit = next((u for u in left if u[0] == t[0] and u[1] == t[1] and u[2] == t[2] and u[5] == t[5]
                        and abs(u[3] - t[3]) <= SILK_TOL and abs(u[4] - t[4]) <= SILK_TOL), None)
            if hit is None: out.append(t)
            else: left.remove(hit)
        return out
    def silk(t): return "%r on %s at (%.2f, %.2f) angle %g" % (t[1], t[2], t[3], t[4], t[5])
    for t in unmatched(a["silk"], b["silk"]): probs.append("silk on the committed board only: " + silk(t))
    for t in unmatched(b["silk"], a["silk"]): probs.append("silk from the generator only: " + silk(t))
    return ("STALE" if probs else "OK"), probs

# The order matters: the checks that read the committed board run before the
# generator overwrites it in the copy (check_board puts it back in any case).
CHECKS = [("schematic", check_schematic), ("sch-pdf", check_sch_pdf),
          ("gerbers", check_gerbers), ("placement", check_placement), ("board", check_board)]

def main(argv):
    keep = "--keep" in argv
    boards = [a for a in argv if not a.startswith("-")] or BOARDS
    unknown = [b for b in boards if b not in BOARDS]
    if unknown:
        print("check-artifacts: unknown board(s) %s; the boards are: %s" % (unknown, " ".join(BOARDS)))
        return 2
    for tool in (PYK, CLI):
        if not os.path.exists(tool):
            print("check-artifacts: %s not found (KiCad 10 is needed)" % tool)
            return 2
    tmp = tempfile.mkdtemp(prefix="p8x-check-artifacts-")
    stale = failed = 0
    try:
        copy_tree(tmp)
        for board in boards:
            kd = os.path.join(tmp, "hardware", board, "kicad")
            print("== %s" % board)
            for name, fn in CHECKS:
                status, probs = fn(tmp, board, kd)
                print("  %-10s %s" % (name, status))
                for p in probs[:12]: print("      " + p)
                if len(probs) > 12: print("      ... and %d more" % (len(probs) - 12))
                stale += status == "STALE"; failed += status in ("FAIL", "SKIP")   # unchecked is not fresh
        print("\nNot checked: routing (.ses, tracks) and the ray-traced renders; see the docstring.")
    finally:
        if keep: print("copy kept at " + tmp)
        else: shutil.rmtree(tmp, ignore_errors=True)
    if stale or failed:
        print("check-artifacts: %d stale, %d could not run. Rebuild with generators/build.sh <board>"
              " (REUSE_ROUTE=1 keeps the route) and commit the result." % (stale, failed))
        return 1
    print("check-artifacts: OK, every checked artifact matches its source")
    return 0

if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "--dump-board":
        dump_board(sys.argv[2], sys.argv[3])
        sys.stdout.flush(); os._exit(0)          # skip the wx exit hang, as kicad_tools.py does
    sys.exit(main(sys.argv[1:]))
