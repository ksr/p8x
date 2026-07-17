# P8X Bus Test Card — Design

> **Status: DESIGN, not built.** Nothing here has been fabbed or verified against
> real silicon. Numbers are calculated, not measured. Open items are listed in §10.

A USB-attached card that brings up the rest of the machine, one card at a time,
by driving the backplane directly and diffing what it sees against the emulator.

---

## 1. The thesis: this is a control card you can type at

The P8X backplane does **not** carry a conventional address/data bus with RD/WR.
It carries the **horizontal microcode control word**. `DOE` selects which card
drives `D0–D7`; `DLD` selects which latches it; `PSEL` selects which pointer drives
`A0–A15`; `ALUS/ALUM/CIN/BSEL/SH*/LDF/LDZN/SETC/CLRC` are control-store outputs
wired straight to the cards. Those lines are driven by the control card's pipeline
register (U14–U17, 74374) — nothing else drives them.

So the useful tool is not a bus pirate. It is a card that **sits exactly where the
control card's pipeline output sits** and presents the same word, one microcycle at
a time, under your fingers.

That framing is what makes card-level bring-up possible: **each card can be
exercised with the rest of the machine absent.**

- **Memory card alone.** `A0–A15` is input-only to every card *except* the register
  bank (§3.2 of the bus definition). With the reg-bank out, the address bus is
  ours: drive an address, `DOE=MEM`, step, read `D`.
- **ALU card alone.** Drive `ALUS/ALUM/CIN/BSEL`, read the result and `FC/FZ/FN/FV`.
  No PC, no memory, no microcode.
- **Reg-bank alone.** `PSEL` + `PTRL/PTRH` + `PINC/PDEC`, watch `A0–A15`.

### 1.1 The card is the sequencer

The microword has 19 fields (`microcode/genucode.py`, `w()`), but **only 16 reach
the backplane**. Three are the control card's own business:

| Field | Why it never leaves the control card |
|-------|--------------------------------------|
| `fcond` | selects which flag the *sequencer* branches on |
| `urst`  | resets the microstep counter to 0 |
| `halt`  | stops the clock |

So the bus test card drives the 16 bus-visible fields **and is itself the
sequencer** for the other three — "what word comes next" is just the next line of
the test script. It never models the microcode ROM, the step counter, or the
pipeline. It only has to reproduce the *phasing* (§4).

### 1.2 The emulator is the reference model

`emulator/p8xemu.c` already models every line this card touches — the `BSEL`
B-input mux, V-flag derivation, the `DOE`/`DLD` decode. So the same ASCII script
can drive the emulator and the card, and the two outputs diffed.

That is the pattern this project already uses everywhere else: `p8cc.py` vs
`p8cc.c` as a differential oracle, and the byte-identical C/asm command twins.
Bring-up becomes **"run the tests against real silicon and diff"** rather than
"poke it and squint at a scope".

---

## 2. Scope

| | |
|---|---|
| Function | Drive/read all 59 backplane signals + 8 high-Z probes, over USB, in ASCII |
| Timing | **Static/stepped only.** Not a logic analyser. |
| Bus role | Drives when the owning card is out; listens otherwise |
| Host link | USB CDC, line-oriented ASCII (typable by a human, parseable by a script) |
| Board | 100 × 200 mm (`W=200, H=100`), DIN 41612 96-pin, MABC96R |
| Firmware | C, Pico SDK |

**Static-only is the load-bearing decision.** It is what allows SPI port expanders
instead of an FPGA, and — more importantly — what makes the series resistors in
§3.2 free. Every safety property below follows from it.

---

## 3. Bus ownership and safety

### 3.1 Wake state: drive nothing

**Every pin comes up as an input. The card drives nothing until a test claims it.**
There is no presence strap and no hardware interlock: a test asserts which cards
are absent, and that assertion is a line in the script.

This works because contention is made *non-destructive*, not *impossible* (§3.2).

The idle state falls out of the bus's own encoding: **all-zeros is inert.**
`DOE=0` is bus-idle, `DLD=0` is no-load, `PINC/PDEC/LDF=0` are no-ops — and `-RES`
is active-low, so low means *held in reset*. A plain pull-down network therefore
gives a safe power-on state before the Pico has even booted, and holds the ~40 HCT
control inputs at a defined level when the control card is out (floating HCT inputs
oscillate and burn current).

**`CLK` pulled low is the real interlock.** With no rising edge, nothing latches
anywhere, whatever else is on the bus.

### 3.2 Series resistors: 1 kΩ, and why they are free

Every driven line and every probe goes through **1 kΩ** (RNISO8 networks).

