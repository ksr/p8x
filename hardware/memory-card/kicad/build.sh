#!/bin/sh
# build.sh -- build + VERIFY the memory card from its placement + netlist.
#
#   hardware/memory-card/kicad/build.sh
#
# The parts placement is deterministic (the PLACE table in gen_mem.py), so this
# keeps the placement and re-runs everything downstream: PCB trace layout
# (Freerouting) -> import + self-heal stitch -> gerbers/drill/render -> the full
# manufacture-readiness check (ERC + gate-sim + DRC + keepout + fab). One command,
# start from placement/netlist, end with a PASS/FAIL verdict. GENERATORS ARE CANON.
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
PYK=/Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/3.9/bin/python3
CLI=/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli
FRJAR="${FRJAR:-$HOME/freerouting/freerouting.jar}"
card=memory-card; BRD="$HERE/p8x-$card.kicad_pcb"
q() { grep -viE 'Debug:|assert|wxApp|handler|Fontconfig'; }

echo "== 1/6  placement + planes + keepouts (gen_mem.py) =="
"$PYK" "$HERE/gen_mem.py" 2>&1 | q | grep -iE 'keepout|wrote'
echo "== 2/6  export Specctra DSN =="
"$PYK" "$HERE/export_dsn.py" 2>&1 | q | grep -iE 'patched|exists'
echo "== 3/6  PCB trace layout (Freerouting) =="
rm -f "$HERE/p8x-$card.ses"
( cd "$HERE" && java -jar "$FRJAR" -de "p8x-$card.dsn" -do "p8x-$card.ses" -mp 30 -oit 100 -mt 1 > fr.log 2>&1 )
[ -f "$HERE/p8x-$card.ses" ] || { echo "  ROUTE FAILED -- see fr.log"; tail -3 "$HERE/fr.log"; exit 2; }
echo "== 4/6  import routing + self-heal stitch (import_ses.py) =="
"$PYK" "$HERE/import_ses.py" 2>&1 | q | grep -iE 'stitch|routed'
echo "== 5/6  gerbers + drill + render =="
rm -f "$HERE/gerbers/"*.gbr "$HERE/gerbers/"*.drl 2>/dev/null; mkdir -p "$HERE/gerbers"
"$CLI" pcb export gerbers --no-protel-ext -o "$HERE/gerbers/" "$BRD" >/dev/null 2>&1
"$CLI" pcb export drill --format excellon --excellon-units mm -o "$HERE/gerbers/" "$BRD" >/dev/null 2>&1
( cd "$HERE" && rm -f "p8x-$card-gerbers.zip" && zip -q "p8x-$card-gerbers.zip" gerbers/*.gbr gerbers/*.gbrjob gerbers/*.drl )
"$CLI" pcb render --side top --quality high --floor -w 1800 -h 1000 -o "$HERE/p8x-$card-render-top.png" "$BRD" >/dev/null 2>&1
echo "  gerbers zipped + render updated"
echo "== 6/6  VERIFY =="
sh "$ROOT/generators/check_card.sh" "$card" 2>&1 | q
