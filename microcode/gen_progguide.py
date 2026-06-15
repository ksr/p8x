#!/usr/bin/env python3
"""P8X Programmer's Guide PDF. Opcode numbers, byte counts and cycle counts
are pulled live from genucode.py (the microcode source of truth); only the
prose is authored here."""
import sys, os
import sys, os
def _find_genucode():
    """Locate the microcode directory regardless of repo layout."""
    here=os.path.dirname(os.path.abspath(__file__))
    cands=[here,
           os.path.join(here,"microcode"),
           os.path.join(here,"..","microcode"),
           os.path.join(here,"..","..","microcode"),
           os.path.join(here,"..","firmware","microcode"),
           os.path.join(os.getcwd(),"microcode"),
           os.getcwd()]
    for d in cands:
        if os.path.isfile(os.path.join(d,"genucode.py")):
            sys.path.insert(0,os.path.abspath(d)); return os.path.abspath(d)
    sys.exit("cannot find genucode.py (looked in: %s)"%", ".join(cands))
UCODE_DIR=_find_genucode()
from genucode import OPC, U
from reportlab.lib.pagesizes import A4
from reportlab.lib import colors
from reportlab.lib.units import mm
from reportlab.platypus import (SimpleDocTemplate, Table, TableStyle, Paragraph,
                                Spacer, PageBreak, Preformatted)
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle

S=getSampleStyleSheet()
H1=ParagraphStyle("h1",parent=S["Heading1"],fontSize=16,spaceAfter=4)
H2=ParagraphStyle("h2",parent=S["Heading2"],fontSize=12,spaceBefore=10,spaceAfter=3)
B=ParagraphStyle("b",parent=S["BodyText"],fontSize=8.6,leading=11.5)
MONO=ParagraphStyle("m",parent=B,fontName="Courier",fontSize=8)
NOTE=ParagraphStyle("n",parent=B,backColor=colors.Color(1,0.97,0.88),
                    borderPadding=4,leftIndent=2)

SHN={"":"","#":" #imm","a":" addr","(P1)":" (P1)","(P2)":" (P2)","(P3)":" (P3)",
     "(P1)+":" (P1)+","(P2)+":" (P2)+","(P3)+":" (P3)+"}
BYTES={"":1,"#":2,"a":3,"(P1)":1,"(P2)":1,"(P3)":1,"(P1)+":1,"(P2)+":1,"(P3)+":1}
DESC={
 ("NOP",""):("-","No operation."),
 ("HLT",""):("-","Halt the clock. Resume only by reset (or emulator exit)."),
 ("LDA","#"):("-","A := immediate byte."),
 ("LDB","#"):("-","B := immediate byte."),
 ("ADD",""):("C Z N","A := A + B."),
 ("SUB",""):("C Z N","A := A - B."),
 ("AND",""):("C Z N","A := A AND B."),
 ("OR",""):("C Z N","A := A OR B."),
 ("XOR",""):("C Z N","A := A XOR B."),
 ("CMP",""):("C Z N","Flags from A - B; A unchanged."),
 ("INC",""):("C Z N","A := A + 1. (B not used.)"),
 ("DEC",""):("C Z N","A := A - 1. (B not used.)"),
 ("SHL",""):("C Z N","A := A << 1, 0 into bit 0. (1)"),
 ("SHR",""):("C Z N","A := A >> 1, 0 into bit 7. (1)"),
 ("JMP","a"):("-","P0 (PC) := addr."),
 ("JSR","(P1)"):("-","Push return address (high byte first) onto P3 stack, "
                 "then P0 := P1. Target must already be in P1."),
 ("RTS",""):("-","Pop return address from P3 stack into P0."),
 ("BZ","a"):("-","Branch to addr if Z=1."),
 ("BNZ","a"):("-","Branch to addr if Z=0."),
 ("BCP","a"):("-","Branch if C=1, i.e. the RAW 74181 Cn+4 pin is high. "
              "Pin high means NO carry out - see note (2)."),
}
for p in (1,2,3):
    DESC[("LDA","(P%d)+"%p)]=("-","A := memory at P%d, then P%d := P%d + 1."%(p,p,p))
    DESC[("STA","(P%d)+"%p)]=("-","Memory at P%d := A, then P%d := P%d + 1."%(p,p,p))
    DESC[("STA","(P%d)"%p)]=("-","Memory at P%d := A."%p)
    DESC[("LPL%d"%p,"#")]=("-","Low byte of P%d := immediate."%p)
    DESC[("LPH%d"%p,"#")]=("-","High byte of P%d := immediate."%p)

