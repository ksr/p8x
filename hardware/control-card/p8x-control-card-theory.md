# Control / Microcode Card — Theory of Operation

The control card is the **brain stem** of the P8X. It generates the system clock,
the reset, and the run/halt/single-step controls; it holds the instruction
register and the four microcode EPROMs; and every clock it emits the 32-bit
**control word** that tells all the other cards what to do. Nothing on any other
card moves without a signal that originated here.

> Source of truth: the netlist in [`../../generators/gen_eagle.py`](../../generators/gen_eagle.py)
> (the `# CONTROL / MICROCODE CARD` section). This document explains *why* it is
> wired the way it is. For the bit layout of the control word see
> [GLOSSARY.md](../../GLOSSARY.md) and [p8x-system-design.md](../../docs/p8x-system-design.md) §3.2.

---

## 1. Role in the machine

The P8X is **microcoded**: each opcode is implemented as a short sequence of
"microsteps," and on every microstep a 32-bit control word drives the datapath.
The control card is a tiny state machine whose only job is to present the right
control word at the right time:

```
            opcode (IR) ─┐
   microstep number ─────┼──► address ──► [4× microcode EPROM] ──► 32-bit word
   branch condition ─────┘                                            │
                                                          [pipeline latches]
                                                                      │
                                       ───────────── backplane ───────┴────────►
                                       DOE DLD PSEL ALUS ALUM CIN SH LDF FCOND …
```

It is purely combinational + two counters; it has **no opinion** about what the
opcodes mean — that knowledge lives entirely in the EPROM contents (built by
`microcode/genucode.py`).

---

## 2. Inputs and outputs

### Inputs (from the backplane unless noted)

| Signal | Source | Purpose |
|--------|--------|---------|
| `D0–D7` | data bus | the opcode byte, captured into the instruction register during fetch |
| `FC FZ FN FV` | ALU card (bus A27–A30) | the four condition flags, fed to the condition mux for branches |
| `IRQ` | bus B29 (rev C) | interrupt request line → the DNP interrupt latch (U21) |
| `X1` | on-card 4 MHz can oscillator | the master timebase |
| `SWR SWS SWT` | on-card pushbuttons | RUN/HALT, single-STEP, RESET |
| `JP1` | on-card jumper | selects raw / ÷2 / ÷4 clock |

### Outputs (to the backplane)

| Signal(s) | Destination | Meaning |
|-----------|-------------|---------|
| `CLK` | every clocked card | the system clock |
| `CLKB` | pipeline + ALU/IO | a buffered/phased copy used to latch the pipeline |
| `-RES` | all cards | active-low reset |
| `DOE0–3` | all driver cards | **D**ata-bus **O**utput **E**nable select (who drives D0–7) |
| `DLD0–3` | all latch cards | **D**ata **L**oa**D** select (who captures D0–7) |
| `PSEL0–2` | register bank | which pointer is active |
| `PINC PDEC` | register bank | increment / decrement the active pointer |
| `ALUS0–3 ALUM CIN` | ALU card | ALU function, mode, carry-in |
| `SH0 SH1 SHCIN` | ALU card | shifter mode + shift-carry-in select |
| `LDF LDZN SETC CLRC` | ALU card | flag-load / Z,N-load / set-carry / clear-carry |
| `BSEL` | ALU card | second-operand mux (B register vs T) |
| `FCOND0–2` | (consumed on-card) | which condition the branch tests |
| `URST` | (on-card) + step counter | "micro-reset": end the instruction, return to fetch |
| `HALT` | (status) | stop the clock |

---

## 3. Block diagram

