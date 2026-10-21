# P8X 8-Slot Backplane — Design Notes

> **Theory of operation:** [p8x-backplane-theory.md](p8x-backplane-theory.md) — deep walkthrough of the bus map, signal integrity, and power.

> **Built version:** the go-forward board is the KiCad build in
> [`kicad/`](kicad/README.md) — **8 slots, 28 mm pitch, 262 × 128 mm**, routed at
> **0.13 mm clearance**, nylon-screw mounting. The board figures in §2–§4 were
> brought up to the 8-slot KiCad build on 2026-10-21 (they were the Eagle rev-C
> notes: 25.4 mm pitch, 10 slots); the bus pinout and theory are unchanged.

## 1. Bus Pinout

The authoritative human-readable bus pinout is in **[p8x-bus-definition.md](p8x-bus-definition.md)**,
which is generated from the same `busnet()` function as the Eagle CAD files.
The machine-authoritative source is `generators/gen_eagle.py`.

Summary for quick reference (rev C2):

| Pin | Row A | Row B | Row C |
|-----|-------|-------|-------|
| 1–2 | +5V | +5V | +5V |
| 3–10 | D0–D7 | GND/SPARE (alt) | A0–A7 |
| 11 | -RES | GND/SPARE (alt) | A8 |
| 12–15 | DOE0–3 | GND/SPARE (alt) | A9–A12 |
| 16–19 | DLD0–3 | GND/SPARE (alt) | A13–A15, ALUS0 |
| 20–21 | PSEL0–1 | GND/SPARE (alt) | ALUS1–2 |
| 22–23 | PINC, PDEC | GND/SPARE (alt) | ALUS3, ALUM |
| 24–25 | CLK, CLKB | GND/SPARE (alt) | CIN, SH0 |
| 26–27 | LDF, FC | GND/SPARE, CLRC | SH1, PSEL2 |
| 28–30 | FZ, FN, FV | BSEL, IRQ, SPARE11 | LDZN, SHCIN, SETC |
| 31–32 | GND | GND | GND |

A27–A30 = FC/FZ/FN/FV (flag lines; were SPARE0–3 in rev C1).
rev C3: C27–C30 = PSEL2/LDZN/SHCIN/SETC and B27 = CLRC (were SPARE4–8).
rev C: B28 = BSEL (ALU B-input mux select, was SPARE9), B29 = IRQ (interrupt
request, was SPARE10); SPARE11 remains on B30.
**rev D: B3–B26 alternate** — odd pins stay GND (guard between signal pairs),
even pins (B4,B6,…,B26) are spare bus lines SPARE12–SPARE23, routed slot-to-slot
for future expansion without a backplane re-spin. See p8x-bus-definition.md for
the authoritative per-pin map.

Signal positions are unchanged from rev B wherever they existed, so only the
power pins moved. **Rev B cards are incompatible** (rev B grounded B2; rev C
puts +5V there). The memory card schematic has been regenerated as rev C.

Current budget: DIN 41612 pins are rated ~2 A each → 6 parallel +5V pins and
~18 ground pins (the 6 pins on rows 31–32 plus the 12 odd-pin B-row guards; rev D
reassigned the 12 even B-row pins from GND to spare lines) carry a 3–4 A system
with comfortable margin and low connector drop.

## 2. PCB Construction — this is where the crosstalk battle is won

**Use a 4-layer board.** At today's fab prices the upcharge is small and it
buys more than any other single decision:

| Layer | Content |
|---|---|
| L1 (top) | Signal: row A nets |
| L2 | **Solid GND plane** — no splits, no routing |
| L3 | **Solid +5V plane** |
| L4 (bottom) | Signal: row C nets |

This answers the "thicker power traces" requirement in the strongest possible
way: the power distribution *is* two solid copper sheets (use 1 oz minimum,
2 oz if offered cheaply). It also gives every signal a tight return path,
which is the primary crosstalk mechanism on a backplane — crosstalk is mostly
a shared-return-inductance problem, and a plane under every trace mostly
dissolves it.

Layout rules:
- **Slot pitch 28 mm**, 8 slots → board 262 × 128 mm (≈ 20 cm of bus between
  the end slots)
- Bus traces run straight connector-to-connector on the outer layers. The
  generated board uses **0.2 mm tracks, 0.13 mm minimum clearance** (Freerouting),
  plus a 0.35 mm `CLOCK` net class for CLK/CLKB (below). Most parallel runs sit at
  the 2.54 mm pin pitch, where coupling is negligible; some sampled-signal pairs
  close to 0.33–0.5 mm centre-to-centre for 10–17 cm (measured 2026-10-21, §2.1)
