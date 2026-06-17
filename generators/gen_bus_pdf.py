#!/usr/bin/env python3
"""P8X Bus Definition rev C -- review PDF.
Pin map generated from the SAME busnet() function as the CAD generators,
so this document cannot drift from the boards."""
from reportlab.lib.pagesizes import letter
from reportlab.lib.units import mm
from reportlab.lib import colors
from reportlab.platypus import (SimpleDocTemplate, Paragraph, Spacer, Table,
                                TableStyle, PageBreak)
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle

# ---- single source of truth (identical to the Eagle/KiCad generators) ----
def busnet(pin):
    r,n=pin[0],int(pin[1:])
    if n in (1,2): return "+5V"
    if n in (31,32): return "GND"
    if r=="B": return {27:"CLRC",28:"SPARE9",29:"SPARE10",30:"SPARE11"}.get(n,"GND")
    if r=="A":
        if 3<=n<=10: return "D%d"%(n-3)
        if n==11: return "-RES"
        if 12<=n<=15: return "DOE%d"%(n-12)
        if 16<=n<=19: return "DLD%d"%(n-16)
        return {20:"PSEL0",21:"PSEL1",22:"PINC",23:"PDEC",24:"CLK",25:"CLKB",26:"LDF",27:"FC",28:"FZ",29:"FN",30:"FV"}.get(n)
    if 3<=n<=18: return "A%d"%(n-3)
    if 19<=n<=22: return "ALUS%d"%(n-19)
    return {23:"ALUM",24:"CIN",25:"SH0",26:"SH1",
            27:"PSEL2",28:"LDZN",29:"SHCIN",30:"SETC"}.get(n,"SPARE%d"%(n-27+4))

DESC={
 "FC":"Flag: Carry. Driven continuously by the ALU card flag register; read by the control card condition mux for conditional branches",
 "FZ":"Flag: Zero. ALU card to control card, as FC",
 "FN":"Flag: Negative (result bit 7). ALU card to control card, as FC",
 "FV":"Flag: oVerflow. ALU card to control card; rev A ALU card drives 0 (V unimplemented, see backlog)",
 "+5V":"Power, 6 pins total","GND":"Ground / row-B guard",
 "-RES":"System reset, active low","CLK":"System clock","CLKB":"Inverted clock",
 "LDF":"Latch flags (ALU card)","PINC":"Selected pointer increment",
 "PDEC":"Selected pointer decrement","ALUM":"74181 mode (logic/arith)",
 "CIN":"ALU carry in","SH0":"Shifter control 0","SH1":"Shifter control 1",
 "PSEL2":"Pointer-select bit 2 (rev B: P0-P3 + PT scratch=4); to reg-bank",
 "LDZN":"Latch Z,N from the data bus on loads (rev B); to ALU card",
 "SHCIN":"Shifter shift-in = C flag, for rotate-through-carry (rev B); to ALU card",
 "SETC":"Force C flag = 1 (SEC, rev B); to ALU card",
 "CLRC":"Force C flag = 0 (CLC, rev B); to ALU card",
}
def desc(net):
    if net in DESC: return DESC[net]
    if net.startswith("D"): return "Data bus bit "+net[1:]
    if net.startswith("A") and net[1:].isdigit(): return "Address bus bit "+net[1:]
    if net.startswith("DOE"): return "Data-source select bit "+net[3:]
    if net.startswith("DLD"): return "Data-destination select bit "+net[3:]
    if net.startswith("PSEL"): return "Pointer select bit "+net[4:]
    if net.startswith("ALUS"): return "74181 function select S"+net[4:]
    if net.startswith("SPARE"): return "Reserved, bused across all slots"
    return ""

styles=getSampleStyleSheet()
H1=styles["Title"]; H2=styles["Heading2"]; N=styles["Normal"]
SM=ParagraphStyle("sm",parent=N,fontSize=8,leading=10)
import os as _os; _DOCS=_os.path.join(_os.path.dirname(_os.path.dirname(_os.path.abspath(__file__))),"hardware","backplane")
doc=SimpleDocTemplate(_os.path.join(_DOCS,"p8x-bus-definition.pdf"),
    pagesize=letter,topMargin=18*mm,bottomMargin=16*mm,
    title="P8X Bus Definition Rev C",author="P8X Project")
story=[]
story.append(Paragraph("P8X Backplane Bus Definition", H1))
story.append(Paragraph("Revision C &mdash; June 2026 &mdash; FOR REVIEW", styles["Heading3"]))
story.append(Spacer(1,6))
story.append(Paragraph(
 "Connector: DIN 41612, 3 rows (A/B/C) &times; 32 pins. Backplane: 10 slots, "
 "25.4&nbsp;mm pitch, 4-layer (signals / GND plane / +5V plane / signals). "
 "Power: A1,B1,C1,A2,B2,C2 = +5V; A31,B31,C31,A32,B32,C32 = GND. "
 "Row B pins 3&ndash;30 are a grounded guard row between the two signal rows. "
 "This table is generated from the same pin-map function used by the CAD "
 "generators, so it cannot drift from the board files.", N))
