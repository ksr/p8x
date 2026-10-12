---
name: project_p8x_kicad_schematics
description: "P8X now generates KiCad schematics for all 9 boards from the netlists (generators/sch/, ported from p32); ELK-wired, netlist-verified"
metadata:
  node_type: memory
  type: project
  originSessionId: 6ffcfef7-73ca-445b-bcdb-f57735fdc98f
  modified: 2026-10-12T04:41:15.533Z
---

**KiCad schematics are generated from the canonical gen_eagle netlists** (2026-10-11),
ported from the P32X schematic toolchain. Lives in `generators/sch/`. No hand-drawn
schematic exists -- edit the generator, regenerate (Hard Rule 1). See [[project_p8x_kicad_cad]].

- **Build:** `cd generators/sch && npm install` (once, fetches elkjs), then
  `sh generators/sch/build_sch.sh all` (or one board). **Unified with the board:**
  output goes in `hardware/<board>/kicad/` (NOT a sch/ subdir) with the board's
  basename `p8x-<board>` sharing its `.kicad_pro`, so KiCad opens ONE project per
  board (schematic + PCB together). Files: `p8x-<board>.kicad_sch` (root, one
  sheet per block) + `-N.kicad_sch` + `p8x.kicad_sym` + `p8x-<board>-schematic.pdf`.
- **Cross-probing auto-linked:** `build_sch.sh` runs `link_board.py` after each
  schematic -- stamps board footprints with the schematic symbols' UUID paths
  (headless KiCad F8 "Update PCB from Schematic"; metadata only, DRC unchanged).
  Re-run build_sch after rebuilding a board (gen_kicad doesn't know the sch UUIDs).
  p8x_kicad_sch.py `--proj` sets the file basename separate from the UUID card name.
- **Pipeline:** `p8x_symlib.py` (typed-pin symbol lib for all 54 devices -- pin
  TYPES in/out/tri/bidir/oc/pwr/gnd + left/right layout; pin NUMBERS come from
  gen_eagle.DEV) -> `p8x_card.py` (adapter wrapping gen_eagle.CARDS, plus
  load("backplane") from gen_eagle.bps/bpn) -> `p8x_kicad_sch.py` (emits
  .kicad_sch; symbols drawn procedurally) + `p8x_kicad_wire.py`/`elk_layout.js`
  (ELK auto-wires logic sheets as orthogonal wires + junctions; power/bus/
  cross-sheet nets stay labels) -> `p8x_sheets.py` (per-board sheet grouping).
- **Verified:** `--check` runs KiCad ERC AND diffs KiCad's own exported netlist
  against the canonical gen_eagle netlist -- a routing/rounding short or break
  fails the build. All 9 boards: netlist matches exactly.
- **ERC: all 9 boards 0 errors.** A few carry benign warnings (isolated single-pin
  labels -- bus test taps / reset lines). bustest's 5 MCP23S17 unused INT pins are
  typed "pas" (tied off to GND on that fixture, the only board using the part) so
  they do not false-error. led-card skipped (deprecated).
- **Gotchas:** runs under HOST python3 (NOT KiCad's pcbnew python -- footprint map
  inlined in p8x_symlib FP_PKG/FP_DEV). node_modules gitignored (npm install to
  restore). `.kicad_prl` gitignored (per-user). The carry-chain RC nets ARE wired
  (threshold: skip same-device chains only past 3 chips) -- that is what makes the
  regbank counter chains flow left-to-right. 74HCT688 !PEQ is totem-pole (out), not
  oc. Datapath/bus-heavy sheets (alu operands) stay label-style rows by nature.
