# P8X ISA extensions for C — design sketch

**Status (2026-09-11): Tier A is IMPLEMENTED on the emulator** — the 24 opcodes
below are in `microcode/genucode.py` (opcodes as listed; `u0–u3.bin`
regenerated), the host assembler parses every new operand shape, `LDPn #imm16`
is a real opcode in both assemblers, the disassembler decodes all of them, and
`emulator/test/test_isa.asm` proves each one on its carry-plane case (tests
C1–D1). The ISA card and programmer's guide are regenerated. **The compiler
emitters (§5) are done as well**, in two steps: the Tier A idioms (`LDW a,#`,
in-place `INCW`/`DECW`/`ADDW`/`SUBW`, `CMPW`, `LPW1`) and then **frames on the
hardware stack** — `SUBP3 #L`, `LDW`/`STW`/`LEAW (P3+d)`, args pushed with
`PHW` and dropped with `ADDP3`, the software C-stack and its runtime gone. That
needed three small additions beyond the sketch: `ADDW`/`SUBW`/`CMPW a,#imm8`
(`$A0–$A2`), `LEAW a,(Pn+d)` (`$A4–$A6`) and `LPW3` (`$79`), plus `PHW` pushing
high-byte-first so a pushed word is little-endian on the stack (§7 caveat 4 is
now moot: the compiler chose SP-relative frames; a Tier B P4 would only simplify
the depth tracking). Then **relative branches** (`$A8–$B0`, 2 bytes, signed
displacement, flags preserved on the taken path) with shrink-only relaxation
in the assembler, opted into by the compiler's `.relax` line so hand sources
stay byte-identical with the native assembler. Then **narrow (8-bit) values
and a peephole pass**, and finally (same day) the **arithmetic helpers were
retired**: `+ - & | ^` and every comparison are one word instruction, which
took twelve more pure-microcode opcodes — `ADDW`/`SUBW`/`CMPW a,#imm16`
(`$B1–$B3`) and `ANDW`/`ORW`/`XORW` in the `a,b` / `a,#imm8` / `a,#imm16`
shapes (`$B4–$BC`); **every immediate form carries a full 16-bit Z** (a 0/1
marker of the low byte's Z kept in T2 and re-latched through the Z plane when
the high byte is zero — 14 steps), so `x == k`, `if (x & m)` and `if (x)` are a
single compare/branch pair, while the `a,b` forms stay high-byte-only for lack
of steps. Functions `main` never reaches are no longer compiled. Result over
all 45 `/bin` C commands: **627,172 → 293,890 bytes, −53.1%**; `finder` 32,630
→ 9,508; 140 opcodes in use. Not yet done: the self-hosting compilers, the
on-target assembler's parsing of the compiler-only shapes (done on the
`os-rewrite` branch), an EPROM reburn for the TTL machine. Tiers B and C
remain proposals. What follows is the original sketch —
real opcode numbers, real microcode in `genucode.py`'s vocabulary, step counts
against the 15-step budget — so it can be argued about and then built. The
motivation, the constraints, three tiers of change, what the compiler does with
them, the expected savings, and the implementation ripple.

---

## 0. Why: where p8cc's bytes actually go

Measured on the icon-grid `finder.c` (32,630 bytes compiled; instruction sizes
from the assembler: `LDA #` 2, `STA a` 3, `JSR a` 3, `PHW/PLW a` 3, `MOVW` 5):

| Pattern p8cc emits today | Count | Bytes each | Total | Share |
|---|---|---|---|---|
| 16-bit value into the **RAM accumulator** `LDA #lo / STA __ax / LDA #hi / STA __ax+1` | ~1130 | 10 | ~11 KB | **~35%** |
| Expression spills `PHW __ax` … `PLW __t` around every binary op | 544 pairs | 6 | ~3.3 KB | 10% |
| Frame-local load/store as a **subroutine** `JSR __ldw ; .word off` | 580 | 5 | ~2.9 KB | 9% |
| Arithmetic/compare as `JSR __add / __sub / __lt …` | 526 | 3 | ~1.6 KB | 5% |
| Function prologue `JSR __entf ; .word frame` | ~80 | 5 | 0.4 KB | 1% |