The machine is **entirely 74HCT** (24 distinct parts in the BOM; no LSTTL
anywhere). HCT inputs are CMOS, drawing ~1 µA. So:

| | |
|---|---|
| DC drop across 1 kΩ | ~1 mV. **Zero cost.** |
| Worst-case contention | expander driving 5 V into an HCT output held low (R<sub>on</sub>≈30 Ω): `4.9V / 1030Ω ≈ 4.8 mA` — safe **indefinitely** for both sides |
| Drive level | against the 10 kΩ pull-down: `5V × 10k/11k = 4.55 V` — far above HCT's V<sub>IH</sub> = 2.0 V |
| Rise time | `1k × ~100 pF ≈ 100 ns` — invisible when stepping by hand |
| Probe over-voltage | a grabber slipped onto 12 V gives `(12−5)/1k = 7 mA` into the expander's internal ESD clamp, under its 20 mA rating — **so no external clamp diodes are needed** |

A wrong test therefore costs a wrong readback, not a dead chip. Had the machine
been LSTTL, `10 loads × 0.4 mA × 1 kΩ = 4 V` of drop would have destroyed the idea.

### 3.3 Passive allocation — do not double up

A pull-up and a pull-down on the same line sit at mid-rail and leave every HCT
input indeterminate. Each line gets exactly one owner:

| Line | Passive | Where | Idle |
|---|---|---|---|
| `D0–D7` | 10k pull-**up** (RN1, exists) | backplane | high = bus idle, per the `DOE=0` spec |
| `-RES` | 10k pull-**up** (**new**) | backplane | deasserted; control card or this card drives it low |
| `-IRQ` | 10k pull-**up** (**new**) | backplane | wired-OR — see §7 |
| `A0–A15` | 10k pull-**down** | this card | `0000` when the reg-bank is out |
| ~40 control lines, `CLK`, `CLKB` | 10k pull-**down** | this card | all-zeros = inert |

This card puts **no** passive on `D`, `-RES`, or `-IRQ` — those belong to the
backplane.

### 3.4 Presence detection is functional, not electrical

When a test wants to *verify* its assumption before claiming lines, it can — with
no straps and no card modifications:

- **Control card**: `CLK` and `CLKB` are complements *by definition*. Release both
  and read. `01`/`10` ⇒ something is driving them. `00` is just our pull-downs ⇒
  no control card. This is guaranteed, unlike level-probing (a halted control card
  and an absent one look identical if you only watch for edges).
- **Reg-bank**: pulse `PINC` and see whether `A0–A15` changes.
- **ALU**: drive an operation and see whether the flags respond.

---

## 4. Clock discipline — the part that is easy to get wrong

### 4.1 The machine is fully static

62256 SRAM + 28C64 EEPROM. **No DRAM, no refresh, no monostables, no 555s.** The
control card already has a single-STEP button, so stepping is a designed-in
capability. The clock can be parked in any phase indefinitely.

### 4.2 `CLKB` is not decorative

`-MEMW` (memory card, U8), and both CF strobes (`-IORD`/`-IOWR`), are gated
**combinationally by `CLK̄`**. The I/O and LED cards clock their latches from it.

**Drive `CLK` alone and writes never strobe** — which presents as a dead memory
card and sends you scope-probing a fault that does not exist. Both lines are
driven independently.

### 4.3 The four states, and why "both low" matters

| `CLK` | `CLKB` | State |
|---|---|---|
| 0 | 0 | **rest/setup** — no edge, every strobe gated off |
| 0 | 1 | **phase A** — strobes assert, source drives `D`, everything settles. Sample `D` here. |
| 1 | 0 | **phase B** — destination register latches; strobes deassert, so an SRAM write commits on this transition |
| 1 | 1 | **illegal** — strobes enabled with `CLK` already high. Reachable deliberately, for fault injection. Never in a normal step. |

`step` = `rest → A → B → rest`.

**`rest` (both low) is a state the real machine physically cannot produce** — its
`CLKB` is always `¬CLK`. It exists here because it is load-bearing twice over:

1. **The microword is not atomic.** Five expanders update sequentially over SPI, and
   the address bits live on a different chip from `DLD`. Setting `DLD=MEMW` while
   `CLKB` is high asserts `-MEMW` *immediately*, while address bytes are still
   arriving — strobing writes into whatever addresses flicker past. Parking at
   `00` gates every strobe off while the word settles.
2. **Gated clocks.** The ALU's flag register (U17) is clocked by
   `CLK & (LDF | LDZN)` through U31. Raise `LDF` while `CLK` is already high and
   that AND gate goes 0→1 — **a manufactured rising edge, latching phantom flags.**
   The real machine cannot do this: its pipeline latches on `CLK̄`, so the control
   word only ever changes as `CLK` falls. This card reproduces that discipline by
   always returning to `CLK`=0 before the word changes.