- **Do not route signals between the planes or split the planes.** Spares
  route like signals (the generated board keeps every track on L1/L4)
- **CLK and CLKB get the royal treatment**: route them with a ground trace
  on each side (guard traces) or with one empty channel between them and
  neighbors; keep them on one layer end to end. **As built (2026-10-21):** a
  `CLOCK` net class at 0.35 mm clearance (`gen_backplane.py`) keeps every
  neighbour ≥ 1.23 mm centre-to-centre (it was CIN at 0.44 mm, 75 mm alongside
  CLKB), with both clocks still the ≈ 230 mm daisy chain. Wider is not possible:
  the DIN pin field leaves 0.395 mm per side for a track threading two pins, and
  above that the clocks detour round the connector ends. A routed ground guard
  is beyond the autorouter; the spacing does its job
- **Decoupling**: one 100 nF within 10 mm of each slot's power pins (C1–C8
  in the schematic), 2 × 470 µF bulk near the power entry (C11/C12)
- Power entry (J11, 4-pos screw terminal: 2 × +5V, 2 × GND) at one end;
  via-stitch generously into the planes (≥ 8 vias per terminal)
- Tie every ground pin straight into L2 at every slot — 18 per slot (the 12
  odd row-B guards plus rows 31–32), 144 along the bus, a low-inductance grid
- Power LED (R1 + LED1) so a dead PSU is diagnosed from across the room

If you must do 2-layer: top = signals + 10 mm power rails along each edge,
bottom = ground pour flooded around a minimal number of crossing traces.
It will work at 2 MHz. The 4-layer board will work at 8 MHz. Choose accordingly.

### 2.1 Dielectric — order a thin outer prepreg

The generator does not set a stackup, so the fab's default 4-layer build applies
(commonly ≈ 0.2 mm from L1 to L2). The trace-to-plane height H is the biggest
remaining crosstalk lever. A common rule of thumb (Johnson) puts the near-end
coupling coefficient near 1 / (1 + (D/H)²), with D the centre-to-centre spacing.
It is an upper bound, reached when the coupled run is long compared with the
edge; the 10–17 cm runs here, slowed by card loading (§3), come close to it.

| Spacing on the routed board | H = 0.2 mm (typical default) | H = 0.1 mm |
|---|---|---|
| 2.54 mm (pin pitch, most runs) | ≈ 0.6 % | ≈ 0.2 % |
| 0.45 mm (tightest pairs) | ≈ 16 % | ≈ 5 % |

So the thin dielectric cuts the worst pairs about 3×, at no layer cost. **When
ordering, choose a 4-layer stackup with ≈ 0.1 mm outer prepreg** (most fabs list
one, often with 3313 glass). The 0.2 mm tracks then drop from ≈ 66 Ω to ≈ 41 Ω
(microstrip, εr 4.3), which is harmless: the loaded bus sits lower than either (§3).
The two levers compound on the clocks: at their 1.23 mm spacing (§2) the estimate
is ≈ 2.6 % at 0.2 mm prepreg and ≈ 0.7 % at 0.1 mm. The tight pairs left are
sampled signals (crosstalk only has to settle before the clock edge) plus two
active-low lines that idle high: `-RES` (104 mm beside D7 at 0.49 mm) and `IRQ`
(beside FZ/FV/LDZN at ≈ 0.5 mm). Both are safe for the same reason: HCT inputs
switch at ≈ 1.4 V, so a line sitting high needs a 72 % dip (5 V → 1.4 V) to see a
false edge, against ≈ 14 % (≈ 0.7 V) worst-case coupling. The vulnerable state is
a line sitting LOW (a 28 % rise reaches threshold), which is the clock case the
`CLOCK` class protects.

### 2.2 The connector pin field

At HCT edge rates the connector, not the PCB, is usually the dominant crosstalk
path on a backplane. Adding layers cannot change it; only the pinout can.

- **Row B gives every row-A and row-C pin a nearby ground return**, but neighbours
  *within* row A or row C are still signal beside signal. That coupling lives in
  the pin field.
- **Keep the plane webs intact.** Every DIN 41612 pin is a through-hole barrel
  that cuts an antipad in every plane. At 2.54 mm pitch, keep antipads ≤ ≈ 1.6 mm
  for the 1.0 mm drill, so that copper stays connected between pins. Return
  current concentrates in the connector field.