story.append(Spacer(1,10))

# ---- full pin table ----
rows=[["Pin","Row A","Row B","Row C"]]
for n in range(1,33):
    rows.append([str(n), busnet("A%d"%n), busnet("B%d"%n), busnet("C%d"%n)])
t=Table(rows,colWidths=[14*mm,42*mm,42*mm,42*mm],repeatRows=1)
def shade(net):
    if net=="+5V": return colors.Color(1,0.85,0.85)
    if net=="GND": return colors.Color(0.85,0.92,1)
    if net.startswith("SPARE"): return colors.Color(0.93,0.93,0.93)
    return colors.white
style=[("FONT",(0,0),(-1,0),"Helvetica-Bold",9),
       ("FONT",(0,1),(-1,-1),"Helvetica",9),
       ("BACKGROUND",(0,0),(-1,0),colors.Color(0.2,0.2,0.2)),
       ("TEXTCOLOR",(0,0),(-1,0),colors.white),
       ("GRID",(0,0),(-1,-1),0.4,colors.grey),
       ("ALIGN",(0,0),(0,-1),"CENTER")]
for ri in range(1,33):
    for ci,col in enumerate("ABC"):
        style.append(("BACKGROUND",(ci+1,ri),(ci+1,ri),shade(busnet("%s%d"%(col,ri)))))
t.setStyle(TableStyle(style))
story.append(PageBreak())
story.append(Paragraph("Pin Assignment (component-side view of card connector)",H2))
story.append(t)
story.append(Paragraph("Shading: red = +5V, blue = GND, grey = spare (bused).",SM))
story.append(PageBreak())
story.append(Paragraph("Legend",H2))
leg=[["Acronym","Meaning","Acronym","Meaning"],
 ["Dn","Data bus, bit n (8-bit)","An","Address bus, bit n (16-bit)"],
 ["DOE0-3","Data Output Enable field: selects\nwhich card drives the data bus","DLD0-3","Data LoaD field: selects which\nregister latches the data bus"],
 ["PSEL0-1","Pointer SELect: which of P0-P3\n(PC/ptr/ptr/SP) is active","PINC / PDEC","Pointer INCrement / DECrement\n(applies to selected pointer)"],
 ["ALUS0-3","74181 ALU function Select lines","ALUM","74181 Mode: logic vs arithmetic"],
 ["CIN","ALU Carry IN","SH0-1","SHifter control (pass/left/right/rotate)"],
 ["LDF","LoaD Flags: latch C,Z,N,V from ALU","-RES","RESet, active low (_N = active low)"],
 ["CLK / CLKB","System CLocK and its complement\n(CLK-Bar); loads on rising CLK,\nwrite strobes gated by CLKB","SPAREn","Unassigned, bused to all 10 slots,\nreserved for future use","FC FZ FN FV","ALU flags to control card\n(condition mux), allocated from\nformer SPARE0-3"]]
leg=[[c.replace("\n","<br/>") if isinstance(c,str) else c for c in row] for row in leg]
legP=[[Paragraph(c,SM) if i>0 else Paragraph("<font color=white><b>%s</b></font>"%c,SM) for c in row] for i,row in enumerate(leg)]
tl=Table(legP,colWidths=[22*mm,58*mm,24*mm,58*mm],repeatRows=1)
tl.setStyle(TableStyle([
 ("BACKGROUND",(0,0),(-1,0),colors.Color(0.2,0.2,0.2)),
 ("GRID",(0,0),(-1,-1),0.3,colors.grey),
 ("VALIGN",(0,0),(-1,-1),"TOP"),
 ("ROWBACKGROUNDS",(0,1),(-1,-1),[colors.white,colors.Color(0.96,0.96,0.96)])]))
story.append(tl)
story.append(PageBreak())

# ---- signal dictionary ----
story.append(Paragraph("Signal Dictionary",H2))
seen={}
for r in "ABC":
    for n in range(1,33):
        net=busnet("%s%d"%(r,n))
        seen.setdefault(net,[]).append("%s%d"%(r,n))
def pinlist(p):
    return ", ".join(p) if len(p)<=6 else "%s ... %s (%d pins)"%(p[0],p[-1],len(p))
order=(["D%d"%i for i in range(8)]+["A%d"%i for i in range(16)]
 +["DOE%d"%i for i in range(4)]+["DLD%d"%i for i in range(4)]
 +["PSEL0","PSEL1","PSEL2","PINC","PDEC","LDF","ALUS0","ALUS1","ALUS2","ALUS3","ALUM",
   "CIN","SH0","SH1","CLK","CLKB","-RES","LDZN","SHCIN","SETC","CLRC"]
 +["FC","FZ","FN","FV"]
 +["SPARE%d"%i for i in range(9,12)]+["+5V","GND"])
