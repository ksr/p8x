---
name: reference_p8x_kicad_pipeline
description: "KiCad card build+verify pipeline — build.sh/check_card.sh, Freerouting quirks, post-route heal steps"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 6ffcfef7-73ca-445b-bcdb-f57735fdc98f
  modified: 2026-09-19T01:48:14.945Z
---

The KiCad card flow (GENERATORS ARE CANON). One command per card or all:
`generators/build.sh <card>|all` → dispatches to each card's bespoke
`hardware/<card>/kicad/build.sh` (memory, peripheral, backplane) or the generic
`generators/build_kicad_card.sh`. Every path ends in `generators/check_card.sh`
(ERC + gate-sim + DRC[blocking vs cosmetic-silk] + keepout + fab). Verdict FAILs
only on blocking DRC / unconnected / keepout / sub-min features.

**Shared steps live in `generators/kicad_tools.py`** (run under KiCad's bundled
python; `sys.stdout.flush(); os._exit(0)` at the end dodges the wx.App exit hang):
- `export_dsn` — unfill zones, mark In1/In2 as power, and **inset the Freerouting
  routing boundary 0.35mm** so copper keeps off the board edge (fixed bustest A2
  hugging the DIN edge at 0.468 vs the 0.5mm rule). Set `KT_NO_EDGE_INSET=1` to
  skip it — the backplane does, its dense bus needs the room.
- `import_ses` — import routing, `stitch_trivial_nets` (collinear 2-pad),
  ZONE_FILLER, then `heal_edge_clearance` + `heal_unconnected`.
- `heal_unconnected` — DRC-driven. The realistic leftover is a **plane-net orphan**:
  an SMD pad on GND/VCC (e.g. DNP coin-cell BT1, Keystone holder is surface-mount)
  can't reach the In1/In2 plane through a barrel and the router skipped its F.Cu
  tie → drop a stitching VIA into solid same-net plane + short F.Cu track, at a
  site clear of other pads AND foreign tracks. Non-plane misses are left for a human.
- `heal_edge_clearance` — pull any track vertex inside the 0.5mm edge rule back in
  (measured to the Edge.Cuts CENTRELINE; the board bbox includes the cut-line
  half-width, which made the first attempt miss by exactly 0.075mm).
- `heal_bus_gaps` (subcommand `heal_bus`, NOT in import_ses) — for backplane bus
  hops: straight/L clearance-checked track between an unconnected pair. On the
  dense backplane the direct paths cross other buses, so it usually can't help.

**Freerouting quirks (1.9.0, `~/freerouting/freerouting.jar`):** run from the card
dir; `-mt 1` (multi-thread optimizer is broken). The heavy optimizer (`-oit 100`)
tripped a `FloatPoint.rotate` NPE and **hung 45 min** on the backplane → backplane
build uses `-oit 10` + a **shell watchdog** (kills after 1200s) so a hang can't
stall the build. `--help` launches the GUI (no headless help) — don't call it.

Status 2026-09-18: ALL nine cards PASS, backplane included -- now fully routed
(0 unconnected) at 8 slots + 0.13mm clearance; see [[reference_p8x_backplane_keepout]].
heal_bus_gaps was NOT needed in the end (Freerouting closed every net at 0.13mm)
but is hardened: reads the board's own clearance rule, lays 0.2mm track, re-fills
planes around new vias, and its self-check copies the .kicad_pro beside the temp so
DRC judges against the real rule, not the 0.2mm default.