GROUPS=[("System",["NOP","HLT"]),
 ("Load / store",["LDA","LDB","STA"]),
 ("ALU  (operands A,B; result to A unless noted)",
  ["ADD","SUB","AND","OR","XOR","CMP","INC","DEC","SHL","SHR"]),
 ("Pointer registers",["LPL1","LPH1","LPL2","LPH2","LPL3","LPH3"]),
 ("Control flow",["JMP","JSR","RTS","BZ","BNZ","BCP"])]

doc=SimpleDocTemplate("/mnt/user-data/outputs/p8x-programmers-guide.pdf",
    pagesize=A4,leftMargin=14*mm,rightMargin=14*mm,topMargin=13*mm,bottomMargin=13*mm)
E=[]
E.append(Paragraph("P8X Programmer's Guide",H1))
E.append(Paragraph("Instruction set rev 1 - generated from the microcode source "
 "(genucode.py); opcode values, byte and cycle counts are extracted from the same "
 "tables that build the EPROM images, so this document cannot drift from the hardware.",B))

E.append(Paragraph("Programming model",H2))
E.append(Paragraph(
 "<b>A, B</b> - 8-bit ALU operand registers; results land in A. "
 "<b>P0-P3</b> - four 16-bit pointer registers; the address bus is always driven by "
 "one of them. <b>P0</b> is the program counter. <b>P3</b> is the stack pointer "
 "(empty-descending: push writes then decrements; initialise it early - see note 3). "
 "P1 and P2 are general pointers used by the (Pn) addressing modes. "
 "<b>FLAGS</b> - C, Z, N, V, latched only by instructions marked in the Flags column.",B))
E.append(Paragraph(
 "<b>Memory map:</b> $0000-$7FFF EEPROM &nbsp;|&nbsp; $8000-$FEFF RAM &nbsp;|&nbsp; "
 "$FF00-$FFFF I/O: $FF00 switches (r), $FF02 LEDs (w), $FF04 ACIA status "
 "(bit0 RX ready, bit1 TX ready), $FF05 ACIA data.",B))
E.append(Paragraph(
 "<b>Reset:</b> P0 is forced to $0000; execution begins there. All other registers "
 "(including P3) are undefined on real hardware.",B))

E.append(Paragraph("Instruction set",H2))
rows=[["Op","Mnemonic","Bytes","Cycles","Flags","Description"]]
spans=[]; styles=[]
r=1
for gname,mns in GROUPS:
    rows.append([gname,"","","","",""]); spans.append(r)
    r+=1
    entries=[(code,mn,sh) for (mn,sh),code in OPC.items() if mn in mns]
    for code,mn,sh in sorted(entries):
        fl,ds=DESC[(mn,sh)]
        cyc=1+len(U[code])
        rows.append(["$%02X"%code, mn+SHN[sh], str(BYTES[sh]), str(cyc), fl,
                     Paragraph(ds,B)])
        r+=1
rows.append(["-","LDPn #imm16","4","6","-",
             Paragraph("Assembler pseudo-op: LPLn + LPHn pair. P<i>n</i> := imm16.",B)])
