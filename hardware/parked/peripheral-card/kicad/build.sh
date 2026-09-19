#!/bin/sh
# build.sh -- build + VERIFY the peripheral card (I/O + CF + PS/2) from its
# placement + netlist.
#
#   hardware/peripheral-card/kicad/build.sh
#
# The bespoke placement (gen_periph.py) is deterministic, so this keeps the
# placement and re-runs everything downstream: PCB trace layout (Freerouting) ->
# import + self-heal stitch -> gerbers/drill/render -> the full manufacture-
# readiness check (ERC + gate-sim + DRC + keepout + fab). GENERATORS ARE CANON.
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
PYK=/Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/3.9/bin/python3
CLI=/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli
FRJAR="${FRJAR:-$HOME/freerouting/freerouting.jar}"
KT="$ROOT/generators/kicad_tools.py"
card=peripheral-card; BRD="$HERE/p8x-$card.kicad_pcb"
q() { grep -viE 'Debug:|assert|wxApp|handler|Fontconfig|traits'; }

echo "== 1/6  bespoke placement + planes + keepouts (gen_periph.py) =="
"$PYK" "$HERE/gen_periph.py" 2>&1 | q | grep -iE 'wrote|overflow|MISMATCH'
echo "== 2/6  export Specctra DSN =="
"$PYK" "$KT" export_dsn "$BRD" 2>&1 | q | grep -i export_dsn
echo "== 3/6  PCB trace layout (Freerouting -- this card is dense, be patient) =="
rm -f "$HERE/p8x-$card.ses"
( cd "$HERE" && java -jar "$FRJAR" -de "p8x-$card.dsn" -do "p8x-$card.ses" -mp 30 -oit 100 -mt 1 > fr.log 2>&1 )
[ -f "$HERE/p8x-$card.ses" ] || { echo "  ROUTE FAILED -- see fr.log"; tail -3 "$HERE/fr.log"; exit 2; }
echo "== 4/6  import routing + self-heal stitch =="
"$PYK" "$KT" import_ses "$BRD" "$HERE/p8x-$card.ses" 2>&1 | q | grep -iE 'stitch|import_ses'
echo "== 5/6  gerbers + drill + render =="
"$PYK" "$KT" finish "$BRD" 2>&1 | q | grep -i finish
echo "== 6/6  VERIFY =="
sh "$ROOT/generators/check_card.sh" "$card" 2>&1 | q
