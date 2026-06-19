# Backplane — Theory of Operation

The backplane is the P8X's **passive motherboard**: ten 96-pin DIN 41612 slots
wired in parallel, plus power distribution, data-bus pull-ups, clock termination
(provisioned but DNP), and decoupling. It contains **no active logic** — every
slot sees the same bus, and the cards plugged into it do all the work. Its theory
of operation is therefore mostly about the **bus pinout**, **signal integrity**,
and **power**.

> Source of truth: the `# BACKPLANE` section and the `busnet()` pin-mapping
> function in [`../../generators/gen_eagle.py`](../../generators/gen_eagle.py).
> Authoritative pinout + signal descriptions: [p8x-bus-definition.md](p8x-bus-definition.md).

---

## 1. Inputs and outputs

| | |
|---|---|
| **Input** | +5 V / GND at the power terminal `J11` |
| **Outputs** | the full 96-pin bus, presented identically at all 10 slots |

The backplane neither drives nor consumes logic signals; it *connects* them. "Who
drives what" is decided entirely by the cards (see the per-card theory docs).

---

## 2. The 96-pin bus map (`busnet()`)

A DIN 41612 connector has three rows (A, B, C) × 32 pins. The mapping:

```
  Pins 1,2  (all rows) ──► VCC          Pins 31,32 (all rows) ──► GND

  ROW A                     ROW C                     ROW B
  ─────                     ─────                     ─────
  A3..A10  = D0..D7         C3..C18 = A0..A15         B1,2  = VCC
  A11      = -RES           C19..22 = ALUS0..3        B31,32= GND
  A12..15  = DOE0..3        C23     = ALUM            B27   = CLRC
  A16..19  = DLD0..3        C24     = CIN             B28   = BSEL  (rev C)
  A20,21   = PSEL0,1        C25,26  = SH0,SH1         B29   = IRQ   (rev C)
  A22      = PINC           C27     = PSEL2           B30   = SPARE11
  A23      = PDEC           C28     = LDZN            B4,6,..26 = SPARE12..23
  A24      = CLK            C29     = SHCIN                       (even pins)
  A25      = CLKB           C30     = SETC            B3,5,..25 = GND guard
  A26      = LDF            (spares: SPARE4..)                    (odd pins)
  A27..30  = FC,FZ,FN,FV
```

Three observations explain the layout:
- **Row B alternates ground guard and spare.** Apart from the control lines
  (B27–B30), B3–B26 alternate: odd pins are GND, even pins are spare bus lines
  (SPARE12–23). The interleaved ground pins still sit between most A/C signal
  pairs to limit crosstalk, while the 12 spares give room to add signals later
  without re-spinning the backplane. (A solid ground guard on all of B3–B26 would
  shield slightly better — the trade was made deliberately for expansion room.)
- **The data bus (A3–A10) and address bus (C3–C18) are on opposite rows**, again
  to keep the two busiest buses apart.
- **The flags (FC/FZ/FN/FV on A27–30)** travel from the ALU card to the control
  card's condition mux; the **control word** fields (DOE/DLD/PSEL/ALUS/…) fan out
  from the control card to everyone.

Because the slots are wired in parallel, a card in *any* slot sees the same
signals — slot position is electrically irrelevant (mechanical layout aside).

---

## 3. Block diagram

```
        +5V ─► J11 ─┬─ CB1/CB2 470µF bulk ─┬───────── VCC rail ───────────────┐
                    │                       │                                  │
                    │   per-slot 100nF: C1..C10 across VCC/GND at each slot    │
                    ▼                                                          ▼
   ┌────────┐  ┌────────┐  ┌────────┐            ┌────────┐    RN1 8×10k pull-ups
   │ SLOT 1 │  │ SLOT 2 │  │ SLOT 3 │   ...      │ SLOT 10│    on D0..D7 ─► VCC
   │  J1    │══│  J2    │══│  J3    │════════════│  J10   │
   └────────┘  └────────┘  └────────┘            └────────┘
        ║           ║           ║      (every pin bused in parallel)
        ╚═══════════╩═══════════╩═══════ 96-pin DIN 41612 bus ═══════════════►

   CLK  ─► RT1 100R + CT1 150p  (AC termination at far slot, DNP)
   CLKB ─► RT2 100R + CT2 150p  (AC termination at far slot, DNP)
   RL1 1k + LED1  = power indicator
```

