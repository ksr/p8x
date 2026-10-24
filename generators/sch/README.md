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

The schematic is generated **alongside the board** in `hardware/<card>/kicad/`,
sharing the board's basename and `.kicad_pro`, so KiCad opens **one unified
project** -- schematic and PCB together, cross-probeable:
- `p8x-<card>.kicad_pro` — the project (the board's; left intact)
- `p8x-<card>.kicad_sch` — hierarchical root, one sheet per functional block
- `p8x-<card>-<n>.kicad_sch` — the sub-sheets: one ELK-wired sheet per functional block, then a label sheet for the bus connector and decoupling
- `p8x-<card>.kicad_pcb` — the board (generated separately; see generators/build.sh)
- `p8x.kicad_sym`, `sym-lib-table` — the generated symbol library (editable in KiCad)
- `p8x-<card>-schematic.pdf` — rendered PDF

**Cross-probing works out of the box.** The schematic and board are generated
independently from the same `gen_eagle` netlist, so they share reference
designators and nets but not UUIDs. `build_sch.sh` runs `link_board.py` after
generating the schematic: it stamps each board footprint with the matching
schematic symbol's UUID path -- the headless equivalent of KiCad's "Update PCB
from Schematic" (F8), metadata only, DRC unchanged. So clicking a symbol
highlights its footprint and vice versa, with no manual step. (Re-run
`build_sch.sh <card>` after rebuilding a board, since the board build does not
know the schematic UUIDs.)

## How it works

| File | Role |
|------|------|
| `p8x_symlib.py` | symbol library: pin **types** (in/out/tri/bidir/oc/pwr/gnd/pas) + left/right **layout** for every device. Pin numbers come from `gen_eagle.DEV`. |
| `p8x_card.py` | adapter: wraps `gen_eagle.CARDS[name]` (parts, nets) into the schematic model; computes the backplane bus-signal set. `VARIANTS` maps a (card, ref) to a schematic-only drawing of its device (same pins and footprint): the io-card's RX/TX swap jumpers as `JMP2X3SWAP`, the DIP-16 resistor networks that feed straight into a row of pins (bustest RN3, io-card RL1 and RM1–RM3) as `RNISO8DSTR`. |
| `p8x_kicad_sch.py` | writes the KiCad `.kicad_sch` project — symbols drawn from the typed pins; label-style or ELK-wired sheets; `--check` runs KiCad ERC and diffs KiCad's own netlist against the canonical one. |
| `p8x_kicad_wire.py` + `elk_layout.js` | ELK (elkjs) places the parts and routes the local nets as orthogonal wires. Power and backplane bus signals keep labels; any other net with two or more pins on a sheet is wired there, and a net that continues to other sheets carries its name as a global label on the wire. Each wire is oriented by drawing side (a right-edge pin feeds a left-edge pin) rather than electrical direction, so a round trip such as ACIA TXD → MAX232 → RXD lays out left to right instead of looping. If ELK cannot route a sheet cleanly, that sheet falls back to label style and `build_sch.sh` prints `falling back`. |
| `p8x_sheets.py` | groups each board's parts into sheets. Default: active ICs on wired sheets in reference order, connectors and passives on label sheets. A card can instead be drawn **by function** (`functional_sheets`): each block names its main parts, and glue gates, LEDs, resistors and connectors that share a local net with it join it automatically. Every card except the backplane is drawn this way since 2026-10-24 (the default grouping remains for a new card). |

**Every build is verified**: KiCad's exported netlist is diffed against the
canonical `gen_eagle` netlist (a routing/rounding short or break shows up there),
so a schematic that does not match the board fails the build.

## Status

All nine boards (eight cards + the backplane) generate, KiCad's netlist matches
the canonical one on every board, and **ERC is 0 errors on all of them**. A few
boards carry benign ERC *warnings* (isolated single-pin labels — bus test taps or
reset lines brought to one pin). The deprecated led-card is skipped.
