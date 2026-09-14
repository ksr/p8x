#!/usr/bin/env python3
"""Render BACKLOG.md into a readable, printable PDF (the full backlog).

Reads ../BACKLOG.md and writes ../BACKLOG.pdf — the complete backlog, not a
summary: every section (NEXT / IDEAS / VERIFY / WONT-DO) starts a fresh page,
the [ ] / [x] / [~] checkbox markers are colour-coded AND kept as bracket
tokens (so the state survives black-and-white printing), two nesting levels
render with hanging indents, bold / `code` / [links] render inline, and a
blockquote becomes a callout box. Completed work lives in BACKLOG-DONE.md and
is not included here.

    python3 tools/mkbacklogpdf.py

Needs reportlab (`pip install reportlab`). Paths are resolved relative to this
file, so it runs from any directory. The PDF is a generated artifact and is
NOT tracked in git — re-run this after the backlog changes.

The backlog is a nested-checkbox markdown document with no code fences and no
tables; this renderer targets exactly that shape.
"""
import re, html, pathlib, datetime
from reportlab.lib.pagesizes import letter
from reportlab.lib import colors
from reportlab.lib.units import mm
from reportlab.platypus import (SimpleDocTemplate, Paragraph, Spacer, PageBreak,
                                Preformatted, HRFlowable)
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.enums import TA_LEFT

ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / "BACKLOG.md"
OUT = ROOT / "BACKLOG.pdf"
STAMP = datetime.datetime.now().strftime("%Y-%m-%d %H:%M")  # per-page footer

# ---- palette -------------------------------------------------------------
INK    = colors.HexColor("#1a1a1a")
MUTED  = colors.HexColor("#5a5f66")
ACCENT = colors.HexColor("#1f5fa8")   # section rules, links

S = getSampleStyleSheet()
TITLE = ParagraphStyle("title", parent=S["Title"], fontSize=22, leading=26,
                       textColor=INK, spaceAfter=2)
SUB   = ParagraphStyle("sub", parent=S["BodyText"], fontSize=9.5, leading=13,
                       textColor=MUTED, spaceAfter=2)
H1    = ParagraphStyle("h1", parent=S["Heading1"], fontSize=15, leading=18,
                       textColor=ACCENT, spaceBefore=2, spaceAfter=4)
H3    = ParagraphStyle("h3", parent=S["Heading3"], fontSize=11, leading=14,
                       textColor=INK, spaceBefore=8, spaceAfter=3)
BODY  = ParagraphStyle("body", parent=S["BodyText"], fontSize=9, leading=12.5,
                       textColor=INK, alignment=TA_LEFT, spaceAfter=1)
PRE   = ParagraphStyle("pre", parent=BODY, fontName="Courier", fontSize=7.6,
                       leading=9.4, textColor=colors.HexColor("#374151"),
                       spaceBefore=1, spaceAfter=1)
NOTEP = ParagraphStyle("note", parent=BODY, textColor=colors.HexColor("#4a4a4a"),
                       backColor=colors.HexColor("#fbf7ec"),
                       borderColor=colors.HexColor("#e2d3a6"), borderWidth=0.7,
                       borderPadding=(7, 7, 7, 7), leftIndent=8, rightIndent=8,
                       leading=13, spaceBefore=5, spaceAfter=6)

HANG = 20  # points reserved for the "[ ] " marker

def item_style(level):
    base = 6 + level * 16
    return ParagraphStyle(f"it{level}", parent=BODY,
                          leftIndent=base + HANG, firstLineIndent=-HANG,
                          spaceBefore=(3 if level == 0 else 0.5), spaceAfter=1.5)

# ---- inline markdown -> reportlab mini-markup ----------------------------
def inline(t):
    t = html.escape(t, quote=False)
    t = re.sub(r"\[([^\]]+)\]\(([^)]+)\)",
               lambda m: f'<font color="#1f5fa8">{m.group(1)}</font>', t)   # [link](url)
    t = re.sub(r"`([^`]+)`",
               lambda m: f'<font face="Courier" color="#8a3b12">{m.group(1)}</font>', t)
    t = re.sub(r"\*\*(.+?)\*\*", r"<b>\1</b>", t)
    return t

MARK = {"[ ]": ("#2b6cb0", "[ ]"), "[x]": ("#2f855a", "[x]"), "[~]": ("#b7791f", "[~]")}

def marker(tok):
    col, txt = MARK[tok]
    return f'<font face="Courier-Bold" color="{col}">{txt}</font>&nbsp;'

# ---- parse ---------------------------------------------------------------
CB = re.compile(r"^(\s*)- \[([ x~])\] (.*)$")
BU = re.compile(r"^(\s*)- (.*)$")
H  = re.compile(r"^(#{1,3}) (.*)$")

def leadsp(s):
    return len(s) - len(s.lstrip(" "))

flow = []
MAJOR = {"NEXT", "IDEAS", "VERIFY", "WONT-DO / SUPERSEDED"}

