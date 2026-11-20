#!/usr/bin/env bash
# Milestone-1 co-simulation: run the same boot on the RTL and the C emulator,
# diff their per-cycle state traces. PASS = the RTL matches the golden model.
#
#   ./run.sh [CYCLES] [ROM] [RXSCRIPT] [CFIMAGE]
#
#     CYCLES    microcycles to compare          (default 20000)
#     ROM       alternate ROM image to boot     (default: the monitor,
#               assembled from firmware/p8xmon.asm). A path ending in .asm is assembled first,
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

# Microcode: the committed images in microcode/ (genucode.py's output, the same
# files `make rom` burns). emulator/u0-u3.bin are gitignored local copies, absent
# from a fresh clone and free to go stale, so the co-sim does not read them.
UC="$ROOT/microcode"
for f in u0.bin u1.bin u2.bin u3.bin; do
  if [ ! -f "$UC/$f" ]; then
    echo "run.sh: $UC/$f is missing. Rebuild it: cd emulator && make ucode" >&2
    exit 2
  fi
done

# The RTL sources: the CPU, the SoC, and everything p8x_soc.v instantiates
# (the SDRAM model and arbiter, and gfx with its gfx_mem). Keep this list in
# step with p8x_soc.v; a missing module stops iverilog with "Unknown module type".
RTL=("$ROOT/fpga/rtl/p8x_cpu.v" "$ROOT/fpga/rtl/p8x_soc.v" "$ROOT/fpga/rtl/gfx.v"
     "$ROOT/fpga/rtl/sdram_model.v" "$ROOT/fpga/tang-nano-20k/sdram/sdram_arb.v"
     "$ROOT/fpga/tang-nano-20k/sdram/gfx_mem.v" "$HERE/tb_p8x.v")

W="$HERE/work"; mkdir -p "$W"; cd "$W"

# microcode images (built artifacts in emulator/)
for f in u0.bin u1.bin u2.bin u3.bin; do ln -sf "$UC/$f" .; done

# ROM under test: the monitor by default, else the given .bin (or assembled .asm)
if [ -z "$ROM" ]; then
  # The monitor, assembled from firmware/p8xmon.asm on every run, as
  # tang-nano-20k/build.sh does: the committed emulator/eeprom.bin is refreshed
  # only by a board build, so it can lag the source by weeks.
  rm -f eeprom.bin
  python3 "$ROOT/assembler/p8xasm.py" "$ROOT/firmware/p8xmon.asm" -o eeprom.bin >/dev/null
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
python3 "$HERE/mk_ucode_mem.py" "$UC" ucode.hex >/dev/null
python3 - <<'PY'
b=open("eeprom.bin","rb").read()
open("eeprom.hex","w").write("".join("%02x\n"%x for x in b))
PY

# --- golden trace from the emulator (machine trace on stderr) ---
# -N: console RX always empty, matching p8x_soc.v's constant $FF04 = 0x02. Without
# it the trace depends on what stdin is (a TTY reports no key; a redirected stdin
# is at EOF, which reads as RDRF set) and the diff is only valid from a terminal.
# -ng: no GL card fitted, matching p8x_soc.v, which has none: its $FF54 (GLID)
# floats $FF. The monitor probes GLID at boot (since 2026-09-09); without -ng the
# emulator answers 'G' and the two models part at the probe, about cycle 101.
cc -O2 -o p8xemu "$EMU/p8xemu.c"
./p8xemu -T -N -ng "${EMU_RX[@]+"${EMU_RX[@]}"}" "${EMU_CF[@]+"${EMU_CF[@]}"}" -l "$CYCLES" eeprom.bin >emu.console.raw 2>emu.raw || true
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
iverilog -g2012 -DP8X_TRACE -I "$ROOT/fpga/rtl" -o sim.vvp "${RTL[@]}"
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
  diff emu.cut rtl.cut | head -20 || true   # head closes the pipe early: no SIGPIPE exit under pipefail
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
    diff emu.console rtl.console | head -10 || true
    rc=1
  fi
fi
exit $rc