**Well over half the binary is scaffolding for emulating a 16-bit register machine
on an 8-bit CPU whose only addressing is `(Pn)` / `(Pn)+`.** p8cc keeps its
accumulator (`__ax`), temp (`__t`), frame pointer (`__fp`) and stack pointer
(`__csp`) in RAM because the ISA gives it nowhere else to put them. Every local
variable access is a subroutine call; every 16-bit constant is 10 bytes; every
operation shuttles through RAM.

That RAM-based software stack is also exactly the machinery that bit us: a
`__csp`/`__fp` in RAM plus balanced `PHW`/`PLW` pairs is fragile — one imbalance
on one path silently writes into data. Frames on the hardware stack with a real
displacement mode remove that bug class, not just the bytes.

---

## 1. Microarchitecture facts that shape the design

From `microcode/genucode.py` (the source of truth):

- **One 8-bit data bus.** Registers: A, B, T, T2 (8-bit; T/T2 are microcode
  scratch, T also a user ALU operand via `LDT`/`ADDT`…). Pointers P0 (PC), P1,
  P2, P3 (SP, empty-descending) + two **hidden** scratch pointers PT (PSEL 4)
  and PT2 (PSEL 5). PSEL is 3 bits: **values 6 and 7 are free.**
- **The ALU is an 8-bit 74181** with A on one input and **B or T** on the other
  (`bsel`). Its carry-in is a *microcode constant* (`cin`), **not the C flag** —
  so a multi-byte add can't chain carry through the ALU pin directly.
- **No address adder.** An address is always a pointer register; the only
  arithmetic on addresses is `PINC`/`PDEC`. So `(Pn+d)` cannot be one micro-step —
  it must be *computed* (P.lo + d through the ALU into PT.lo, then P.hi + carry
  into PT.hi) and then used as `(PT)`. Still far cheaper than today's `JSR __ldw`.
- **Carry propagation IS available** — via the condition planes. `fcond=C` on a
  step routes the C flag to ROM address bit A12, so the *next* step is a
  `(plane0, plane1)` pair chosen by C. `branch()` already uses this. A 16-bit add
  is: lo-byte `ADD` (latches C) → a step carrying `fcond="C"` → a pair
  `{ADD, ADC1}` for the high byte. That is the whole trick behind every 16-bit
  op below.
- **Step budget: 16 per opcode, step 0 = fetch, so 15 usable.** MOVW is the
  current max at 12. Everything below fits in ≤ 14.
- **Flags C, Z, N, V and signed branches `BLT/BGE/BLE/BGT` already exist**
  (`N^V`, `(N^V)|Z`). p8cc's "int is unsigned" is a *compiler* choice.
- **Pure-microcode additions are free on every target.** The emulator and the
  FPGA both *execute the same `u0-u3.bin`*, so a new opcode defined in
  `genucode.py` works in the emulator, the co-sim and on the Tang Nano with
  **no emulator or RTL code change**. Only `genucode.py`, the assembler (new
  operand shapes) and the compiler change. Adding a *register* (Tier B) is the
  first thing that touches hardware.
- Opcodes: 88 defined, **168 free** — `$05-$07, $09-$0F, $18, $1C, $2C-$30, $34,
  $38-$3F, $4B, $4D-$50, $57, $5B-$5D, $64-$67, $6E-$6F, $79-$7F, $88-$FF`.

Three small microcode helpers the listings below assume (additions to
`genucode.py`):

```python
ALU["ZERO"] = (0b0011, 1, 1)   # 74181 logic mode F=0: a bus-able zero (zero-extend)
ALU["SBB"]  = (0b0110, 0, 1)   # subtract WITH borrow: cin pin high = carry-in 0 = A-B-1
def alu_mid(op, dld, psel=0, ldf=1, **kw):      # an ALU step that does NOT end the opcode
    s, m, c = ALU[op]
    return w(doe="ALU", dld=dld, psel=psel, alus=s, m=m, cin=c, ldf=ldf, **kw)
```

