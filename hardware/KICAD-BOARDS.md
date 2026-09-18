# P8X KiCad Boards — Status

KiCad 4-layer boards (F/B signals, In1=GND, In2=VCC planes), generated from the
canonical gen_eagle netlists by `generators/gen_kicad.py` (per-card) /
`gen_backplane.py`, autorouted with Freerouting via
`generators/build_kicad_card.sh <card>`. Each lives in `hardware/<card>/kicad/`.
Standard: bypass cap above each IC, labelled LED/jumper bank, part values on silk,
placement PDF + top/3D renders + orderable gerbers.

| Board | Size (mm) | Routed | Unconn. | Notes |
|-------|-----------|--------|---------|-------|
| memory-card | 210×100 | ✅ | 0 | rev F, hand-tuned (bespoke `gen_mem.py`) |
| led-card | 200×100 | ✅ | 0 | |
| control-card | 300×100 | ✅ | 0 | |
| cf-card | 200×100 | ✅ | 0 | IDE 2×20, RTC, coin-cell subs |
| alu-card | 300×100 | ✅ | 1 | 1 net short of complete |
| io-card | 400×100 | ✅ | 1 | ACIA/MAX232/RTC/DIP-sw subs |
| regbank-card | 340×100 | ✅ | 1 | largest (95 parts, 3920 tracks) |
| bustest-card | 230×100 | ⚠ placed | — | Pico bus too dense to auto-route |
| backplane | 560×320 | ⚠ placed | — | 10-slot bus is a large routing job |

## Known follow-ups
- **Oversized boards.** The auto-placer (cap-above-each-IC + safe gaps) is less
  dense than the hand-routed Eagle cards, so the big cards run 300–400 mm wide
  instead of ~210. They route and are orderable, but a denser placement pass would
  bring them closer to the memory-card size.
- **Cosmetic silk.** The generic silk placement leaves some ref/value overlaps
  (fab-clipped over pads); not as tuned as the memory card's.
- **1 unrouted net** on io/alu/regbank — Freerouting left a single connection;
  finish by hand or a longer pass.
- **bustest + backplane routing** — placed + netlisted + planes; routing pending.

## Not built (need input)
- **PS/2 keyboard/mouse card** — designed only as docs (`hardware/ps2-card/`), no
  net-level netlist. Building it means deriving the exact wiring (74HC164/161/574,
  7407 open-collector, decode) — a design task to confirm, not auto-generate.
- **Graphics card** — the Tang Nano 20K FPGA card; a bespoke FPGA/video board with
  no TTL netlist. Needs a from-scratch schematic/netlist decision.

Exotic parts use the closest standard KiCad footprint (flagged at build time).
