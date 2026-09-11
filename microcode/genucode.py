#!/usr/bin/env python3
"""P8X microcode generator. Emits the four 28C64 images (u0-u3.bin) that are
BOTH burned to the control card EPROMs and interpreted by the C emulator.
Control word layout (matches control card pipeline mapping exactly):
  bits 0-3 DOE | 4-7 DLD | 8-10 PSEL (P0-P3 + PT scratch=4) | 11 PINC |
  12 PDEC | 13-16 ALUS | 17 ALUM | 18 CIN(pin, active-low carry) |
  19 SH0 | 20 SH1 | 21 LDF | 22-24 FCOND | 25 uRST | 26 HALT |
  27 LDZN (latch Z,N only) | 28 SHCIN (shifter shift-in = C flag, for rotates) |
  29 SETC (force C=1) | 30 CLRC (force C=0) |
  31 BSEL (ALU B-input mux: 0=B register, 1=T register)
PSEL is 3 bits (rev: was 2). PT (=4) is a hidden microcode-only scratch pointer
used for absolute addressing; PT2 (=5, rev D) is a second scratch pointer, the
write cursor for MOVW (16-bit mem→mem). Neither is programmer-visible.
LDZN gives loads conventional set-Z/N-from-loaded-value behaviour without
touching C/V (LDF latches all four flags from the ALU; LDZN only Z and N).
CARRY (rev B): the C flag is CONVENTIONAL active-high — C=1 means carry-out
(ADD) / no-borrow i.e. A>=B (SUB/CMP). Shift ops latch the shifted-out bit into
C; with SHCIN the shifted-in bit is the current C (rotate through carry).
SETC/CLRC force C only, leaving Z/N/V untouched (for SEC/CLC).
ROM address: A0-7 = IR, A8-11 = step, A12 = condition mux output.
Step 0 of every opcode is the fetch cycle (MEM@P0 -> IR, P0+)."""
import struct

DOE=dict(idle=0,A=1,B=2,T=3,T2=4,ALU=5,FLAGS=6,MEM=7,PTRL=8,PTRH=9)
DLD=dict(none=0,A=1,B=2,T=3,T2=4,FLAGS=5,IR=6,MEMW=7,PTRL=8,PTRH=9)
FC=dict(never=0,always=1,C=2,Z=3,N=4,V=5,LT=6,LE=7)
#   C = conventional carry (rev B): 1 = carry / A>=B (unsigned ordering)
#   LT = N^V (signed A<B), LE = (N^V)|Z (signed A<=B) — rev C signed compares.
#   The condition mux gets N^V on input 6 and (N^V)|Z on input 7 (control card).
PT=4   # hidden microcode-only scratch pointer (PSEL=4), for absolute addressing
PT2=5  # 2nd hidden scratch pointer (PSEL=5) — the write cursor for MOVW. Both PT
       # and PT2 are up-counters in hardware (74169s): PHW/PLW/LPW1/LPW2 and MOVW
       # all PINC them, so PT is NOT a load-only latch (regbank card rev D).

def w(doe=0,dld=0,psel=0,pinc=0,pdec=0,alus=0,m=0,cin=1,sh0=0,sh1=0,
      ldf=0,fcond=0,urst=0,halt=0,ldzn=0,shcin=0,setc=0,clrc=0,bsel=0):
    return (DOE[doe] if isinstance(doe,str) else doe) \
        | (DLD[dld] if isinstance(dld,str) else dld)<<4 \
        | psel<<8 | pinc<<11 | pdec<<12 | alus<<13 | m<<17 | cin<<18 \
        | sh0<<19 | sh1<<20 | ldf<<21 \
        | (FC[fcond] if isinstance(fcond,str) else fcond)<<22 | urst<<25 | halt<<26 \
        | ldzn<<27 | shcin<<28 | setc<<29 | clrc<<30 | bsel<<31

FETCH=w(doe="MEM",dld="IR",psel=0,pinc=1)

# ALU helper: (S, M, CINpin). CIN pin is ACTIVE-LOW carry on the 74181.
ALU=dict(ADD=(0b1001,0,1), ADC1=(0b1001,0,0), SUB=(0b0110,0,0),
         AND=(0b1011,1,1), OR=(0b1110,1,1), XOR=(0b0110,1,1),
         PASSA=(0b1111,1,1), INC=(0b0000,0,0), DEC=(0b1111,0,1),
         SBB=(0b0110,0,1),    # subtract WITH borrow: CIN pin high = carry-in 0 = A-B-1
         ZERO=(0b0011,1,1))   # 74181 logic mode S=0011: F=0 -- a bus-able zero (zero-extend)