(`alu()` today hard-codes `urst=1`; mid-sequence steps need the variant.)

---

## 2. Tier A — pure microcode, no hardware

The order is by payoff. Byte counts are *instruction* sizes; "replaces" is the
p8cc idiom today.

### A1. `LDPn #imm16` — 16-bit immediate into a pointer  `$38 $39 $3A`  (3 bytes, 4 steps)

Today `LDP1 #x` is an assembler **macro** = `LPL1 #lo ; LPH1 #hi` (4 bytes).
A real opcode is 3 bytes and one fetch.

```python
for p in (1, 2, 3):
    op(0x37 + p, "LDP%d" % p, "#w",                   # new shape "#w": 16-bit immediate
       w(doe="MEM", dld="T",  psel=0, pinc=1),        # T  = imm.lo
       w(doe="MEM", dld="T2", psel=0, pinc=1),        # T2 = imm.hi
       w(doe="T",  dld="PTRL", psel=p),
       w(doe="T2", dld="PTRH", psel=p, urst=1))       # 4 steps; clobbers T/T2 only
```

### A2. `ADDP3 #imm8` / `SUBP3 #imm8` — adjust the stack pointer  `$3C $3D`  (2 bytes, 5 steps)

Frame allocate / free. Replaces `JSR __entf ; .word n` (5 bytes + the routine)
and the matching `__retf`. **Clobbers A** (it is the ALU's only A-input).

```python
op(0x3C, "ADDP3", "#",
   w(doe="MEM", dld="T", psel=0, pinc=1),                     # 1  T = imm8
   w(doe="PTRL", dld="A", psel=3),                            # 2  A = P3.lo
   alu_mid("ADD", dld="PTRL", psel=3, bsel=1),                # 3  P3.lo = A+T ; latch C
   w(doe="PTRH", dld="A", psel=3, fcond="C"),                 # 4  A = P3.hi ; route C -> plane mux
   ( alu_mid("PASSA", dld="PTRH", psel=3, ldf=0, urst=1),     # 5  C=0: P3.hi unchanged
     alu_mid("INC",   dld="PTRH", psel=3, ldf=0, urst=1) ))   #    C=1: P3.hi + 1
# SUBP3: step 3 = SUB (C=1 means no borrow), step 5 pair = { DEC (borrow), PASSA }
```

Note the hazard-safe ordering: the flag latches at the *end* of step 3; step 4
carries `fcond` so the mux sees the settled C; step 5 is the pair.

### A3. `LDA (Pn+d8)` / `STA (Pn+d8)` — displacement addressing  `$88-$8A` / `$8C-$8E`  (2 bytes)

The C-enabling mode. d8 is **unsigned 0..255** (see §5 for why the frame
layout uses positive offsets). Computes PT = Pn + d8 through the ALU, then
accesses `(PT)`.

```python
def _pt_disp(p):        # steps: PT = Pn + T(d8), carry-correct. Clobbers A.
    return ( w(doe="PTRL", dld="A", psel=p),                       # A = Pn.lo
             alu_mid("ADD", dld="PTRL", psel=PT, bsel=1),          # PT.lo = Pn.lo + d8 ; latch C
             w(doe="PTRH", dld="A", psel=p, fcond="C"),            # A = Pn.hi ; route C
             ( alu_mid("PASSA", dld="PTRH", psel=PT, ldf=0),       # C=0: PT.hi = Pn.hi
               alu_mid("INC",   dld="PTRH", psel=PT, ldf=0) ) )    # C=1: PT.hi = Pn.hi + 1

for p in (1, 2, 3):
    op(0x87 + p, "LDA", "(P%d+d)" % p,                    # 2 bytes: op d8 ; 6 steps
       w(doe="MEM", dld="T", psel=0, pinc=1),             # T = d8
       *_pt_disp(p),
       w(doe="MEM", dld="A", psel=PT, ldzn=1, urst=1))    # A = mem[PT]  (A is the dest: fine)

    op(0x8B + p, "STA", "(P%d+d)" % p,                    # 2 bytes ; 8 steps
       w(doe="MEM", dld="T", psel=0, pinc=1),             # T = d8
       w(doe="A", dld="T2"),                              # T2 = A  (save the value: ALU needs A)
       *_pt_disp(p),
       w(doe="T2", dld="MEMW", psel=PT),                  # mem[PT] = saved A
       w(doe="T2", dld="A", urst=1))                      # restore A: STA leaves A intact
```

### A4. `LDW a,(Pn+d8)` / `STW (Pn+d8),a` — a 16-bit local to/from a memory word  `$90-$92` / `$94-$96`  (4 bytes, 13 steps)

This is the direct replacement for p8cc's `JSR __ldw ; .word off` (which loads
the word at `__fp+off` into `__ax`) and `__stw`. Encoding: `op a.lo a.hi d8`.
**Clobbers A** (documented contract, like MOVW clobbers T/T2 — p8cc never keeps
a live value in A across statements; its accumulator is in RAM).

