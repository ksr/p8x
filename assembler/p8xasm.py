#!/usr/bin/env python3
"""P8X two-pass assembler. Mnemonics/encodings come from genucode.OPC --
the same table that generates the microcode ROMs (single source of truth).

Syntax:  label:  MNEMONIC operand   ; comment
  operands:  #expr (imm8) | (Pn) | (Pn)+ | expr (abs16) | none
  exprs:     $1F 0x1F 31 'c' label  with + -  and <expr (lo) >expr (hi)
  directives: .org e | .byte e,... | .word e,... | .ascii "s" | .asciiz "s"
              .fill n[,v] | NAME = expr  (or .equ NAME, expr)
  pseudo:    LDPn #expr16  ->  LPLn #<expr, LPHn #>expr
Output: 32K eeprom image + listing."""
import sys, re, os
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
from genucode import OPC

SIZE={"":1,"#":2,"a":3}

def err(ln,line,msg):
    sys.exit("p8xasm: line %d: %s\n  %s"%(ln,msg,line))

def tokenize(text):
    out=[]
    for ln,raw in enumerate(text.splitlines(),1):
        line=raw.split(";")[0].rstrip()
        if not line.strip(): continue
        out.append((ln,raw.rstrip(),line))
    return out

def parse_operand(opnd):
    """-> (shape, exprtext or None)"""
    opnd=opnd.strip()
    if not opnd: return "",None
    m=re.fullmatch(r"\(\s*P([123])\s*\)(\+?)",opnd,re.I)
    if m: return "(P%s)%s"%(m.group(1),m.group(2)),None
    if opnd.startswith("#"): return "#",opnd[1:].strip()
    return "a",opnd

class Asm:
    def __init__(self):
        self.sym={}; self.img=bytearray(0x8000); self.lst=[]
    def expr(self,e,ln,line,pass2):
        e=e.strip()
        if e.startswith("<"): return self.expr(e[1:],ln,line,pass2)&0xFF
        if e.startswith(">"): return (self.expr(e[1:],ln,line,pass2)>>8)&0xFF
        tot,sign=0,1
        for tok in re.findall(r"'.'|[+-]|[^+\-\s]+",e):   # 'c' first: char literals may hold space/+/-
            if tok=="+": sign=1; continue
            if tok=="-": sign=-1; continue
            if re.fullmatch(r"\$[0-9A-Fa-f]+",tok): v=int(tok[1:],16)
            elif re.fullmatch(r"0[xX][0-9A-Fa-f]+",tok): v=int(tok,16)
            elif tok.isdigit(): v=int(tok)
            elif len(tok)==3 and tok[0]=="'" and tok[2]=="'": v=ord(tok[1])
            elif tok in self.sym: v=self.sym[tok]
            elif not pass2: v=0
            else: err(ln,line,"undefined symbol '%s'"%tok)
            tot+=sign*v; sign=1
        return tot&0xFFFF
    def run(self,lines,pass2):
        pc=0
        for ln,raw,line in lines:
            emitted=[]
            m=re.match(r"^\s*(\w+)\s*:\s*(.*)$",line)
            if m:
                if not pass2:
                    if m.group(1) in self.sym: err(ln,line,"duplicate label")
                    self.sym[m.group(1)]=pc
                line=m.group(2)
            if not line.strip():
                if pass2: self.lst.append((pc,[],raw)); continue
                continue
            m=re.match(r"^\s*(\w+)\s*=\s*(.+)$",line)
            if m:
                self.sym[m.group(1)]=self.expr(m.group(2),ln,line,pass2)
                if pass2: self.lst.append((pc,[],raw))
                continue
            parts=line.split(None,1)
            mn=parts[0].upper(); opnd=parts[1] if len(parts)>1 else ""
            def emit(*bs):
                nonlocal pc
                for b in bs:
                    if pass2:
                        if pc>=0x8000: err(ln,line,"address past EEPROM")
                        self.img[pc]=b&0xFF; emitted.append(b&0xFF)
                    pc+=1
            if mn==".ORG":
                pc=self.expr(opnd,ln,line,pass2)
            elif mn==".EQU":
                nm,e=opnd.split(",",1); self.sym[nm.strip()]=self.expr(e,ln,line,pass2)
            elif mn==".BYTE":
                for e in opnd.split(","): emit(self.expr(e,ln,line,pass2))
            elif mn==".WORD":
                for e in opnd.split(","):
                    v=self.expr(e,ln,line,pass2); emit(v&0xFF,v>>8)
            elif mn in (".ASCII",".ASCIIZ"):
                m2=re.fullmatch(r'\s*"(.*)"\s*',opnd)
                if not m2: err(ln,line,"expected quoted string")
                s=m2.group(1).encode().decode("unicode_escape")
                emit(*[ord(c) for c in s])
                if mn==".ASCIIZ": emit(0)
            elif mn==".FILL":
                es=opnd.split(","); n=self.expr(es[0],ln,line,pass2)
                v=self.expr(es[1],ln,line,pass2) if len(es)>1 else 0
                emit(*([v]*n))
            elif re.fullmatch(r"LDP[123]",mn):           # pseudo: 16-bit ptr load
                shape,etext=parse_operand(opnd)
                if shape!="#": err(ln,line,"LDPn needs #imm16")
                p=mn[-1]; v=self.expr(etext,ln,line,pass2)
                emit(OPC[("LPL%s"%p,"#")],v&0xFF)
                emit(OPC[("LPH%s"%p,"#")],v>>8)
            else:
                shape,etext=parse_operand(opnd)
                key=(mn,shape)
                if key not in OPC:
                    err(ln,line,"unknown instruction '%s %s'"%(mn,opnd))
                emit(OPC[key])
                if shape=="#": emit(self.expr(etext,ln,line,pass2))
                elif shape=="a":
                    v=self.expr(etext,ln,line,pass2); emit(v&0xFF,v>>8)
            if pass2: self.lst.append((pc-len(emitted),emitted,raw))
def main():
    a=sys.argv[1:]
    src=a[0]; out="eeprom.bin"; lstf=None
    if "-o" in a: out=a[a.index("-o")+1]
    if "-l" in a: lstf=a[a.index("-l")+1]
    lines=tokenize(open(src).read())
    A=Asm(); A.run(lines,False); A.run(lines,True)
    open(out,"wb").write(A.img)
    if lstf:
        with open(lstf,"w") as f:
            for pc,bs,raw in A.lst:
                f.write("%04X  %-12s %s\n"%(pc," ".join("%02X"%b for b in bs),raw))
    print("%s: %d symbols -> %s (32K)"%(src,len(A.sym),out))
if __name__=="__main__": main()
