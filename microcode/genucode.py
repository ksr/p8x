#!/usr/bin/env python3
"""P8X microcode generator. Emits the four 28C64 images (u0-u3.bin) that are
BOTH burned to the control card EPROMs and interpreted by the C emulator.
Control word layout (matches control card pipeline mapping exactly):
  bits 0-3 DOE | 4-7 DLD | 8-9 PSEL | 10 PINC | 11 PDEC | 12-15 ALUS |
  16 ALUM | 17 CIN(pin, active-low carry) | 18 SH0 | 19 SH1 | 20 LDF |
  21-23 FCOND | 24 uRST | 25 HALT | 26-31 spare
ROM address: A0-7 = IR, A8-11 = step, A12 = condition mux output.
Step 0 of every opcode is the fetch cycle (MEM@P0 -> IR, P0+)."""
import struct

DOE=dict(idle=0,A=1,B=2,T=3,T2=4,ALU=5,FLAGS=6,MEM=7,PTRL=8,PTRH=9)
DLD=dict(none=0,A=1,B=2,T=3,T2=4,FLAGS=5,IR=6,MEMW=7,PTRL=8,PTRH=9)
FC=dict(never=0,always=1,C=2,Z=3,N=4,V=5)   # C = raw 74181 Cn+4 pin (1 = no carry!)

def w(doe=0,dld=0,psel=0,pinc=0,pdec=0,alus=0,m=0,cin=1,sh0=0,sh1=0,
      ldf=0,fcond=0,urst=0,halt=0):
    return (DOE[doe] if isinstance(doe,str) else doe) \
        | (DLD[dld] if isinstance(dld,str) else dld)<<4 \
        | psel<<8 | pinc<<10 | pdec<<11 | alus<<12 | m<<16 | cin<<17 \
        | sh0<<18 | sh1<<19 | ldf<<20 \
        | (FC[fcond] if isinstance(fcond,str) else fcond)<<21 | urst<<24 | halt<<25

FETCH=w(doe="MEM",dld="IR",psel=0,pinc=1)

# ALU helper: (S, M, CINpin). CIN pin is ACTIVE-LOW carry on the 74181.
ALU=dict(ADD=(0b1001,0,1), ADC1=(0b1001,0,0), SUB=(0b0110,0,0),
         AND=(0b1011,1,1), OR=(0b1110,1,1), XOR=(0b0110,1,1),
         PASSA=(0b1111,1,1), INC=(0b0000,0,0), DEC=(0b1111,0,1))
def alu(op,dld="A",ldf=1,**kw):
    s,m,c=ALU[op]; return w(doe="ALU",dld=dld,alus=s,m=m,cin=c,ldf=ldf,urst=1,**kw)

U={}     # opcode -> list of (cond0_word, cond1_word) per step (after fetch)
OPC={}   # (BASE_MNEMONIC, shape) -> opcode    -- shared with the assembler
def op(code,name,shape,*steps):
    U[code]=[(s,s) if not isinstance(s,tuple) else s for s in steps]
    OPC[(name,shape)]=code

NOP=w(urst=1)
op(0x00,"NOP","", NOP)
op(0x01,"HLT","", w(halt=1,urst=1))
op(0x10,"LDA","#", w(doe="MEM",dld="A",psel=0,pinc=1,urst=1))
op(0x11,"LDB","#", w(doe="MEM",dld="B",psel=0,pinc=1,urst=1))
for p in (1,2,3):
    op(0x14+p,"LDA","(P%d)+"%p, w(doe="MEM",dld="A",psel=p,pinc=1,urst=1))
    op(0x18+p,"STA","(P%d)+"%p, w(doe="A",dld="MEMW",psel=p,pinc=1,urst=1))
    op(0x1C+p,"STA","(P%d)"%p,  w(doe="A",dld="MEMW",psel=p,urst=1))