rows=[["Signal","Pin(s)","Dir*","Description"]]
DIR={"CLK":"C>","CLKB":"C>","-RES":"C>","+5V":"PWR","GND":"PWR"}
def sigdir(net):
    if net in DIR: return DIR[net]
    if net.startswith("D"): return "<>"
    if net.startswith("A") and net[1:].isdigit(): return "RB>"
    if net.startswith("SPARE"): return "n/a"
    if net in ("FC","FZ","FN","FV"): return "ALU>"
    return "C>"
for net in order:
    rows.append([net,pinlist(seen[net]),sigdir(net),desc(net)])
t2=Table(rows,colWidths=[22*mm,46*mm,14*mm,84*mm],repeatRows=1)
t2.setStyle(TableStyle([
 ("FONT",(0,0),(-1,0),"Helvetica-Bold",8),
 ("FONT",(0,1),(-1,-1),"Helvetica",8),
 ("BACKGROUND",(0,0),(-1,0),colors.Color(0.2,0.2,0.2)),
 ("TEXTCOLOR",(0,0),(-1,0),colors.white),
 ("GRID",(0,0),(-1,-1),0.3,colors.grey),
 ("ROWBACKGROUNDS",(0,1),(-1,-1),[colors.white,colors.Color(0.96,0.96,0.96)])]))
story.append(t2)
story.append(Spacer(1,8))
story.append(Paragraph("Dir Field Legend",H2))
dleg=[["Symbol","Meaning"],
 ["C>","Driven by the Control card; received by all other cards"],
 ["RB>","Driven by the Register Bank card (sole address-bus driver)"],
 ["ALU>","Driven by the ALU card (flag register outputs)"],
 ["<>","Bidirectional: exactly one driver per microcycle, enforced by one-hot DOE decode"],
 ["PWR","Power distribution pin (+5V or GND planes)"],
 ["n/a","Spare: bused across all slots, no driver assigned"]]
dlegP=[[Paragraph("<font color=white><b>%s</b></font>"%c,SM) if i==0 else Paragraph(c,SM) for c in row] for i,row in enumerate(dleg)]
td=Table(dlegP,colWidths=[20*mm,142*mm],repeatRows=1)
td.setStyle(TableStyle([
 ("BACKGROUND",(0,0),(-1,0),colors.Color(0.2,0.2,0.2)),
 ("GRID",(0,0),(-1,-1),0.3,colors.grey),
 ("VALIGN",(0,0),(-1,-1),"TOP"),
 ("ROWBACKGROUNDS",(0,1),(-1,-1),[colors.white,colors.Color(0.96,0.96,0.96)])]))
story.append(td)
story.append(PageBreak())

# ---- field encodings ----
story.append(Paragraph("DOE / DLD Field Encodings",H2))
doe=[["Code","DOE: bus source","DLD: bus destination"],
 ["0","(bus idle - pulled up on backplane)","none"],
 ["1","A register","A register"],["2","B register","B register"],
 ["3","T (hidden temp)","T (hidden temp)"],["4","T2 (hidden temp)","T2 (hidden temp)"],
 ["5","ALU result via shifter","FLAGS (restore)"],["6","FLAGS","IR (instruction register)"],
 ["7","MEM read (memory / I/O)","MEMW write strobe (memory / I/O)"],
 ["8","PTRL - selected pointer low byte","PTRL - load selected pointer low"],
 ["9","PTRH - selected pointer high byte","PTRH - load selected pointer high"],
 ["10-15","reserved","reserved"]]
t3=Table(doe,colWidths=[16*mm,72*mm,78*mm],repeatRows=1)
t3.setStyle(TableStyle([
 ("FONT",(0,0),(-1,0),"Helvetica-Bold",8),
 ("FONT",(0,1),(-1,-1),"Helvetica",8),
 ("BACKGROUND",(0,0),(-1,0),colors.Color(0.2,0.2,0.2)),
 ("TEXTCOLOR",(0,0),(-1,0),colors.white),
 ("GRID",(0,0),(-1,-1),0.3,colors.grey)]))
story.append(t3)
story.append(PageBreak())
story.append(Paragraph("Review Notes",H2))
for note in [
 "1. RC clock termination (backplane far end) ships DNP; populate only if scope shows ringing.",
 "2. D0-D7 carry 10k pull-ups on the backplane only; cards never add bus conditioning.",
 "3. Loads occur on rising CLK; write strobes are gated with CLKB (second half-cycle).",
 "4. Address bus is driven exclusively by the register-bank card (selected pointer).",
 "5. rev C3: C27-C30 = PSEL2/LDZN/SHCIN/SETC and B27 = CLRC (were SPARE4-8). SPARE9-11 (B28-B30) remain reserved.",
 "5b. SPARE0-3 were reallocated as flag lines FC/FZ/FN/FV (A27-A30). SPARE numbering therefore starts at 4.",
 "5c. Row B ground guard now spans B3-B26; B27-B30 carry SPARE8-11.",
 "6. Verify row A/C orientation against physical DIN connectors before first fab."]:
    story.append(Paragraph(note,N))
doc.build(story)
print("PDF written")