- **Reserve the spares next to the clocks for slow signals.** SPARE22 (B24) sits
  directly between CLK (A24) and CIN (C24); SPARE23 (B26) is diagonal to CLKB
  (A25). Assign only sampled, non-edge signals to those two if they are ever used.

### 2.3 Reference — the stackup with no layer budget

For the record, the low-crosstalk ideal if layer count were free (8 layers, every
signal layer against a solid ground):

| Layer | Role | Contents |
|---|---|---|
| L1 | GND | Solid pour and shield; only connector pins pass through |
| L2 | Signal (stripline) | CLK, CLKB, -RES, IRQ, strobes: the edge-sensitive lines, widely spaced |
| L3 | GND | Solid |
| L4 | Signal (stripline) | A0–A15 |
| L5 | GND | Solid |
| L6 | Signal | D0–D7, ALU/flag/control fields |
| L7 | +5V | ≤ 0.1 mm to L8: the pair acts as built-in decoupling |
| L8 | GND | Solid |

Stripline (a trace between two planes) is shielded on both sides. Its far-end
crosstalk is near zero, whereas on an outer layer it keeps growing with
parallel length. No two signal layers are adjacent.

**For this machine it buys little.** At 74HCT edge rates the 4-layer board with a
thin outer prepreg (§2.1) captures most of the benefit, and the connector field
(§2.2) is unaffected either way. For a prototype run an 8-layer board of this
size costs several times the 4-layer price (JLCPCB estimate, 2026-10-21).

## 3. Termination — analysis and recommendation

**The physics:** the bus is ≈ 20 cm between the end slots (8 slots at 28 mm).
Unloaded propagation is ≈ 1.2 ns end to end (≈ 6 ps/mm on an outer layer). Each
filled slot hangs ≈ 10–15 pF on every line (connector, stub, transceiver pin);
spread along the bus that gives a loaded impedance Z₀ / √(1 + C_load / C_line)
of roughly **20–35 Ω** (lower as more slots fill) and stretches the delay by
1.4–2.3×. Round trip ≈ 4–6 ns. 74HCT edges are 3–5 ns — comparable to the
round trip, which puts the bus at the *edge* of the transmission-line regime:
you'll see some ringing on a scope, but at 2–4 MHz there are hundreds of
nanoseconds for it to settle before anything is clocked. **Termination is not
required for functional correctness at the design speed.** Which signals care:

- **Edge-sensitive** — anything used *as* an edge: CLK, CLKB, -RES, latch
  strobes. One glitch across threshold is a false clock.
- **Sampled** — data, address, the encoded DOE/DLD/PSEL fields: read at a clock
  edge, so they only need to have settled by then. Crosstalk on them is
  mostly harmless.

The ranked list of what actually prevents trouble:

1. Ground plane + row-B guard grounds (overwhelmingly the biggest factor)
2. Pull-ups on the data bus — RN1 (8 × 10 k) in the schematic. Not a
   termination at all, but essential with HCT: DOE=0 leaves D0–D7 undriven,
   and floating CMOS inputs oscillate and burn power. 10 k parks idle lines
   at a legal high
3. Clean clock distribution (guard traces; optionally a 33 Ω series resistor
   at the clock *driver* on the control card to soften the launched edge)

**Why classic passive (Thevenin) termination is wrong for this bus:** the
220/330 Ω pairs on S-100 and Multibus backplanes bias undriven lines to
~2 V — fine for LS-TTL inputs, but 2 V is dead in the middle of an HCT
input's threshold region, recreating the floating-input problem on purpose,
plus ~25 mA of standing current per terminated line. Don't copy it onto an
HCT bus.

**Active termination** (a regulated ~2.7 V rail feeding ~120 Ω per line —
the SCSI approach) fixes Thevenin's power waste but keeps the mid-threshold
bias problem for CMOS and adds a regulator. Justifiable on a long, fast,
heavily-loaded bus; overkill by an order of magnitude here. Done properly it is
a whole signalling system rather than a part: low-swing open-drain transceivers
(GTL/GTLP, BTL) with reference-voltage receivers. Bolted onto HCT it fixes
nothing, and those transceivers are SMD-only, against the through-hole build.

