#!/bin/sh
# build_kicad_card.sh <cardname> -- full KiCad pipeline for one gen_eagle card:
# generate board -> export DSN -> Freerouting -> import routing -> gerbers+renders.
# Needs KiCad + a Freerouting jar (set FRJAR, default ~/freerouting/freerouting.jar).
card="$1"
PYK=/Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/3.9/bin/python3
CLI=/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli
FRJAR="${FRJAR:-$HOME/freerouting/freerouting.jar}"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
d="$ROOT/hardware/$card/kicad"; brd="$d/p8x-$card.kicad_pcb"
dsn="$d/p8x-$card.dsn"; ses="$d/p8x-$card.ses"
"$PYK" "$ROOT/generators/gen_kicad.py" "$card" 2>/dev/null | grep -viE 'Debug|traits' || exit 1
"$PYK" "$ROOT/generators/kicad_tools.py" export_dsn "$brd" 2>/dev/null | grep -v traits || exit 1
rm -f "$ses"
java -jar "$FRJAR" -de "$dsn" -do "$ses" -mp 30 -oit 100 > "$d/fr.log" 2>&1
if [ ! -f "$ses" ]; then echo "  ROUTE FAILED ($card) -- see fr.log"; tail -3 "$d/fr.log"; exit 2; fi
"$PYK" "$ROOT/generators/kicad_tools.py" import_ses "$brd" "$ses" 2>/dev/null | grep -v traits
echo -n "  DRC: "; "$CLI" pcb drc "$brd" 2>/dev/null | grep -v Fontconfig | grep -iE 'Found .* violation|Found .* unconnected' | tr '\n' ' '; echo
"$PYK" "$ROOT/generators/kicad_tools.py" finish "$brd" 2>/dev/null | grep -v traits