```python
for p in (1, 2, 3):
    op(0x8F + p, "LDW", "a,(P%d+d)" % p,
       *_ld_pt2(),                                   # 1-4  a -> PT2  (dest word)   [a T/T2 loader for PT2]
       w(doe="MEM", dld="T", psel=0, pinc=1),        # 5    T = d8
       *_pt_disp(p),                                 # 6-9  PT = Pn + d8
       w(doe="MEM", dld="T", psel=PT, pinc=1),       # 10   T = mem[Pn+d]      PT++
       w(doe="T", dld="MEMW", psel=PT2, pinc=1),     # 11   mem[a]   = T       PT2++
       w(doe="MEM", dld="T", psel=PT),               # 12   T = mem[Pn+d+1]
       w(doe="T", dld="MEMW", psel=PT2, urst=1))     # 13   mem[a+1] = T
    # STW (Pn+d),a: same skeleton, read from PT2 (a) and write to PT (Pn+d).
```

`_ld_pt2()` is `_ld_pt()` with `psel=PT2` — the operand loader MOVW already uses.

### A5. `LDW a,#imm8` (zero-extended) / `LDW a,#imm16` — 16-bit constant to memory  `$98` / `$99`  (4 / 5 bytes)

The single most frequent idiom. Today: `LDA #lo/STA a/LDA #hi/STA a+1` = **10 bytes**.
Most C constants fit in 8 bits, so the zero-extending form is the workhorse.
Does not clobber A.

```python
op(0x98, "LDW", "a,#",                               # 4 bytes: op a.lo a.hi imm8 ; 7 steps
   *_ld_pt(),                                        # 1-4  a -> PT
   w(doe="MEM", dld="T", psel=0, pinc=1),            # 5    T = imm8
   w(doe="T", dld="MEMW", psel=PT, pinc=1),          # 6    mem[a]   = imm8   PT++
   alu_mid("ZERO", dld="MEMW", psel=PT, ldf=0, urst=1))   # 7  mem[a+1] = 0  (74181 logic-0)
op(0x99, "LDW", "a,#w",                              # 5 bytes ; 8 steps
   *_ld_pt(),
   w(doe="MEM", dld="T", psel=0, pinc=1),  w(doe="T", dld="MEMW", psel=PT, pinc=1),
   w(doe="MEM", dld="T", psel=0, pinc=1),  w(doe="T", dld="MEMW", psel=PT, urst=1))
```

### A6. `ADDW a,b` / `SUBW a,b` / `CMPW a,b` — 16-bit memory arithmetic  `$9A $9B $9C`  (5 bytes, 14 steps)

`mem[a] op= mem[b]`, carry/borrow propagated through the C plane. Replaces the
`JSR __add/__sub/__lt` runtime routines *and*, with the codegen change in §5,
the `PHW/PLW` spill pair around them. Uses T (via `bsel`) for the second operand
so **only A is clobbered**. Flags are latched from the high-byte step, so **C =
16-bit unsigned a≥b and N^V = signed a<b are correct; Z reflects the high byte
only** (see §7).

