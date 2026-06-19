#!/usr/bin/env python3
"""P8X Bus one-page quick-reference card.

The 96-pin DIN 41612 pin->signal map is reproduced EXACTLY from busnet() --
the SAME authoritative function used by gen_eagle.py (the CAD generator) and
by gen_bus_pdf.py. Copied verbatim here so the card cannot drift from the
boards; do not edit the map by hand. Signal-group descriptions follow
hardware/backplane/p8x-bus-definition.md.

Output: hardware/backplane/p8x-bus-card.pdf  (one US-Letter landscape page).
"""
import os
from reportlab.lib.pagesizes import letter, landscape
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.platypus import (SimpleDocTemplate, Paragraph, Spacer, Table,
                                TableStyle)
from reportlab.platypus.flowables import KeepInFrame
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle


# ---- single source of truth: identical to gen_eagle.py busnet() -------------
# (gen_eagle returns "VCC" for power; the human-facing bus doc renders it "+5V".)
def busnet(pin):
    r, n = pin[0], int(pin[1:])
    if n in (1, 2): return "+5V"
    if n in (31, 32): return "GND"
    if r == "B":
        if n in (27, 28, 29, 30): return {27: "CLRC", 28: "BSEL", 29: "IRQ", 30: "SPARE11"}[n]
        if 3 <= n <= 26 and n % 2 == 0: return "SPARE%d" % (12 + (n - 4) // 2)  # even -> SPARE12..23
        return "GND"   # odd pins stay ground guards
    if r == "A":
        if 3 <= n <= 10: return "D%d" % (n - 3)
        if n == 11: return "-RES"
        if 12 <= n <= 15: return "DOE%d" % (n - 12)
        if 16 <= n <= 19: return "DLD%d" % (n - 16)
        return {20: "PSEL0", 21: "PSEL1", 22: "PINC", 23: "PDEC", 24: "CLK",
                25: "CLKB", 26: "LDF", 27: "FC", 28: "FZ", 29: "FN", 30: "FV"}.get(n)
    if 3 <= n <= 18: return "A%d" % (n - 3)
    if 19 <= n <= 22: return "ALUS%d" % (n - 19)
    return {23: "ALUM", 24: "CIN", 25: "SH0", 26: "SH1",
            27: "PSEL2", 28: "LDZN", 29: "SHCIN", 30: "SETC"}.get(n, "SPARE%d" % (n - 27 + 4))


# ---- styles -----------------------------------------------------------------
S = getSampleStyleSheet()
H1 = ParagraphStyle("h1", parent=S["Title"], fontSize=15, spaceAfter=2)
SUB = ParagraphStyle("sub", parent=S["Normal"], fontSize=7.5, textColor=colors.grey)
H2 = ParagraphStyle("h2", parent=S["Heading2"], fontSize=8.5, spaceBefore=2, spaceAfter=2)
LEG = ParagraphStyle("leg", parent=S["Normal"], fontSize=6.4, leading=7.6)
LEGH = ParagraphStyle("legh", parent=LEG, textColor=colors.white, fontName="Helvetica-Bold")


def shade(net):
    if net == "+5V": return colors.Color(1, 0.85, 0.85)
    if net == "GND": return colors.Color(0.85, 0.92, 1)
    if net.startswith("SPARE"): return colors.Color(0.93, 0.93, 0.93)
    return colors.white


# ---- 96-pin table: pin no. + one column per row A/B/C -----------------------
head = ["Pin", "Row A", "Row B", "Row C"]
rows = [head]
for n in range(1, 33):
    rows.append([str(n), busnet("A%d" % n), busnet("B%d" % n), busnet("C%d" % n)])

t = Table(rows, colWidths=[9 * mm, 27 * mm, 27 * mm, 27 * mm], repeatRows=1)
style = [("FONT", (0, 0), (-1, 0), "Helvetica-Bold", 7),
         ("FONT", (0, 1), (-1, -1), "Courier", 7),
         ("BACKGROUND", (0, 0), (-1, 0), colors.Color(0.2, 0.2, 0.2)),
         ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
         ("GRID", (0, 0), (-1, -1), 0.3, colors.grey),
         ("ALIGN", (0, 0), (0, -1), "CENTER"),
         ("TOPPADDING", (0, 0), (-1, -1), 0.8),
         ("BOTTOMPADDING", (0, 0), (-1, -1), 0.8)]
for ri in range(1, 33):
    for ci, col in enumerate("ABC"):
        style.append(("BACKGROUND", (ci + 1, ri), (ci + 1, ri),
                      shade(busnet("%s%d" % (col, ri)))))
t.setStyle(TableStyle(style))


# ---- signal-group legend ----------------------------------------------------
def legtbl(data, widths):
    body = [[Paragraph(c, LEGH if i == 0 else LEG) for c in row]
            for i, row in enumerate(data)]
    tl = Table(body, colWidths=widths, repeatRows=1)
    tl.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), colors.Color(0.2, 0.2, 0.2)),
        ("GRID", (0, 0), (-1, -1), 0.3, colors.grey),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING", (0, 0), (-1, -1), 0.8),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 0.8),
        ("LEFTPADDING", (0, 0), (-1, -1), 2),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.Color(0.96, 0.96, 0.96)])]))
    return tl