**Rule: the microword may only change while `CLK` is low.** `rest` enforces it.

---

## 5. Circuit

### 5.1 Pin budget

| Group | Lines |
|---|---|
| `D0–D7` | 8 |
| `A0–A15` | 16 |
| Control (`DOE`×4, `DLD`×4, `PSEL`×3, `PINC`, `PDEC`, `CLK`, `CLKB`, `LDF`, `LDZN`, `SETC`, `CLRC`, `BSEL`, `ALUS`×4, `ALUM`, `CIN`, `SH0`, `SH1`, `SHCIN`, `-RES`, `-IRQ`) | 35 |
| Flags in (`FC`, `FZ`, `FN`, `FV`) | 4 |
| Probes | 8 |
| **Total** | **71** |

**5 × MCP23S17** = 80 lines with per-pin direction and per-pin pull-ups. ~9 spare;
some wired to `SPARE12–23` (already routed slot-to-slot) for future use.

### 5.2 Parts

| Ref | Device | Role | New to generator? |
|---|---|---|---|
| U1–U5 | MCP23S17 (DIP-28) | 80 bidirectional 5 V lines, SPI | **add** |
| U6 | 74HCT244 | SPI level-shift, 3.3 V → 5 V (SCK/MOSI/CS/RESET) | reuse |
| U7–U10 | 74HCT244 | LED buffers (D, A-lo, A-hi, probes) | reuse |
| A1 | Pico (2×20 headers) | RP2040, USB CDC | **add** |
| J2 | 2×5 header | 8 probes + 2 GND | **add** |
| RN* | RNISO8 | 1k series (×9), 10k pull-down (×7), LED limit (×5) | reuse |
| LED* | LEDARR8 | 40 status/state LEDs | reuse |
| J1 | MABC96R | DIN 41612 edge connector | supplied by `card()` |

`card()` also supplies the per-IC 100 nF decoupling caps, so the project's caps
rule is satisfied structurally rather than by remembering.

**Level shifting is one chip, one direction.** A bidirectional `74HCT245` is not
needed: the Pico only *sends* to the expanders (SCK/MOSI/CS/RESET). HCT's
V<sub>IH</sub>=2.0 V accepts 3.3 V and its outputs swing to 5 V. MISO returns
through a two-resistor divider. The MCP23S17s run at 5 V and talk TTL directly.

### 5.3 Power

All from backplane +5 V (per-slot budget is not a constraint here).

- Expanders + buffers: backplane 5 V directly.
- Pico: backplane 5 V → **Schottky** → VSYS. This is the documented way to let an
  external supply and USB coexist; the Pico's own VBUS diode blocks backfeed into
  the host.
- **5 V sense**: a divider from backplane +5 V to a GPIO. Firmware refuses to drive
  without it. This closes the one bad case: USB plugged in with the backplane
  *off* leaves the Pico alive driving unpowered expander/buffer inputs — latch-up
  territory. Two resistors.

Worst case ≈ 400 mA (40 LEDs ≈ 160 mA, Pico 30–100 mA, five expanders, buffers).

### 5.4 LEDs

The io-card already proves the pattern — its U11–U13 are `74244`s monitoring
A0–7, A8–15, D0–7. Copied here, so LEDs cost **zero expander pins**: they tap the
**bus side** of the series resistors through `74244` buffers, loading the bus with
~1 µA instead of the ~4 mA an LED would steal from an HCT output.

| LEDs | Source |
|---|---|
| `D0–D7` (8) | `74244` buffer |
| `A0–A15` (16) | 2 × `74244` |
| Probes 0–7 (8) | `74244` |
| Status (8) — 5V-OK, ARMED, LISTEN, CLK, CLKB, -RES, ERR, USB-ACT | Pico GPIO direct |

The io-card duplicates the D/A display, but during card-level bring-up the io-card
is not in the backplane — these are the only ones lit when it matters.

### 5.5 Board

`W=200, H=100`. J1 hugs the left edge (x≈0) and parts flow left-to-right, so the
extra 40 mm over a standard Eurocard lands at the **outer** end — where the USB
socket, the 2×5 probe header, and the LED bank belong, because that is the end you
can reach with the card seated.

`card()` currently hardcodes `BW,BH = 160.0, 100.0`. Parameterize with defaults
`W=160.0, H=100.0` so **every existing card stays byte-identical** (verify, do not
assume).

**Mechanical**: 200 mm cantilevered off the DIN connector, with only the two
mounting holes at y=±45 carrying it. If the card guides are cut for 160 mm, the
last 40 mm is unsupported and the connector absorbs the moment every time a
grabber is clipped or USB is plugged. This card gets handled far more than the
others — a guide rail or an outer standoff is wanted.

