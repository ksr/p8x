#!/usr/bin/env python3
"""P8X instruction-set one-page quick-reference card.

Opcode values, mnemonics and addressing shapes are imported LIVE from
genucode.py (the microcode source of truth) -- the same OPC table the
assembler (p8xasm.py) and the programmer's guide (gen_progguide.py) import,
so this card cannot drift. Cycle counts come from U[opcode]. Only the prose
descriptions are authored here.

Output: docs/p8x-isa-card.pdf  (one US-Letter landscape page).
"""
import sys, os
from xml.sax.saxutils import escape   # descriptions contain <, >, & (e.g. "A < B")


def _find_genucode():
    """Locate the microcode dir regardless of repo layout (cf. gen_progguide.py)."""
    here = os.path.dirname(os.path.abspath(__file__))
    cands = [here,
             os.path.join(here, "microcode"),
             os.path.join(here, "..", "microcode"),
             os.path.join(here, "..", "..", "microcode"),
             os.path.join(os.getcwd(), "microcode"),
             os.getcwd()]
    for d in cands:
        if os.path.isfile(os.path.join(d, "genucode.py")):
            sys.path.insert(0, os.path.abspath(d)); return os.path.abspath(d)
    sys.exit("cannot find genucode.py")


_find_genucode()
from genucode import OPC, U  # noqa: E402

from reportlab.lib.pagesizes import letter, landscape  # noqa: E402
from reportlab.lib import colors  # noqa: E402
from reportlab.lib.units import mm  # noqa: E402
from reportlab.platypus import (SimpleDocTemplate, Table, TableStyle, Paragraph,  # noqa: E402
                                Spacer)
from reportlab.platypus.flowables import KeepInFrame  # noqa: E402
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle  # noqa: E402

# ---- operand-shape rendering + byte counts (same as gen_progguide.py) -------
SHN = {"": "", "#": " #imm", "a": " addr", "(P1)": " (P1)", "(P2)": " (P2)",
       "(P3)": " (P3)", "(P1)+": " (P1)+", "(P2)+": " (P2)+", "(P3)+": " (P3)+"}
BYTES = {"": 1, "#": 2, "a": 3, "(P1)": 1, "(P2)": 1, "(P3)": 1,
         "(P1)+": 1, "(P2)+": 1, "(P3)+": 1}