def alu(op,dld="A",ldf=1,**kw):
    s,m,c=ALU[op]; return w(doe="ALU",dld=dld,alus=s,m=m,cin=c,ldf=ldf,urst=1,**kw)
def alu_mid(op,dld,psel=0,ldf=1,**kw):   # an ALU step that does NOT end the opcode
    s,m,c=ALU[op]; return w(doe="ALU",dld=dld,psel=psel,alus=s,m=m,cin=c,ldf=ldf,**kw)

U={}     # opcode -> list of (cond0_word, cond1_word) per step (after fetch)
OPC={}   # (BASE_MNEMONIC, shape) -> opcode    -- shared with the assembler
def op(code,name,shape,*steps):
    # 16 steps per opcode, step 0 is the fetch: 15 usable. A 16th step would
    # alias into the condition plane (A12), so refuse it here, not on silicon.
    assert len(steps)<=15, "%s %s: %d steps (max 15)"%(name,shape,len(steps))
    assert code not in U, "opcode $%02X defined twice (%s)"%(code,name)
    U[code]=[(s,s) if not isinstance(s,tuple) else s for s in steps]
    OPC[(name,shape)]=code

NOP=w(urst=1)
op(0x00,"NOP","", NOP)
op(0x01,"HLT","", w(halt=1,urst=1))
# ---- interrupts (rev C) -------------------------------------------------------
# EI/DI just toggle the interrupt-enable latch (driven by an opcode decode on the
# control card, not a microcode bit); their microcode is a plain NOP.
op(0x02,"EI","", NOP)              # enable maskable interrupts
op(0x03,"DI","", NOP)              # disable maskable interrupts
# IRQ entry: the forcing buffer injects opcode $08 at fetch (which still did P0++)
# AND drives $08 on the bus whenever this opcode is running with DOE=idle, so the
# two PTR loads below build P0 = $0808 (the ROM vector). Sequence: undo the
# fetch's P0++, push return PC (hi,lo) and flags onto P3, then vector to $0808.
op(0x08,"IRQ","",
   w(psel=0,pdec=1),                              # P0 = return address (undo fetch P0++)
   w(doe="PTRH",dld="T",psel=0),
   w(doe="T",dld="MEMW",psel=3,pdec=1),           # push return hi
   w(doe="PTRL",dld="T",psel=0),
   w(doe="T",dld="MEMW",psel=3,pdec=1),           # push return lo
   w(doe="FLAGS",dld="T",psel=0),
   w(doe="T",dld="MEMW",psel=3,pdec=1),           # push flags
   w(doe="idle",dld="PTRH",psel=0),               # P0.hi = $08 (forcing buffer)
   w(doe="idle",dld="PTRL",psel=0,urst=1))        # P0.lo = $08 -> P0 = $0808
# RTI: pop flags then return PC; re-enables interrupts (IE set by opcode decode).
op(0x04,"RTI","",
   w(psel=3,pinc=1),
   w(doe="MEM",dld="T",psel=3),                   # T = saved flags
   w(doe="T",dld="FLAGS",psel=0),                 # restore C/Z/N/V
   w(psel=3,pinc=1),
   w(doe="MEM",dld="T",psel=3),                   # T = return lo
   w(psel=3,pinc=1),
   w(doe="MEM",dld="T2",psel=3),                  # T2 = return hi
   w(doe="T",dld="PTRL",psel=0),
   w(doe="T2",dld="PTRH",psel=0,urst=1))
op(0x10,"LDA","#", w(doe="MEM",dld="A",psel=0,pinc=1,ldzn=1,urst=1))
op(0x11,"LDB","#", w(doe="MEM",dld="B",psel=0,pinc=1,ldzn=1,urst=1))
# absolute addressing: operand lo,hi -> PT scratch pointer, then access via PT
def _ld_pt():     # steps 1-4: read 16-bit operand into PT (P0 advances past it)
    return ( w(doe="MEM",dld="T", psel=0,pinc=1),
             w(doe="MEM",dld="T2",psel=0,pinc=1),
             w(doe="T", dld="PTRL",psel=PT),
             w(doe="T2",dld="PTRH",psel=PT) )
