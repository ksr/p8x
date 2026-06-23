# P8X Bus Definition — Rev C2

This document is the authoritative human-readable description of the P8X backplane
bus. The machine-authoritative source is the `busnet()` function in
`generators/gen_eagle_full.py`; the PDF rendering of this same table is generated
by `generators/gen_bus_pdf.py`. When any conflict exists, trust the generator code.

---

## 1. Physical Interface

| Item | Spec |
|---|---|
| Connector | DIN 41612, 96-pin, 3 rows (A / B / C), 32 pins per row |
| Backplane | 10 slots, 25.4 mm (1") pitch |
| Card edge | Male right-angle DIN 41612; row A nearest board surface |
| Mating orientation | VERIFY against physical connectors before first fab |

Rows A and C carry signals. Row B is mostly ground guard between them, but B3–B26
now **alternate**: the odd pins (B3,B5,…,B25) stay GND (a guard between each
signal pair), and the even pins (B4,B6,…,B26) are **spare bus lines SPARE12–SPARE23**
— routed slot-to-slot so they can be used later without re-spinning the backplane.
B27 (CLRC), B28 (BSEL), B29 (IRQ) and B30 (SPARE11) are unchanged.

---

## 2. Pin Map

Pins 1–2 are power; pins 31–32 are ground. Signals occupy pins 3–30.

| Pin | Row A | Row B | Row C |
|-----|-------|-------|-------|
| 1 | +5V | +5V | +5V |
| 2 | +5V | +5V | +5V |
| 3 | D0 | GND | A0 |
| 4 | D1 | SPARE12 | A1 |
| 5 | D2 | GND | A2 |
| 6 | D3 | SPARE13 | A3 |
| 7 | D4 | GND | A4 |
| 8 | D5 | SPARE14 | A5 |
| 9 | D6 | GND | A6 |
| 10 | D7 | SPARE15 | A7 |
| 11 | -RES | GND | A8 |
| 12 | DOE0 | SPARE16 | A9 |
| 13 | DOE1 | GND | A10 |
| 14 | DOE2 | SPARE17 | A11 |
| 15 | DOE3 | GND | A12 |
| 16 | DLD0 | SPARE18 | A13 |
| 17 | DLD1 | GND | A14 |
| 18 | DLD2 | SPARE19 | A15 |
| 19 | DLD3 | GND | ALUS0 |
| 20 | PSEL0 | SPARE20 | ALUS1 |
| 21 | PSEL1 | GND | ALUS2 |
| 22 | PINC | SPARE21 | ALUS3 |
| 23 | PDEC | GND | ALUM |
| 24 | CLK | SPARE22 | CIN |
| 25 | CLKB | GND | SH0 |
| 26 | LDF | SPARE23 | SH1 |
| 27 | FC | CLRC | PSEL2 |
| 28 | FZ | BSEL | LDZN |
| 29 | FN | IRQ | SHCIN |
| 30 | FV | SPARE11 | SETC |
| 31 | GND | GND | GND |
| 32 | GND | GND | GND |

**Notes:**
- A27–A30 were reallocated from SPARE0–3 to flag lines FC/FZ/FN/FV (rev C2).
  SPARE numbering therefore starts at 4. There are no SPARE0–3.
- B3–B26 alternate: odd pins = GND (ground guard between signal pairs), even
  pins = SPARE12–SPARE23 (12 spare bus lines, routed slot-to-slot for future use
  without a backplane re-spin).
- rev C3 allocated the rev-B control signals: C27–C30 = PSEL2/LDZN/SHCIN/SETC
  (were SPARE4–7) and B27 = CLRC (was SPARE8). rev C added B28 = BSEL (ALU
  B-input mux select, was SPARE9). rev C also took B29 = IRQ (interrupt request,
  was SPARE10); SPARE11 remains on B30.

---

## 3. Signal Descriptions

### 3.1 Data Bus — D0–D7

8-bit bidirectional data bus. At all times, exactly **one** card drives it or
it is idle (high via backplane pull-up RN1, 10 kΩ × 8). The driving card is
selected by the one-hot DOE field decode. Never drive D0–D7 from a bare
output; always use a tri-state buffer enabled by the card's assigned DOE code.

### 3.2 Address Bus — A0–A15

16-bit address bus, input-only to every card except the register bank. The
address is always driven by one of the four 16-bit pointer registers (74169
counters) selected by PSEL0–1:

| PSEL1 | PSEL0 | Pointer | Role |
|-------|-------|---------|------|
| 0 | 0 | P0 | Program Counter (PC) |
| 0 | 1 | P1 | General-purpose pointer |
| 1 | 0 | P2 | General-purpose pointer |
| 1 | 1 | P3 | Stack Pointer (SP) — empty-descending |

### 3.3 DOE — Data Output Enable (4-bit field, A12–A15)

Selects which resource drives D0–D7 this microcycle. One-hot decoded per card
(74138). The field is 4 bits; codes 10–15 are reserved.

| Code | Bus Source |
|------|-----------|
| 0 | Idle (bus released; backplane pull-up holds high) |
| 1 | A register |
| 2 | B register |
| 3 | T (hidden temp) |
| 4 | T2 (hidden temp) |
| 5 | ALU result (via shifter) |
| 6 | FLAGS register |
| 7 | MEM read (memory or I/O, from addressed location) |
| 8 | PTRL — selected pointer, low byte |
| 9 | PTRH — selected pointer, high byte |
| 10–15 | Reserved |

### 3.4 DLD — Data LoaD (4-bit field, A16–A19)

Selects which register or destination latches D0–D7 on the rising CLK edge
(or issues a write strobe for MEMW). One-hot decoded per card (74138). Codes
10–15 are reserved.

| Code | Destination |
|------|-------------|
| 0 | None (no load) |
| 1 | A register |
| 2 | B register |
| 3 | T (hidden temp) |
| 4 | T2 (hidden temp) |
| 5 | FLAGS (restore from bus — not a computed flag update) |
| 6 | IR (instruction register) |
| 7 | MEMW — write strobe (memory or I/O) |
| 8 | PTRL — load selected pointer low byte |
| 9 | PTRH — load selected pointer high byte |
| 10–15 | Reserved |

### 3.5 Pointer Control — PSEL0–1, PINC, PDEC

| Signal | Description |
|--------|-------------|
| PSEL0, PSEL1 | Select which pointer (P0–P3) drives the address bus and is the target of PINC/PDEC/PTRL/PTRH operations |
| PINC | Increment the selected pointer after this microcycle |
| PDEC | Decrement the selected pointer after this microcycle |

### 3.6 ALU Control — ALUS0–3, ALUM, CIN

These lines connect the control card's microcode ROM output directly to the
74181 ALU on the ALU card.

| Signal | Description |
|--------|-------------|
| ALUS0–3 | 74181 function select (S0–S3) — selects one of 16 arithmetic/logic operations |
| ALUM | 74181 mode: 0 = arithmetic, 1 = logic |
| CIN | Carry input to 74181 (Cn pin, **active-low** — CIN=1 means carry-in=0) |

### 3.7 Shift Control — SH0, SH1

| Signal | Description |
|--------|-------------|
| SH0 | Shift left: rotate ALU result one bit left before presenting to data bus |
| SH1 | Shift right: rotate ALU result one bit right before presenting to data bus |

Only one of SH0/SH1 should be asserted at a time. Both zero = pass-through.

### 3.8 Flag Lines — FC, FZ, FN, FV (formerly SPARE0–3)

Four flag bits driven by the ALU card to the control card's condition
multiplexer. Allocated from what was SPARE0–3 in rev C1.

| Signal | Flag | Polarity |
|--------|------|----------|
| FC | Carry | **Active-low** — latches raw 74181 Cn+4 (1 = no carry out). See note below. |
| FZ | Zero | Active-high — 1 when ALU result is all-zeros |
| FN | Negative | Active-high — 1 when bit 7 of ALU result is set |
| FV | Overflow | Hardwired 0 in rev A (V flag unimplemented on ALU card) |

**C flag polarity note (deliberate hardware quirk):** The flag register latches
the raw 74181 Cn+4 output pin, which asserts low on carry. FC=1 therefore means
*no carry out*. The emulator reproduces this exactly. Do not invert it — this is
a VERIFY item in BACKLOG.md (add inverter in rev B vs. adopt as the convention).

### 3.9 Clock — CLK, CLKB

| Signal | Description |
|--------|-------------|
| CLK | System clock. Registers and IR latch on the **rising edge**. |
| CLKB | Complement of CLK. Write strobes (MEMW) are gated with CLKB so address/data settle in the first half-cycle and the write strobe fires in the second. |

CLK and CLKB receive special layout treatment: guard traces on each side on
the backplane; optionally a 33 Ω series resistor at the driver on the control
card. AC termination footprints (RT1/CT1, RT2/CT2: 100 Ω + 150 pF to GND at
the far slot) are provided DNP — populate only if ringing observed on scope.

### 3.10 LDF — Load Flags

When asserted, causes the FLAGS register to latch the ALU result flags (C, Z, N)
at the end of the microcycle. This is distinct from DLD=FLAGS (code 5), which
restores FLAGS from the data bus.

### 3.11 -RES — Reset (active-low)

System reset, active-low. Drives all cards to a known state. The control card
generates -RES from the front-panel reset button and power-on RC circuit.

### 3.12 rev-B/C control signals (PSEL2, LDZN, SHCIN, SETC, CLRC, BSEL), IRQ and SPARE11

Allocated from spares in rev C3 (and rev C for BSEL) to carry the rev-B/C
microcode-word additions, all driven by the control card's pipeline latches:

| Signal | Pin | Consumer | Function |
|--------|-----|----------|----------|
| PSEL2 | C27 | Reg-bank | 3rd pointer-select bit (P0–P3 + PT scratch=4) |
| LDZN | C28 | ALU | Latch Z,N from the data bus on loads (without touching C/V) |
| SHCIN | C29 | ALU | Shifter shift-in = current C flag (rotate through carry) |
| SETC | C30 | ALU | Force C = 1 (SEC) |
| CLRC | B27 | ALU | Force C = 0 (CLC) |
| BSEL | B28 | ALU | ALU B-input mux select: 0 = B register, 1 = T register (microcode word bit 31, pipe U17.Q8; drives ALU-card U32/U33) |
| IRQ | B29 | Control | Maskable interrupt request (rev C, reserved). Any card may pull it; the control-card interrupt controller (DNP footprints U20/U21) samples it. The controller circuit is not yet built — see BACKLOG. |

SPARE11 (B30) remains bused across all 10 slots, reserved; no card may use it
without a formal allocation recorded here.

---

## 4. Microcode Word Layout

Each microcode word is 32 bits wide, stored across four 28C64 EEPROMs
(u0.bin–u3.bin, 8 bits each). The ROM address is:

```
A[7:0]  = IR (instruction register)
A[11:8] = microstep (0–15)
A[12]   = condition flag selected by FCOND of the *previous* step (pipeline)
```

Step 0 of every opcode is the fetch cycle: MEM@P0 → IR, P0+.

Layout updated for rev B (3-bit PSEL + new flag/shift control bits):

| Bits | Field | Description |
|------|-------|-------------|
| 3:0 | DOE | Data output enable (see §3.3) |
| 7:4 | DLD | Data load destination (see §3.4) |
| 10:8 | PSEL | Pointer select (3 bits: P0–P3 + PT scratch = 4) |
| 11 | PINC | Pointer increment |
| 12 | PDEC | Pointer decrement |
| 16:13 | ALUS | ALU function select S0–S3 |
| 17 | ALUM | ALU mode (0=arithmetic, 1=logic) |
| 18 | CIN | Carry input (active-low pin, passed to 74181 Cn) |
| 19 | SH0 | Shift left |
| 20 | SH1 | Shift right |
| 21 | LDF | Load all four flags from the ALU result |
| 24:22 | FCOND | Selects which flag drives A12 for the *next* ROM lookup |
| 25 | URST | Micro-step reset (return to step 0 = next fetch) |
| 26 | HALT | Halt the clock |
| 27 | LDZN | Latch Z,N only, from the loaded byte (loads set flags) |
| 28 | SHCIN | Shifter shift-in = C flag (rotate through carry) |
| 29 | SETC | Force C = 1 |
| 30 | CLRC | Force C = 0 |
| 31 | — | Reserved |

The C flag is **conventional active-high** in rev B (C=1 = carry-out / A≥B); the
ALU card inverts the raw 74181 Cn+4 pin. SETC/CLRC force the C latch directly.

FCOND encoding: 0=C, 1=Z, 2=N, 3=V (selects which flag pin drives A12).

---

## 5. Memory Map

| Range | Device | Notes |
|-------|--------|-------|
| $0000–$3FFF | EEPROM (28C256, low 16 KB) | ROM monitor + ROM BASIC (rev D) |
| $4000–$FEFF | SRAM (2× 62256) | General RAM, 48 KB (rev D) |
| $FF00 | I/O: switches | Read |
| $FF02 | I/O: LEDs | Write |
| $FF04–$FF05 | I/O: ACIA (6850) | $FF04=control/status, $FF05=data |
| $FF10–$FF17 | I/O: CF-IDE | 8-bit mode, memory-mapped |

I/O decode: address bits A8–A15 all high ($FFxx). Sub-decoded by 74138 on
the I/O card. Cards must register their I/O address allocation in this
document before building.

---

## 6. Bus Protocol Summary

1. At the start of each microcycle the control card presents DOE, DLD, PSEL,
   PINC, PDEC, ALUS, ALUM, CIN, SH0, SH1, LDF, URST from the microcode ROM.
2. The addressed pointer drives A0–A15.
3. The DOE-selected card tri-states D0–D7 with the appropriate data.
4. On the **rising CLK edge**: the DLD-selected register latches D0–D7; if
   LDF is set, FLAGS latches ALU result flags.
5. If PINC/PDEC: the selected pointer increments/decrements after the clock edge.
6. If URST: the microstep counter resets to 0 (next cycle is a fetch).
7. The FCOND field of this step selects which flag drives A12 for the *next*
   ROM lookup (condition pipeline — the branch decision for the following step).
8. Write cycles (DLD=MEMW): the card uses CLKB as a write strobe so data/address
   are stable before the strobe asserts.

---

## 7. DOE/DLD Code Allocation by Card

| Card | DOE codes used | DLD codes used |
|------|---------------|----------------|
| Register bank | 1 (A), 2 (B), 8 (PTRL), 9 (PTRH) | 1 (A), 2 (B), 8 (PTRL), 9 (PTRH) |
| ALU card | 5 (ALU result) | — |
| Control card | 3 (T), 4 (T2), 6 (FLAGS) | 3 (T), 4 (T2), 5 (FLAGS restore), 6 (IR) |
| Memory / I/O | 7 (MEM read) | 7 (MEMW write) |
| All | 0 (idle) | 0 (none) |

---

## 8. Revision History

| Rev | Date | Change |
|-----|------|--------|
| A | — | Initial bus definition |
| B | — | Signal positions established; B2 tied GND (incompatible with rev C) |
| C | — | Power rearranged: 6×+5V top (A1–C2), 6×GND bottom (A31–C32); row B3–B26 full GND guard |
| C1 | — | SPARE0–3 on A27–A30 |
| C2 | 2026-06 | A27–A30 reallocated to FC/FZ/FN/FV; SPARE8–11 opened on B27–B30; eight official spares (SPARE4–11) |
| C3 | 2026-06 | rev-B control signals allocated: C27–C30 = PSEL2/LDZN/SHCIN/SETC, B27 = CLRC (were SPARE4–8); SPARE9–11 remain on B28–B30 |
| C  | 2026-06 | 2nd ALU-input mux added: B28 = BSEL (was SPARE9), ALU B-side selects B reg / T reg; SPARE10–11 remain on B29–B30 |
| C  | 2026-06 | Interrupt support: B29 = IRQ (was SPARE10); control-card controller provisioned as DNP footprints (U20/U21); SPARE11 remains on B30 |