# (mnemonic, shape) -> (flags, one-line description). Authored prose only.
DESC = {
    ("NOP", ""): ("-", "No operation."),
    ("HLT", ""): ("-", "Halt clock; resume only by reset."),
    ("EI", ""): ("-", "Enable maskable interrupts (IE:=1)."),
    ("DI", ""): ("-", "Disable maskable interrupts (IE:=0)."),
    ("RTI", ""): ("-", "Return from interrupt: pop flags then PC; re-enable IE."),
    ("IRQ", ""): ("-", "SW interrupt: push PC+flags, vector to $0808."),
    ("CLC", ""): ("C", "C:=0."),
    ("SEC", ""): ("C", "C:=1."),
    ("ADD", ""): ("CZN", "A:=A+B."),
    ("SUB", ""): ("CZN", "A:=A-B."),
    ("AND", ""): ("CZN", "A:=A AND B."),
    ("OR", ""): ("CZN", "A:=A OR B."),
    ("XOR", ""): ("CZN", "A:=A XOR B."),
    ("CMP", ""): ("CZN", "Flags from A-B; A unchanged."),
    ("INC", ""): ("CZN", "A:=A+1 (B unused)."),
    ("DEC", ""): ("CZN", "A:=A-1 (B unused)."),
    ("SHL", ""): ("CZN", "A:=A<<1, 0->bit0, out->C."),
    ("SHR", ""): ("CZN", "A:=A>>1, 0->bit7, out->C."),
    ("ROL", ""): ("CZN", "Rotate A left through carry."),
    ("ROR", ""): ("CZN", "Rotate A right through carry."),
    ("LDT", "#"): ("-", "T:=immediate."),
    ("LDT", "a"): ("-", "T:=byte at addr (absolute)."),
    ("ADDT", ""): ("CZN", "A:=A+T (B preserved)."),
    ("SUBT", ""): ("CZN", "A:=A-T (B preserved)."),
    ("ANDT", ""): ("CZN", "A:=A AND T (B preserved)."),
    ("ORT", ""): ("CZN", "A:=A OR T (B preserved)."),
    ("XORT", ""): ("CZN", "A:=A XOR T (B preserved)."),
    ("CMPT", ""): ("CZN", "Flags from A-T; A,B unchanged."),
    ("LDA", "#"): ("ZN", "A:=immediate."),
    ("LDB", "#"): ("ZN", "B:=immediate."),
    ("LDA", "a"): ("ZN", "A:=byte at addr (absolute)."),
    ("LDB", "a"): ("ZN", "B:=byte at addr (absolute)."),
    ("STA", "a"): ("-", "byte at addr:=A (absolute)."),
    ("PHA", ""): ("-", "Push A onto P3 stack."),
    ("PLA", ""): ("ZN", "Pop A from P3 stack."),
    ("JMP", "a"): ("-", "P0(PC):=addr."),
    ("JSR", "(P1)"): ("-", "Push return addr, P0:=P1."),
    ("JSR", "a"): ("-", "Push return addr, P0:=addr."),
    ("RTS", ""): ("-", "Pop return addr from P3 into P0."),
    ("BZ", "a"): ("-", "Branch if Z=1. (JZ alias.)"),
    ("BNZ", "a"): ("-", "Branch if Z=0. (JNZ alias.)"),
    ("BCP", "a"): ("-", "Branch if C=1 / A>=B unsigned. (JC alias.)"),
    ("JNC", "a"): ("-", "Branch if C=0 / A<B unsigned."),
    ("BLT", "a"): ("-", "Branch if signed A<B (N^V=1). After CMP."),
    ("BGE", "a"): ("-", "Branch if signed A>=B (N^V=0). After CMP."),
    ("BLE", "a"): ("-", "Branch if signed A<=B ((N^V)|Z). After CMP."),
    ("BGT", "a"): ("-", "Branch if signed A>B. After CMP."),
}
for p in (1, 2, 3):
    DESC[("LDA", "(P%d)+" % p)] = ("ZN", "A:=[P%d], P%d++." % (p, p))
    DESC[("STA", "(P%d)+" % p)] = ("-", "[P%d]:=A, P%d++." % (p, p))
    DESC[("STA", "(P%d)" % p)] = ("-", "[P%d]:=A." % p)
    DESC[("LDA", "(P%d)" % p)] = ("ZN", "A:=[P%d] (P%d kept)." % (p, p))
    DESC[("LPL%d" % p, "#")] = ("-", "P%d low byte:=imm." % p)
    DESC[("LPH%d" % p, "#")] = ("-", "P%d high byte:=imm." % p)
    DESC[("INP%d" % p, "")] = ("-", "P%d:=P%d+1." % (p, p))
    DESC[("DEP%d" % p, "")] = ("-", "P%d:=P%d-1." % (p, p))
    DESC[("TAP%dL" % p, "")] = ("-", "P%d low:=A." % p)
    DESC[("TAP%dH" % p, "")] = ("-", "P%d high:=A." % p)
    DESC[("TPA%dL" % p, "")] = ("ZN", "A:=P%d low." % p)
    DESC[("TPA%dH" % p, "")] = ("ZN", "A:=P%d high." % p)

# Category grouping (mirrors gen_progguide.py GROUPS).
GROUPS = [
    ("System", ["NOP", "HLT", "CLC", "SEC"]),
    ("Interrupts (rev C)", ["EI", "DI", "RTI", "IRQ"]),
    ("Load / store", ["LDA", "LDB", "STA"]),
    ("ALU (A,B -> A)", ["ADD", "SUB", "AND", "OR", "XOR", "CMP", "INC", "DEC",
                        "SHL", "SHR", "ROL", "ROR"]),
    ("ALU with T (rev C; 2nd operand=T, B preserved)",
     ["LDT", "ADDT", "SUBT", "ANDT", "ORT", "XORT", "CMPT"]),
    ("Stack", ["PHA", "PLA"]),
    ("Control flow", ["JMP", "JSR", "RTS", "BZ", "BNZ", "BCP", "JNC"]),
    ("Signed branches (rev C; after CMP)", ["BLT", "BGE", "BLE", "BGT"]),
    ("Pointer registers", ["LPL1", "LPH1", "LPL2", "LPH2", "LPL3", "LPH3",
                           "INP1", "INP2", "INP3", "DEP1", "DEP2", "DEP3",
                           "TAP1L", "TAP1H", "TAP2L", "TAP2H", "TAP3L", "TAP3H",
                           "TPA1L", "TPA1H", "TPA2L", "TPA2H", "TPA3L", "TPA3H"]),
]

# ---- styles -----------------------------------------------------------------
S = getSampleStyleSheet()
H1 = ParagraphStyle("h1", parent=S["Title"], fontSize=14, spaceAfter=1)
SUB = ParagraphStyle("sub", parent=S["Normal"], fontSize=6.8, textColor=colors.grey)
CELL = ParagraphStyle("cell", parent=S["Normal"], fontSize=5.9, leading=6.8)

HDR_BG = colors.Color(0.15, 0.25, 0.45)
GRP_BG = colors.Color(0.85, 0.89, 0.96)