op(0x12,"LDA","a", *_ld_pt(), w(doe="MEM",dld="A",psel=PT,ldzn=1,urst=1))
op(0x13,"LDB","a", *_ld_pt(), w(doe="MEM",dld="B",psel=PT,ldzn=1,urst=1))
op(0x14,"STA","a", *_ld_pt(), w(doe="A",dld="MEMW",psel=PT,urst=1))
for p in (1,2,3):
    op(0x14+p,"LDA","(P%d)+"%p, w(doe="MEM",dld="A",psel=p,pinc=1,ldzn=1,urst=1))
    op(0x18+p,"STA","(P%d)+"%p, w(doe="A",dld="MEMW",psel=p,pinc=1,urst=1))
    op(0x1C+p,"STA","(P%d)"%p,  w(doe="A",dld="MEMW",psel=p,urst=1))
    op(0x50+p,"LDA","(P%d)"%p,  w(doe="MEM",dld="A",psel=p,ldzn=1,urst=1))  # non-incrementing
# ALU ops: result -> A, flags latched
op(0x20,"ADD","", alu("ADD")); op(0x21,"SUB","", alu("SUB"))
op(0x22,"AND","", alu("AND")); op(0x23,"OR","",  alu("OR"))
op(0x24,"XOR","", alu("XOR")); op(0x25,"CMP","", alu("SUB",dld="none"))
op(0x26,"INC","", alu("INC")); op(0x27,"DEC","", alu("DEC"))
op(0x28,"SHL","", w(doe="ALU",dld="A",alus=0b1111,m=1,cin=0,sh0=1,ldf=1,urst=1))
op(0x29,"SHR","", w(doe="ALU",dld="A",alus=0b1111,m=1,cin=0,sh1=1,ldf=1,urst=1))
# rotates through carry: shift-in = current C (SHCIN), shifted-out bit -> C
op(0x2A,"ROL","", w(doe="ALU",dld="A",alus=0b1111,m=1,sh0=1,shcin=1,ldf=1,urst=1))
op(0x2B,"ROR","", w(doe="ALU",dld="A",alus=0b1111,m=1,sh1=1,shcin=1,ldf=1,urst=1))
# T-operand ALU ops (rev C: 2nd ALU-input mux selects T as the B operand via
# BSEL). Same operations as 0x20-0x25 but second operand = T register, so e.g.
# ADDT computes A = A + T in one step without shuffling T through B.
op(0x80,"ADDT","", alu("ADD",bsel=1)); op(0x81,"SUBT","", alu("SUB",bsel=1))
op(0x82,"ANDT","", alu("AND",bsel=1)); op(0x83,"ORT","",  alu("OR", bsel=1))
op(0x84,"XORT","", alu("XOR",bsel=1)); op(0x85,"CMPT","", alu("SUB",dld="none",bsel=1))
# T is otherwise microcode-scratch only; these expose it as a loadable operand
# so the T-mux ops above are actually usable. (No flags touched: T isn't the
# accumulator.) LDT a reuses the PT-scratch operand-fetch like LDA a.
op(0x86,"LDT","#", w(doe="MEM",dld="T",psel=0,pinc=1,urst=1))
op(0x87,"LDT","a", *_ld_pt(), w(doe="MEM",dld="T",psel=PT,urst=1))
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
# JSR abs: read target -> PT, push return P0 (H then L) onto P3, then PT -> P0
op(0x43,"JSR","a", w(doe="MEM",dld="T", psel=0,pinc=1),   # target lo -> T
         w(doe="MEM",dld="T2",psel=0,pinc=1),             # target hi -> T2 (P0 = return)
         w(doe="T", dld="PTRL",psel=PT),                  # PT.lo = target lo
         w(doe="T2",dld="PTRH",psel=PT),                  # PT.hi = target hi
         w(doe="PTRH",dld="T",psel=0),                    # T = return hi
         w(doe="T",dld="MEMW",psel=3,pdec=1),             # push hi
         w(doe="PTRL",dld="T",psel=0),                    # T = return lo
         w(doe="T",dld="MEMW",psel=3,pdec=1),             # push lo
         w(doe="PTRL",dld="T",psel=PT),                   # T = target lo
         w(doe="T",dld="PTRL",psel=0),                    # P0.lo = target lo
         w(doe="PTRH",dld="T",psel=PT),                   # T = target hi
         w(doe="T",dld="PTRH",psel=0,urst=1))             # P0.hi = target hi
# RTS: inc-then-read L,H from P3 -> P0
op(0x42,"RTS","", w(psel=3,pinc=1),
         w(doe="MEM",dld="T",psel=3),
         w(psel=3,pinc=1),
         w(doe="MEM",dld="T2",psel=3),
         w(doe="T",dld="PTRL",psel=0),
         w(doe="T2",dld="PTRH",psel=0,urst=1))
