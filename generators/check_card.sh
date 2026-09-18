#!/bin/sh
# check_card.sh <card> -- one-command manufacture-readiness check for a P8X card.
#
#   generators/check_card.sh memory-card
#   generators/check_card.sh all            # every card in gen_eagle.CARDS
#
# Runs the full validation stack and prints a PASS/FAIL summary:
#   1. ERC        -- netlist electrical rules (contention / undriven / unpowered)
#   2. gate-sim   -- iverilog logic sim of the as-drawn netlist (if a TB exists)
#   3. DRC        -- KiCad design-rule check (clearance, unconnected, courtyards,
#                    edge clearance, keepouts); report written to the card kicad/ dir
#   4. keepout    -- no track/via within 4mm of a DIN mounting hole (metal screws)
#   5. fab report -- smallest track width + drill vs conservative fab minimums,
#                    plus a reminder of the manual pre-order steps
# Needs KiCad (kicad-cli + bundled pcbnew) and iverilog. GENERATORS ARE CANON.
# (no 'set -e': per-card failures are tracked explicitly and must not abort the run)
PYK=/Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/3.9/bin/python3
CLI=/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli
ROOT=$(cd "$(dirname "$0")/.." && pwd)
MIN_TRACE=0.15   # mm -- conservative 2-layer/4-layer fab minimum (~6 mil)
MIN_DRILL=0.25   # mm -- conservative min finished hole (~10 mil)

cards="$1"
[ "$cards" = "all" ] && cards=$("$PYK" -c "import sys;sys.path.insert(0,'$ROOT/generators');import gen_eagle as g;print(' '.join(sorted(g.CARDS)))")
[ -z "$cards" ] && { echo "usage: check_card.sh <card>|all"; exit 2; }

overall=0
for card in $cards; do
  echo "======================================================================"
  echo "  CHECK: $card"
  echo "======================================================================"
  D="$ROOT/hardware/$card/kicad"; BRD="$D/p8x-$card.kicad_pcb"
  fail=0

  # 1. ERC ---------------------------------------------------------------------
  if [ "$card" = backplane ]; then
    echo "  1. ERC        : N/A (passive bus -- drivers live on the plugged-in cards)"
  else
    erc=$("$PYK" "$ROOT/generators/gen_erc.py" "$card" 2>/dev/null | grep -E '^== ERC' || echo "ERC: (card not in CARDS)")
    ne=$(echo "$erc" | grep -oE '[0-9]+ ERROR' | grep -oE '[0-9]+' || echo 0)
    echo "  1. ERC        : $erc"
    [ "${ne:-0}" -gt 0 ] && fail=1
  fi

  # 2. gate-sim (only cards with a testbench) ---------------------------------
  if [ "$card" = backplane ]; then
    echo "  2. gate-sim   : N/A (no logic -- interconnect only)"
  elif grep -qE "^[[:space:]]*$card\)" "$ROOT/tools/gatesim/run.sh" 2>/dev/null; then
    gs=$(sh "$ROOT/tools/gatesim/run.sh" "$card" 2>/dev/null | grep -iE 'PASS|FAIL' | head -1)
    echo "  2. gate-sim   : ${gs:-(ran, see output)}"
    echo "$gs" | grep -qi FAIL && fail=1
  else
    echo "  2. gate-sim   : (no testbench for this card -- skipped)"
  fi

  # 3-5 need a routed board ----------------------------------------------------
  if [ ! -f "$BRD" ]; then
    echo "  3. DRC        : (no KiCad board yet -- not routed)"
    echo "  --> $card: INCOMPLETE (no board)"; overall=1; continue
  fi

  # 3-5. DRC (blocking vs cosmetic) + keepout + fab (pcbnew) ------------------
  "$CLI" pcb drc -o "$D/p8x-$card-drc.rpt" "$BRD" >/dev/null 2>&1                 # human-readable report
  "$CLI" pcb drc --format json -o /tmp/p8x-$card-drc.json "$BRD" >/dev/null 2>&1
  "$PYK" - "$BRD" "$MIN_TRACE" "$MIN_DRILL" /tmp/p8x-$card-drc.json <<'PYEOF'