```python
op(0x9A, "ADDW", "a,a",
   *_ld_pt2(),                                          # 1-4  a -> PT2
   *_ld_pt(),                                           # 5-8  b -> PT
   w(doe="MEM", dld="T", psel=PT, pinc=1),              # 9    T = b.lo     PT++
   w(doe="MEM", dld="A", psel=PT2),                     # 10   A = a.lo
   alu_mid("ADD", dld="MEMW", psel=PT2, bsel=1, pinc=1),# 11   a.lo = A+T ; latch C ; PT2++
   w(doe="MEM", dld="T", psel=PT),                      # 12   T = b.hi
   w(doe="MEM", dld="A", psel=PT2, fcond="C"),          # 13   A = a.hi ; route C
   ( alu_mid("ADD",  dld="MEMW", psel=PT2, bsel=1, urst=1),   # 14  C=0: a.hi = A+T
     alu_mid("ADC1", dld="MEMW", psel=PT2, bsel=1, urst=1) )) #     C=1: a.hi = A+T+1
# SUBW: 11 = SUB (C=1: no borrow) ; 14 pair = { SBB (borrow), SUB }
# CMPW: as SUBW with dld="none" on steps 11 and 14 (flags only, memory untouched)
```

### A7. `INCW a` / `DECW a` — 16-bit increment/decrement in memory  `$9E $9F`  (3 bytes, 8 steps)

`i = i + 1` is in every loop; today it is a 16-bit load, an add and a store
(~15 bytes). Clobbers A.

```python
op(0x9E, "INCW", "a",
   *_ld_pt(),                                              # 1-4  a -> PT
   w(doe="MEM", dld="A", psel=PT),                         # 5    A = a.lo
   alu_mid("INC", dld="MEMW", psel=PT, pinc=1),            # 6    a.lo++ ; latch C ; PT++
   w(doe="MEM", dld="A", psel=PT, fcond="C"),              # 7    A = a.hi ; route C
   ( alu_mid("PASSA", dld="MEMW", psel=PT, ldf=0, urst=1), # 8    C=0: done
     alu_mid("INC",   dld="MEMW", psel=PT, ldf=0, urst=1) ))#    C=1: a.hi++
# DECW: 6 = DEC (C=1 means no borrow) ; 8 pair = { DEC, PASSA }
```

### A8. Signed compares — already there; compiler-only

`CMP`/`CMPT` set N and V; `BLT/BGE/BLE/BGT` test `N^V`. p8cc should emit them
for `int` comparisons instead of the unsigned `C` idiom. **Zero hardware, zero
microcode**, and it fixes the bug class where `i >= 0` on a `-1` sentinel is
always true.

---

## 3. Tier B — one hardware register: a frame pointer, P4

Everything in Tier A works with P3 (SP)-relative frames. But a *dedicated*
frame pointer is what makes C codegen simple and robust (locals at fixed
offsets regardless of pushes), and the control word already has room for it:
**PSEL 6 is unused.**

- **Hardware:** a fourth programmer-visible 16-bit pointer on the regbank card —
  the same four 74169 4-bit up/down counters the other pointers use (the rev-D
  note: "PT and PT2 are up-counters in hardware (74169s)"), decoded at PSEL=6,
  with the existing PTRL/PTRH bus read/write paths. Roughly 5–6 chips. **On the
  FPGA it is a register declaration.**
- **Opcodes (all in the free ranges, filling the P4 slot of each family):**
  `LDP4 #w $3B`, `ADDP4/SUBP4 #imm8 $3E/$3F`, `LDA/STA (P4+d) $8B/$8F`,
  `LDW/STW (P4+d) $93/$97`, plus the byte transfers `TAP4L/H $64/$65`,
  `TPA4L/H $66/$67`, `INP4 $57`, `DEP4 $5B`. The microcode is the Tier-A
  families with `psel=6`.