# pointer inc/dec by opcode, A<->pointer-byte transfers, push/pop A
for p in (1,2,3):
    op(0x53+p,"INP%d"%p,"", w(psel=p,pinc=1,urst=1))
    op(0x57+p,"DEP%d"%p,"", w(psel=p,pdec=1,urst=1))
    op(0x5C+p*2,"TAP%dL"%p,"", w(doe="A",dld="PTRL",psel=p,urst=1))    # A -> Pn low
    op(0x5D+p*2,"TAP%dH"%p,"", w(doe="A",dld="PTRH",psel=p,urst=1))    # A -> Pn high
    op(0x66+p*2,"TPA%dL"%p,"", w(doe="PTRL",dld="A",psel=p,ldzn=1,urst=1))  # Pn low -> A
    op(0x67+p*2,"TPA%dH"%p,"", w(doe="PTRH",dld="A",psel=p,ldzn=1,urst=1))  # Pn high -> A
op(0x70,"PHA","", w(doe="A",dld="MEMW",psel=3,pdec=1,urst=1))          # push A, SP--
op(0x71,"PLA","", w(psel=3,pinc=1), w(doe="MEM",dld="A",psel=3,ldzn=1,urst=1))  # SP++, A=[SP]
# 16-bit push/pop of a memory word (collapses the compiler's LDA/PHA/LDA/PHA and
# PLA/STA/PLA/STA 16-bit-operand idioms into one instruction). Byte order on the
# stack (2026-09-11, for the Tier A frame model): PHW pushes the HIGH byte first,
# then the low byte, so the pushed word lies LITTLE-ENDIAN at P3+1..P3+2 -- the
# same layout JSR/IRQ leave for a return address, and exactly what `LDW a,(P3+d)`
# reads. A C argument pushed with PHW is therefore a plain frame word to the
# callee. PLW pops lo (top) then hi. (Before this, PHW pushed lo first; PHW/PLW
# are only ever used as pairs, so nothing else observed the layout.) Scratch: PT
# holds the operand address (incremented for the high byte), T/T2 the two bytes.
op(0x74,"PHW","a", *_ld_pt(),
   w(doe="MEM",dld="T", psel=PT),                 # T  = mem[a]   (lo)
   w(psel=PT,pinc=1),                             # PT = a+1
   w(doe="MEM",dld="T2",psel=PT),                 # T2 = mem[a+1] (hi)
   w(doe="T2",dld="MEMW",psel=3,pdec=1),          # push hi, SP--
   w(doe="T", dld="MEMW",psel=3,pdec=1,urst=1))   # push lo, SP--  (lo ends on top)
op(0x75,"PLW","a", *_ld_pt(),
   w(psel=3,pinc=1),                              # SP++
   w(doe="MEM",dld="T", psel=3),                  # T  = [SP] (lo, last pushed)
   w(psel=3,pinc=1),                              # SP++
   w(doe="MEM",dld="T2",psel=3),                  # T2 = [SP] (hi)
   w(doe="T", dld="MEMW",psel=PT),                # mem[a]   = lo   (PT = a)
   w(psel=PT,pinc=1),                             # PT = a+1
   w(doe="T2",dld="MEMW",psel=PT,urst=1))         # mem[a+1] = hi
# Load a 16-bit pointer (P1/P2) from a memory word — collapses the compiler's
# LDA a / TAP1L / LDA a+1 / TAP1H idiom (set a pointer from a C pointer variable
# or __ax). PT holds the source address (read), Pn is the destination; the read
# and the pointer-byte write use different PSELs in sequence, so no 2nd scratch
# pointer is needed (pure microcode, unlike MOVW).
for p in (1,2,3):                                 # LPW3 ($79, 2026-09-11): restore a
    op(0x75+p if p<3 else 0x79,"LPW%d"%p,"a", *_ld_pt(),   # saved stack pointer
       w(doe="MEM",dld="T",psel=PT,pinc=1),       # T = mem[a]   (lo), PT = a+1
       w(doe="T",dld="PTRL",psel=p),              # P%d.lo = T
       w(doe="MEM",dld="T",psel=PT),              # T = mem[a+1] (hi)
       w(doe="T",dld="PTRH",psel=p,urst=1))       # P%d.hi = T
