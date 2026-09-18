#!/bin/sh
# build.sh -- build + VERIFY the P8X backplane (the 10-slot DIN41612 bus) from its
# placement + netlist.
#
#   hardware/backplane/kicad/build.sh
#
# The backplane is a passive bus, not a logic card, so ERC/gate-sim are N/A -- the
# verify step runs DRC + keepout + fab only. Placement (gen_backplane.py) is
# deterministic; this re-runs everything downstream: PCB trace layout (Freerouting,
# a big ~960-pin bus so be patient) -> import + self-heal stitch -> gerbers/render
# -> the readiness check. GENERATORS ARE CANON.
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
PYK=/Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/3.9/bin/python3
CLI=/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli
FRJAR="${FRJAR:-$HOME/freerouting/freerouting.jar}"
KT="$ROOT/generators/kicad_tools.py"
BRD="$HERE/p8x-backplane.kicad_pcb"
q() { grep -viE 'Debug:|assert|wxApp|handler|Fontconfig|traits'; }

echo "== 1/6  placement + planes + keepouts (gen_backplane.py) =="
"$PYK" "$ROOT/generators/gen_backplane.py" 2>&1 | q | grep -iE 'keepout|wrote'
echo "== 2/6  export Specctra DSN =="
"$PYK" "$KT" export_dsn "$BRD" 2>&1 | q | grep -i export_dsn
echo "== 3/6  PCB trace layout (Freerouting -- ~960-pin bus, this takes a while) =="
rm -f "$HERE/p8x-backplane.ses"
( cd "$HERE" && java -jar "$FRJAR" -de "p8x-backplane.dsn" -do "p8x-backplane.ses" -mp 30 -oit 100 -mt 1 > fr.log 2>&1 )
[ -f "$HERE/p8x-backplane.ses" ] || { echo "  ROUTE FAILED -- see fr.log"; tail -3 "$HERE/fr.log"; exit 2; }
echo "== 4/6  import routing + self-heal stitch =="
"$PYK" "$KT" import_ses "$BRD" "$HERE/p8x-backplane.ses" 2>&1 | q | grep -iE 'stitch|import_ses'
echo "== 5/6  gerbers + drill + render =="
"$PYK" "$KT" finish "$BRD" 2>&1 | q | grep -i finish
echo "== 6/6  VERIFY (DRC + keepout + fab; ERC/gate-sim N/A for a passive bus) =="
sh "$ROOT/generators/check_card.sh" backplane 2>&1 | q