t=Table(rows,colWidths=[11*mm,26*mm,12*mm,13*mm,14*mm,100*mm],repeatRows=1)
st=[("FONT",(0,0),(-1,-1),"Helvetica",8),
    ("FONT",(0,0),(-1,0),"Helvetica-Bold",8.5),
    ("FONT",(0,1),(1,-1),"Courier",8),
    ("BACKGROUND",(0,0),(-1,0),colors.Color(0.15,0.25,0.45)),
    ("TEXTCOLOR",(0,0),(-1,0),colors.white),
    ("GRID",(0,0),(-1,-1),0.4,colors.Color(0.75,0.75,0.75)),
    ("VALIGN",(0,0),(-1,-1),"MIDDLE"),
    ("ROWBACKGROUNDS",(0,1),(-1,-1),[colors.white,colors.Color(0.96,0.97,1)])]
for sr in spans:
    st+=[("SPAN",(0,sr),(-1,sr)),
         ("BACKGROUND",(0,sr),(-1,sr),colors.Color(0.85,0.89,0.96)),
         ("FONT",(0,sr),(-1,sr),"Helvetica-Bold",8.5)]
t.setStyle(TableStyle(st))
E.append(t)

E.append(Paragraph("Notes",H2))
E.append(Paragraph(
 "<b>(1) Shifts:</b> the shift-in bit is wired to the microcode CIN line and is 0 for "
 "SHL/SHR. The C flag latches the 74181 carry chain, not the shifted-out bit, in rev A.",NOTE))
E.append(Spacer(1,3))
E.append(Paragraph(
 "<b>(2) C flag polarity:</b> the flag register latches the RAW 74181 Cn+4 pin, which "
 "is an ACTIVE-LOW carry: after ADD, C=0 means a carry occurred; after SUB/CMP, C=0 "
 "means no borrow (A &gt;= B). BCP branches on the pin being HIGH. This matches the "
 "rev A ALU card exactly; a rev B inverter (or embracing the convention) is an open "
 "BACKLOG item. The emulator reproduces it faithfully.",NOTE))
E.append(Spacer(1,3))
E.append(Paragraph(
 "<b>(3) Stack:</b> JSR pushes the return address high byte then low byte, "
 "decrementing after each write (empty-descending). RTS increments then reads. "
 "Software must initialise P3 (e.g. LDP3 #$FEFF) before the first JSR. "
 "<b>(4) V flag:</b> reads 0 in rev A. <b>(5) JSR addressing:</b> only (P1) - load the "
 "target into P1 first; an absolute-JSR opcode is a natural future addition.",NOTE))

E.append(Paragraph("Assembler quick reference (p8xasm.py)",H2))
E.append(Preformatted(
"""label:  MNEMONIC operand        ; comment
operands:   #expr (immediate)  |  (Pn) / (Pn)+  |  expr (16-bit address)
exprs:      $1F  0x1F  31  'c'  symbol   with +/-,  <expr = low byte, >expr = high
directives: .org e   .byte e,...   .word e,...   .ascii "s"   .asciiz "s"
            .fill n[,v]    NAME = expr    .equ NAME, expr
pseudo-op:  LDPn #imm16              ; expands to LPLn #<imm, LPHn #>imm
usage:      python3 p8xasm.py prog.asm -o eeprom.bin [-l prog.lst]""",MONO))

E.append(Paragraph("Example: print a string",H2))
E.append(Preformatted(
"""ACIA_D = $FF05
        .org 0
        LDP2 #ACIA_D        ; P2 -> ACIA data register
        LDP1 #msg           ; P1 -> string
        LDB  #0
loop:   LDA  (P1)+          ; fetch byte, advance
        OR                  ; A := A|0 - sets Z on the terminator
        BZ   done
        STA  (P2)           ; transmit
        JMP  loop
done:   HLT
msg:    .asciiz "P8X lives!\\r\\n" """,MONO))
doc.build(E)
print("guide written")
