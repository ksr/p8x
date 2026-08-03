#!/usr/bin/env bash
# Milestone-1 co-simulation: run the same boot on the RTL and the C emulator,
# diff their per-cycle state traces. PASS = the RTL matches the golden model.
#
#   ./run.sh [CYCLES]      (default 20000)
#
# Needs: a C compiler (for the emulator) and iverilog (from oss-cad-suite).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
EMU="$ROOT/emulator"
CYCLES="${1:-20000}"

W="$HERE/work"; mkdir -p "$W"; cd "$W"

# microcode + monitor ROM images (built artifacts in emulator/)
for f in u0.bin u1.bin u2.bin u3.bin eeprom.bin; do ln -sf "$EMU/$f" .; done

# $readmemh init files for the RTL
python3 "$HERE/mk_ucode_mem.py" "$EMU" ucode.hex >/dev/null
python3 - <<'PY'
b=open("eeprom.bin","rb").read()
open("eeprom.hex","w").write("".join("%02x\n"%x for x in b))
PY

# --- golden trace from the emulator (machine trace on stderr) ---
cc -O2 -o p8xemu "$EMU/p8xemu.c"
./p8xemu -T -l "$CYCLES" eeprom.bin >/dev/null 2>emu.raw || true
grep -E '^[0-9]' emu.raw > emu.trace

# --- RTL trace ---
if ! command -v iverilog >/dev/null 2>&1; then
  echo "iverilog not found. Install oss-cad-suite (also needed for the board),"
  echo "then re-run.  Emulator golden trace is ready at: $W/emu.trace"
  exit 2
fi
iverilog -g2012 -DP8X_TRACE -o sim.vvp \
  "$ROOT/fpga/rtl/p8x_cpu.v" "$ROOT/fpga/rtl/p8x_soc.v" "$HERE/tb_p8x.v"
vvp sim.vvp +cycles="$CYCLES" | grep -E '^[0-9]' > rtl.trace

# --- compare ---
# clip to the shorter length (tail-end off-by-one on the cycle cap is not a bug)
N=$(( $(wc -l < emu.trace) < $(wc -l < rtl.trace) ? $(wc -l < emu.trace) : $(wc -l < rtl.trace) ))
head -n "$N" emu.trace > emu.cut; head -n "$N" rtl.trace > rtl.cut
if diff -q emu.cut rtl.cut >/dev/null; then
  echo "PASS: RTL matches emulator for $N cycles"
else
  echo "DIVERGENCE (first differing cycles):"
  diff emu.cut rtl.cut | head -20
  exit 1
fi
