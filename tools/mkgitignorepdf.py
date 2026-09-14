#!/usr/bin/env python3
"""Printable PDF of everything git ignores in the P8X repo.

Writes ../GITIGNORE-TREE.pdf in two parts:
  1. The ignore rules -- every tracked .gitignore file, verbatim (comments
     kept: they explain the allow-list strategy for emulator/test and the
     FPGA build dirs).
  2. The complete tree of currently-ignored files (git ls-files -o -i
     --exclude-standard), rendered as an indented directory tree with a
     breadcrumb of where each block sits.

    python3 tools/mkgitignorepdf.py

Self-contained: it runs git itself to discover the .gitignore files and the
ignored-file list, resolving the repo root relative to this file. Needs
reportlab (`pip install reportlab`). The PDF is a generated artifact and is
NOT tracked in git -- re-run this after the ignore set changes.
"""
import os, subprocess, datetime, pathlib
from reportlab.lib.pagesizes import letter
from reportlab.lib import colors
from reportlab.lib.units import mm
from reportlab.platypus import (SimpleDocTemplate, Paragraph, PageBreak,
                                Preformatted, HRFlowable, Table, TableStyle)
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "GITIGNORE-TREE.pdf"
STAMP = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")  # per-page footer

def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, text=True,
                          capture_output=True).stdout

# ignored files (sorted); .gitignore files come from the tracked file list
FILES = sorted(f for f in git("ls-files", "--others", "--ignored",
                              "--exclude-standard").split("\n") if f.strip())
GIS = [g for g in git("ls-files", ".gitignore", "**/.gitignore").split("\n")
       if g.strip()]

INK   = colors.HexColor("#1a1a1a")
MUTED = colors.HexColor("#5a5f66")
ACC   = colors.HexColor("#1f5fa8")
DIRC  = colors.HexColor("#1a4d80")

S = getSampleStyleSheet()
TITLE = ParagraphStyle("t", parent=S["Title"], fontSize=21, leading=25, textColor=INK, spaceAfter=2)
SUB   = ParagraphStyle("s", parent=S["BodyText"], fontSize=9.5, leading=13, textColor=MUTED)
H1    = ParagraphStyle("h1", parent=S["Heading1"], fontSize=14, leading=17, textColor=ACC, spaceBefore=2, spaceAfter=3)
H3    = ParagraphStyle("h3", parent=S["Heading3"], fontSize=10.5, leading=13, textColor=DIRC, spaceBefore=9, spaceAfter=2)
BODY  = ParagraphStyle("b", parent=S["BodyText"], fontSize=9, leading=12.5, textColor=INK)
MONO  = ParagraphStyle("m", parent=BODY, fontName="Courier", fontSize=7.3, leading=8.9,
                       textColor=colors.HexColor("#333333"), spaceBefore=0, spaceAfter=0)
CRUMB = ParagraphStyle("cr", parent=BODY, fontName="Helvetica-Oblique", fontSize=8,
                       leading=10, textColor=DIRC, spaceBefore=4, spaceAfter=1)
RULEM = ParagraphStyle("r", parent=MONO, fontSize=7.6, leading=9.4, backColor=colors.HexColor("#f4f6f8"),
                       borderPadding=(4, 4, 4, 4), leftIndent=2)

flow = []
flow.append(Paragraph("P8X &mdash; Git-Ignored Files", TITLE))
flow.append(Paragraph("The complete tree of everything git ignores, plus the "
                      "rules that ignore it. Generated %s." % STAMP, SUB))
flow.append(HRFlowable(width="100%", thickness=0.8, color=ACC, spaceBefore=5, spaceAfter=7))

# ---- summary counts ------------------------------------------------------
counts = {}
for f in FILES:
    top = f.split("/")[0] if "/" in f else "(repo root)"
    counts[top] = counts.get(top, 0) + 1
rows = [["Top-level location", "Ignored files"]]
for k, v in sorted(counts.items(), key=lambda kv: -kv[1]):
    rows.append([k, str(v)])
