# ALU Card — Theory of Operation

The ALU card is the P8X's **datapath**. It holds the working registers
(A, B, T, T2), the 8-bit arithmetic/logic unit (two 74181s + a 74182 carry
look-ahead), a post-ALU **shifter**, and the **flag register** (C, Z, N, V). It is
where bytes are added, ANDed, shifted, and compared, and where the condition flags
that drive branches are produced.

> Source of truth: the `# ALU CARD` section of
> [`../../generators/gen_eagle.py`](../../generators/gen_eagle.py).

---

## 1. Inputs and outputs

### Inputs (from the backplane)

| Signal | Purpose |
|--------|---------|
| `D0–D7` | data bus — loads A/B/T/T2; also the source for Z/N-on-load and the bus zero-detect |
| `DLD0–3` | which register captures `D0–7` this clock |
| `DOE0–3` | which source drives `D0–7` (a register, the ALU result, or the flags) |
| `ALUS0–3`, `ALUM`, `CIN` | 74181 function select, mode (logic/arith), carry-in |
| `SH0`, `SH1`, `SHCIN` | shifter mode (none/left/right) and shift-carry-in select |
| `LDF`, `LDZN`, `SETC`, `CLRC` | load all flags / load just Z,N / force carry set / clear |
| `BSEL` | second-operand select: B register (0) or T register (1) |
| `CLK`, `-RES` | clock, reset (clears the flag register) |

### Outputs (to the backplane)

| Signal | Meaning |
|--------|---------|
| `D0–D7` | the selected register / ALU result / flag byte, when its DOE is asserted |
| `FC FZ FN FV` (bus A27–A30) | the four condition flags, consumed by the control card's condition mux |

---

## 2. Block diagram

```
              D0-7 (load)                                   D0-7 (load)
                 │                                              │
        ┌────────┴───────┬───────────┬───────────┐             │
        ▼ -LDA           ▼ -LDB      ▼ -LDT       ▼ -LDT2       │
   ┌─────────┐      ┌─────────┐  ┌─────────┐  ┌─────────┐       │
   │U1 A REG │      │U3 B REG │  │U5 T REG │  │U7 T2 REG│       │  (74377 latches)
   │ 74377   │      │ 74377   │  │ 74377   │  │ 74377   │       │
   └────┬────┘      └────┬────┘  └────┬────┘  └────┬────┘       │
        │AQ              │BQ          │TQ          │            │
        │           ┌────▼────────────▼───┐        │            │
        │           │U32/U33 B-MUX 74157  │◄BSEL   │            │
        │           │ BSEL=0→B  BSEL=1→T  │        │            │
        │           └──────────┬──────────┘        │            │
        │AQ0-7                 │BMX0-7              │            │
        ▼                      ▼                    │            │
   ┌─────────────────────────────────┐             │            │
   │ U9/U10 74181 (4-bit ×2)          │  ALUS,M,CIN │            │
   │ U11 74182 carry look-ahead       │◄────────────┘            │
   │   F0-7 result, Cn+4 carry-out    │                          │
   └───────────────┬─────────────────┘                          │
                   │F0-7                                         │
   ┌───────────────▼─────────────────┐  SH0,SH1                  │
   │ U12-U15 74157 SHIFTER (2 stages) │◄── + SHIN (shift-in mux U30, SHCIN)
   │ none / left / right              │                          │
   └───────────────┬─────────────────┘                          │
                   │R0-7                                         │
        ┌──────────▼─────────┐ -DOEALU      ┌────────────────┐   │
        │U16 74244 ALU OUT   ├──► D0-7      │ FLAG REGISTER  │   │
        └────────────────────┘              │ U17 74175 ZNV  │   │
                                            │ U26 7474   C   │◄LDF/LDZN/SETC/CLRC
   A/B/T/T2 OUT buffers (U2/U4/U6/U8,        │ U18/U27 Z-det  │   │
   74244, each gated by -DOEx)  ──► D0-7    │ U34/U35 V-calc │   │
                                            └───────┬────────┘   │
   DOE decode: U20 74138 (Y1-6)                     │ FQC/FQZ/FQN/FQV
   DLD decode: U21 74138                            ▼
                                          U23 74244 FLAG OUT ──► D0-7 (-DOEFLG)
                                                    └──────────► FC FZ FN FV (bus)
```

---

## 3. How it works

### 3.1 The working registers (U1/U3/U5/U7) and their output buffers
A, B, T, T2 are 74377 octal latches that capture `D0–7` when their load strobe
(`-LDA`/`-LDB`/`-LDT`/`-LDT2`, decoded from `DLD` by `U21`) is active on a `CLK`
edge. Each register also has a 74244 tristate **output buffer** (`U2/U4/U6/U8`)
that can drive its value back onto the data bus when the `DOE` field selects it.
The DOE decoder `U20` (74138) makes these mutually exclusive — only one of
`-DOEA/-DOEB/-DOET/-DOET2/-DOEALU/-DOEFLG` is ever low — so there is no contention
*on this card*.

### 3.2 Operand routing and the second-input mux (rev C)
The 74181 takes two 8-bit operands. The **A operand** is the A register, wired
straight to the 74181 A inputs (`AQ → U9/U10.A`). The **B operand** goes through
the rev-C B-mux `U32/U33` (74157): when `BSEL=0` it passes the B register, when
`BSEL=1` it passes T. The muxed result `BMX` feeds the 74181 B inputs. This is
what lets opcodes like `ADDT` compute `A := A + T` in one step without first
shuffling T through B — at the cost of one mux delay ahead of the carry path.

