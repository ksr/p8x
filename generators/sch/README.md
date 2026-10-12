# P8X schematic generator

KiCad schematics for the P8X boards, generated from the **canonical gen_eagle
netlists** — the same source the KiCad boards are built from. There is no
hand-drawn schematic to drift: edit the generator, regenerate (Hard Rule 1).

Ported from the P32X schematic toolchain (ELK-wired sheets).

## Build

```sh
cd generators/sch && npm install      # once: fetches elkjs (ELK layout engine)
sh generators/sch/build_sch.sh all    # every board  (or: build_sch.sh cf-card)
```

Each board lands in `hardware/<card>/kicad/sch/`:
- `<card>.kicad_sch` — hierarchical root, one sheet per functional block
- `<card>-<n>.kicad_sch` — the sub-sheets (ELK-wired logic + label sheets)
- `p8x.kicad_sym`, `sym-lib-table` — the generated symbol library (editable in KiCad)
- `<card>-schematic.pdf` — rendered PDF

## How it works

| File | Role |
|------|------|
| `p8x_symlib.py` | symbol library: pin **types** (in/out/tri/bidir/oc/pwr/gnd/pas) + left/right **layout** for every device. Pin numbers come from `gen_eagle.DEV`. |
| `p8x_card.py` | adapter: wraps `gen_eagle.CARDS[name]` (parts, nets) into the schematic model; computes the backplane bus-signal set. |
| `p8x_kicad_sch.py` | writes the KiCad `.kicad_sch` project — symbols drawn from the typed pins; label-style or ELK-wired sheets; `--check` runs KiCad ERC and diffs KiCad's own netlist against the canonical one. |
| `p8x_kicad_wire.py` + `elk_layout.js` | ELK (elkjs) places the parts and routes the local nets as orthogonal wires; power, bus and cross-sheet nets keep labels. |
| `p8x_sheets.py` | groups each board's parts into sheets (active ICs on wired sheets, connectors and passives on label sheets). |

**Every build is verified**: KiCad's exported netlist is diffed against the
canonical `gen_eagle` netlist (a routing/rounding short or break shows up there),
so a schematic that does not match the board fails the build.

## Status

All nine boards (eight cards + the backplane) generate, KiCad's netlist matches
the canonical one on every board, and **ERC is 0 errors on all of them**. A few
boards carry benign ERC *warnings* (isolated single-pin labels — bus test taps or
reset lines brought to one pin). The deprecated led-card is skipped.
