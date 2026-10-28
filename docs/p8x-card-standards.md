# P8X Card Design Standards

Applies to every plug-in card (control, register bank, ALU, memory, I/O,
CF-IDE, PS/2, the bus test card, and future cards). The backplane has its own design notes and is
explicitly out of scope here. When a card deviates from a rule, the deviation
and its reason go in that card's schematic notes — silent exceptions are bugs.

Memory card rev D was the reference implementation of these standards in the
Eagle flow; since 2026-09-18 the boards are generated in KiCad, with the rev F
memory card as the reference ([hardware/KICAD-BOARDS.md](../hardware/KICAD-BOARDS.md)).

---

## 1. Mechanical

| Item | Standard |
|---|---|
| Board size | 280 × 140 mm, 1.6 mm thickness — the uniform KiCad card size since 2026-09-18 (first planned as a 160 × 100 mm Eurocard); the 140 mm connector edge leaves room beyond the ~94 mm DIN 41612 |
| Connector | DIN 41612, 3-row 96-pin male, right-angle, on the left board edge as laid out in KiCad; status LEDs on the opposite edge |
| Connector placement | Pin row spans y = 10.16–88.90 mm; row A nearest board surface — VERIFY against mated orientation before first fab and then freeze the footprint |
| Component height | ≤ 20 mm (planned for a 1" slot pitch; the KiCad backplane's pitch is 28 mm); nothing on the back side except pin protrusion |
| Card extraction | Leave 5 mm strip at the front edge (opposite the connector) free of components for a puller/handle; card name visible there |
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
- Power pins per rev C/D bus: +5V = A1, B1, C1, A2, B2, C2; GND = A31, B31, C31, A32, B32, C32, plus the **odd** row-B guard pins B3, B5, …, B25 (stitch these straight into the GND plane). **Do NOT stitch B4, B6, …, B26 — those are spare bus lines SPARE12–SPARE23 — nor B27–B30 (CLRC/BSEL/IRQ/SPARE11), which are signals.**
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
  SH0–1, SPARE4–23). Active-low signals are prefixed with a dash
  (e.g. -RES, -RD, -MEMW)
- Reference designators: U = ICs, J = connectors, C = caps, R/RN = resistors/
  networks, D/LED as usual. J1 is always the bus connector
- Card value/title block carries: card name, rev letter, date, expected
  current, and deviations from this document
- One generator script per card is the canonical netlist; the CAD files are
  artifacts of it. A netlist change means regenerate, never hand-edit copper
  against an stale netlist

## 8. Silkscreen

- Card name + rev, large, on the front-edge strip (readable with card installed),
  with `cottageworker.com` beneath it (2026-10-26; it replaces `onepagecomputer.com`).
  `silk_labels.title_block()` prints the block on every board, trying the front
  (right) edge first; the backplane, which has no front edge, takes any clear edge
- Pin 1 markers on every IC; connector A1/C32 corners labeled
- Designators readable after assembly (not under sockets): the generators print
  every reference outside every part's courtyard, with the IC type beside it, and
  `check_card.sh` fails a board where one is hidden or under a part (2026-10-24)

## 9. Status LEDs (required on every card)

- **PWR LED (green)**: top-right corner of the card, 1 kΩ from +5V, LED to
  GND. Visible with the card installed
- **SEL LED (yellow)**: directly below the PWR LED. Lights whenever the card
  is *selected* — defined per card as the union of its decoded DOE/DLD codes
  (and address decode for memory-mapped cards). A card may instead provide a
  **finer-grained LED set whose union covers SEL's meaning** — the memory
  card does this with four: ROM access, RAM access, read cycle, write cycle.
  Select-type LEDs must gate raw chip-select/address decode with the
  bus-access qualifier (e.g. -BOE) so they indicate real accesses, not idle
  address-bus residue
- **Drive rules**: never hang an LED directly on a bus or decoded control
  net — buffer it through a spare gate (which cards have anyway; this is the
  approved exception to the tie-unused-inputs-to-GND rule: a repurposed gate's
  inputs go to the signal instead). Sink configuration: +5V → 1 kΩ → LED →
  gate output; lights when the buffered active-low select is low
- **Brightness semantics**: at full speed the SEL LED's brightness is duty
  cycle — it reads as an activity meter. At single-step it's a static "this
  card is on the bus this microcycle" indicator, which is the debugging
  payoff. If single-pulse visibility at full speed is ever wanted, a pulse
  stretcher (RC + transistor or 74123) may be added per card; note it as a
  deviation

## 10. Assembly & Test Provisions

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

## 11. Fab Checklist (per card, before Gerbers)

- [ ] Pour planes, run DRC clean at 0.3/0.4 rules
- [ ] Zero airwires
- [ ] Connector footprint verified against physical part (orientation!)
- [ ] Every pin netted/tied/NC-accounted
- [ ] Decoupling count = IC count
- [ ] Silkscreen: name, rev, pin-1 marks
- [ ] PWR + SEL LEDs present, top-right, buffered per section 9
- [ ] Gerber + drill reviewed in an independent viewer

## 12. Rules for New Boards (Ken, 2026-10-24, all of his systems)

For future work only: they do not apply to any card already built or ordered (no P8X board has been fabricated
yet). **Always ask Ken before changing a card that might be built, ordered or in production**, for any change.

- Switches, buttons, LEDs and the connectors for outside cables (video, DB9 and other D-subs, USB, network) go on
  the front edge, the edge farthest from the bus connector.
- Cable connectors point outwards: a right-angle part with its mating face at the board edge, so a cable plugs
  straight in.