def build_col(groups):
    """Return (table, rendered_opcode_count) for a list of groups."""
    rows = [["Op", "Mnemonic", "By", "Cy", "Fl", "Description"]]
    spans = []
    n_ops = 0
    r = 1
    for gname, mns in groups:
        rows.append([gname, "", "", "", "", ""]); spans.append(r); r += 1
        entries = [(code, mn, sh) for (mn, sh), code in OPC.items() if mn in mns]
        for code, mn, sh in sorted(entries):
            # JZ/JNZ/JC are pure aliases (same opcode as BZ/BNZ/BCP) -- skip the
            # duplicate rows; the alias is noted in the BCP/BZ/BNZ descriptions.
            if (mn, sh) not in DESC:
                continue
            fl, ds = DESC[(mn, sh)]
            cyc = 1 + len(U[code])  # +1 fetch cycle
            rows.append(["$%02X" % code, mn + SHN[sh], str(BYTES[sh]), str(cyc),
                         fl, Paragraph(escape(ds), CELL)])
            n_ops += 1; r += 1
    t = Table(rows, colWidths=[8 * mm, 17 * mm, 5 * mm, 5 * mm, 7 * mm, 49 * mm],
              repeatRows=1)
    st = [("FONT", (0, 0), (-1, -1), "Helvetica", 5.9),
          ("FONT", (0, 0), (-1, 0), "Helvetica-Bold", 6),
          ("FONT", (0, 1), (1, -1), "Courier", 5.9),
          ("BACKGROUND", (0, 0), (-1, 0), HDR_BG),
          ("TEXTCOLOR", (0, 0), (-1, 0), colors.white),
          ("GRID", (0, 0), (-1, -1), 0.25, colors.Color(0.75, 0.75, 0.75)),
          ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
          ("TOPPADDING", (0, 0), (-1, -1), 0.4),
          ("BOTTOMPADDING", (0, 0), (-1, -1), 0.4),
          ("LEFTPADDING", (0, 0), (-1, -1), 1.5),
          ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.Color(0.96, 0.97, 1)])]
    for sr in spans:
        st += [("SPAN", (0, sr), (-1, sr)),
               ("BACKGROUND", (0, sr), (-1, sr), GRP_BG),
               ("FONT", (0, sr), (-1, sr), "Helvetica-Bold", 6)]
    t.setStyle(TableStyle(st))
    return t, n_ops


# Split categories across two side-by-side columns to fit one landscape page.
LEFT = GROUPS[:5]    # system, interrupts, load/store, ALU, ALU-T
RIGHT = GROUPS[5:]   # stack, control flow, signed branches, pointers
tL, nL = build_col(LEFT)
tR, nR = build_col(RIGHT)
N_OPS = nL + nR

legend = Paragraph(
    "<b>Operands:</b> #imm immediate | addr 16-bit absolute | (Pn) ptr indirect | "
    "(Pn)+ post-increment | (no operand) implied. &nbsp; "
    "<b>By</b>=bytes, <b>Cy</b>=cycles (incl. fetch). &nbsp; "
    "<b>Flags (Fl):</b> C carry (active-high: ADD carry-out / SUB,CMP no-borrow A>=B), "
    "Z zero, N negative (bit7), V overflow. '-' = none. Signed branches test N^V / Z. &nbsp; "
    "<b>Memory (rev D):</b> $0000-3FFF ROM | $4000-FEFF RAM | $FF00-FFFF I/O. "
    "P0=PC, P3=stack (empty-descending). JZ/JNZ/JC are aliases of BZ/BNZ/BCP.",
    SUB)

two_col = Table([[tL, tR]], colWidths=[93 * mm, 93 * mm])
two_col.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"),
                             ("LEFTPADDING", (1, 0), (1, 0), 5)]))

story = [Paragraph("P8X Instruction Set -- Quick Reference (rev C)", H1),
         Paragraph("Opcodes, mnemonics and cycle counts generated live from "
                   "genucode.py (the microcode source of truth) -- cannot drift "
                   "from the hardware.", SUB),
         Spacer(1, 2), legend, Spacer(1, 3), two_col]

_DOCS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "docs")
doc = SimpleDocTemplate(os.path.join(_DOCS, "p8x-isa-card.pdf"),
                        pagesize=landscape(letter),
                        leftMargin=9 * mm, rightMargin=9 * mm,
                        topMargin=7 * mm, bottomMargin=7 * mm,
                        title="P8X ISA Card", author="P8X Project")
frame_w = landscape(letter)[0] - 18 * mm
frame_h = landscape(letter)[1] - 14 * mm
doc.build([KeepInFrame(frame_w, frame_h, story, mode="shrink")])
print("ISA card written: %s  (%d opcodes)" % (os.path.join(_DOCS, "p8x-isa-card.pdf"), N_OPS))
