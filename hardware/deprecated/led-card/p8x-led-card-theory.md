# LED Output Card — Theory of Operation

A minimal memory-mapped **output port**: a write to `$FF0C` latches the data byte
and drives 8 LEDs from it. Write-only — there is nothing to read back. It is the
simplest possible peripheral on the P8X bus (address-decode → write strobe →
latch → display) and was built as a CAD-workflow trial, but it is a complete,
standards-conforming card.

> Source of truth: the `# LED OUTPUT CARD` section of
> [`../../generators/gen_eagle.py`](../../generators/gen_eagle.py).

---

## 1. Inputs and outputs

### Inputs (from the backplane)

| Signal | Purpose |
|--------|---------|
| `A1–A4`, `A8–A15` | address — page-decoded (`$FFxx`) and port-decoded (`A1–A3`, with `A4=0`) |
| `D0–D7` | the data byte to display |
| `DLD0–3` | decoded here to the write strobe `-MEMW` |
| `CLKB` | phases the latch clock so data is captured as the write completes |

### Outputs

| | |
|---|---|
| 8 LEDs (`LA1`) | the latched byte, one bit per LED |
| (no bus output) | the card never drives the data bus — it only consumes writes |

Because it never drives `D0–7`, this card **cannot cause bus contention** — a nice
property for a first board to fabricate and test.

---

## 2. Block diagram

```
  A8..A15 ─►┌────────┐ IOPG (low = $FFxx)
            │U1 7430 ├───────────────┐
            │I/O page│                │ !G2A
            └────────┘                ▼
  A1,A2,A3 ───────────────────► ┌──────────┐ Y6
                       A4 ─────►│U2 74138  ├──────► -SEL  ($FF0C, A4=0 region)
                          !G2B  │ addr dec │
                                └──────────┘
  DLD0-3 ─►┌──────────┐ Y7
           │U3 74138  ├────────────────────────────► -MEMW
           │ DLD dec  │
           └──────────┘
   -SEL ──►┌──────────┐ WRSEL (low = write to our port)        ┌──────────┐
   -MEMW ─►│U4 74HCT32│──────────┬──────────────────► LED4 K   │          │
           │ OR gate1 │          │                    (WR LED) │          │
           └──────────┘          ▼ 2A                          │          │
  CLKB ──►┌──────────┐ CLKBN  ┌──────────┐ LCK                 │          │
          │U5 74HC14 ├───────►│U4 OR gt2 ├────────────► CLK ──►│U6 74374  │
          │ inverter │   2B   └──────────┘                     │ LED latch│
          └──────────┘                                         └────┬─────┘
  D0-7 ──────────────────────────────────────────► U6 D1-8         │ Q1-8 = LP0-7
                                                                    ▼
                                              ┌──────┐ LR0-7  ┌──────────┐
                                              │RL1   ├───────►│LA1 8-LED │
                                              │8×330R│        │ array    │
                                              └──────┘        └────┬─────┘
                                                              GND ─┘ (cathodes)
```

---

## 3. How it works

### 3.1 Address decode → `-SEL`
The decode is two-level, mirroring the I/O card. `U1` (7430 8-input NAND) drives
`IOPG` low when `A8–A15` are all high — any `$FFxx` address. `U2` (74138) then
decodes the low address bits `A1–A3`, but only when **enabled**: `!G2A = IOPG`
(must be the I/O page) and `!G2B = A4` (must be `A4 = 0`, i.e. the `$FF00–$FF0F`
region). Output `Y6` corresponds to `A1–A3 = 110` = `$FF0C`, so `-SEL` goes low
exactly on an access to `$FF0C` (modulo the `A5–7` aliasing noted below).

### 3.2 Write strobe → `-MEMW`
The control word's `DLD` field is decoded locally by `U3` (74138); output `Y7` is
the memory-write code, giving `-MEMW`. This is the same per-card decode every I/O
card does, so the LED card recognizes a *write* cycle without depending on any
other card.

### 3.3 Forming the latch clock
The 74374 captures its inputs on a **rising edge** of its clock. We want that edge
to occur once, cleanly, when a write to our port completes:
1. `WRSEL = -SEL OR -MEMW` (`U4` gate 1) — an OR of two active-low signals, so
   `WRSEL` is low **only when both** are asserted, i.e. only during a write to
   `$FF0C`.
2. `CLKBN = ~CLKB` (`U5` inverter) — the bus clock, inverted.
3. `LCK = WRSEL OR CLKBN` (`U4` gate 2) — combines the two so a clean rising edge
   lands inside the qualified write window, clocking `U6`.

This is the same proven clock-gating shape the I/O card uses for its `$FF02` LED
port; it avoids latching on stray bus activity.

### 3.4 Latch and display
On that edge, `U6` (74374) captures `D0–7`. Its `!OC` is tied low so the latch
outputs are always driven (we never tri-state them — they don't touch the bus).
The outputs `LP0–7` drive the LED array `LA1` through the 330 Ω network `RL1`
(anode side); the LED cathodes return to GND. A `1` bit sources current through
its resistor and lights the LED. The byte stays displayed until the next write.

### 3.5 Indicators and housekeeping
`LED3` (green) is the standard power indicator. `LED4` (yellow) is a
write-activity LED whose cathode sits on `WRSEL`, so it blinks on each write to
the port. The unused `U4` OR gates and `U5` inverters have their inputs tied to
GND (no floating inputs), and `card()` adds the DIN96C connector, per-IC 100 nF
decoupling, and the IC power-pin wiring automatically.

---

## 4. Worked example — `POKE $FF0C, $A5`

1. The CPU drives `A0–15 = $FF0C` and `D0–7 = $A5` with `DLD = 7` (write).
2. `U1` sees `$FFxx` → `IOPG` low; `U2` is enabled (`A4 = 0`) and decodes
   `A1–3 = 110` → `Y6` = `-SEL` low. `U3` decodes `DLD = 7` → `-MEMW` low.
3. `WRSEL` (= `-SEL` OR `-MEMW`) goes low; combined with `CLKBN`, `LCK` produces a
   rising edge that clocks `U6`, capturing `$A5`.
4. `U6` outputs `10100101`; the corresponding LEDs (`*.*..*.*`) light, and `LED4`
   flickers to show the write. The pattern persists until the next `$FF0C` write.

---

## 5. Known issues / verify

- **Address aliasing:** `A5–A7` are not decoded, so the port also responds at
  `$FF2C`, `$FF4C`, … (every 32 bytes in the page). Harmless for a scratch card;
  add `A5–A7 = 0` qualification (or a fuller decode) if it becomes permanent.
- **No reset clear:** the 74374 has no clear input, so the LEDs power up in a
  random state until the first write. Add a reset-forced clear (or a register with
  `!CLR`) if a defined power-up pattern is wanted.
- **WR LED drive:** `LED4`'s cathode is driven from a gate output (`WRSEL`) — the
  same source-drive deviation noted on the I/O card; confirm brightness at
  bring-up.
- Confirmed OK: no bus-drive (cannot contend), no floating gate inputs, all 6 ICs
  powered, standards-conforming connector + decoupling. Generates with 0
  validation errors.

This is a test/scratch card and may be removed. See [README.md](README.md).
