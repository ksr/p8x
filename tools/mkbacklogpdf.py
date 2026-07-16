#!/usr/bin/env python3
"""Build a printable one-glance summary of BACKLOG.md (live work only).

Reads ../BACKLOG.md and writes ../BACKLOG-summary.pdf — a few pages you can
print and mark up, one line per open item, completed work excluded (that lives
in BACKLOG-DONE.md). Re-run it after the backlog changes; the PDF is a generated
artifact and is NOT tracked in git.

    python3 tools/mkbacklogpdf.py

Needs reportlab (`pip install reportlab`). Paths are resolved relative to this
file, so it runs from any directory.
"""
import re, datetime, pathlib, sys
from reportlab.lib.pagesizes import letter
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.lib.styles import ParagraphStyle
from reportlab.platypus import (SimpleDocTemplate, Paragraph, Spacer, Table,
                               TableStyle, KeepTogether)
from reportlab.graphics.shapes import Drawing, Rect, Line

def checkbox(kind):
    """A drawn box, not a glyph: the built-in fonts have no box characters and
    render them as solid black squares."""
    d = Drawing(9, 9)
    d.add(Rect(0.5, 0.6, 6.6, 6.6, strokeColor=colors.HexColor('#33475b'),
               strokeWidth=0.7, fillColor=None))
    if kind == 'part':                      # half-filled = partly done
        d.add(Rect(0.5, 0.6, 3.3, 6.6, strokeColor=None,
                   fillColor=colors.HexColor('#8fa6bb')))
    elif kind == 'wont':                    # crossed = decided against
        d.add(Line(0.9, 1.0, 6.8, 6.8, strokeColor=colors.HexColor('#8a3b3b'), strokeWidth=0.8))
        d.add(Line(6.8, 1.0, 0.9, 6.8, strokeColor=colors.HexColor('#8a3b3b'), strokeWidth=0.8))
    return d


ROOT = pathlib.Path(__file__).resolve().parent.parent
SRC = ROOT / 'BACKLOG.md'
OUT = ROOT / 'BACKLOG-summary.pdf'

# ---------- parse ----------
if not SRC.exists():
    sys.exit(f'{SRC} not found')
lines = SRC.read_text().split('\n')
secs = [(i, l[3:].strip()) for i, l in enumerate(lines) if l.startswith('## ')]
secs.append((len(lines), 'EOF'))

def items(s, e):
    out, cur = [], None
    for i in range(s + 1, e):
        l = lines[i]
        if re.match(r'^- ', l):
            if cur: out.append(cur)
            cur = [l, []]
        elif cur is not None and l.strip():
            cur[1].append(l.strip())
    if cur: out.append(cur)
    return out

def clean(t):
    t = re.sub(r'\*\*(.+?)\*\*', r'\1', t)
    t = re.sub(r'`(.+?)`', r'\1', t)
    t = re.sub(r'\[(.+?)\]\(.+?\)', r'\1', t)
    t = t.replace('**', '')
    return re.sub(r'\s+', ' ', t).strip()

def split_item(head, body):
    m = re.match(r'^- (\[[ x~]\] )?(.*)', head)
    mark = (m.group(1) or '').strip()
    rest = clean(m.group(2))
    # title = up to the first sentence-ish break
    mt = re.match(r'^(.{0,78}?)(?:\.\s|\s—\s|\s-\s|$)(.*)', rest, re.S)
    title, tail = (mt.group(1), mt.group(2)) if mt else (rest[:78], rest[78:])
    gist = clean(tail + ' ' + ' '.join(body))
    return mark, title.strip(' .—-'), gist

# ---------- styles ----------
BLUE = colors.HexColor('#1a3a5c')
GREY = colors.HexColor('#5a5a5a')
RULE = colors.HexColor('#b8c4d0')

st_title = ParagraphStyle('t', fontName='Helvetica-Bold', fontSize=17, leading=20,
                          textColor=BLUE, spaceAfter=1)
st_sub = ParagraphStyle('s', fontName='Helvetica', fontSize=8.4, leading=11,
                        textColor=GREY, spaceAfter=7)
