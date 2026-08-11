#!/usr/bin/env bash
# Milestone-1 co-simulation: run the same boot on the RTL and the C emulator,
# diff their per-cycle state traces. PASS = the RTL matches the golden model.
#
#   ./run.sh [CYCLES] [ROM]
#
#     CYCLES  microcycles to compare            (default 20000)
#     ROM     alternate ROM image to boot       (default: the monitor,
#             emulator/eeprom.bin). A path ending in .asm is assembled first,
#             so `./run.sh 60000 isa_test.asm` runs the all-opcode exerciser.
#
# Needs: a C compiler (for the emulator) and iverilog (from oss-cad-suite).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
EMU="$ROOT/emulator"
CYCLES="${1:-20000}"
ROM="${2:-}"

W="$HERE/work"; mkdir -p "$W"; cd "$W"

# microcode images (built artifacts in emulator/)
for f in u0.bin u1.bin u2.bin u3.bin; do ln -sf "$EMU/$f" .; done

# ROM under test: the monitor by default, else the given .bin (or assembled .asm)
if [ -z "$ROM" ]; then
  ln -sf "$EMU/eeprom.bin" .
else
  case "$ROM" in /*) src="$ROM";; *) src="$HERE/$ROM";; esac
  [ -f "$src" ] || { echo "run.sh: no such ROM: $src" >&2; exit 2; }
  case "$src" in
    *.asm) python3 "$ROOT/assembler/p8xasm.py" "$src" -o rom.bin >/dev/null
           rm -f eeprom.bin; cp rom.bin eeprom.bin ;;
    *)     rm -f eeprom.bin; cp "$src" eeprom.bin ;;
  esac
  echo "ROM under test: $ROM ($(wc -c < eeprom.bin | tr -d ' ') bytes)"
fi

# $readmemh init files for the RTL
python3 "$HERE/mk_ucode_mem.py" "$EMU" ucode.hex >/dev/null
python3 - <<'PY'
b=open("eeprom.bin","rb").read()
open("eeprom.hex","w").write("".join("%02x\n"%x for x in b))
PY

# --- golden trace from the emulator (machine trace on stderr) ---
# -N: console RX always empty, matching p8x_soc.v's constant $FF04 = 0x02. Without
# it the trace depends on what stdin is (a TTY reports no key; a redirected stdin
# is at EOF, which reads as RDRF set) and the diff is only valid from a terminal.
cc -O2 -o p8xemu "$EMU/p8xemu.c"
./p8xemu -T -N -l "$CYCLES" eeprom.bin >/dev/null 2>emu.raw || true
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