rows.append(["TOTAL", str(len(FILES))])
tbl = Table(rows, colWidths=[120 * mm, 40 * mm], hAlign="LEFT")
tbl.setStyle(TableStyle([
    ("FONT", (0, 0), (-1, 0), "Helvetica-Bold", 9),
    ("FONT", (0, 1), (-1, -1), "Helvetica", 8.5),
    ("FONT", (0, -1), (-1, -1), "Helvetica-Bold", 9),
    ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
    ("BACKGROUND", (0, 0), (-1, 0), ACC),
    ("BACKGROUND", (0, -1), (-1, -1), colors.HexColor("#e8eef5")),
    ("ROWBACKGROUNDS", (0, 1), (-1, -2), [colors.white, colors.HexColor("#f6f8fa")]),
    ("LINEBELOW", (0, 0), (-1, -1), 0.3, colors.HexColor("#c7d2de")),
    ("ALIGN", (1, 0), (1, -1), "RIGHT"),
    ("LEFTPADDING", (0, 0), (-1, -1), 6), ("RIGHTPADDING", (0, 0), (-1, -1), 6),
    ("TOPPADDING", (0, 0), (-1, -1), 2.5), ("BOTTOMPADDING", (0, 0), (-1, -1), 2.5),
]))
flow.append(Paragraph("Where the ignored files live", H1))
flow.append(tbl)
flow.append(Paragraph("%d <b>.gitignore</b> files drive this. Most ignored paths "
                      "are build artifacts (emulator/test scratch, the on-disk OS "
                      "image, FPGA netlists/bitstreams)." % len(GIS), BODY))

# ---- part 1: the rules ---------------------------------------------------
flow.append(PageBreak())
flow.append(Paragraph("Part 1 &mdash; The ignore rules", H1))
flow.append(HRFlowable(width="100%", thickness=0.5, color=colors.HexColor("#c7d2de"), spaceAfter=5))
for gi in GIS:
    flow.append(Paragraph(gi, H3))
    text = (ROOT / gi).read_text().rstrip("\n")
    lines = [ln if ln.strip() else " " for ln in text.split("\n")]
    flow.append(Preformatted("\n".join(lines), RULEM))

# ---- part 2: the complete tree ------------------------------------------
flow.append(PageBreak())
flow.append(Paragraph("Part 2 &mdash; Complete tree of ignored files "
                      "(%d files)" % len(FILES), H1))
flow.append(HRFlowable(width="100%", thickness=0.5, color=colors.HexColor("#c7d2de"), spaceAfter=5))

tree = {}
for path in FILES:
    parts = path.split("/")
    node = tree
    for p in parts[:-1]:
        node = node.setdefault(p + "/", {})
    node[parts[-1]] = None

lines = []       # (display_text, dir_path_of_this_line)
def walk(node, depth, prefix):
    dirs = sorted([k for k in node if k.endswith("/")], key=str.lower)
    files = sorted([k for k in node if not k.endswith("/")], key=str.lower)
    for d in dirs:
        lines.append(("  " * depth + d, prefix))
        walk(node[d], depth + 1, prefix + d)
    for f in files:
        lines.append(("  " * depth + f, prefix))
walk(tree, 0, "")

CHUNK = 108
for i in range(0, len(lines), CHUNK):
    chunk = lines[i:i + CHUNK]
    crumb = chunk[0][1] or "(repo root)"
    flow.append(Paragraph("&bull;&nbsp; in <b>%s</b>" % crumb, CRUMB))
    flow.append(Preformatted("\n".join(t for t, _ in chunk), MONO))

# ---- furniture -----------------------------------------------------------
def furniture(canvas, doc):
    canvas.saveState()
    canvas.setFont("Helvetica", 7.5); canvas.setFillColor(MUTED)
    canvas.drawString(16 * mm, 10 * mm, "P8X - Git-Ignored Files")
    canvas.drawCentredString(doc.pagesize[0] / 2, 10 * mm, "Generated " + STAMP)
    canvas.drawRightString(doc.pagesize[0] - 16 * mm, 10 * mm, "page %d" % doc.page)
    canvas.setStrokeColor(colors.HexColor("#d7dee6")); canvas.setLineWidth(0.4)
    canvas.line(16 * mm, 12 * mm, doc.pagesize[0] - 16 * mm, 12 * mm)
    canvas.restoreState()

doc = SimpleDocTemplate(str(OUT), pagesize=letter, leftMargin=16 * mm, rightMargin=16 * mm,
                        topMargin=15 * mm, bottomMargin=16 * mm,
                        title="P8X Git-Ignored Files")
doc.build(flow, onFirstPage=furniture, onLaterPages=furniture)
print("wrote", OUT, "-", len(FILES), "ignored files,", len(GIS), "gitignore files")
