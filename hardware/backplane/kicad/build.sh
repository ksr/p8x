#!/bin/sh
# build.sh -- build + VERIFY the P8X backplane (the 8-slot DIN41612 bus) from its
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

# Steps 1-4 retry until the route is complete. The route is order-sensitive:
# KiCad writes the DSN's components and keepouts in a different order on every
# placement run (fresh UUIDs), and Freerouting's result depends on that order.
# Since the CLOCK net class (gen_backplane.py, 2026-10-21) some orders leave a
# connection unrouted; re-routing the SAME DSN (more passes, or a completion
# pass from the existing wiring) reproduces the miss exactly, but a fresh
# placement run is a fresh order. Every attempt is pure generator output.
# An attempt is kept only if it is complete (0 unconnected) AND neither clock
# detoured: a CLOCK-class track takes a whole pin-row gap to itself, so some
# routes push CLK or CLKB around the connector ends (≈ 450 mm instead of the
# ≈ 230 mm daisy chain). CLOCK_MAX_MM rejects those.
ROUTE_TRIES=${ROUTE_TRIES:-6}
CLOCK_MAX_MM=${CLOCK_MAX_MM:-300}
try=1
while :; do
echo "== 1/6  placement + planes + keepouts (gen_backplane.py) =="
"$PYK" "$ROOT/generators/gen_backplane.py" 2>&1 | q | grep -iE 'keepout|wrote'
echo "== 2/6  export Specctra DSN (no edge inset -- the dense bus needs every mm) =="
KT_NO_EDGE_INSET=1 "$PYK" "$KT" export_dsn "$BRD" 2>&1 | q | grep -i export_dsn
echo "== 3/6  PCB trace layout (Freerouting -- ~960-pin bus, this takes a while) =="
# -oit 10 (not 100): the heavy optimiser tripped a FloatPoint.rotate NPE and hung
# on this board; a lighter optimisation pass routes it without the crash. A
# watchdog kills any hang so it can never stall the build indefinitely.
rm -f "$HERE/p8x-backplane.ses"
( cd "$HERE" && java -jar "$FRJAR" -de "p8x-backplane.dsn" -do "p8x-backplane.ses" -mp 30 -oit 10 -mt 1 > fr.log 2>&1 ) &
JPID=$!
W=0; MAX=1200
while kill -0 "$JPID" 2>/dev/null; do
  sleep 15; W=$((W+15))
  if [ "$W" -ge "$MAX" ]; then echo "  ROUTE WATCHDOG: killing Freerouting after ${MAX}s"; kill "$JPID" 2>/dev/null; sleep 2; kill -9 "$JPID" 2>/dev/null; break; fi
done
wait "$JPID" 2>/dev/null
[ -f "$HERE/p8x-backplane.ses" ] || { echo "  ROUTE FAILED -- see fr.log"; tail -5 "$HERE/fr.log"; exit 2; }
echo "== 4/6  import routing + self-heal stitch =="
"$PYK" "$KT" import_ses "$BRD" "$HERE/p8x-backplane.ses" 2>&1 | q | grep -iE 'stitch|import_ses'
# count unconnected exactly as check_card.sh does
RC="$HERE/.route-check.json"
"$CLI" pcb drc --format json -o "$RC" "$BRD" >/dev/null 2>&1
U=$(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1])).get('unconnected_items', [])))" "$RC" 2>/dev/null || echo "?")
rm -f "$RC"
CL=$(python3 - "$BRD" <<'PYEOF'
import re, sys, collections
L = collections.Counter()
for x1, y1, x2, y2, n in re.findall(r'\(segment\s*\(start ([\d.-]+) ([\d.-]+)\)\s*\(end ([\d.-]+) ([\d.-]+)\)'
                                    r'\s*\(width [\d.]+\)\s*\(layer "[^"]+"\)\s*\(net "(CLKB?)"\)', open(sys.argv[1]).read()):
    L[n] += ((float(x2) - float(x1)) ** 2 + (float(y2) - float(y1)) ** 2) ** .5
print(int(max(L.values() or [0])))
PYEOF
)
echo "  route attempt $try/$ROUTE_TRIES: $U unconnected, longest clock ${CL} mm (max $CLOCK_MAX_MM)"
[ "$U" = "0" ] && [ "$CL" -le "$CLOCK_MAX_MM" ] && break
if [ "$try" -ge "$ROUTE_TRIES" ]; then
  [ "$U" = "0" ] && echo "  WARN: complete, but a clock detoured (${CL} mm) after $try attempts -- keeping this route" \
                 || echo "  still $U unconnected after $try attempts -- the check below will FAIL"
  break
fi
try=$((try+1))
done
echo "== 5/6  gerbers + drill + render =="
"$PYK" "$KT" finish "$BRD" 2>&1 | q | grep -i finish
echo "== 6/6  VERIFY (DRC + keepout + fab; ERC/gate-sim N/A for a passive bus) =="
sh "$ROOT/generators/check_card.sh" backplane 2>&1 | q
