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
motherboard (262 × 128 mm).

**None of these boards has been fabricated yet.** Each `kicad/` directory holds the
orderable Gerbers (`p8x-<board>-gerbers.zip`), the DRC report, a placement PDF and
the renders. The DRC reports list 0 unconnected pads on every board; the remaining
DRC items are silkscreen warnings.

| Board | Routed | Unconn. | Notes |
|-------|--------|---------|-------|
| memory-card | ✅ | 0 | rev F, bespoke `gen_mem.py` |
| cf-card | ✅ | 0 | **rev B: two 8-bit True IDE drives** — drive 0 `$FF10-17` (J2), drive 1 `$FF18-1F` (J5), each own 74245 buffer + strobe glue + pull-ups + activity LED; headers 71mm apart for two CF-IDE adapters; bespoke `gen_cf.py`. **NOTE:** drive 1 needs the firmware/emulator port-base change (pending); drive 0 works on current firmware |
| control-card | ✅ | 0 | 14-pin oscillator |
| alu-card | ✅ | 0 | |
| io-card | ✅ | 0 | **rev B: 2x ACIA/DB9** — ACIA1 `$FF04/5` + ACIA2 `$FF08`, two DB9 sockets with RX/TX-swap jumpers (one MAX232 for both), switches, LED bars, bus monitor; bespoke `gen_io.py` (DB9s+switch bottom, LED bars top). RTC/coin cell is DNP |
| ps2-card | ✅ | 0 | keyboard + mouse, **ATmega1284P** latch-bridge at `$FF58-5F`; custom mini-DIN-6 sockets (bottom edge), 4 status LEDs (right edge), ICSP; no level-shift (5V-native); bespoke `gen_ps2.py` |
| regbank-card | ✅ | 0 | 95 parts — routed (5m45s auto + ~13min optimizer) |
| bustest-card | ✅ | 0 | Pico (RP2040) + 5× MCP23S17 + 16 LEDs; routed with right-edge LED bank |
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
> 2nd ACIA at `$FF08` and two DB9s with RX/TX-swap jumpers) were carried over to
> the standalone io-card rev B the same day.

**Assembly render.** [`assembly/`](assembly/README.md) holds 3D renders of the
backplane with all eight cards seated in their slots, built from these boards by
`generators/render_assembly.py` (`sh hardware/assembly/build.sh`). Rebuild it after
a board's placement or parts change.

## Known follow-ups
- **Cosmetic silk crowding** on the densest cards — part values on every part get
  tight; readable and fab-clipped over pads, but not as clean as the memory card.
- **Placement is auto** (courtyard-spaced flow, 0 overlaps) — a hand pass would
  tidy grouping/silk further; the MiniDIN-6 / DB9 connectors are auto-placed, not
  yet guaranteed on a board edge for cable access.

## Not built
- **Graphics card** — Tang Nano 20K FPGA/video board; no TTL netlist.

Exotic parts use the closest standard KiCad footprint (flagged at build time).