---

## 6. The ASCII protocol

Field names are **`genucode.py`'s names, verbatim** — that is what makes a script
meaningful against both the card and the emulator.

```
DOE  = idle A B T T2 ALU FLAGS MEM PTRL PTRH        (0..9)
DLD  = none A B T T2 FLAGS IR MEMW PTRL PTRH        (0..9)
PSEL = P0 P1 P2 P3 PT PT2                           (0..5; PT/PT2 hidden scratch)
also: PINC PDEC ALUS M CIN SH0 SH1 SHCIN LDF LDZN SETC CLRC BSEL
```

Responses are `KEY=VAL` — typable *and* trivially parseable. Errors are `!ERR
<reason>`: unmistakable, the same instinct as the compiler's poison directive.

```
p8x> id
P8XBUS 1.0  5V=ok  owns=(none)

p8x> owns                       ; power-on: drives nothing
drive=(none)  hiz=ctrl,addr,data,probes

p8x> drive ctrl addr            ; this test asserts: control card and reg-bank are OUT
p8x> w DOE=MEM DLD=none PSEL=P0
p8x> a 2000
p8x> step                       ; rest -> A -> B -> rest
p8x> r D
D=EA
p8x> r flags
FC=0 FZ=1 FN=0 FV=0
p8x> probe
PR=1011_0010
```

`step` performs the correct phasing by default; reaching the illegal `CLK=1
CLKB=1` requires an explicit `clk 1 1`.

---

## 7. `-IRQ`: fix the polarity before anything is built

The bus definition calls it `IRQ` (active-high by name) but describes it as *"any
card may pull it"* — that is wired-OR, which means open-drain, which means
**active-low**. Both cannot be true. The emulator does not settle it: it models
interrupts abstractly (a write to `$FF06` sets `irq_pending`), never as a line.
And the circuit is the one unbuilt hardware item (control card U20/U21, DNP).

**Recommendation: rename to `-IRQ`, active-low, open-drain, 10 kΩ pull-up on the
backplane.** Cards assert with an open-drain buffer — `74HC07` is a hex open-drain
buffer in DIP, so the through-hole rule holds. This is what makes "any card may
pull it" actually work: open-drain drivers cannot fight each other, whereas the
HCT push-pull parts used everywhere else in this machine **physically cannot be
wired-OR'd**. Active-high would need open-source drivers or a diode-OR — both
worse. Nothing is built yet, so this costs nothing today.

This card can then assert `-IRQ` on demand and single-step the machine into the
`$08` vector — which is how the interrupt hardware should be brought up, with the
emulator's `IE`/`irq_pending`/`$08`-injection model as the reference.

---

## 8. Bring-up sequences

Each runs with only the card under test in the backplane.

**Memory card.** Drive `A`, `DOE=MEM`, step, read `D`. Walk all 8 K and diff
against `eeprom.bin` — the golden image already exists. Then write/read-back the
SRAM (`DLD=MEMW`; note the write commits on the A→B transition, §4.3).

**ALU card.** Sweep `ALUS/ALUM/CIN/BSEL` over operand pairs; diff result and
`FC/FZ/FN/FV` against the emulator. At ~40 µs/vector, **all 65,536 operand pairs
for one function ≈ 3 s; all 16 functions well under a minute.** This is exhaustive
verification of the card that gates the T-operand work, including the 74157 B-mux.

**Reg-bank.** `PSEL` + `PTRL/PTRH` load, `PINC`/`PDEC`, read `A`. Covers all six
pointers including the hidden `PT`/`PT2` scratch.

**Then insert the control card**, release everything, and watch the real machine
run in listen mode.

---

## 9. Known limitation: `IR`

`IR` lives on the control card, so **`DLD=IR` is a no-op during card-level
bring-up** — the only time this card drives. Instruction-register loading cannot
be exercised until the control card is in, at which point this card is
listen-only. That is inherent to the approach, not a fixable gap.

---

## 10. Open items

- **Mating orientation** — the bus definition still carries *"VERIFY against
  physical connectors before first fab"*. Unresolved, and it bites this card as
  much as any other.
- **Where `CLK` parks when halted** — affects listen-mode sampling only.
- **Status LED set** — the eight in §5.4 are a guess and want a second opinion
  from whoever will stare at them.
- **Layout** — 5 × DIP-28 + 5 × 74244 + ~21 resistor networks + 5 LED arrays + Pico
  + J1. Should fit 200 × 100 comfortably; confirm when placed.
- **Nothing here is measured.** Every number above is calculated from datasheet
  values and the existing design docs.
