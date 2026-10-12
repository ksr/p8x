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
ALL="control-card regbank-card alu-card io-card cf-card ps2-card memory-card bustest-card backplane"
[ -d "$HERE/node_modules/elkjs" ] || { echo "run: cd generators/sch && npm install"; exit 2; }

one() {
  card=$1
  out="$ROOT/hardware/$card/kicad/sch"
  echo "===== $card ====="
  python3 "$HERE/p8x_kicad_sch.py" "$card" "$out" --check 2>&1 | grep -viE 'Fontconfig|falling back|^$' | tail -1
  "$CLI" sch export pdf -o "$out/$card-schematic.pdf" "$out/$card.kicad_sch" >/dev/null 2>&1 \
    && echo "  PDF -> hardware/$card/kicad/sch/$card-schematic.pdf"
}

if [ "$1" = "all" ] || [ -z "$1" ]; then
  for c in $ALL; do one "$c"; done
else
  one "$1"
fi