# MOVW dst,src — 16-bit memory->memory move, collapses the compiler's most common
# idiom (LDA src / STA dst / LDA src+1 / STA dst+1, 12 bytes) into 5. Needs TWO
# live addresses (read src, write dst) so it uses BOTH scratch pointers: PT2 = the
# dst (write) cursor, PT = the src (read) cursor. Operand order in the stream is
# dst word then src word (matching `MOVW dst,src`). 12 steps, inside the 16 budget.
op(0x78,"MOVW","a,a",
   w(doe="MEM",dld="T", psel=0,pinc=1),           # T  = dst.lo, P0++
   w(doe="MEM",dld="T2",psel=0,pinc=1),           # T2 = dst.hi, P0++
   w(doe="T", dld="PTRL",psel=PT2),               # PT2.lo = dst.lo
   w(doe="T2",dld="PTRH",psel=PT2),               # PT2.hi = dst.hi
   w(doe="MEM",dld="T", psel=0,pinc=1),           # T  = src.lo, P0++
   w(doe="MEM",dld="T2",psel=0,pinc=1),           # T2 = src.hi, P0++
   w(doe="T", dld="PTRL",psel=PT),                # PT.lo = src.lo
   w(doe="T2",dld="PTRH",psel=PT),                # PT.hi = src.hi
   w(doe="MEM",dld="T",psel=PT,pinc=1),           # T = mem[src],   PT++
   w(doe="T",dld="MEMW",psel=PT2,pinc=1),         # mem[dst] = T,   PT2++
   w(doe="MEM",dld="T",psel=PT),                  # T = mem[src+1]
   w(doe="T",dld="MEMW",psel=PT2,urst=1))         # mem[dst+1] = T

op(0x72,"CLC","", w(clrc=1,urst=1))    # C := 0
op(0x73,"SEC","", w(setc=1,urst=1))    # C := 1

# ---- Tier A: the C-compiler ISA (2026-09-11, docs/p8x-isa-c-extensions.md) ----
# Pure microcode: no new register, no new bus path. Everything below is built
# from the existing datapath -- PT/PT2 as address scratch, T as the ALU's second
# operand (BSEL), and the condition planes for CARRY PROPAGATION: an ALU step
# latches C (LDF); the NEXT step carries fcond="C" so the plane mux samples a
# settled flag; the step after that is a (C=0, C=1) plane pair. That two-step
# lag is the hardware pipeline (flag register -> mux -> ROM address), not an
# emulator artefact: do not "optimise" the fcond onto the ALU step.
# Contracts (on the ISA card):
#   * the (Pn+d) forms, ADDP3/SUBP3, LDW/STW (Pn+d), ADDW/SUBW/CMPW, INCW/DECW
#     CLOBBER A (it is the ALU's only A input) and LATCH THE FLAGS -- unlike
#     LDA/STA abs. p8cc holds nothing live in A or the flags across statements.
#   * d8 is UNSIGNED 0..255 (frames use positive offsets).
#   * ADDW/SUBW/CMPW: C = 16-bit carry / no-borrow (unsigned a>=b); N and V are
#     the high byte's, so BLT/BGE after CMPW is a correct SIGNED 16-bit compare;
#     Z reflects the high byte only (equality needs a separate test).
#   * INCW/DECW/ADDP3/SUBP3: flags are the LOW byte's (C = carry/no-borrow out).
#   * LDW a,# / LDW a,#w / LDPn #w: no A clobber, no flags.
# Byte-stream order for the two-operand forms: the 16-bit address FIRST, then
# the displacement / immediate -- for BOTH `LDW a,(Pn+d)` and `STW (Pn+d),a`, so
# one microcode skeleton serves both (the assembler reorders `STW`'s operands).
def _ld_pt2():    # steps 1-4: read 16-bit operand into PT2 (the MOVW dst loader)
    return ( w(doe="MEM",dld="T", psel=0,pinc=1),
             w(doe="MEM",dld="T2",psel=0,pinc=1),
             w(doe="T", dld="PTRL",psel=PT2),
             w(doe="T2",dld="PTRH",psel=PT2) )
def _pt_disp(p):  # PT = Pn + T(d8), carry-correct. 4 steps; clobbers A; latches flags.
    return ( w(doe="PTRL",dld="A",psel=p),                        # A = Pn.lo
             alu_mid("ADD",dld="PTRL",psel=PT,bsel=1),             # PT.lo = Pn.lo + d8 ; latch C
             w(doe="PTRH",dld="A",psel=p,fcond="C"),               # A = Pn.hi ; route C -> mux
             ( alu_mid("PASSA",dld="PTRH",psel=PT,ldf=0),          # C=0: PT.hi = Pn.hi
               alu_mid("INC",  dld="PTRH",psel=PT,ldf=0) ) )       # C=1: PT.hi = Pn.hi + 1