def emit_item(marker_html, level, textcol, body0, conts):
    """conts: list of (indent, rawtext) continuation lines already gathered.

    A continuation aligned with the item's text column (relative indent <= 1)
    is wrapped prose and joins the paragraph; anything indented further is a
    sub-block and is preserved verbatim in a monospace run.
    """
    base = 6 + level * 16
    segs = [("prose", body0)]
    for ind, raw in conts:
        kind = "prose" if (ind - textcol) <= 1 else "pre"
        if kind == "prose":
            if segs and segs[-1][0] == "prose":
                segs[-1] = ("prose", segs[-1][1] + " " + raw.strip())
            else:
                segs.append(("prose", raw.strip()))
        else:
            dedent = raw[textcol:] if len(raw) > textcol else raw.strip()
            if segs and segs[-1][0] == "pre":
                segs[-1] = ("pre", segs[-1][1] + [dedent])
            else:
                segs.append(("pre", [dedent]))
    flow.append(Paragraph(marker_html + inline(segs[0][1]), item_style(level)))
    cont_style = ParagraphStyle(f"c{level}", parent=BODY,
                                leftIndent=base + HANG, spaceAfter=1.5)
    for kind, val in segs[1:]:
        if kind == "prose":
            flow.append(Paragraph(inline(val), cont_style))
        else:
            pre = ParagraphStyle(f"p{level}", parent=PRE, leftIndent=base + HANG)
            for ln in val:
                flow.append(Preformatted(ln if ln.strip() else " ", pre))

lines = SRC.read_text().split("\n")
i, n = 0, len(lines)
section = None
started = False

while i < n:
    line = lines[i]
    m = H.match(line)
    if m:
        hashes, text = m.group(1), m.group(2).strip()
        if len(hashes) == 1:
            flow.append(Paragraph(inline(text), TITLE))
            flow.append(Spacer(1, 2))
            leg = ('<font face="Courier-Bold" color="#2b6cb0">[ ]</font> open&nbsp;&nbsp;&nbsp;'
                   '<font face="Courier-Bold" color="#2f855a">[x]</font> done sub-step&nbsp;&nbsp;&nbsp;'
                   '<font face="Courier-Bold" color="#b7791f">[~]</font> partial&nbsp;&nbsp;&nbsp;'
                   '<font color="#9b2c2c">&bull;</font> settled decision')
            flow.append(Paragraph(leg, SUB))
            flow.append(HRFlowable(width="100%", thickness=0.8, color=ACCENT,
                                   spaceBefore=4, spaceAfter=6))
        elif len(hashes) == 2:
            section = text
            if started and text in MAJOR:
                flow.append(PageBreak())
            flow.append(Paragraph(inline(text), H1))
            flow.append(HRFlowable(width="100%", thickness=0.5,
                                   color=colors.HexColor("#c7d2de"),
                                   spaceBefore=1, spaceAfter=5))
            started = True
        else:
            flow.append(Paragraph(inline(text), H3))
            started = True
        i += 1
        continue

    if line.strip() == "---" or line.strip() == "":
        i += 1
        continue

    if re.match(r"^\s*>", line):
        segs, cur = [], []
        while i < n and re.match(r"^\s*>", lines[i]):
            body = re.sub(r"^\s*>\s?", "", lines[i])
            if body.strip() == "":
                if cur:
                    segs.append(" ".join(cur)); cur = []
            else:
                cur.append(body.strip())
            i += 1
        if cur:
            segs.append(" ".join(cur))
        flow.append(Paragraph("<br/><br/>".join(inline(s) for s in segs), NOTEP))
        started = True
        continue

    cbm = CB.match(line)
    bum = BU.match(line)
    if cbm or bum:
        indent = leadsp(line)
        level = 0 if indent < 4 else 1
        if cbm:
            tok = "[%s]" % cbm.group(2)
            body0 = cbm.group(3)
            textcol = indent + 6
            mk = marker(tok)
        else:
            body0 = bum.group(2)
            textcol = indent + 2
            bcol = "#9b2c2c" if section and "WONT" in section else "#5a5f66"
            mk = f'<font color="{bcol}"><b>&bull;</b></font>&nbsp;'
        conts = []
        j = i + 1
        while j < n:
            nx = lines[j]
            if nx.strip() == "" or H.match(nx) or nx.strip() == "---":
                break
            ind = leadsp(nx)
            if ind <= indent and (CB.match(nx) or BU.match(nx)):
                break
            if CB.match(nx) and ind > indent:
                break  # a nested item starts its own block
            conts.append((ind, nx))
            j += 1
        emit_item(mk, level, textcol, body0, conts)
        started = True
        i = j
        continue

    # bare prose (rare): join consecutive plain lines into one paragraph
    buf = [line.strip()]
    i += 1
    while i < n and lines[i].strip() and not H.match(lines[i]) \
            and lines[i].strip() != "---" and not CB.match(lines[i]) \
            and not BU.match(lines[i]) and not re.match(r"^\s*>", lines[i]):
        buf.append(lines[i].strip()); i += 1
    flow.append(Paragraph(inline(" ".join(buf)), BODY))
    started = True

# ---- page furniture ------------------------------------------------------
def furniture(canvas, doc):
    canvas.saveState()
    canvas.setFont("Helvetica", 7.5)
    canvas.setFillColor(MUTED)
    canvas.drawString(16 * mm, 10 * mm, "P8X Project Backlog")
    canvas.drawCentredString(doc.pagesize[0] / 2, 10 * mm, "Generated " + STAMP)
    canvas.drawRightString(doc.pagesize[0] - 16 * mm, 10 * mm, "page %d" % doc.page)
    canvas.setStrokeColor(colors.HexColor("#d7dee6"))
    canvas.setLineWidth(0.4)
    canvas.line(16 * mm, 12 * mm, doc.pagesize[0] - 16 * mm, 12 * mm)
    canvas.restoreState()

doc = SimpleDocTemplate(str(OUT), pagesize=letter,
                        leftMargin=16 * mm, rightMargin=16 * mm,
                        topMargin=15 * mm, bottomMargin=16 * mm,
                        title="P8X Project Backlog")
doc.build(flow, onFirstPage=furniture, onLaterPages=furniture)
print("wrote", OUT)
