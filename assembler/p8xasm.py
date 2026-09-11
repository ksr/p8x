#!/usr/bin/env python3
"""P8X two-pass assembler. Mnemonics/encodings come from genucode.OPC --
the same table that generates the microcode ROMs (single source of truth).

Syntax:  label:  MNEMONIC operand[,operand]   ; comment
  operands:  #expr (imm8, or imm16 where the opcode takes one: LDPn #, LDW a,#)
             | (Pn) | (Pn)+ | (Pn+d) (d = unsigned 0..255) | expr (abs16) | none
             two-operand forms: MOVW dst,src  ADDW/SUBW/CMPW a,b  LDW a,(Pn+d)
             STW (Pn+d),a  LDW a,#imm
  exprs:     $1F 0x1F 31 'c' label  with + -  and <expr (lo) >expr (hi)
  directives: .org e | .byte e,... | .word e,... | .ascii "s" | .asciiz "s"
              .fill n[,v] | NAME = expr  (or .equ NAME, expr)
  immediates: where an opcode exists in BOTH an imm8 and an imm16 form (LDW a,#)
             the width is chosen from the operand's TEXT -- a literal that fits a
             byte ($xx, 0xXX, 0..255, 'c', <e, >e) is imm8, anything else (a
             label, a wider literal, an expression) is imm16 -- so pass 1 and
             pass 2 always agree on the instruction size.

Usage: p8xasm.py src.asm [-o out] [-l listing] [--base ADDR] [-D NAME=VAL ...]
  default    -> 8K ROM image from $0000 (cap $2000)
  --base A   -> RAM-resident blob: labels resolve to the run address A and only
                the bytes A..high are written (e.g. an OS/program loaded to $2000)
  -D N=V     -> define+lock symbol N (decimal / 0x.. / $..); overrides a source
                `N = default`, so one source builds at several orgs/data bases.
Output: with --base, the A..high blob; otherwise the 8K ROM image (+listing)."""
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

# Operand components and the bytes each one contributes after the opcode.
# "#w" is a 16-bit immediate (lo,hi); "(Pn+d)" is the unsigned 8-bit displacement.
COMP_BYTES={"":0,"#":1,"#w":2,"a":2,"(P1+d)":1,"(P2+d)":1,"(P3+d)":1,
            "(P1)":0,"(P2)":0,"(P3)":0,"(P1)+":0,"(P2)+":0,"(P3)+":0}

def err(ln,line,msg):
    sys.exit("p8xasm: line %d: %s\n  %s"%(ln,msg,line))

def tokenize(text):
    out=[]
    for ln,raw in enumerate(text.splitlines(),1):
        line=raw.split(";")[0].rstrip()
        if not line.strip(): continue
        out.append((ln,raw.rstrip(),line))
    return out

def expand_includes(path,_stack=None):
    """Return the text of `path` with every `.include "file"` line replaced by the
    (recursively expanded) contents of that file, resolved relative to the
    including file's directory. Lets sources share a committed equates file
    (e.g. a generated memmap.inc). Cycles are an error."""
    _stack=_stack or []
    ap=os.path.abspath(path)
    if ap in _stack:
        sys.exit("p8xasm: .include cycle: %s"%" -> ".join(_stack+[ap]))
    try:
        text=open(path).read()
    except OSError as e:
        sys.exit("p8xasm: cannot open %r: %s"%(path,e))
    out=[]
    for raw in text.splitlines():
        code=raw.split(";")[0].strip()
        m=re.match(r'\.include\s+"([^"]+)"\s*$',code) or re.match(r"\.include\s+'([^']+)'\s*$",code)
        if m:
            inc=os.path.join(os.path.dirname(ap),m.group(1))
            out.append(expand_includes(inc,_stack+[ap]))
        else:
            out.append(raw)
    return "\n".join(out)

def split_top(s):
    """Split an operand field on commas that are outside parentheses and outside
    a 'c' character literal (so `LDA #','` and `(P1+2),x` both survive)."""
    parts=[]; cur=""; depth=0; i=0
    while i<len(s):
        c=s[i]
        if c=="'" and i+2<len(s) and s[i+2]=="'":       # 'c' literal, any c
            cur+=s[i:i+3]; i+=3; continue
        if c=="(": depth+=1
        elif c==")": depth-=1
        if c=="," and depth==0: parts.append(cur); cur=""
        else: cur+=c
        i+=1
    parts.append(cur)
    return parts

def parse_one(opnd):
    """one operand -> (component shape, exprtext or None)"""
    opnd=opnd.strip()
    m=re.fullmatch(r"\(\s*P([123])\s*\)(\+?)",opnd,re.I)
    if m: return "(P%s)%s"%(m.group(1),m.group(2)),None
    m=re.fullmatch(r"\(\s*P([123])\s*\+\s*(.+?)\s*\)",opnd,re.I)   # (Pn+d)
    if m: return "(P%s+d)"%m.group(1),m.group(2)
    if opnd.startswith("#"): return "#",opnd[1:].strip()
    return "a",opnd

def parse_operand(opnd):
    """-> (shape, [(component, exprtext)]) -- a two-operand form joins its
    component shapes with ',' in TEXTUAL order, e.g. 'STW (P3+d),a'."""
    opnd=opnd.strip()
    if not opnd: return "",[]
    comps=[parse_one(p) for p in split_top(opnd)]
    return ",".join(c for c,_ in comps),comps

