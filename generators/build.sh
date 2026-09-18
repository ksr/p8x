#!/bin/sh
# build.sh <card>|all -- one-command BUILD + VERIFY for any P8X card, dispatching
# to the right builder (each ends with the full manufacture-readiness check):
#
#   generators/build.sh memory-card       # bespoke flow
#   generators/build.sh peripheral-card   # bespoke flow
#   generators/build.sh control-card      # generic gen_kicad flow
#   generators/build.sh all               # every plug-in card, in order
#
# The bespoke cards (memory, peripheral) have their own kicad/build.sh; every
# other gen_eagle card routes through generators/build_kicad_card.sh. Both paths
# run: generate placement -> Freerouting -> import + stitch -> gerbers ->
# ERC + gate-sim + DRC + keepout + fab. GENERATORS ARE CANON.
ROOT=$(cd "$(dirname "$0")/.." && pwd)

run_one() {
  echo "############################## BUILD: $1 ##############################"
  case "$1" in
    memory-card)     sh "$ROOT/hardware/memory-card/kicad/build.sh" ;;
    peripheral-card) sh "$ROOT/hardware/peripheral-card/kicad/build.sh" ;;
    *)               sh "$ROOT/generators/build_kicad_card.sh" "$1" ;;
  esac
}

# build order: simplest/fastest first, the dense boards last
ALL="cf-card led-card bustest-card control-card io-card alu-card regbank-card memory-card peripheral-card"
if [ "$1" = "all" ]; then
  for c in $ALL; do
    # skip cards with no KiCad board target (e.g. the deprecated led-card)
    [ "$c" = "led-card" ] && { echo "skip led-card (deprecated)"; continue; }
    run_one "$c"
  done
elif [ -n "$1" ]; then
  run_one "$1"
else
  echo "usage: build.sh <card>|all   (cards: $ALL)"; exit 2
fi