# A1. LDPn #imm16 -- a real 3-byte opcode (was the 4-byte LPLn/LPHn macro).
for p in (1,2,3):
    op(0x37+p,"LDP%d"%p,"#w",
       w(doe="MEM",dld="T", psel=0,pinc=1),                        # T  = imm.lo
       w(doe="MEM",dld="T2",psel=0,pinc=1),                        # T2 = imm.hi
       w(doe="T", dld="PTRL",psel=p),
       w(doe="T2",dld="PTRH",psel=p,urst=1))
# A2. ADDP3/SUBP3 #imm8 -- frame allocate / free on the hardware stack.
op(0x3C,"ADDP3","#",
   w(doe="MEM",dld="T",psel=0,pinc=1),                             # T = imm8
   w(doe="PTRL",dld="A",psel=3),                                   # A = P3.lo
   alu_mid("ADD",dld="PTRL",psel=3,bsel=1),                        # P3.lo = A+T ; latch C
   w(doe="PTRH",dld="A",psel=3,fcond="C"),                         # A = P3.hi ; route C
   ( alu_mid("PASSA",dld="PTRH",psel=3,ldf=0,urst=1),              # C=0: P3.hi unchanged
     alu_mid("INC",  dld="PTRH",psel=3,ldf=0,urst=1) ))            # C=1: P3.hi + 1
op(0x3D,"SUBP3","#",
   w(doe="MEM",dld="T",psel=0,pinc=1),
   w(doe="PTRL",dld="A",psel=3),
   alu_mid("SUB",dld="PTRL",psel=3,bsel=1),                        # P3.lo = A-T ; C=1: no borrow
   w(doe="PTRH",dld="A",psel=3,fcond="C"),
   ( alu_mid("DEC",  dld="PTRH",psel=3,ldf=0,urst=1),              # C=0: borrow -> P3.hi - 1
     alu_mid("PASSA",dld="PTRH",psel=3,ldf=0,urst=1) ))            # C=1: unchanged
# A3. LDA/STA (Pn+d8) -- displacement addressing (2 bytes: op d8).
for p in (1,2,3):
    op(0x87+p,"LDA","(P%d+d)"%p,                                    # 6 steps
       w(doe="MEM",dld="T",psel=0,pinc=1),                         # T = d8
       *_pt_disp(p),
       w(doe="MEM",dld="A",psel=PT,ldzn=1,urst=1))                 # A = mem[PT]
    op(0x8B+p,"STA","(P%d+d)"%p,                                    # 8 steps
       w(doe="MEM",dld="T",psel=0,pinc=1),                         # T = d8
       w(doe="A",dld="T2"),                                        # T2 = A (the ALU needs A)
       *_pt_disp(p),
       w(doe="T2",dld="MEMW",psel=PT),                             # mem[PT] = saved A
       w(doe="T2",dld="A",urst=1))                                 # restore A: STA leaves A intact
# A4. LDW a,(Pn+d8) / STW (Pn+d8),a -- a 16-bit local <-> a memory word (4 bytes:
# op a.lo a.hi d8; 13 steps). The direct replacement for p8cc's JSR __ldw/__stw.
for p in (1,2,3):
    op(0x8F+p,"LDW","a,(P%d+d)"%p,
       *_ld_pt2(),                                                 # 1-4  a -> PT2 (dest)
       w(doe="MEM",dld="T",psel=0,pinc=1),                         # 5    T = d8
       *_pt_disp(p),                                               # 6-9  PT = Pn + d8
       w(doe="MEM",dld="T",psel=PT,pinc=1),                        # 10   T = mem[Pn+d]    PT++
       w(doe="T",dld="MEMW",psel=PT2,pinc=1),                      # 11   mem[a] = T       PT2++
       w(doe="MEM",dld="T",psel=PT),                               # 12   T = mem[Pn+d+1]
       w(doe="T",dld="MEMW",psel=PT2,urst=1))                      # 13   mem[a+1] = T
    op(0x93+p,"STW","(P%d+d),a"%p,
       *_ld_pt2(),                                                 # 1-4  a -> PT2 (source)
       w(doe="MEM",dld="T",psel=0,pinc=1),                         # 5    T = d8
       *_pt_disp(p),                                               # 6-9  PT = Pn + d8 (dest)
       w(doe="MEM",dld="T",psel=PT2,pinc=1),                       # 10   T = mem[a]       PT2++
       w(doe="T",dld="MEMW",psel=PT,pinc=1),                       # 11   mem[Pn+d] = T    PT++
       w(doe="MEM",dld="T",psel=PT2),                              # 12   T = mem[a+1]
       w(doe="T",dld="MEMW",psel=PT,urst=1))                       # 13   mem[Pn+d+1] = T