- **The compiler model then is the textbook one:** P3 = SP (hardware stack,
  frames live on it), P4 = FP (points at the frame base, set once in the
  prologue), P1/P2 free for pointers and register-allocated hot locals. No
  `__csp`, no `__fp`, no `__entf/__retf`.

## 4. Tier C — later: a 16-bit accumulator

After A+B, the remaining big cost is the *accumulator model* itself (the
`STA __ax` round-trips). A 16-bit accumulator register (`W`, or A:B as a true
pair with 16-bit ops) removes it — but that is a real datapath change (16-bit
ALU path or double-pumped 8-bit with hardware carry chaining) and a large
compiler rewrite. Worth it eventually; it is not the first step.

---

## 5. What the compiler does with Tier A

The instructions only pay off with matching codegen. The new idioms:

| C | today (bytes) | with Tier A (bytes) |
|---|---|---|
| `x = 5;` (local) | `LDA #5/STA __ax/LDA #0/STA __ax+1` (10) + `JSR __stw;.word` (5) = 15 | `LDW __ax,#5` (4) + `STW (P3+d),__ax` (4) = 8; or **directly** `LDA #5/STA (P3+d)` + zero hi = 6 |
| `y = x + z;` | 2× `JSR __ldw`(10) + `PHW/PLW`(6) + `JSR __add`(3) + `JSR __stw`(5) = 24 | `LDW __ax,(P3+dx)`(4) `LDW __t,(P3+dz)`(4) `ADDW __ax,__t`(5) `STW (P3+dy),__ax`(4) = 17, **no spill, no routine call** |
| `i = i + 1;` | ~15 | `INCW i` (3) — or on a local, `INCW` after a `LDW`/`STW`, ~11 |
| `if (a < b)` (signed) | `JSR __lt` + `JSR __not` + branch on the result word | `CMPW a,b` (5) + `BGE` (3) |
| function entry | `JSR __entf ; .word n` (5) + routine | `SUBP3 #n` (2) |
| `LDP1 #buf` | 4 (macro) | 3 |

Two conventions make it work:

1. **Frames on the hardware stack, positive offsets.** `SUBP3 #n` in the
   prologue reserves the frame; locals sit at `(P3+0 .. P3+n-1)`; the caller's
   pushed args are above the return address at `(P3+n+2 ..)`. All offsets are
   0..255 unsigned, which is why the displacement form needs no sign
   extension. The compiler tracks the SP delta across its own pushes (standard
   SP-relative codegen) — or, with Tier B, uses P4 and stops tracking.
2. **Leaf operands go straight to `__t`.** Today every binary op pushes the
   left operand while evaluating the right. When the right operand is a leaf
   (constant, local, global — the overwhelming case), load it into `__t` with
   one `LDW` first, then evaluate the left into `__ax` and `ADDW __ax,__t`. No
   `PHW`/`PLW` at all. Only nested non-leaf right operands still spill.

---

## 6. Expected savings

Against `finder.c` (32.6 KB), Tier A plus the §5 codegen:

| Change | Saves |
|---|---|
| 16-bit constants: 10 → 4 bytes (`LDW a,#imm8`), ~800 of the 1130 | ~4.8 KB |
| Spills eliminated for leaf operands (~75% of 544 pairs × 6) | ~2.5 KB |
| `JSR __op` (3) → `ADDW` (5) but with the spill gone: net 9 → 5 per op | ~1.5 KB |
| Locals `JSR __ldw` (5) → `LDW (P3+d)` (4), + the runtime routines themselves | ~0.8 KB |
| Prologues 5 → 2, `INCW/DECW` for counters | ~0.6 KB |
| **Total, Tier A + codegen** | **~10 KB ≈ 30%** |

And **speed**: a local access goes from a subroutine call plus a 16-bit add in
software (~60 cycles) to one 13-microstep instruction; a 16-bit add from ~90
cycles of routine to 14 microsteps. Roughly 2–3× on the compiled code paths.