```
   4MHz                                        ┌──────────── D0-7 (opcode) ───────────┐
  ┌─────┐  OSCO   ┌────────┐ DIVQA/B  ┌────┐   ▼                                       │
  │ X1  ├────────►│U1 74161├─────────►│JP1 │  ┌───────────┐ IRQ0-7 (A0-7)              │
  │ OSC │         │  ÷2 ÷4 │          │ sel│  │U7 74377 IR├──────────────┐            │
  └─────┘         └────────┘          └─┬──┘  └───────────┘              │            │
                                  CLKRAW │       ▲  -IRLD                 ▼            │
   RUN/HALT  STEP   RESET                │       │                ┌──────────────┐    │
   SWR        SWS    SWT                 │   ┌───┴────┐           │ U10..U13     │    │
    │          │      │ RC(R1,C1)        │   │U8 74138│◄DLD0-3    │ 4× 28C64     │    │
    ▼          ▼      ▼                  │   │ DLD dec│           │ microcode    │    │
  ┌─────────────────────┐  CLKEN  ┌──────┴┐  └────────┘           │ EPROM        │    │
  │ U3 7474  U2 HEX14   ├────────►│U5 AND ├──► CLK ───────────────┤ (32-bit out) │    │
  │ U4 NAND  U6 OR      │         │ gate  │   CLKB                │              │    │
  │ run/halt/step/reset │         └───────┘                       └──────┬───────┘    │
  └─────────┬───────────┘                  ┌─────────┐ SQ0-3 (A8-11)     │            │
            │ -RES                          │U18 74161│──────────────────┤            │
            └──────────────────────────────►│STEP CNT │  CONDY (A12)     │            │
                          -USTL (from URST) │  0..15  │      ▲           │            │
                                            └─────────┘      │           ▼            │
   FC FZ FN FV ──► ┌──────────┐  NV ┌────┐ ┌────────┐  ┌──────────────────────┐      │
   (from ALU)      │U19 XOR   ├────►│U6  ├►│U9 74151│  │ U14..U17 4× 74374    │      │
                   │ N^V      │ NVZ │OR  │ │COND MUX│  │ PIPELINE LATCHES     │      │
                   └──────────┘     └────┘ └───┬────┘  │ (latch on CLKB)      │      │
                                    FCOND0-2 ──┘       └──────────┬───────────┘      │
                                                                  ▼ control word     │
                            ══════════ backplane ═══════ DOE DLD PSEL ALUS … BSEL ═══╧═══►
```

---

## 4. How it works, subsystem by subsystem

### 4.1 Clock generation (X1, U1, JP1, U5)
The 4 MHz can oscillator `X1` feeds `OSCO`, which goes both to the divider `U1`
(a 74161 counter wired free-running: `ENP=ENT=!LOAD=VCC`, `!CLR=-RES`) and to the
clock-select jumper `JP1`. `U1` produces `DIVQA` (÷2) and `DIVQB` (÷4); `JP1`
picks raw `OSCO`, `÷2`, or `÷4` and calls the result `CLKRAW`. Starting slow is a
classic bring-up tactic — you can single-step or run at a few hundred kHz while
debugging before trusting full speed.

`CLKRAW` is gated by the run/halt logic into the live system clock `CLK`
(`U5.1Y`), which fans out to the IR (`U7`), the step counter (`U18`), and the
backplane. A buffered/inverted copy `CLKB` (`U2.6Y`, a hex-inverter stage) is the
**pipeline latch clock** and also goes to the ALU/IO cards. `CLKB` is deliberately
a half-cycle relative to `CLK` so the pipeline registers the freshly-addressed
microcode word for the *next* phase (see §5).

### 4.2 Reset (SWT, R1/C1, U2)
The RESET button `SWT` with RC network `R1/C1` produces a slow `RSTRAW` edge,
cleaned by two Schmitt-trigger inverter stages in `U2` (`4A→4Y`, `5A→5Y`) into
the clean active-low `-RES`. `-RES` clears the clock divider, the run/halt FF, and
the step counter, and is broadcast to every card.

### 4.3 Run / Halt / Single-step (SWR, SWS, U2, U3, U4, U6)
This is the trickiest little circuit on the card. `U3` (a dual 7474 D-FF) and
gates in `U2/U4/U6` form:
- a **run/halt latch** toggled by the RUN/HALT button (`SWR` → `RUND` → `U3.1D`),
  whose output `RUNQ` gates the clock via `CLKEN` (`U6.1Y → U5.1B`);
- a **one-pulse single-step** path: the STEP button (`SWS`) is synchronized by
  `U3.2` (clocked by the *free-running* `CLKRAW`, not the gated `CLK` — that is
  what lets a single pulse get through while the system clock is otherwise
  stopped) and self-clears via `STEPCLR` (`U4.1Y → U3.!2CLR`).

The LEDs `LED4`/`LED5` show RUN and HALT state.

> **Verify (already tracked):** the one-pulse single-step needs bench
> confirmation that exactly one `CLK` edge is released per press (refine the
> debounce RC if it double-steps). The topology — synchronizer clocked from
> `CLKRAW` — is correct.

### 4.4 Instruction register (U7)
`U7` (a 74377 octal register) captures the opcode from `D0–D7` when the microcode
asserts the load-IR strobe `-IRLD`. `-IRLD` is `U8.Y6` — i.e. it appears when the
`DLD` field of the control word decodes to 6 (the fetch microstep ends by loading
the IR). The IR outputs `IRQ0–IRQ7` become the low 8 address bits of every
microcode EPROM.

### 4.5 The microcode store (U10–U13) — the heart
Four 28C64 EPROMs (8 KB each) share a 13-bit address bus:

```
   A0..A7   = IRQ0..7   (the opcode in IR)         256 opcodes
   A8..A11  = SQ0..3    (the microstep, 0..15)      16 steps
   A12      = CONDY     (the selected branch flag)   2 condition planes
```

