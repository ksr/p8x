# P8X Card Design Standards

Applies to every plug-in card (control, register bank, ALU, memory, I/O,
CF-IDE, and future cards). The backplane has its own design notes and is
explicitly out of scope here. When a card deviates from a rule, the deviation
and its reason go in that card's schematic notes — silent exceptions are bugs.

Memory card rev C is the reference implementation of these standards.

---

## 1. Mechanical

| Item | Standard |
|---|---|
| Board size | Eurocard 160 × 100 mm, 1.6 mm thickness |
| Connector | DIN 41612, 3-row 96-pin male, right-angle, at the right board edge |
| Connector placement | Pin row spans y = 10.16–88.90 mm; row A nearest board surface — VERIFY against mated orientation before first fab and then freeze the footprint |
| Component height | ≤ 20 mm (1" slot pitch minus card + clearance); nothing on the back side except pin protrusion |
| Card extraction | Leave 5 mm strip at the left (front) edge free of components for a puller/handle; card name visible there |
| Mounting | No card-level mounting holes required; front strip may take an ejector later — keep it clear |

## 2. Stackup & Layout

| Item | Standard |
|---|---|
| Layers | 4: Top = signal, In1 = solid GND plane, In2 = solid +5V plane, Bottom = signal (Eagle layer setup 1\*2\*15\*16) |
| Planes | Never split, never route on. Power distribution is the planes, period |
| Signal traces | 0.4 mm width, 0.3 mm minimum clearance |
| Bus entry | Backplane signals fan out from the connector on Top where possible; keep bus stubs short (< 25 mm from connector pad to first IC pin) |
| Clock | CLK routed first, shortest practical path, no stubs to chips that don't use it |
| Vias | 0.8 mm pad / 0.4 mm drill standard |

## 3. Power & Decoupling

- 100 nF ceramic per IC, placed within 5 mm of its VCC pin, via straight to both planes
- One 10 µF bulk per card near the connector power pins
- Power pins per rev C bus: +5V = A1, B1, C1, A2, B2, C2; GND = A31, B31, C31, A32, B32, C32; row B3–B30 = GND (stitch every row-B pin straight into the GND plane — free stitching grid)
- Budget: declare expected current draw on the schematic title block (rule of thumb ~20 mA per HCT IC average, more for LS or anything driving LEDs)

## 4. Logic Family & Unused Pins

- Default family **74HCT** (TTL-compatible thresholds, low power). Mixing in 74LS/74F is allowed only for speed-critical paths and must be noted
- **Unused CMOS inputs are never left floating** — tie to GND (or VCC where logic demands). This includes unused gates in a package
- Unused outputs: leave open, mark with no-connect intent in the schematic (KiCad: NC flag; Eagle: accept the ERC warning, list the pins in a schematic note)
- Every pin on the schematic must be accounted for: netted, tied, or explicitly NC. The generators enforce this mechanically — keep that property

## 5. Bus Interface Rules (the constitution of this machine)

1. **Drive the data bus only through a tri-state buffer/transceiver enabled by
   this card's decoded DOE code.** Never from a bare output
2. **Field decoding is per-card**: each card carries its own decoder(s) for
   the DOE/DLD codes assigned to it (74138/74154). Codes are allocated in the
   bus pinout document; a card uses only its assigned codes
3. **Loads happen on the rising CLK edge** when the card's DLD code is
   present. Write-type strobes (memory, I/O latches) are gated with CLK̄ so
   address/data settle in the first half-cycle and strobe in the second —
   copy the memory card's WE̅ circuit
4. The address bus is input-only to every card except the register bank
5. Never add pull-ups/pull-downs to backplane signals on a card — bus
   conditioning (D0–D7 pull-ups, clock termination) lives on the backplane
   only, exactly once
6. Control signals a card doesn't use: leave the connector pin unconnected
   (NC), never tie a bus signal to a rail on a card

## 6. Address Decoding (memory-mapped cards)

- I/O page is $FF00–$FFFF; detect with 8-input NAND on A8–A15 (the memory
  card's 7430 pattern). Sub-decode with a 74138
- I/O address allocations are recorded in the bus pinout document before a
  card is built — no squatting
- Any card asserting data onto the bus for a read must qualify on
  (its address decode) ∧ (DOE = MEM)

## 7. Schematic & Naming Conventions

- Net names match the bus pinout document exactly (D0–D7, A0–A15, DOE0–3,
  DLD0–3, PSEL0–1, PINC, PDEC, CLK, CLKB, -RES, LDF, ALUS0–3, ALUM, CIN,
  SH0–1, SPARE0–7). Active-low signals are prefixed with a dash
  (e.g. -RES, -RD, -MEMW)
- Reference designators: U = ICs, J = connectors, C = caps, R/RN = resistors/
  networks, D/LED as usual. J1 is always the bus connector
- Card value/title block carries: card name, rev letter, date, expected
  current, and deviations from this document
- One generator script per card is the canonical netlist; the CAD files are
  artifacts of it. A netlist change means regenerate, never hand-edit copper
  against an stale netlist

## 8. Silkscreen

- Card name + rev, large, on the front-edge strip (readable with card installed)
- Pin 1 markers on every IC; connector A1/C32 corners labeled
- Designators readable after assembly (not under sockets)

## 9. Assembly & Test Provisions

- **All ICs socketed** (machined-pin) — this is a hobby machine; chips will
  be swapped and probed for years
- Test points (loop or pad) on: card-local decoded strobes (e.g. RD_N,
  MEMW_N equivalents), and any card-internal clock or state line you'd want
  a scope on at 2 a.m.
- Every card must be safe to insert alone with only the control card present:
  no card may require another card (other than control) to avoid bus
  contention or undefined drive
- Bring-up note on each schematic: the one-line test that proves the card
  alive (memory card example: "monitor reads $FF17, RDY set")

## 10. Fab Checklist (per card, before Gerbers)

- [ ] Pour planes, run DRC clean at 0.3/0.4 rules
- [ ] Zero airwires
- [ ] Connector footprint verified against physical part (orientation!)
- [ ] Every pin netted/tied/NC-accounted
- [ ] Decoupling count = IC count
- [ ] Silkscreen: name, rev, pin-1 marks
- [ ] Gerber + drill reviewed in an independent viewer