Tier B adds a few percent more bytes but mostly buys *simplicity and safety*
(fixed frame offsets, no SP tracking). Tier C is where the next big block
(the accumulator round-trips, ~35% of today's binary) comes from — that is the
route to the 40–50% figure.

A compiler-only peephole pass (no ISA change: keep values in A:B across
adjacent ops, constant folding, `MOVW` more aggressively) is worth ~10–15% on its
own and is prerequisite restructuring anyway.

---

## 7. Ripple, sequence, risks

**What changes for Tier A**

- `microcode/genucode.py` — the opcodes + the three helpers. Regenerates
  `u0-u3.bin`; **emulator, co-sim and FPGA follow with no code change.** The ISA
  card (`gen_isa_card.py`) and the on-target opcode table (`gen_p8xopc.py`) are
  generated from it and follow too.
- `assembler/p8xasm.py` — new operand **shapes**: `#w` (16-bit immediate, size
  3), `(Pn+d)` (size 2), `a,(Pn+d)` / `(Pn+d),a` (size 4), `a,#` (size 4),
  `a,#w` (size 5). Today `SIZE={"":1,"#":2,"a":3}` plus special cases; the
  `LDP1 #` macro becomes a real opcode. The **on-target assembler**
  (`apps/p8xasm.asm`) must parse the same syntax — its opcode table is
  generated, its operand parser is not.
- `compiler/p8cc.py` — the §5 codegen (frame model, leaf-to-`__t`, the new
  emitters). This is the bulk of the work.
- `compiler/p8cc.c` and `apps/p8xcc.asm` — the self-hosting compilers must emit
  the new instructions too, or self-hosting silently regresses to the old,
  larger output. Sequence them after `p8cc.py` proves the design.
- Tests: `make test` end to end; `c_demo` (the CSTACKTOP check) becomes far
  less tight; a new codegen regression test per idiom.

**Tier B additionally:** regbank card (TTL) or one Verilog register (FPGA),
plus the `psel=6` decode in RTL; the emulator's pointer array grows by one.

**Risks and caveats to design around**

1. **Flag-latch → plane-select timing.** The C flag is latched at the end of
   the ALU step; the `fcond="C"` must be on the *following* step so the
   condition mux samples a settled flag, and the pair comes after that. Every
   listing above is written that way. Verify once on the emulator (it models the
   pipeline exactly) before trusting it on silicon.
2. **`CMPW` Z is high-byte-only.** C and N^V are correct for the full 16 bits;
   equality is not. Either the compiler keeps a separate `==` path (`SUBW` into
   a temp, then `OR` the two bytes), or add `EQW a,b` later (16 steps needed —
   over budget as one op; two ops or a T-accumulated OR would fit).
3. **`ZERO` uses a 74181 logic-mode code** (M=1, S=0011 → F=0). Check the
   emulator's 74181 model implements the full S table before relying on it.
4. **`A` is a clobber for the memory-to-memory forms** (`LDW/STW (Pn+d)`,
   `ADDW/SUBW/CMPW`, `INCW/DECW`, `ADDP3/SUBP3`). Acceptable for a compiler
   contract (p8cc holds nothing live in A across statements) and consistent
   with MOVW clobbering T/T2 — but hand-written asm must know. Document it on
   the ISA card.
5. **d8 is unsigned.** Frames must use positive offsets (§5). A signed variant
   is possible (sign-extend into the high-byte pair: `{DEC,PASSA}` when bit7
   set) at +2 steps; not needed if the frame layout is right.
6. **Step budget headroom.** `ADDW` is 14 of 15. Any "one more thing" in that
   family needs a second opcode, not a longer one.

**Suggested sequence**

1. Compiler-only wins first (signed compares on `BLT/BGE`, the leaf-to-`__t`
   restructure, a peephole pass) — measured against the whole `/bin` suite.
   Prerequisite work; ~10–15%.
2. Tier A in `genucode.py` + assembler shapes; prove each opcode with a
   per-instruction test in `test_isa.asm`; then the p8cc emitters. Recompile
   `/bin`, measure, `make test`.
3. Self-hosting compilers follow.
4. Tier B on the FPGA first (a register), TTL regbank card when it earns it.
5. Tier C when the accumulator model is the next wall.