leg_data = [
    ["Group", "Signals", "Meaning"],
    ["Data bus", "D0-D7 (A3-A10)", "8-bit bidirectional data bus; one driver/microcycle (one-hot DOE)."],
    ["Address bus", "A0-A15 (C3-C18)", "16-bit address; driven solely by the register-bank card (selected pointer)."],
    ["DOE field", "DOE0-3 (A12-A15)", "Data Output Enable: selects which card drives the data bus."],
    ["DLD field", "DLD0-3 (A16-A19)", "Data LoaD: selects which register latches the data bus."],
    ["Pointer sel", "PSEL0-1 (A20-A21), PSEL2 (C27)", "Selects active pointer P0-P3 (+PT scratch=4); PINC/PDEC inc/dec it."],
    ["Ptr inc/dec", "PINC (A22), PDEC (A23)", "Increment / decrement the selected pointer."],
    ["ALU select", "ALUS0-3 (C19-C22), ALUM (C23), CIN (C24)", "74181 function select, mode (logic/arith), carry-in."],
    ["Shifter", "SH0 (C25), SH1 (C26), SHCIN (C29)", "Shifter control; SHCIN = shift-in is C flag (rotate-through-carry)."],
    ["Flags out", "FC FZ FN FV (A27-A30)", "Carry/Zero/Negative/oVerflow; ALU card -> control card cond mux."],
    ["Flag latch", "LDF (A26), LDZN (C28)", "LDF latches C/Z/N/V; LDZN latches only Z,N on loads."],
    ["C control", "SETC (C30), CLRC (B27)", "Force C=1 (SEC) / C=0 (CLC), leaving Z/N/V untouched."],
    ["Clock/reset", "CLK (A24), CLKB (A25), -RES (A11)", "System clock + complement; reset active-low. (Control card -> all.)"],
    ["Rev-C lines", "BSEL (B28), IRQ (B29)", "BSEL: ALU B-mux 0=B reg,1=T reg. IRQ: maskable int request (reserved)."],
    ["Power/GND", "+5V (1,2 all rows), GND (31,32 + row-B guard)", "+5V/GND planes; row B 3-26 is a grounded guard between signal rows."],
    ["Spare", "SPARE4-11 (rev-C reallocations noted)", "Reserved, bused to all 10 slots. SPARE0-3 became FC/FZ/FN/FV."],
]
leg = legtbl(leg_data, [16 * mm, 38 * mm, 105 * mm])

note = Paragraph(
    "Connector: DIN 41612, 3 rows (A/B/C) x 32 pins, 10 slots @ 25.4 mm. "
    "Shading: <font backColor='#FFD9D9'>&nbsp;+5V&nbsp;</font> "
    "<font backColor='#D9EBFF'>&nbsp;GND&nbsp;</font> "
    "<font backColor='#EEEEEE'>&nbsp;spare&nbsp;</font>. "
    "Generated from the same busnet() pin-map as the CAD files -- cannot drift from the boards.",
    SUB)


# ---- page assembly: pin table (left) + legend (right), all on one page ------
_HW = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                   "hardware", "backplane")
doc = SimpleDocTemplate(os.path.join(_HW, "p8x-bus-card.pdf"),
                        pagesize=landscape(letter),
                        leftMargin=10 * mm, rightMargin=10 * mm,
                        topMargin=8 * mm, bottomMargin=8 * mm,
                        title="P8X Bus Card", author="P8X Project")

right = [Paragraph("Signal Groups", H2), leg, Spacer(1, 4), note]
two_col = Table([[t, KeepInFrame(165 * mm, 175 * mm, right, mode="shrink")]],
                colWidths=[95 * mm, 170 * mm])
two_col.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"),
                             ("LEFTPADDING", (1, 0), (1, 0), 6)]))

story = [Paragraph("P8X Backplane Bus -- Quick Reference (rev C)", H1),
         Paragraph("DIN 41612 96-pin pin&rarr;signal map (component-side view of card connector)", SUB),
         Spacer(1, 3), two_col]

# Keep everything on a single page: shrink-to-fit the whole body if needed.
frame_w = landscape(letter)[0] - 20 * mm
frame_h = landscape(letter)[1] - 16 * mm
doc.build([KeepInFrame(frame_w, frame_h, story, mode="shrink")])
print("bus card written:", os.path.join(_HW, "p8x-bus-card.pdf"))
