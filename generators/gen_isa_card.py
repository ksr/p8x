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
SHN = {"": "", "#": " #imm", "a": " addr", "a,a": " dst,src",
       "(P1)": " (P1)", "(P2)": " (P2)",
       "(P3)": " (P3)", "(P1)+": " (P1)+", "(P2)+": " (P2)+", "(P3)+": " (P3)+",
       # Tier A (2026-09): d = unsigned 8-bit displacement
       "#w": " #imm16", "(P1+d)": " (P1+d)", "(P2+d)": " (P2+d)", "(P3+d)": " (P3+d)",
       "a,(P1+d)": " addr,(P1+d)", "a,(P2+d)": " addr,(P2+d)", "a,(P3+d)": " addr,(P3+d)",
       "(P1+d),a": " (P1+d),addr", "(P2+d),a": " (P2+d),addr", "(P3+d),a": " (P3+d),addr",
       "a,#": " addr,#imm8", "a,#w": " addr,#imm16", "r": " rel8"}
BYTES = {"": 1, "#": 2, "a": 3, "a,a": 5, "(P1)": 1, "(P2)": 1, "(P3)": 1,
         "(P1)+": 1, "(P2)+": 1, "(P3)+": 1,
         "#w": 3, "(P1+d)": 2, "(P2+d)": 2, "(P3+d)": 2,
         "a,(P1+d)": 4, "a,(P2+d)": 4, "a,(P3+d)": 4,
         "(P1+d),a": 4, "(P2+d),a": 4, "(P3+d),a": 4, "a,#": 4, "a,#w": 5, "r": 2}

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
    ("PHW", "a"): ("-", "Push 16-bit word at addr (hi then lo: lies little-endian at P3+1)."),
    ("PLW", "a"): ("-", "Pop 16-bit word into addr (lo then hi)."),
    ("LPW3", "a"): ("-", "P3 := 16-bit word at addr (restore a saved SP)."),
    ("ADDW", "a,#"): ("CZNV", "word a:=a+imm8 (zero-ext), 16-bit; C=carry out; Z of the FULL word. A!"),
    ("SUBW", "a,#"): ("CZNV", "word a:=a-imm8; C=1 no borrow; Z full word. A!"),
    ("CMPW", "a,#"): ("CZNV", "flags from a-imm8 (16-bit), memory unchanged; Z full word (a==imm). A!"),
    ("ADDW", "a,#w"): ("CZNV", "word a:=a+imm16; C=carry out; Z full word. A!"),
    ("SUBW", "a,#w"): ("CZNV", "word a:=a-imm16; C=1 no borrow; Z full word. A!"),
    ("CMPW", "a,#w"): ("CZNV", "flags from a-imm16, memory unchanged: C=a>=imm unsigned, Z=a==imm, BLT/BGE signed. A!"),
    ("ANDW", "a,a"): ("ZN", "word a:=a AND b; Z high byte only. A!"),
    ("ORW", "a,a"): ("ZN", "word a:=a OR b; Z high byte only. A!"),
    ("XORW", "a,a"): ("ZN", "word a:=a XOR b; Z high byte only. A!"),
    ("ANDW", "a,#"): ("ZN", "word a:=a AND imm8 (high byte cleared); Z full word: `ANDW x,#1 / JZ` tests a bit. A!"),
    ("ORW", "a,#"): ("ZN", "word a:=a OR imm8 (high byte kept); Z full word. A!"),
    ("XORW", "a,#"): ("ZN", "word a:=a XOR imm8 (high byte kept); Z full word. A!"),
    ("ANDW", "a,#w"): ("ZN", "word a:=a AND imm16; Z full word. A!"),
    ("ORW", "a,#w"): ("ZN", "word a:=a OR imm16; Z full word. A!"),
    ("XORW", "a,#w"): ("ZN", "word a:=a XOR imm16 (#$FFFF = bitwise NOT); Z full word. A!"),
    ("LEAW", "a,(P1+d)"): ("CZN", "word at addr:=P1+d (the address of a frame local). A!"),
    ("LEAW", "a,(P2+d)"): ("CZN", "word at addr:=P2+d. A!"),
    ("LEAW", "a,(P3+d)"): ("CZN", "word at addr:=P3+d (address of a stack local). A!"),
    # relative branches: 2 bytes; signed d8 from the next instruction; A and flags preserved
    ("JMP", "r"): ("-", "P0:=P0+rel8 (2-byte jump; A/flags kept; assembler .relax / JMP.R)."),
    ("BZ", "r"): ("-", "Branch rel8 if Z=1. (JZ.R alias.)"),
    ("BNZ", "r"): ("-", "Branch rel8 if Z=0. (JNZ.R alias.)"),
    ("BCP", "r"): ("-", "Branch rel8 if C=1. (JC.R alias.)"),
    ("JNC", "r"): ("-", "Branch rel8 if C=0."),
    ("BLT", "r"): ("-", "Branch rel8 if signed A<B (N^V)."),
    ("BGE", "r"): ("-", "Branch rel8 if signed A>=B."),
    ("BLE", "r"): ("-", "Branch rel8 if signed A<=B."),
    ("BGT", "r"): ("-", "Branch rel8 if signed A>B."),
    ("LPW1", "a"): ("-", "P1 := 16-bit word at addr."),
    ("LPW2", "a"): ("-", "P2 := 16-bit word at addr."),
    ("MOVW", "a,a"): ("-", "16-bit mem->mem: word at src -> dst."),
    # Tier A -- the C-compiler ISA (pure microcode). "A!" = clobbers A.
    ("LDP1", "#w"): ("-", "P1:=imm16 (3 bytes; was the LPL1/LPH1 pair)."),
    ("LDP2", "#w"): ("-", "P2:=imm16."),
    ("LDP3", "#w"): ("-", "P3:=imm16."),
    ("ADDP3", "#"): ("CZN", "P3:=P3+imm8 (free a frame). A!; flags from the low byte."),
    ("SUBP3", "#"): ("CZN", "P3:=P3-imm8 (allocate a frame). A!; flags from the low byte."),
    ("LDA", "(P1+d)"): ("CZN", "A:=byte at P1+d (d unsigned 0..255). C from the address add, Z/N from A."),
    ("LDA", "(P2+d)"): ("CZN", "A:=byte at P2+d."),
    ("LDA", "(P3+d)"): ("CZN", "A:=byte at P3+d (a stack local)."),
    ("STA", "(P1+d)"): ("CZN", "byte at P1+d:=A. A kept; flags clobbered by the address add."),
    ("STA", "(P2+d)"): ("CZN", "byte at P2+d:=A."),
    ("STA", "(P3+d)"): ("CZN", "byte at P3+d:=A (a stack local)."),
    ("LDW", "a,(P1+d)"): ("CZN", "word at addr:=word at P1+d. A!"),
    ("LDW", "a,(P2+d)"): ("CZN", "word at addr:=word at P2+d. A!"),
    ("LDW", "a,(P3+d)"): ("CZN", "word at addr:=word at P3+d (local -> memory word). A!"),
    ("STW", "(P1+d),a"): ("CZN", "word at P1+d:=word at addr. A!"),
    ("STW", "(P2+d),a"): ("CZN", "word at P2+d:=word at addr. A!"),
    ("STW", "(P3+d),a"): ("CZN", "word at P3+d:=word at addr (memory word -> local). A!"),
    ("LDW", "a,#"): ("-", "word at addr:=imm8 zero-extended (4 bytes)."),
    ("LDW", "a,#w"): ("-", "word at addr:=imm16 (5 bytes)."),
    ("ADDW", "a,a"): ("CZNV", "word a:=a+b, 16-bit; C=carry out. A!; Z from the high byte only."),
    ("SUBW", "a,a"): ("CZNV", "word a:=a-b, 16-bit; C=1 no borrow (a>=b unsigned). A!; Z high byte only."),
    ("CMPW", "a,a"): ("CZNV", "flags from a-b (16-bit), memory unchanged: C=unsigned a>=b, BLT/BGE = signed. A!"),
    ("INCW", "a"): ("CZN", "word at addr += 1. A!; flags from the low byte."),
    ("DECW", "a"): ("CZN", "word at addr -= 1. A!; flags from the low byte."),
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
    ("16-bit memory (rev D)", ["PHW", "PLW", "LPW1", "LPW2", "LPW3", "MOVW"]),
    ("Tier A: C-compiler ISA (2026-09, pure microcode; A! = clobbers A)",
     ["LDP1", "LDP2", "LDP3", "ADDP3", "SUBP3", "LDW", "STW", "LEAW",
      "ADDW", "SUBW", "CMPW", "ANDW", "ORW", "XORW", "INCW", "DECW"]),
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
    "<b>Memory (rev E):</b> $0000-1FFF ROM | $2000-FEFF RAM | $FF00-FFFF I/O. "
    "P0=PC, P3=stack (empty-descending). JZ/JNZ/JC are aliases of BZ/BNZ/BCP.",
    SUB)

