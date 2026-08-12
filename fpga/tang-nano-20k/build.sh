#!/usr/bin/env bash
# Build (and optionally flash) the Tang Nano 20K bitstream with the open flow.
#
#   ./build.sh            synthesize -> place&route -> pack   (no board needed)
#   ./build.sh load       ... then load to SRAM   (volatile, gone on power cycle)
#   ./build.sh flash      ... then write onboard flash (persists across power)
#
# Needs oss-cad-suite on PATH. If it is not, this sources ~/oss-cad-suite/environment
# for you. On macOS the tarball is unsigned, so after extracting it once:
#     xattr -dr com.apple.quarantine ~/oss-cad-suite
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
ACTION="${1:-build}"

if ! command -v yosys >/dev/null 2>&1; then
  [ -f "$HOME/oss-cad-suite/environment" ] || {
    echo "oss-cad-suite not found. Download the darwin-arm64 release from"
    echo "https://github.com/YosysHQ/oss-cad-suite-build/releases, extract to"
    echo "~/oss-cad-suite, then: xattr -dr com.apple.quarantine ~/oss-cad-suite"; exit 2; }
  # shellcheck disable=SC1091
  source "$HOME/oss-cad-suite/environment"
fi

DEVICE="GW2AR-LV18QN88C8/I7"
FAMILY="GW2A-18C"          # nextpnr needs this explicitly for the GW2A series;
                           # without --vopt family=... it errors out and stops.
PACKDEV="GW2A-18C"

echo "==> synthesize"
yosys -p "read_verilog rtl/top.v rtl/uart.v; synth_gowin -top top -json p8x.json" >synth.log 2>&1 \
  || { tail -20 synth.log; exit 1; }

echo "==> place & route"
nextpnr-himbaechel --json p8x.json --write pnr.json \
  --device "$DEVICE" --vopt family="$FAMILY" --vopt cst=tangnano20k.cst >pnr.log 2>&1 \
  || { tail -20 pnr.log; exit 1; }
grep -E "LUT4:|DFF:" pnr.log | sed 's/^Info:/   /' || true

echo "==> pack"
gowin_pack -d "$PACKDEV" -o p8x.fs pnr.json >pack.log 2>&1 || { tail -20 pack.log; exit 1; }
echo "   bitstream: $(ls -lh p8x.fs | awk '{print $5}')"

case "$ACTION" in
  load)  echo "==> load to SRAM (volatile)"; openFPGALoader -b tangnano20k p8x.fs ;;
  flash) echo "==> write onboard flash (persistent)"; openFPGALoader -b tangnano20k -f p8x.fs ;;
  build) echo "(not loaded -- run './build.sh load' to program the board)" ;;
  *)     echo "unknown action: $ACTION (use build|load|flash)"; exit 2 ;;
esac