So the address is exactly `opcode | step<<8 | cond<<12` — identical to what
`genucode.py` writes when it builds the images, which is why the same `u0–u3.bin`
run on the emulator and the silicon. Each EPROM contributes 8 bits, so the four
together output the full **32-bit control word** in parallel. `!CE`/`!OE` are
tied active and `!WE` tied high (read-only).

The two condition planes (A12 = 0 or 1) let a single microstep branch: the
microcode author stores one control word at `cond=0` and a different one at
`cond=1`, and `CONDY` picks which fires this cycle.

### 4.6 Step counter (U18)
`U18` (74161) is the microstep sequencer. It counts 0,1,2,… on each `CLK`. It is
cleared by `-RES` and **reloaded to 0** by `-USTL` whenever the control word
asserts `URST` (`U4` gates `URST → -USTL → U18.!LOAD`). `URST` is the microcode's
way of saying "this instruction is finished — go back to step 0 (fetch)." So an
instruction is "however many steps until the microcode asserts URST."

### 4.7 Condition mux (U9) and signed-compare logic (U19, U6)
`U9` (74151 8:1 mux) selects which condition `CONDY` reflects, chosen by
`FCOND0–2`:

| FCOND | Input | Condition |
|-------|-------|-----------|
| 0 | `D0`=GND | never |
| 1 | `D1`=VCC | always |
| 2 | `FC` | carry / unsigned ≥ |
| 3 | `FZ` | zero / equal |
| 4 | `FN` | negative |
| 5 | `FV` | overflow |
| 6 | `NV` = `FN^FV` (U19) | signed `<` |
| 7 | `NVZ` = `NV \| FZ` (U6) | signed `≤` |

The XOR `U19` and the spare OR gate in `U6` synthesize the signed-comparison
conditions added in rev C. `CONDY` becomes EPROM address line A12.

### 4.8 Pipeline latches (U14–U17)
The 32-bit EPROM output is captured into four 74374 octal latches on `CLKB`, and
their outputs are the actual control-word signals broadcast to the backplane. The
bit→latch mapping is the `PIPE` dict in the generator and **must** match
`genucode.py`'s bit numbering exactly (it does). This one register stage is the
machine's pipeline: while the datapath acts on cycle *N*'s control word, the EPROMs
are already settling on cycle *N+1*'s.

### 4.9 Interrupt footprints (U20, U21 — DNP)
`U20` (74244 "forcing buffer") and `U21` (7474 IE/pending FF) are placed but **not
populated**. Only the safe connections exist: `U20`'s inputs carry the fixed `$08`
pattern, its outputs are forced high-Z (`!G1=!G2=VCC`), and the `IRQ` bus line
reaches `U21.1D`. The bus-critical wiring (driving `$08` onto the data bus, the
service sequencer, EI/DI/RTI decode, and memory-read suppression) is intentionally
absent — see the card README and BACKLOG for why this must be designed with
DRC/breadboard first.

---

## 5. Worked example — one instruction

Trace a generic instruction at full speed:

1. **Fetch (step 0).** The microcode word for `(opcode=anything, step=0)` drives
   `PSEL`=PC, `DOE`=memory-read, so the memory card puts the byte at PC on `D0–7`;
   `DLD`=6 so `U8.Y6` asserts `-IRLD`. On the `CLK` edge `U7` latches the opcode;
   `PINC` increments the PC.
2. **Address update.** The new IR value re-addresses the EPROMs (A0–7); the step
   counter has advanced to 1 (A8–11). The EPROMs output the step-1 word; `CLKB`
   latches it into the pipeline.
3. **Execute (steps 1..k).** Each step's word steers the register bank, ALU, and
   memory. Branch steps set `FCOND` so `CONDY` (A12) selects between two stored
   words — e.g. a taken vs not-taken branch.
4. **Retire.** The last microstep asserts `URST`; `-USTL` reloads the step counter
   to 0, and we are back at fetch for the next opcode.

---

## 6. Known issues / verify (from the design review)

- **IC power pins:** *fixed* — the `card()` helper now connects every IC's
  dedicated VCC/GND supply pin to the power pours (the review found it previously
  wired only functional pins and the decoupling caps). Verified: every IC on this
  card has both rails. (The memory card's original hand-wired power pins were the
  reference for the fix; it is now `card()`-built too.)
- **Single-step one-pulse:** bench-verify one edge per press (§4.3).
- **Pipeline timing:** confirm the microcode EPROM access time fits inside the
  `CLK`→`CLKB` half-cycle at the intended clock rate; if not, slow the clock with
  `JP1` or add a wait state.
- **IRQ controller (U20/U21):** DNP; do not populate until the bus-drive path is
  designed with DRC (§4.9).

See [README.md](README.md) for the chip-by-chip parts list and
[../../BACKLOG.md](../../BACKLOG.md) for the live issue list.