# A5. LDW a,#imm8 (zero-extended, 4 bytes) / LDW a,#imm16 (5 bytes) -- a 16-bit
# constant into a memory word. p8cc's single most frequent idiom (was 10 bytes).
op(0x98,"LDW","a,#",
   *_ld_pt(),                                                      # 1-4  a -> PT
   w(doe="MEM",dld="T",psel=0,pinc=1),                             # 5    T = imm8
   w(doe="T",dld="MEMW",psel=PT,pinc=1),                           # 6    mem[a] = imm8    PT++
   alu_mid("ZERO",dld="MEMW",psel=PT,ldf=0,urst=1))                # 7    mem[a+1] = 0
op(0x99,"LDW","a,#w",
   *_ld_pt(),
   w(doe="MEM",dld="T",psel=0,pinc=1), w(doe="T",dld="MEMW",psel=PT,pinc=1),
   w(doe="MEM",dld="T",psel=0,pinc=1), w(doe="T",dld="MEMW",psel=PT,urst=1))
# A6. ADDW/SUBW/CMPW a,b -- mem[a] op= mem[b], carry/borrow through the C plane
# (5 bytes: op a.lo a.hi b.lo b.hi; 14 steps). CMPW = SUBW with the writes off.
def _wordop(code,name,lo,hi_pair,store=True):
    dst="MEMW" if store else "none"
    op(code,name,"a,a",
       *_ld_pt2(),                                                 # 1-4  a -> PT2
       *_ld_pt(),                                                  # 5-8  b -> PT
       w(doe="MEM",dld="T",psel=PT,pinc=1),                        # 9    T = b.lo         PT++
       w(doe="MEM",dld="A",psel=PT2),                              # 10   A = a.lo
       alu_mid(lo,dld=dst,psel=PT2,bsel=1,pinc=1),                 # 11   a.lo = A op T ; latch C ; PT2++
       w(doe="MEM",dld="T",psel=PT),                               # 12   T = b.hi
       w(doe="MEM",dld="A",psel=PT2,fcond="C"),                    # 13   A = a.hi ; route C
       ( alu_mid(hi_pair[0],dld=dst,psel=PT2,bsel=1,urst=1),       # 14   C=0 plane
         alu_mid(hi_pair[1],dld=dst,psel=PT2,bsel=1,urst=1) ))     #      C=1 plane
_wordop(0x9A,"ADDW","ADD",("ADD","ADC1"))          # C=1 from the low byte: carry in
_wordop(0x9B,"SUBW","SUB",("SBB","SUB"))           # C=0 from the low byte: borrow in
_wordop(0x9C,"CMPW","SUB",("SBB","SUB"),store=False)
# A7. INCW/DECW a -- 16-bit increment/decrement in memory (3 bytes, 8 steps).
op(0x9E,"INCW","a",
   *_ld_pt(),                                                      # 1-4  a -> PT
   w(doe="MEM",dld="A",psel=PT),                                   # 5    A = a.lo
   alu_mid("INC",dld="MEMW",psel=PT,pinc=1),                       # 6    a.lo++ ; latch C ; PT++
   w(doe="MEM",dld="A",psel=PT,fcond="C"),                         # 7    A = a.hi ; route C
   ( alu_mid("PASSA",dld="MEMW",psel=PT,ldf=0,urst=1),             # 8    C=0: done
     alu_mid("INC",  dld="MEMW",psel=PT,ldf=0,urst=1) ))           #      C=1: a.hi++
op(0x9F,"DECW","a",
   *_ld_pt(),
   w(doe="MEM",dld="A",psel=PT),
   alu_mid("DEC",dld="MEMW",psel=PT,pinc=1),                       # a.lo-- ; C=1: no borrow
   w(doe="MEM",dld="A",psel=PT,fcond="C"),
   ( alu_mid("DEC",  dld="MEMW",psel=PT,ldf=0,urst=1),             # C=0: borrow -> a.hi--
     alu_mid("PASSA",dld="MEMW",psel=PT,ldf=0,urst=1) ))           # C=1: done