# ALU ops: result -> A, flags latched
op(0x20,"ADD","", alu("ADD")); op(0x21,"SUB","", alu("SUB"))
op(0x22,"AND","", alu("AND")); op(0x23,"OR","",  alu("OR"))
op(0x24,"XOR","", alu("XOR")); op(0x25,"CMP","", alu("SUB",dld="none"))
op(0x26,"INC","", alu("INC")); op(0x27,"DEC","", alu("DEC"))
op(0x28,"SHL","", w(doe="ALU",dld="A",alus=0b1111,m=1,cin=0,sh0=1,ldf=1,urst=1))
op(0x29,"SHR","", w(doe="ALU",dld="A",alus=0b1111,m=1,cin=0,sh1=1,ldf=1,urst=1))
# pointer byte loads: LPLn #imm / LPHn #imm  (via T: mem read uses P0)
for p in (1,2,3):
    op(0x30+p,"LPL%d"%p,"#", w(doe="MEM",dld="T",psel=0,pinc=1),
               w(doe="T",dld="PTRL",psel=p,urst=1))
    op(0x34+p,"LPH%d"%p,"#", w(doe="MEM",dld="T",psel=0,pinc=1),
               w(doe="T",dld="PTRH",psel=p,urst=1))
# JMP abs: operand lo,hi -> T,T2 -> P0
op(0x40,"JMP","a", w(doe="MEM",dld="T",psel=0,pinc=1),
         w(doe="MEM",dld="T2",psel=0,pinc=1),
         w(doe="T",dld="PTRL",psel=0),
         w(doe="T2",dld="PTRH",psel=0,urst=1))
# JSR (P1): push PC (H then L, write-then-dec) onto P3, then P1 -> P0 via T
op(0x41,"JSR","(P1)", w(doe="PTRH",dld="T",psel=0),
         w(doe="T",dld="MEMW",psel=3,pdec=1),
         w(doe="PTRL",dld="T",psel=0),
         w(doe="T",dld="MEMW",psel=3,pdec=1),
         w(doe="PTRL",dld="T",psel=1),
         w(doe="T",dld="PTRL",psel=0),
         w(doe="PTRH",dld="T",psel=1),
         w(doe="T",dld="PTRH",psel=0,urst=1))
# RTS: inc-then-read L,H from P3 -> P0
op(0x42,"RTS","", w(psel=3,pinc=1),
         w(doe="MEM",dld="T",psel=3),
         w(psel=3,pinc=1),
         w(doe="MEM",dld="T2",psel=3),
         w(doe="T",dld="PTRL",psel=0),
         w(doe="T2",dld="PTRH",psel=0,urst=1))
# conditional branches abs: Bcc addr. FCOND emitted while fetching operand;
# cond plane 1 = take (load P0 from T/T2), plane 0 = fall through.
def branch(code,name,flag):
    op(code,name,"a", w(doe="MEM",dld="T",psel=0,pinc=1),
             w(doe="MEM",dld="T2",psel=0,pinc=1,fcond=flag),
             ( w(urst=1,fcond=flag),                 # not taken
               w(doe="T",dld="PTRL",psel=0,fcond=flag) ),
             ( NOP, w(doe="T2",dld="PTRH",psel=0,urst=1) ))
branch(0x48,"BZ","Z")
branch(0x4A,"BCP","C")  # branch if Cn+4 PIN set (pin high = NO carry!)
op(0x49,"BNZ","a", w(doe="MEM",dld="T",psel=0,pinc=1),   # invert by plane swap
         w(doe="MEM",dld="T2",psel=0,pinc=1,fcond="Z"),
         ( w(doe="T",dld="PTRL",psel=0,fcond="Z"), w(urst=1,fcond="Z") ),
         ( w(doe="T2",dld="PTRH",psel=0,urst=1), NOP ))

# ---- assemble images ----------------------------------------------------------
def build_images(outdir="."):
    roms=[bytearray(8192) for _ in range(4)]
    def put(addr,word):
        for k in range(4): roms[k][addr]=(word>>(8*k))&0xFF
    for ir in range(256):
        for cond in (0,1):
            put(ir | 0 | cond<<12, FETCH)            # step 0 = fetch, both planes
            steps=U.get(ir,[ (w(urst=1),w(urst=1)) ])  # undefined op = NOP
            for s,(w0,w1) in enumerate(steps,start=1):
                put(ir | s<<8 | 0<<12, w0)
                put(ir | s<<8 | 1<<12, w1)
            for s in range(len(steps)+1,16):       # safety: rail to fetch
                put(ir | s<<8, w(urst=1)); put(ir | s<<8 | 1<<12, w(urst=1))
    import os
    for k in range(4):
        open(os.path.join(outdir,"u%d.bin"%k),"wb").write(roms[k])
    print("u0-u3.bin written:",", ".join("%d bytes"%len(r) for r in roms))
    print("defined opcodes:",len(U))

if __name__=="__main__":
    build_images()