st_sec = ParagraphStyle('h', fontName='Helvetica-Bold', fontSize=10.4, leading=12,
                        textColor=colors.white, spaceBefore=0, spaceAfter=0,
                        leftIndent=4)
st_it = ParagraphStyle('i', fontName='Helvetica-Bold', fontSize=8.3, leading=10)
st_g = ParagraphStyle('g', fontName='Helvetica', fontSize=7.3, leading=8.7,
                      textColor=GREY)
st_note = ParagraphStyle('n', fontName='Helvetica-Oblique', fontSize=7.4,
                         leading=9.2, textColor=GREY)

BLURB = {
 'NEXT':  'Committed, in rough priority order.',
 'IDEAS': 'Captured, not yet committed.',
 'VERIFY': 'Open questions / checks before trusting something.',
 'WONT-DO / SUPERSEDED':
    'Settled decisions NOT to do something. Read before starting anything that '
    'looks obviously missing — acting on the first one shipped a buffer overflow.',
}

def sec_bar(name, n):
    cnt = f'{n} item{"s" if n != 1 else ""}'
    t = Table([[Paragraph(name, st_sec),
                Paragraph(f'<font color="#d5e2ee">{cnt}</font>', st_sec)]],
              colWidths=[120*mm, 52*mm])
    t.setStyle(TableStyle([
        ('BACKGROUND', (0,0), (-1,-1), BLUE),
        ('TOPPADDING', (0,0), (-1,-1), 3.2),
        ('BOTTOMPADDING', (0,0), (-1,-1), 3.4),
        ('ALIGN', (1,0), (1,0), 'RIGHT'),
        ('VALIGN', (0,0), (-1,-1), 'MIDDLE'),
    ]))
    return t

story = []
story.append(Paragraph('P8X — Project Backlog', st_title))
story.append(Paragraph(
    'Live work only — nothing here is done. Completed work lives in '
    'BACKLOG-DONE.md. &nbsp;&nbsp;Empty box = open; half-filled = partly done '
    '(the remainder is why it is still listed); crossed = decided against. Generated '
    + datetime.date.today().isoformat() + ' from BACKLOG.md.', st_sub))

for (s, name), (e, _) in zip(secs, secs[1:]):
    if name in ('How to use', 'EOF'):
        continue
    its = items(s, e)
    block = [Spacer(1, 3.5), sec_bar(name, len(its)), Spacer(1, 2.2)]
    if name in BLURB:
        block.append(Paragraph(BLURB[name], st_note))
        block.append(Spacer(1, 1.5))
    story.append(KeepTogether(block))

    rows, styl = [], [
        ('VALIGN', (0,0), (-1,-1), 'TOP'),
        ('LEFTPADDING', (0,0), (-1,-1), 0),
        ('RIGHTPADDING', (0,0), (-1,-1), 2),
        ('TOPPADDING', (0,0), (-1,-1), 2.6),
        ('BOTTOMPADDING', (0,0), (-1,-1), 2.6),
        ('LINEBELOW', (0,0), (-1,-2), 0.25, RULE),
    ]
    wont = name.startswith('WONT')
    for head, body in its:
        mark, title, gist = split_item(head, body)
        kind = 'part' if '~' in mark else ('wont' if wont else 'open')
        cell = [Paragraph(title, st_it)]
        if gist:
            cell.append(Paragraph(gist[:250] + ('…' if len(gist) > 250 else ''), st_g))
        rows.append([checkbox(kind), cell])
    t = Table(rows, colWidths=[6.5*mm, 165.5*mm])
    t.setStyle(TableStyle(styl))
    story.append(t)

def foot(canv, doc):
    canv.saveState()
    canv.setFont('Helvetica', 7)
    canv.setFillColor(GREY)
    canv.drawString(19*mm, 11*mm, 'P8X backlog summary — live items only')
    canv.drawRightString(196*mm, 11*mm, f'page {doc.page}')
    canv.restoreState()

SimpleDocTemplate(str(OUT), pagesize=letter,
                  leftMargin=19*mm, rightMargin=19*mm,
                  topMargin=14*mm, bottomMargin=16*mm,
                  title='P8X Project Backlog — summary',
                  author='p8x').build(story, onFirstPage=foot, onLaterPages=foot)
print('wrote', OUT)
