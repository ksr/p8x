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
  cpu)  SRC="../rtl/p8x_cpu.v ../rtl/p8x_mdu.v rtl/p8x_top.v rtl/uart.v rtl/cf_sd.v rtl/sd_spi.v"; TOP=p8x_top;  FS=p8x_cpu.fs ;;
  # `lcd` = cpu + the 480x272 panel, verified working on hardware. Kept a
  # separate target so the plain `cpu` build stays byte-for-byte what it was and
  # costs no block RAM for a display it does not have.
  # lcd now pulls in the SDRAM framebuffer stack: the controller, the arbiter,
  # the engine's pixel back-end, the span filler and the line-buffered scanout.
  # video_rgb.v is gone -- sdram_video.v replaces it.
  lcd)  SRC="../rtl/p8x_cpu.v ../rtl/gfx.v ../rtl/p8x_mdu.v rtl/p8x_top.v rtl/uart.v rtl/cf_sd.v rtl/sd_spi.v sdram/p8x_sdram.v sdram/sdram_arb.v sdram/gfx_mem.v sdram/gfx_span.v sdram/sdram_video.v"; TOP=p8x_top; FS=p8x_lcd.fs; YOSYS_DEFS="-DLCD" ;;
  *)    echo "unknown target: $TARGET (use echo|cpu|lcd)"; exit 2 ;;
esac

# The CPU and LCD builds initialise their BRAM from these; regenerate so a
# microcode or monitor change can never be silently baked into a stale bitstream.
#
# `lcd` was missing from this test, which defeated the whole point: a firmware
# change followed by `build.sh lcd load` produced a bitstream carrying the OLD
# monitor ROM, and loaded it without a word. A CFWAIT timeout fix was "verified"
# on hardware this way and had in fact never reached the board.
if [ "$TARGET" = cpu ] || [ "$TARGET" = lcd ]; then
  python3 mk_compact_ucode.py
  # Assemble the monitor FROM SOURCE, right here. This used to read
  # emulator/eeprom.bin -- a binary someone else was trusted to have
  # refreshed -- and in August 2026 that baked a three-day-old monitor into
  # two consecutive bitstreams while the source grew a boot splash: the exact
  # silent-staleness this block's comment warns about, one level up.
  python3 ../../assembler/p8xasm.py ../../firmware/p8xmon.asm -o ../../emulator/eeprom.bin >/dev/null
  echo "==> eeprom.bin reassembled from firmware/p8xmon.asm"
  python3 - <<'PY'
rom = open("../../emulator/eeprom.bin", "rb").read()[:8192]
rom = rom + b"\x00" * (8192 - len(rom))
open("mem.hex", "w").write("".join("%02x\n" % b for b in rom) + "00\n" * (65536 - 8192))
PY
  echo "==> ucode_c.hex + irmap.vh + mem.hex regenerated"
fi

DEVICE="GW2AR-LV18QN88C8/I7"
FAMILY="GW2A-18C"          # nextpnr needs this explicitly for the GW2A series;
                           # without --vopt family=... it errors out and stops.
PACKDEV="GW2A-18C"

echo "==> synthesize ($TOP)"
yosys -p "read_verilog ${YOSYS_DEFS:-} $SRC; synth_gowin -top $TOP -json p8x.json" >synth.log 2>&1 \
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
