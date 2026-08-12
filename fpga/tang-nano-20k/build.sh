#!/usr/bin/env bash
# Build (and optionally flash) a Tang Nano 20K bitstream with the open flow.
#
#   ./build.sh [TARGET] [ACTION]
#
#     TARGET  echo  Milestone-0 first light: UART echo + heartbeat  (default)
#             cpu   Milestone-3: the real P8X CPU running the monitor
#     ACTION  build synthesize -> place & route -> pack   (default, no board)
#             load  ... then load to SRAM   (volatile, gone on power cycle)
#             flash ... then write onboard flash (persists across power)
#
#   ./build.sh cpu load        <- the interesting one
#
# Needs oss-cad-suite on PATH; if absent this sources ~/oss-cad-suite/environment.
# On macOS the tarball is unsigned, so after extracting it once:
#     xattr -dr com.apple.quarantine ~/oss-cad-suite
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HERE"
TARGET="${1:-echo}"
ACTION="${2:-build}"

if ! command -v yosys >/dev/null 2>&1; then
  [ -f "$HOME/oss-cad-suite/environment" ] || {
    echo "oss-cad-suite not found. Download the darwin-arm64 release from"
    echo "https://github.com/YosysHQ/oss-cad-suite-build/releases, extract to"
    echo "~/oss-cad-suite, then: xattr -dr com.apple.quarantine ~/oss-cad-suite"; exit 2; }
  # shellcheck disable=SC1091
  source "$HOME/oss-cad-suite/environment"
fi

case "$TARGET" in
  echo) SRC="rtl/top.v rtl/uart.v";                      TOP=top;      FS=p8x.fs ;;
  cpu)  SRC="../rtl/p8x_cpu.v rtl/p8x_top.v rtl/uart.v"; TOP=p8x_top;  FS=p8x_cpu.fs ;;
  *)    echo "unknown target: $TARGET (use echo|cpu)"; exit 2 ;;
esac

# The CPU build initialises its BRAM from these; regenerate so a microcode or
# monitor change can never be silently baked into a stale bitstream.
if [ "$TARGET" = cpu ]; then
  python3 ../sim/mk_ucode_mem.py ../../emulator ucode.hex >/dev/null
  python3 - <<'PY'
rom = open("../../emulator/eeprom.bin", "rb").read()[:8192]
rom = rom + b"\x00" * (8192 - len(rom))
# 32K aliased main memory -- see the note in rtl/p8x_top.v
open("mem.hex", "w").write("".join("%02x\n" % b for b in rom) + "00\n" * (32768 - 8192))
PY
  echo "==> ucode.hex + mem.hex regenerated"
fi

DEVICE="GW2AR-LV18QN88C8/I7"
FAMILY="GW2A-18C"          # nextpnr needs this explicitly for the GW2A series;
                           # without --vopt family=... it errors out and stops.
PACKDEV="GW2A-18C"

echo "==> synthesize ($TOP)"
yosys -p "read_verilog $SRC; synth_gowin -top $TOP -json p8x.json" >synth.log 2>&1 \
  || { tail -20 synth.log; exit 1; }

echo "==> place & route"
nextpnr-himbaechel --json p8x.json --write pnr.json \
  --device "$DEVICE" --vopt family="$FAMILY" --vopt cst=tangnano20k.cst >pnr.log 2>&1 \
  || { tail -20 pnr.log; exit 1; }
grep -E "LUT4:|DFF:|BSRAM:" pnr.log | sed 's/^Info:/  /' || true
grep -E "Max frequency for clock" pnr.log | head -2 | sed 's/^Info:/  /' || true

echo "==> pack"
gowin_pack -d "$PACKDEV" -o "$FS" pnr.json >pack.log 2>&1 || { tail -20 pack.log; exit 1; }
echo "   bitstream: $FS ($(ls -lh "$FS" | awk '{print $5}'))"

case "$ACTION" in
  load)  echo "==> load to SRAM (volatile)";        openFPGALoader -b tangnano20k "$FS" ;;
  flash) echo "==> write onboard flash (persists)"; openFPGALoader -b tangnano20k -f "$FS" ;;
  build) echo "(not loaded -- run './build.sh $TARGET load' to program the board)" ;;
  *)     echo "unknown action: $ACTION (use build|load|flash)"; exit 2 ;;
esac
