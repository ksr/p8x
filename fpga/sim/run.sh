#!/usr/bin/env bash
# Milestone-1 co-simulation: run the same boot on the RTL and the C emulator,
# diff their per-cycle state traces. PASS = the RTL matches the golden model.
#
#   ./run.sh [CYCLES] [ROM] [RXSCRIPT] [CFIMAGE]
#
#     CYCLES    microcycles to compare          (default 20000)
#     ROM       alternate ROM image to boot     (default: the monitor,
#               emulator/eeprom.bin). A path ending in .asm is assembled first,
#               so `./run.sh 60000 isa_test.asm` runs the all-opcode exerciser.
#     RXSCRIPT  file of console input bytes fed identically to both models, so
#               the monitor can be driven past its prompt. Both sides use the
#               same rule -- RDRF = "bytes remain", one byte consumed per $FF05
#               read -- so there is no timing to diverge on. When given, the
#               console OUTPUT of both models is diffed too.
#     CFIMAGE   CF disk image (e.g. os/run-disk.img). Copied into work/ first,
#               so a run can never mutate the real disk. With it the monitor's
#               B command boots the OS inside the simulation.
#
# Needs: a C compiler (for the emulator) and iverilog (from oss-cad-suite).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
EMU="$ROOT/emulator"
CYCLES="${1:-20000}"
ROM="${2:-}"
RXS="${3:-}"
CF="${4:-}"      # CF disk image, attached read-only to both models

# The microcode images and the monitor ROM are build products of the emulator
# tree, and u0-u3.bin are gitignored -- a fresh clone does not have them. Check
# before use: without this the first failure is a Python traceback out of
# mk_ucode_mem.py, which says nothing about what to run.
for f in u0.bin u1.bin u2.bin u3.bin eeprom.bin; do
  if [ ! -f "$EMU/$f" ]; then
    echo "run.sh: $EMU/$f is missing." >&2
    echo "  The emulator tree builds it. From the repo root:" >&2
    echo "      cd emulator && make" >&2
    exit 2
  fi
done

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

# CF disk. Copied into work/ so the co-sim can never touch the real image: the
# emulator opens it read-write and a stray WRITE SECTORS would corrupt a 6 MB
# OS disk, while the RTL model opens read-only. Same bytes either way.
EMU_CF=(); RTL_CF=()
if [ -n "$CF" ]; then
  case "$CF" in /*) csrc="$CF";; *) csrc="$ROOT/$CF";; esac
  [ -f "$csrc" ] || { echo "run.sh: no such disk image: $csrc" >&2; exit 2; }
  cp "$csrc" disk.img
  EMU_CF=(-c disk.img); RTL_CF=("+cf=disk.img")
  echo "CF disk: $CF ($(du -h disk.img | cut -f1 | tr -d ' '), copy, read-only)"
fi

# scripted console input: raw bytes for the emulator, one hex byte per line for
# the RTL. Same bytes, two encodings -- generated together so they cannot drift.
EMU_RX=(); RTL_RX=()
if [ -n "$RXS" ]; then
  case "$RXS" in /*) rsrc="$RXS";; *) rsrc="$HERE/$RXS";; esac
  [ -f "$rsrc" ] || { echo "run.sh: no such input script: $rsrc" >&2; exit 2; }
  # newline -> CR: the monitor's line reader expects CR, and a plain text file
  # is far easier to read and edit than a blob of raw control bytes.
  python3 - "$rsrc" <<'PY'
import sys
b=open(sys.argv[1],"rb").read().replace(b"\n",b"\r")
open("rx.bin","wb").write(b)
open("rx.hex","w").write("".join("%02x\n"%x for x in b))
PY
  EMU_RX=(-i rx.bin); RTL_RX=("+rx=rx.hex")
  echo "console input: $RXS ($(wc -c < rx.bin | tr -d ' ') bytes)"
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
./p8xemu -T -N "${EMU_RX[@]+"${EMU_RX[@]}"}" "${EMU_CF[@]+"${EMU_CF[@]}"}" -l "$CYCLES" eeprom.bin >emu.console.raw 2>emu.raw || true
grep -E '^[0-9]' emu.raw > emu.trace
# Guard: the emulator must respect -l. It used to drop the cycle cap whenever
# stdin was a TTY, so a -T run launched from a shell streamed a trace line per
# cycle until the disk filled (80 GB in one sitting, held open by an orphaned
# process so rm did not even free it). Fixed in p8xemu, but fail loudly rather
# than silently regenerate the hazard.
EL=$(wc -l < emu.trace | tr -d ' ')
if [ "$EL" -gt $(( CYCLES + 1000 )) ]; then
  echo "run.sh: emulator ignored -l ($EL trace lines for $CYCLES cycles) -- aborting" >&2
  rm -f emu.raw emu.trace
  exit 3
fi
# emulator console bytes -> the same one-hex-byte-per-line form the RTL logs
python3 - <<'PY'
b=open("emu.console.raw","rb").read()
open("emu.console","w").write("".join("%02x\n"%x for x in b))
PY

# --- RTL trace ---
if ! command -v iverilog >/dev/null 2>&1; then
  echo "iverilog not found. Install oss-cad-suite (also needed for the board),"
  echo "then re-run.  Emulator golden trace is ready at: $W/emu.trace"
  exit 2
fi
iverilog -g2012 -DP8X_TRACE -o sim.vvp \
  "$ROOT/fpga/rtl/p8x_cpu.v" "$ROOT/fpga/rtl/p8x_soc.v" "$HERE/tb_p8x.v"
rm -f rtl.console
vvp sim.vvp +cycles="$CYCLES" "${RTL_RX[@]+"${RTL_RX[@]}"}" "${RTL_CF[@]+"${RTL_CF[@]}"}" +tx=rtl.console \
  | grep -E '^[0-9]' > rtl.trace
touch rtl.console

# --- compare ---
# clip to the shorter length (tail-end off-by-one on the cycle cap is not a bug)
N=$(( $(wc -l < emu.trace) < $(wc -l < rtl.trace) ? $(wc -l < emu.trace) : $(wc -l < rtl.trace) ))
head -n "$N" emu.trace > emu.cut; head -n "$N" rtl.trace > rtl.cut
rc=0
if diff -q emu.cut rtl.cut >/dev/null; then
  echo "PASS: RTL matches emulator for $N cycles"
else
  echo "DIVERGENCE (first differing cycles):"
  diff emu.cut rtl.cut | head -20
  rc=1
fi

# --- console output: an independent check on the same run ---
# The trace diff already covers the registers; this catches a console model that
# agrees cycle-by-cycle but emits different bytes.
if [ -n "$RXS" ]; then
  ec=$(wc -l < emu.console | tr -d ' '); rcn=$(wc -l < rtl.console | tr -d ' ')
  if diff -q emu.console rtl.console >/dev/null; then
    echo "PASS: console output identical ($ec bytes)"
  else
    echo "CONSOLE MISMATCH (emulator $ec bytes, RTL $rcn bytes):"
    diff emu.console rtl.console | head -10
    rc=1
  fi
fi
exit $rc
