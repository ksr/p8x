---
name: reference_p8x_kicad_pipeline
description: "KiCad card build+verify pipeline — build.sh/check_card.sh, Freerouting quirks, post-route heal steps"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 6ffcfef7-73ca-445b-bcdb-f57735fdc98f
  modified: 2026-10-21T20:02:43.662Z
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

**2026-10-21 — backplane CLOCK net class + order-sensitive routing (8d533b1):**
- **Freerouting is ORDER-sensitive and KiCad's DSN order changes every placement
  run** (fresh UUIDs → components/keepouts emitted in a different order). Same
  board, different order → different result. Re-routing the SAME DSN (more `-mp`
  passes, `-oit 0`, or a completion pass from a DSN that includes the existing
  wiring) reproduces a miss EXACTLY — don't bother. Only a fresh placement run
  rerolls. So `hardware/backplane/kicad/build.sh` now loops placement→DSN→route
  (`ROUTE_TRIES` 6) until 0 unconnected AND longest clock ≤ `CLOCK_MAX_MM` 300.
  A gate on "0 unconnected" alone is not enough: some complete routes detour a clock.
- **DIN41612 pin-field threading ceiling:** 1.55mm pads on 2.54mm pitch leave
  0.99mm; a 0.2mm track between two pins has **0.395mm per side**. A net-class
  clearance applies at PADS too, so any class clearance > ~0.39 means that net
  can't pass between pins and detours round the connector ends (0.5mm doubled
  CLK/CLKB length and left unrouteds). 0.35 works; 0.38 too near the limit.
- A Specctra `(clearance N (type wire_wire))` in a DSN class parses but is NOT
  honoured reliably by Freerouting — can't separate wire-wire from wire-pad spacing.
- **KiCad 10 pcbnew python netclass API:** `ns = board.GetDesignSettings().m_NetSettings`;
  `nc = pcbnew.NETCLASS("CLOCK")`; `ns.SetNetclass(name, nc)`;
  `ns.SetNetclassPatternAssignment("CLK", "CLOCK")`; then
  `board.SynchronizeNetsAndNetClasses(True)`. SaveBoard persists it to .kicad_pro
  and ExportSpecctraDSN emits `(class CLOCK CLK CLKB ... (clearance 350))`.
  `net.GetNetClass()` and `board.GetConnectivity()` return UNWRAPPED swig objects —
  use `ns.GetEffectiveNetClass(name)`, and `kicad-cli pcb drc --format json` for
  unconnected counts.
- **2026-10-24 additions:** `REUSE_ROUTE=1 sh generators/build.sh <card>` re-imports the
  committed .ses instead of re-routing — ONLY for silkscreen-only changes (pads unmoved);
  DRC still catches a stale route. SES import matches footprints BY REFERENCE: duplicate
  refs (the backplane's six `REF**` holes, now H1–H6) get shuffled on re-import — give
  every footprint a unique ref. `silk_labels.py` runs last in every generator; check 6 in
  check_card.sh fails hidden/under-part refs. DSN export routes at 0.21 mm (Freerouting
  polygonises round pads; 0.199 mm misses at Pico pads). Generic flow has a `PINNED`
  table in gen_kicad.py. Silk renders: kicad-cli svg + qlmanage crops to a square — edit
  the SVG viewBox to the region first.
