#!/bin/sh
# build_sch.sh [card]|all -- generate KiCad schematics for the P8X boards from the
# canonical gen_eagle netlists, and render a PDF per board.
#
#   sh generators/sch/build_sch.sh all          # every active card
#   sh generators/sch/build_sch.sh cf-card      # one card
#
# Each board's schematic goes in hardware/<card>/kicad/sch/ : the hierarchical
# <card>.kicad_sch (one sheet per functional block), the generated symbol library
# p8x.kicad_sym, and <card>-schematic.pdf. Every board is checked -- KiCad ERC plus
# a diff of KiCad's own exported netlist against the canonical one -- so a schematic
# that drifts from the board's netlist fails the build. Needs node (ELK wiring) and
# KiCad 10. GENERATORS ARE CANON.
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
CLI=/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli
PYK=/Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/3.9/bin/python3
ALL="control-card regbank-card alu-card io-card cf-card ps2-card memory-card bustest-card backplane"
[ -d "$HERE/node_modules/elkjs" ] || { echo "run: cd generators/sch && npm install"; exit 2; }

# The schematic is generated alongside the board (same directory + basename
# p8x-<card>, sharing <card>'s .kicad_pro) so KiCad opens one unified project --
# schematic and PCB together, cross-probeable. The board's .kicad_pro is left
# intact (write_project only creates one if absent).
one() {
  card=$1
  out="$ROOT/hardware/$card/kicad"
  proj="p8x-$card"
  echo "===== $card ====="
  python3 "$HERE/p8x_kicad_sch.py" "$card" "$out" --proj "$proj" --check 2>&1 | grep -viE 'Fontconfig|falling back|^$' | tail -1
  "$CLI" sch export pdf -o "$out/$proj-schematic.pdf" "$out/$proj.kicad_sch" >/dev/null 2>&1 \
    && echo "  PDF -> hardware/$card/kicad/$proj-schematic.pdf"
  # link the board footprints to the schematic symbols (the F8 "Update PCB from
  # Schematic" linkage; metadata only -- DRC unchanged). Run after the board exists.
  if [ -f "$out/$proj.kicad_pcb" ]; then
    "$PYK" "$HERE/link_board.py" "$card" 2>&1 | grep -iE 'linked' || true
  fi
}

if [ "$1" = "all" ] || [ -z "$1" ]; then
  for c in $ALL; do one "$c"; done
else
  one "$1"
fi