def lit8(text):
    """True when an immediate's TEXT is a byte-sized literal: $xx, 0xXX, 0..255,
    'c', or a <lo / >hi byte selector. Decides imm8 vs imm16 for opcodes that
    have both forms; it depends only on the text so both passes agree."""
    t=text.strip()
    if t.startswith("<") or t.startswith(">"): return True
    if re.fullmatch(r"\$[0-9A-Fa-f]{1,2}",t): return True
    if re.fullmatch(r"0[xX][0-9A-Fa-f]{1,2}",t): return True
    if t.isdigit(): return int(t)<=255
    if len(t)==3 and t[0]=="'" and t[2]=="'": return True
    return False

def resolve_shape(mn,shape,comps):
    """Pick the OPC key for (mnemonic, textual shape). A '#' component may stand
    for an imm16 ('#w') when only that form exists (LDPn #), or when both exist
    and the text is not a byte literal (LDW a,#)."""
    if (mn,shape) in OPC and not any(c=="#" for c,_ in comps): return shape
    narrow=shape; wide=",".join("#w" if c=="#" else c for c in shape.split(","))
    have=[s for s in (narrow,wide) if (mn,s) in OPC]
    if not have: return None
    if len(have)==1: return have[0]
    imm=[e for c,e in comps if c=="#"][0]
    return narrow if lit8(imm) else wide

class Asm:
    def __init__(self,base=0,cap=0x2000,defines=None):
        # img spans the full 64K; `base` is where the output blob starts and
        # `cap` is the highest legal address+1 (0x2000 for the 8K ROM, 0x10000 for a
        # RAM-resident image assembled with --base). hi tracks the high-water
        # mark so a RAM image emits only its own bytes.
        self.sym={}; self.img=bytearray(0x10000); self.lst=[]
        self.base=base; self.cap=cap; self.hi=base
        # -D NAME=VALUE defines: pre-seed and lock so a source `NAME = ...`
        # default is overridden (the source keeps its own default when no -D).
        self.locked=set()
        for nm,val in (defines or {}).items():
            self.sym[nm]=val; self.locked.add(nm)
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
                if m.group(1) not in self.locked:        # -D defines win
                    self.sym[m.group(1)]=self.expr(m.group(2),ln,line,pass2)
                if pass2: self.lst.append((pc,[],raw))
                continue
            parts=line.split(None,1)
            mn=parts[0].upper(); opnd=parts[1] if len(parts)>1 else ""
            def emit(*bs):
                nonlocal pc
                for b in bs:
                    if pass2:
                        if pc>=self.cap:
                            err(ln,line,"address past %s"%
                                ("8K ROM" if self.cap==0x2000 else "64K"))
                        if pc<self.base: err(ln,line,"address below --base")
                        self.img[pc]=b&0xFF; emitted.append(b&0xFF)
                        if pc+1>self.hi: self.hi=pc+1
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
            else:
                shape,comps=parse_operand(opnd)
                key=resolve_shape(mn,shape,comps)
                if key is None:
                    err(ln,line,"unknown instruction '%s %s'"%(mn,opnd))
                emit(OPC[(mn,key)])
                # Byte-stream order: every 16-bit ADDRESS component first (in
                # textual order), then the immediate / displacement bytes. This
                # is what lets `LDW a,(Pn+d)` and `STW (Pn+d),a` share one
                # microcode skeleton (op a.lo a.hi d8) and keeps MOVW dst,src.
                rcomps=[(c,e) for c,e in zip(key.split(","),[e for _,e in comps])]
                for c,e in sorted(rcomps,key=lambda ce: 0 if ce[0]=="a" else 1):
                    n=COMP_BYTES[c]
                    if n==0: continue
                    v=self.expr(e,ln,line,pass2)
                    if n==1:
                        if pass2 and c.startswith("(P") and not 0<=v<=255:
                            err(ln,line,"displacement %d out of range 0..255"%v)
                        emit(v&0xFF)
                    else: emit(v&0xFF,(v>>8)&0xFF)
            if pass2: self.lst.append((pc-len(emitted),emitted,raw))
def main():
    a=sys.argv[1:]
    src=a[0]; out="eeprom.bin"; lstf=None; base=None; defs={}
    if "-o" in a: out=a[a.index("-o")+1]
    if "-l" in a: lstf=a[a.index("-l")+1]
    if "--base" in a: base=int(a[a.index("--base")+1],0)
    # -D NAME=VALUE (repeatable): override a source default symbol. VALUE may be
    # decimal, 0x.. or $.. hex.
    for i,t in enumerate(a):
        if t=="-D":
            nm,_,val=a[i+1].partition("=")
            val=val.strip()
            defs[nm.strip()]=int(val[1:],16) if val.startswith("$") else int(val,0)
    lines=tokenize(expand_includes(src))
    # --base: RAM-resident blob (e.g. an OS loaded to $2000); emit only the
    # bytes from base..hi. No --base: 8K ROM image from $0000.
    if base is not None:
        A=Asm(base=base,cap=0x10000,defines=defs); A.run(lines,False); A.run(lines,True)
        open(out,"wb").write(A.img[base:A.hi])
        size="%d bytes @ $%04X"%(A.hi-base,base)
    else:
        A=Asm(defines=defs); A.run(lines,False); A.run(lines,True)
        open(out,"wb").write(A.img[:0x2000])
        size="8K"
    if lstf:
        with open(lstf,"w") as f:
            for pc,bs,raw in A.lst:
                f.write("%04X  %-12s %s\n"%(pc," ".join("%02X"%b for b in bs),raw))
    print("%s: %d symbols -> %s (%s)"%(src,len(A.sym),out,size))
if __name__=="__main__": main()