# A9 (2026-09-11). ADDW/SUBW/CMPW a,#imm8 -- mem[a] op= imm8 zero-extended
# (4 bytes: op a.lo a.hi imm8; 10 steps). The compiler's `x + k`, pointer
# stepping and `if (n < k)` without a constant load. Same flag contract as the
# a,b forms: the high-byte step runs the ALU against T = 0 (ZERO'd after the
# low byte, flags kept), so C is the 16-bit carry / no-borrow and N^V the signed
# order; Z high byte only. Clobbers A.
def _wordimm(code,name,lo,hi_pair,store=True):
    dst="MEMW" if store else "none"
    op(code,name,"a,#",
       *_ld_pt(),                                                  # 1-4  a -> PT
       w(doe="MEM",dld="T",psel=0,pinc=1),                         # 5    T = imm8
       w(doe="MEM",dld="A",psel=PT),                               # 6    A = a.lo
       alu_mid(lo,dld=dst,psel=PT,bsel=1,pinc=1),                  # 7    a.lo op= imm ; latch C ; PT++
       alu_mid("ZERO",dld="T",ldf=0),                              # 8    T = 0 (flags kept)
       w(doe="MEM",dld="A",psel=PT,fcond="C"),                     # 9    A = a.hi ; route C
       ( alu_mid(hi_pair[0],dld=dst,psel=PT,bsel=1,urst=1),        # 10   C=0 plane
         alu_mid(hi_pair[1],dld=dst,psel=PT,bsel=1,urst=1) ))      #      C=1 plane
_wordimm(0xA0,"ADDW","ADD",("ADD","ADC1"))
_wordimm(0xA1,"SUBW","SUB",("SBB","SUB"))
_wordimm(0xA2,"CMPW","SUB",("SBB","SUB"),store=False)
# A10 (2026-09-11). LEAW a,(Pn+d) -- mem[a] := Pn + d (the ADDRESS of a frame
# local: arrays, &x, struct locals). 4 bytes, 13 steps, clobbers A.
for p in (1,2,3):
    op(0xA3+p,"LEAW","a,(P%d+d)"%p,
       *_ld_pt2(),                                                 # 1-4  a -> PT2
       w(doe="MEM",dld="T",psel=0,pinc=1),                         # 5    T = d8
       *_pt_disp(p),                                               # 6-9  PT = Pn + d
       w(doe="PTRL",dld="T",psel=PT),                              # 10   T = PT.lo
       w(doe="T",dld="MEMW",psel=PT2,pinc=1),                      # 11   mem[a] = lo     PT2++
       w(doe="PTRH",dld="T",psel=PT),                              # 12   T = PT.hi
       w(doe="T",dld="MEMW",psel=PT2,urst=1))                      # 13   mem[a+1] = hi

# conditional branches abs: Bcc addr. FCOND emitted while fetching operand;
# cond plane 1 = take (load P0 from T/T2), plane 0 = fall through.
def branch(code,name,flag):
    op(code,name,"a", w(doe="MEM",dld="T",psel=0,pinc=1),
             w(doe="MEM",dld="T2",psel=0,pinc=1,fcond=flag),
             ( w(urst=1,fcond=flag),                 # not taken
               w(doe="T",dld="PTRL",psel=0,fcond=flag) ),
             ( NOP, w(doe="T2",dld="PTRH",psel=0,urst=1) ))
def branch_inv(code,name,flag):   # taken when flag==0 (plane swap)
    op(code,name,"a", w(doe="MEM",dld="T",psel=0,pinc=1),
             w(doe="MEM",dld="T2",psel=0,pinc=1,fcond=flag),
             ( w(doe="T",dld="PTRL",psel=0,fcond=flag), w(urst=1,fcond=flag) ),
             ( w(doe="T2",dld="PTRH",psel=0,urst=1), NOP ))
branch(0x48,"BZ","Z")
branch(0x4A,"BCP","C")  # branch if carry set (rev B: C is conventional active-high)
branch_inv(0x49,"BNZ","Z")
branch_inv(0x4C,"JNC","C")   # branch if carry clear
# conventional aliases (same opcodes): JZ=BZ, JNZ=BNZ, JC=BCP
OPC[("JZ","a")]=0x48; OPC[("JNZ","a")]=0x49; OPC[("JC","a")]=0x4A
# signed comparison branches (rev C): use after CMP/SUB. LT = N^V, LE = (N^V)|Z.
branch(0x44,"BLT","LT")          # signed A <  B
branch_inv(0x45,"BGE","LT")      # signed A >= B
branch(0x46,"BLE","LE")          # signed A <= B
branch_inv(0x47,"BGT","LE")      # signed A >  B

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
    # Intel HEX for the EEPROM programmer is built into rom/ by tools/build_rom.sh
    # (`make rom`); these .bin are what the emulator and tests load.
    print("u0-u3.bin written:",", ".join("%d bytes"%len(r) for r in roms))
    print("defined opcodes:",len(U))

if __name__=="__main__":
    build_images()