---

## 4. How it works

### 4.1 Power distribution
+5 V enters at terminal block `J11` onto the VCC rail; GND likewise. Two 470 µF
electrolytics (`CB1/CB2`) provide **bulk** charge near the entry for the whole
backplane, and a 100 nF ceramic (`C1–C10`) sits across VCC/GND **at every slot** so
each card has local high-frequency bypass right at its connector. (Each card *also*
carries its own per-IC decoupling — see the card standards.) `LED1` (via `RL1`)
indicates power-on.

### 4.2 Data-bus pull-ups (RN1)
The data bus is tri-stated most of the time (whichever card has its `DOE`/read
enable drives it; otherwise nobody does). To keep `D0–7` from floating to
indeterminate levels between drivers, `RN1` (an 8×10 kΩ network, common to VCC)
gently pulls every data line high. 10 kΩ is weak enough not to fight any active
driver but strong enough to define the idle level — this is why a read of an
unmapped address returns `$FF` rather than garbage.

### 4.3 Clock termination (RT1/CT1, RT2/CT2 — DNP)
`CLK` and `CLKB` are the fastest, most-loaded nets — they reach a clocked chip on
nearly every card across the whole length of the board, so they are the most prone
to reflections/ringing. Series-RC **AC termination** (100 Ω + 150 pF) is
provisioned at the *far* slot for each clock, but shipped **DNP**: whether it is
needed depends on the real edge rates and trace length, which you measure on a
scope at bring-up. (A Thévenin termination was rejected because HCT inputs sit near
mid-rail and would draw steady current; AC termination only acts on edges. Only
the clocks are terminated — the slower bused signals don't warrant it.)

### 4.4 Why passive
There is deliberately no logic on the backplane: keeping it passive means it can
never be the cause of a logic bug, it's cheap, and it's the natural place to do the
analog things (power, bypass, termination, pull-ups) that don't belong on any one
functional card. It's the cheapest board to fabricate first as a validation
article.

---

## 5. Signal flow summary

There is no sequencing here — every signal is continuous and bidirectional across
all slots. A useful mental model of one bus cycle:

1. The **control card** drives `CLK`, `CLKB`, `-RES`, and the **control word**
   (DOE/DLD/PSEL/ALUS/…) onto the bus → reaches all slots.
2. The **register bank** drives the **address bus** (C3–C18) from the selected
   pointer → reaches the memory/I/O/CF cards.
3. Exactly one card (selected by `DOE` + address decode) drives the **data bus**
   (A3–A10); the `RN1` pull-ups hold it at `$FF` if none does.
4. The **ALU card** drives the **flag lines** (A27–30) back to the control card's
   condition mux.

---

## 6. Known issues / verify (from the design review)

- **No IC power-pin problem here** — the backplane has no DIP logic ICs; its only
  parts are connectors, the resistor network, caps, and an LED, all explicitly
  netted.
- **Clock termination (DNP):** scope `CLK`/`CLKB` at the far slot after bring-up
  and decide whether to populate `RT/CT`.
- **Clearance:** the clock verticals run close (~0.6 mm) to the slot-10 pad
  columns — confirm against the fab's DRC rules (a board-routing item, tracked in
  VERIFY).
- **Fusion import / DRC / airwires** on the `.sch`/`.brd` pair before fab; order
  the backplane first as the cheap validation article.

See [p8x-backplane-design.md](p8x-backplane-design.md),
[p8x-bus-definition.md](p8x-bus-definition.md), and
[../../BACKLOG.md](../../BACKLOG.md).