### 3.3 The ALU proper (U9, U10, U11)
Two 74181 4-bit ALUs (`U9` low nibble, `U10` high nibble) do the actual operation.
A 74181 is controlled by `S0–S3` (function), `M` (mode: `M=1` logic, `M=0`
arithmetic), and a carry-in. To make the two nibbles act as one fast 8-bit unit,
the carries are *not* rippled — instead `U11` (74182 carry look-ahead) takes the
nibble **propagate/generate** signals (`!P0/!G0`, `!P1/!G1`) and computes the
inter-nibble carry `CNX` directly, feeding `U10`'s carry-in. The final carry-out
`Cn+4` comes from `U10`. Unused 74182 groups 2/3 are tied off (`!P2/!G2/!P3/!G3` =
VCC).

The raw 74181 carry-out is active-low; rev B inverts it (a spare NAND in `U25`)
so the C flag is **conventional active-high** (C=1 means carry / unsigned ≥).

### 3.4 The shifter (U12–U15) and shift-in mux (U30)
The 8-bit ALU result `F0–7` passes through a two-stage shifter built from 74157
muxes (`U12/U13` stage 1, `U14/U15` stage 2), controlled by `SH0/SH1`: pass-through,
shift left, or shift right. The bit shifted *in* comes from `U30` (74157), which
selects between the carry-in `CIN` and the current carry flag (`FQC`) depending on
`SHCIN` — that is how `ROL`/`ROR` rotate *through* carry while `ASL`/`LSR` shift in
a fixed bit. The shifter output `R0–7` is the final datapath result, driven onto
the data bus by `U16` (74244) when `-DOEALU` is asserted.

### 3.5 The flag register (the subtle part)
Four flags, three storage elements:

- **Z and N** live in `U17` (74175). Their *source* is muxed by `U22` (74157,
  select = `LDZN`): normally Z/N come from the ALU result (zero-detect `U18`
  74260 over `R0–7`, and result bit 7 for N); but on a plain **load** the
  microcode asserts `LDZN` so Z/N instead reflect the *bus* byte (bus zero-detect
  `U27` 74260 over `D0–7`, and `D7`). That is how `LDA`/`LDB` set Z/N from the
  byte loaded, not from a stale ALU result.
- **V (overflow)** also lives in `U17`. It is computed combinationally (rev C) by
  the sign-bit method: `V = (A7 ^ F7) & (A7 ^ B7 ^ ~ALUS2)`, where `A7`=A sign,
  `B7`=muxed-B sign, `F7`=raw result sign, and `~ALUS2` distinguishes add-like
  from subtract-like ops. `U34` (74HCT86) does the XORs, `U35` (74HCT08) the AND,
  result `VSRC → U17.D3`. It is ungated by mode, so V is only *meaningful* right
  after ADD/SUB/CMP (a documented convention).
- **C** lives in its own `U26` (7474) so it can be force-set/cleared independently:
  `SETC`/`CLRC` drive its async preset/clear (via inverters in `U25`), `LDF` clocks
  it from the C-source mux `U29` (which picks the shifter carry-out when shifting,
  else the inverted 74181 carry).

`U17` is clocked by `CLK & (LDF | LDZN)` (`U31`) so flags update only on
flag-affecting microsteps; `-RES` clears it.

### 3.6 Flag output (U23)
All four flags (`FQC` from `U26`, `FQZ/FQN/FQV` from `U17`) feed `U23` (74244),
which both (a) drives the flag byte onto `D0–7` when `-DOEFLG` is asserted (so the
flags can be pushed/pulled, e.g. for interrupts), and (b) continuously drives the
dedicated bus flag lines `FC/FZ/FN/FV` (A27–A30) that the control card's condition
mux reads for branches.

---

## 4. Worked example — `CMP` then `BLT` (signed less-than)

1. **CMP A,B.** Microcode sets `ALUS`/`ALUM`/`CIN` for subtract, `BSEL=0` (B
   operand = B register), `LDF=1`. The 74181s compute `A − B`; `U18` flags zero,
   bit 7 gives N, `U34/U35` compute V, the carry mux gives C. On the clock edge the
   flag register latches C,Z,N,V. (The result `R0–7` is discarded — CMP doesn't
   write a register.)
2. **BLT.** The control card sets `FCOND=6`, so its condition mux selects
   `NV = FN ^ FV` (computed from the `FN`/`FV` bus lines this card is driving). If
   `N≠V` the branch microcode path loads a new PC; otherwise it falls through. The
   signed comparison works precisely because V was computed in step 1.

---

## 5. Known issues / verify (from the design review)

- **IC power pins:** built by the generator `card()` helper, which currently does
  not net IC VCC/GND supply pins to the pours — **fix before fab** (see BACKLOG).
- **Timing (bring-up):** the rev-C B-mux (`U32/U33`) adds a 74157 delay *ahead* of
  the 74181/74182 carry path, and the V-flag XOR/AND chain adds delay off the flag
  path. Confirm the worst-case combinational path (operand → B-mux → 74181 →
  74182 → carry → shifter → setup at the flag/result latch) fits the clock period;
  slow the clock during bring-up if needed.
- **V validity:** V is only meaningful after ADD/SUB/CMP (ungated by mode) — a
  software/microcode convention, not a hardware fault.
- Confirmed OK: DOE one-hot (no on-card bus contention), 74182 unused groups tied
  off, conventional-carry inversion, Z/N source muxing.

See [README.md](README.md) and [../../BACKLOG.md](../../BACKLOG.md).