**Damped, not matched.** Termination has to suit the driver's strength. An HCT
bus driver (output resistance roughly 30–50 Ω) driving the 20–35 Ω loaded bus
launches only about a third to a half of the swing; the reflection off the
unterminated far end completes the edge. A *matched* far-end termination removes
that reflection and turns a clean edge into a slow RC climb. So the provisioned
networks are deliberately above the line impedance (100 Ω): they damp ringing
without demanding matched-line current. The corollary: **do not swap the bus
drivers for a stronger, faster family (ACT, ABT) without revisiting this
section** — faster edges move the bus fully into the transmission-line regime,
where it would then need real termination.

By signal class:

| Class | Lines | Treatment |
|---|---|---|
| Clocks | CLK, CLKB | Spacing/guard on the board (§2); optional 22–33 Ω series at the driver (control card); 100 Ω + 150 pF at the far end (R2/C13, R3/C14), fitted only if the scope shows ringing |
| Async / strobes | -RES, latch strobes | Same as the clocks if a scope shows ringing |
| Open-drain, wired-OR | IRQ | The pull-up R4 (10 kΩ) *is* its termination. With all slots filled (≈ 100 pF) it rises in ≈ 1 µs; if release must be seen within a few cycles, drop R4 to 2.2 kΩ (≈ 0.2 µs, ≈ 2.3 mA per asserting driver) |
| Bidirectional data | D0–D7 | RN1 10 kΩ pull-ups (idle level, not termination). If ever needed, RC at *both* ends — any slot can drive |
| Address / fields | A0–A15, DOE, DLD, PSEL | None — sampled after settling |

**What the board provisions instead — AC (RC) termination** on the two lines
that merit it: CLK and CLKB each get 100 Ω + 150 pF to ground at the far end
of the bus (R2/C13, R3/C14). AC termination damps reflections during edges
but draws zero DC and imposes no bias level — the CMOS-friendly choice.
Assembly guidance: **leave them unpopulated at first**. Bring the machine up,
probe CLK at the far slot, and fit them only if you see ringing that crosses
threshold regions. Footprints cost nothing; debugging mystery double-clocks
costs weekends. If data/strobe lines ever ring problematically at higher
clock speeds, the same RC treatment applies — but expect the planes to have
already solved it.

## 4. Backplane BOM

| Ref | Part |
|---|---|
| J1–J8 | DIN 41612 Type C 96-pin **female, straight (vertical), THT solder** — see the connector note below |
| J11 | 4-pos screw terminal, 5.08 mm |
| C11, C12 | 470 µF 10 V electrolytic |
| C1–C8 | 100 nF ceramic disc |
| RN1 | 10 kΩ × 8 bussed SIP-9 |
| R4 | 10 kΩ ¼ W — IRQ pull-up (wired-OR, open-drain line) |
| R2, R3 | 100 Ω ¼ W (DNP initially) |
| C13, C14 | 150 pF ceramic (DNP initially) |
| R1, LED1 | 1 kΩ + 5 mm LED |

### The DIN 41612 connector pair

The backplane and the plug-in cards use a matched DIN 41612 **Type C, 3×32
(96-way), 2.54 mm pitch, THT solder** pair — one gender per side:

| Side | Footprint (KiCad `Connector_DIN`) | Orientation | Representative part (Harting) |
|---|---|---|---|
| **Backplane** (J1–J8) | `DIN41612_C_3x32_Female_Vertical_THT` | female, straight/vertical | `09 03 296 6824` (96-pos female, 2.9 mm solder pins, THT) |
| **Plug-in card** (J1) | `DIN41612_C_3x32_Male_Horizontal_THT` | male, right-angle | `09 03 196 6921` (96-way, Type C, 3-row, right-angle, solder) |

Equivalent Type C 96-way solder parts are made by Amphenol (FCI), ERNI/TE and
Assmann WSW, often better stocked at US distributors. Class 2 (tin tails) is
adequate for a bench build; Class 3 adds gold plating and mating cycles.

Footprint desk-check done 2026-10-11: both footprints are the KiCad-stock Type C
3×32 pair — 2.54 mm column and row pitch, two M2.5 fixing holes (2.85 mm), 1.0 mm
signal drill — and the pin numbering is the DIN 41612 standard on both, so a
matched male/female pair mates a-a/b-b/c-c. Every card's J1 and every backplane
slot assign pin X to `busnet(X)` from the one source, so a given pin carries the
same signal on both sides. **Before ordering the full set:** confirm the exact
manufacturer part number and live stock against its datasheet (body, fixing-hole
pattern, THT-solder variant — not press-fit, not a contacts-not-included
housing), and dry-fit one card male against one backplane female — which is why
the backplane is ordered first.