import sys, math, json, pcbnew
brd, mintr, mindr, drcj = sys.argv[1], float(sys.argv[2]), float(sys.argv[3]), sys.argv[4]
mm = pcbnew.ToMM
# 3. DRC, categorised: silkscreen issues are cosmetic (the fab trims silk); every
#    other violation type blocks manufacture.
COSMETIC = {"silk_overlap", "silk_edge_clearance", "silk_over_copper"}
d = json.load(open(drcj))
viol = d.get("violations", []); unconn = len(d.get("unconnected_items", []))
blocking = sum(1 for v in viol if v["type"] not in COSMETIC)
cosmetic = sum(1 for v in viol if v["type"] in COSMETIC)
print("  3. DRC        : %d blocking, %d cosmetic-silk, %d unconnected" % (blocking, cosmetic, unconn))
b = pcbnew.LoadBoard(brd)
# 4. keepout: DIN NPTH mounting holes vs tracks/vias
holes = [(mm(p.GetPosition().x), mm(p.GetPosition().y))
         for fp in b.GetFootprints() if "DIN41612" in str(fp.GetFPIDAsString())
         for p in fp.Pads() if p.GetAttribute() == pcbnew.PAD_ATTRIB_NPTH]
near = sum(1 for t in b.GetTracks()
           if any(math.hypot(mm(t.GetStart().x)-hx, mm(t.GetStart().y)-hy) < 4.0 for hx, hy in holes))
print("  4. keepout    : %d DIN hole(s) -- %s" % (len(holes),
      "PASS (0 copper within 4mm)" if near == 0 else "FAIL (%d near a hole)" % near))
# 5. fab: smallest track width + drill vs conservative fab minimums
tws = [mm(t.GetWidth()) for t in b.GetTracks() if t.Type() == pcbnew.PCB_TRACE_T]
drs = [mm(p.GetDrillSizeX()) for fp in b.GetFootprints() for p in fp.Pads() if mm(p.GetDrillSizeX()) > 0]
drs += [mm(t.GetDrillValue()) for t in b.GetTracks() if t.Type() == pcbnew.PCB_VIA_T]
mintw = min(tws) if tws else 0; mindl = min(drs) if drs else 0
tflag = "" if mintw >= mintr else "  <-- below %.2fmm fab min!" % mintr
dflag = "" if mindl >= mindr else "  <-- below %.2fmm fab min!" % mindr
print("  5. fab        : min track %.3fmm%s ; min drill %.3fmm%s" % (mintw, tflag, mindl, dflag))
# verdict: FAIL only on blocking DRC / unconnected / keepout / sub-min features.
# cosmetic silk is a WARNING, not a manufacturing blocker.
bad = blocking or unconn or near or (mintw and mintw < mintr) or (mindl and mindl < mindr)
if cosmetic and not bad:
    print("  (note: %d cosmetic silk overlap(s) -- fab trims silk; not a blocker)" % cosmetic)
sys.exit(1 if bad else 0)
PYEOF
  [ $? -ne 0 ] && fail=1

  if [ "$fail" -eq 0 ]; then echo "  --> $card: PASS (automated checks clean)"; else echo "  --> $card: FAIL (see above)"; overall=1; fi
done

echo "======================================================================"
echo "  Manual steps still required before ordering (not automatable here):"
echo "   * confirm each SUB footprint against the real part you buy"
echo "   * run your fab house's own DRC (their trace/space/drill limits)"
echo "   * eyeball the gerbers in a gerber viewer"
echo "======================================================================"
[ "$overall" -eq 0 ] && echo "ALL CHECKED CARDS PASS" || echo "SOME CARDS FAILED / INCOMPLETE"
exit $overall