- Jumper blocks and cable headers (ribbons, probes, ICSP) go near a board edge, never in the middle of the board.
- A plug-in module (Pico, Tang Nano, ...) goes at an edge other than the bus connector's, where possible, with its
  USB port facing that edge.
- Every reference (U12, R3, ...) stays readable with the parts fitted: printed outside the part, never under a chip,
  socket or module. ICs get their type (74HCT374, ...) printed beside it.
- Every switch, button and LED is labelled with its function (RESET, STEP, RUN, ...), and each switch position with
  what it selects.
- Placement drawings (PDF) show the outline and the parts in one orientation, on a sheet shaped like the board.
- `cottageworker.com` is on the silkscreen of every card, beside the board's name and revision (2026-10-26).

## 13. Rules Stated Elsewhere

Rules the boards follow that are written in other files, not above:

| Rule | Source |
|---|---|
| Bypass cap above each IC; LED/jumper labels and part values on the silk | [KICAD-BOARDS.md](../hardware/KICAD-BOARDS.md) |
| Every card gets a placement PDF, top and 3D renders, and Gerbers | KICAD-BOARDS.md |
| Boards are generated, never hand-edited: `gen_kicad.py`, or a card's own `gen_*.py` (memory, I/O, CF, PS/2) | [hardware/README.md](../hardware/README.md) |
| `check_card.sh` gate: ERC, gate-level simulation, DRC, the mounting-hole keep-out, fab minimums 0.15 mm track / 0.25 mm drill | hardware/README.md, `generators/check_card.sh` |
| 4.0 mm copper keep-out around the card's DIN connector mounting holes | `generators/gen_kicad.py` |
| Plane pours: 0.2 mm clearance, 0.13 mm minimum thickness | [memory card KiCad README](../hardware/memory-card/kicad/README.md) |
| Exotic parts get the closest standard KiCad footprint, flagged at build time | KICAD-BOARDS.md |
| Fab: 4 layers, 1.6 mm FR-4, HASL | memory card KiCad README |

## 14. Exceptions (2026-10-24)

None of these is written in the card's schematic notes yet, as the preamble asks. None of the boards has been
fabricated, so each is either a note to add or a fix to make before ordering: Ken's call.

| Card | Rule | How it differs | Source |
|---|---|---|---|
| All cards | §2 tracks, clearance, vias; §11 DRC rules | Generated with 0.2 mm tracks, 0.2 mm clearance and 0.6/0.3 mm vias, not 0.4/0.3 and 0.8/0.4; `check_card.sh` enforces only 0.15 mm track / 0.25 mm drill | each `.kicad_pro`, `gen_kicad.py` and the card `gen_*.py`, `check_card.sh` |
| All cards | §1 connector pin row | J1 is centred on the 140 mm edge (pins at about y = 30.6–109.4), not at y = 10.16–88.90 | `gen_kicad.py` |
| All cards | §3 bulk cap | No 10 µF bulk cap on any card (the only electrolytics are the backplane's 470 µF) | `hardware/p8x-bom.csv` |
| All cards | §10 sockets | The BOM lists sockets only as "recommended", not as parts | `generators/gen_bom.py` |
| Control card | §9 SEL LED | PWR, RUN and HALT LEDs; no SEL | `generators/gen_eagle.py` |
| Control card | — | U20 and U21 are DNP by design, but the BOM marks them fitted | `gen_eagle.py`, `p8x-bom.csv` |
| I/O card | §9 LED drive and position | The SEL LED is driven from the gate's output to the anode (source), not sunk; PWR and SEL sit bottom-right on the front edge | `gen_eagle.py`, `gen_io.py` |
| I/O card | — | KICAD-BOARDS.md says the RTC is DNP; the BOM marks U16 and BT1 fitted (with a "DNP option" note) | KICAD-BOARDS.md, `p8x-bom.csv` |
| PS/2 card | §4 logic family, §9 LEDs | An ATmega1284P; its LEDs (KBD-RD, MSE-RD, KEY-AVAIL) are driven high by the ATmega's pins, none follows the bus select | KICAD-BOARDS.md, `gen_eagle.py` |
| PS/2 card | §5 rule 5 | Bus -RES reaches the local reset through 470 Ω, with a 10k pull-up on the card side | `gen_eagle.py` |
| Bus test card | §4, §9 | A Pico (RP2040) and 5× MCP23S17; no SEL LED; the power LED ("5V") is not top-right, which holds the Schottky D1 on an LED footprint | KICAD-BOARDS.md, `gen_eagle.py` |
| CF-IDE card | §6 allocations | Drive 1 at `$FF18–1F` is not yet in the bus document's I/O table | [p8x-bus-definition.md](../hardware/backplane/p8x-bus-definition.md) |

## 15. Where the Files Disagree (to sort out)

1. **Card size in comments:** `gen_kicad.py` says "210x100mm-class" and "pads centred in 100mm", `gen_mem.py` says
   Eurocard 100 mm; the code and every board are 280 × 140 mm.
2. **Bus revision:** §3 says rev C/D; `p8x-bus-definition.md` is titled Rev C2 but holds C3/D content;
   `hardware/README.md` says rev C2.
3. **Net names (§7):** list SPARE4–23, but `busnet()` in `gen_eagle.py` now names PSEL2, FC/FZ/FN/FV, LDZN, SHCIN,
   SETC, CLRC, BSEL and IRQ on those pins.
4. **LED size:** the BOM says 3 mm; the footprint everywhere is 5 mm.
5. **Bus connector:** the BOM says FABC96R with M2.5 mounting holes; the boards use the male MABC96R, and §1 says no
   card mounting holes while the backplane README mentions the screw ring the cards use.
6. **Stale entries:** the BOM still lists the deprecated led-card's parts; the backplane KiCad README still lists the
   parked peripheral card in a slot.
