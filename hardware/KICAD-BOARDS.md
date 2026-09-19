# P8X KiCad Boards — Status

KiCad 4-layer boards (F/B signals, In1=GND, In2=VCC planes), generated from the
canonical gen_eagle netlists by `generators/gen_kicad.py` (per-card) /
`gen_backplane.py`, autorouted with Freerouting via
`generators/build_kicad_card.sh <card>`. Standard per card: bypass cap above each
IC, LED/jumper labels + part values on silk, placement PDF + top/3D renders +
gerbers.

**Uniform card size: 280 × 140 mm** — status LEDs on the edge opposite the connector. Every plug-in card is the same dimensions
(the connector-edge is 140 mm — the DIN41612 is only ~94 mm, so the extra room
lets components use more rows and keeps the depth down). The backplane is the
motherboard and is physically larger.

| Board | Routed | Unconn. | Notes |
|-------|--------|---------|-------|
| memory-card | ✅ | 0 | rev F, bespoke `gen_mem.py` |
| cf-card | ✅ | 0 | IDE/RTC/coin subs |
| control-card | ✅ | 0 | 14-pin oscillator |
| alu-card | ✅ | 0 | |
| io-card | ✅ | 0 | ACIA/MAX232/RTC/DIP-sw subs; coin-cell GND healed via plane via |
| ps2-card | ✅ | 0 | keyboard + mouse, ATmega328 latch-bridge at `$FF58-5F`; MiniDIN-6 + ICSP; no level-shift (5V-native) |
| regbank-card | ✅ | 0 | 95 parts — routed (5m45s auto + ~13min optimizer) |
| bustest-card | ✅ | 0 | Pico + 17 LEDs; routed with right-edge LED bank |
| backplane | ✅ | 0 | **8-slot** DIN41612 motherboard, 262×128mm (28mm slot pitch, slots left-justified, power/pull-up parts on the right; power entry = Phoenix MSTBA 2,5/2-G-5,08, Digikey 1729128). Routes clean at **0.13mm clearance** (netclass in the `.kicad_pro`) with **nylon-screw** 2mm keepouts. |

> **Deprecated:** the **led-card** (previously routed here) was a CAD-workflow
> test card, never planned to be built. It was moved to
> `hardware/deprecated/led-card/` on 2026-09-18 and its I/O address `$FF0C` freed.
> Not rebuilt or maintained going forward.

> **Parked:** the **peripheral-card** (combined I/O + CF + PS/2, bespoke
> `gen_periph.py`, routed + PASS) was moved to `hardware/parked/peripheral-card/`
> on 2026-09-19 when the design reverted to three separate cards (io + cf + ps2).
> Its netlist is kept intact behind `PARK_PERIPHERAL` in `gen_eagle.py` so it can
> return whole; it is not built or checked in the active flow. Its I/O extras (a
> 2nd ACIA at `$FF08` and two DB9s with RX/TX-swap jumpers) are parked with it.

## Known follow-ups
- **Cosmetic silk crowding** on the densest cards — part values on every part get
  tight; readable and fab-clipped over pads, but not as clean as the memory card.
- **Placement is auto** (courtyard-spaced flow, 0 overlaps) — a hand pass would
  tidy grouping/silk further; the MiniDIN-6 / DB9 connectors are auto-placed, not
  yet guaranteed on a board edge for cable access.

## Not built
- **Graphics card** — Tang Nano 20K FPGA/video board; no TTL netlist.

Exotic parts use the closest standard KiCad footprint (flagged at build time).
