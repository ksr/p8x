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
| memory-card | ✅ | 1 | rev F, bespoke `gen_mem.py` |
| led-card | ✅ | 0 | |
| cf-card | ✅ | 0 | IDE/RTC/coin subs |
| control-card | ✅ | 0 | 14-pin oscillator |
| alu-card | ✅ | 0 | |
| io-card | ✅ | 1 | ACIA/MAX232/RTC/DIP-sw subs |
| regbank-card | ✅ | 0 | 95 parts — routed (5m45s auto + ~13min optimizer) |
| bustest-card | ✅ | 0 | Pico + 17 LEDs; routed with right-edge LED bank |
| backplane | ⚠ placed | — | 10-slot DIN41612 motherboard, ~560×320mm; bus routing is a big follow-up |

## Known follow-ups
- **regbank + bustest routing.** Placed + netlisted + planes at 280×140, but the
  two densest boards defeated Freerouting's time budget. Options: a longer/tuned
  Freerouting pass, or a touch more depth for just those two (breaks strict
  uniformity), or hand-routing.
- **Cosmetic silk crowding** on the densest cards — part values on every part get
  tight; readable and fab-clipped over pads, but not as clean as the memory card.
- **1 stray net** on memory/io — a single Freerouting gap to finish by hand.
- **Placement is auto** (courtyard-spaced flow, 0 overlaps) — a hand pass would
  tidy grouping/silk further.

## Not built (need input)
- **PS/2 keyboard/mouse card** — docs only (`hardware/ps2-card/`), no net-level
  netlist; deriving the wiring is a design task. Level-shifting: **NOYITO TXS0102
  breakout** (user-specified) for the CLK/DATA lines.
- **Graphics card** — Tang Nano 20K FPGA/video board; no TTL netlist.

Exotic parts use the closest standard KiCad footprint (flagged at build time).