two_col = Table([[tL, tR]], colWidths=[93 * mm, 93 * mm])
two_col.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"),
                             ("LEFTPADDING", (1, 0), (1, 0), 5)]))

story = [Paragraph("P8X Instruction Set -- Quick Reference (rev D)", H1),
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

# ---- the Markdown twin (ships on-target as /docs/ISACARD.MD) ----------------
# Same live OPC/U data, one table per group; the print-layout two-column
# split is a PDF concern and does not apply.
_md = []
_md.append("# P8X Instruction Set — Quick Reference (rev D)\n")
_md.append("Opcodes, mnemonics and cycle counts generated live from "
           "`genucode.py` (the microcode source of truth) — cannot drift from "
           "the hardware.\n")
_md.append("**Operands:** `#imm` immediate | `addr` 16-bit absolute | `(Pn)` "
           "ptr indirect | `(Pn)+` post-increment | (no operand) implied. "
           "**By**=bytes, **Cy**=cycles (incl. fetch). **Flags:** C carry "
           "(active-high: ADD carry-out / SUB,CMP no-borrow A>=B), Z zero, N "
           "negative (bit7), V overflow; `-` = none. Signed branches test "
           "N^V / Z. **Memory (rev E):** $0000-1FFF ROM | $2000-FEFF RAM | "
           "$FF00-FFFF I/O. P0=PC, P3=stack (empty-descending). JZ/JNZ/JC are "
           "aliases of BZ/BNZ/BCP.\n")
for _g, _mns in GROUPS:
    _md.append("## %s\n" % _g)
    _md.append("| Op | Mnemonic | By | Cy | Fl | Description |")
    _md.append("|---|---|---|---|---|---|")
    _ents = [(c, m, sh) for (m, sh), c in OPC.items() if m in _mns]
    for _c, _m, _sh in sorted(_ents):
        if (_m, _sh) not in DESC:
            continue
        _fl, _ds = DESC[(_m, _sh)]
        _md.append("| $%02X | `%s` | %d | %d | %s | %s |"
                   % (_c, _m + SHN[_sh], BYTES[_sh], 1 + len(U[_c]), _fl,
                      _ds.replace("|", "\\|")))
    _md.append("")
_mdp = os.path.join(_DOCS, "p8x-isa-card.md")
open(_mdp, "w").write("\n".join(_md) + "\n")
print("ISA card markdown written: %s" % _mdp)
