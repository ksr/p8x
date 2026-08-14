#!/usr/bin/env bash
# Interactive P8X console on the RTL -- type at the monitor running inside the
# Verilog simulation, before any hardware exists.
#
#   ./console.sh [ROM] [CFIMAGE]
#                             ROM defaults to the monitor (emulator/eeprom.bin);
#                             a .asm path is assembled first, as in run.sh.
#                             CFIMAGE attaches a disk (a WRITABLE copy), so the
#                             monitor B command boots the OS: try os/run-disk.img
#
# This is NOT the co-sim: a live console is not reproducible, so nothing is
# diffed here. Use run.sh for verification and this for driving the machine.
#
# Quit with Ctrl-D (EOF ends the simulation). Ctrl-C also works.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
EMU="$ROOT/emulator"
ROM="${1:-}"
CF="${2:-}"

# The microcode images and the monitor ROM are build products of the emulator
# tree, and u0-u3.bin are gitignored -- a fresh clone does not have them. Check
# before use: without this the first failure is a Python traceback out of
# mk_ucode_mem.py, which says nothing about what to run.
for f in u0.bin u1.bin u2.bin u3.bin eeprom.bin; do
  if [ ! -f "$EMU/$f" ]; then
    echo "console.sh: $EMU/$f is missing." >&2
    echo "  The emulator tree builds it. From the repo root:" >&2
    echo "      cd emulator && make" >&2
    exit 2
  fi
done

W="$HERE/work"; mkdir -p "$W"; cd "$W"

for f in u0.bin u1.bin u2.bin u3.bin; do ln -sf "$EMU/$f" .; done

if [ -z "$ROM" ]; then
  ln -sf "$EMU/eeprom.bin" .
else
  case "$ROM" in /*) src="$ROM";; *) src="$HERE/$ROM";; esac
  [ -f "$src" ] || { echo "console.sh: no such ROM: $src" >&2; exit 2; }
  case "$src" in
    *.asm) python3 "$ROOT/assembler/p8xasm.py" "$src" -o rom.bin >/dev/null
           rm -f eeprom.bin; cp rom.bin eeprom.bin ;;
    *)     rm -f eeprom.bin; cp "$src" eeprom.bin ;;
  esac
fi

RTL_CF=()
if [ -n "$CF" ]; then
  case "$CF" in /*) csrc="$CF";; *) csrc="$ROOT/$CF";; esac
  [ -f "$csrc" ] || { echo "console.sh: no such disk image: $csrc" >&2; exit 2; }
  # A COPY, always: the session writes to it (+cfrw below), and the real image
  # must not be modified by an exploratory run. Your changes therefore live in
  # work/disk.img and are replaced the next time console.sh starts -- copy it out
  # if you want to keep them.
  cp "$csrc" disk.img
  RTL_CF=("+cf=disk.img" "+cfrw")
fi

python3 "$HERE/mk_ucode_mem.py" "$EMU" ucode.hex >/dev/null
python3 - <<'PY'
b=open("eeprom.bin","rb").read()
open("eeprom.hex","w").write("".join("%02x\n"%x for x in b))
PY

command -v iverilog >/dev/null 2>&1 || { echo "iverilog not found (brew install icarus-verilog)"; exit 2; }

# no -DP8X_TRACE: stdout belongs to the console, not the trace
iverilog -g2012 -o console.vvp \
  "$ROOT/fpga/rtl/p8x_cpu.v" "$ROOT/fpga/rtl/p8x_soc.v" "$HERE/tb_p8x.v"

# Char-at-a-time, no echo (the monitor echoes), Enter stays CR. Deliberately NOT
# `stty raw`: raw also clears ISIG, which would swallow Ctrl-C and leave no way
# out but killing the process from another terminal. These are the same termios
# bits p8xemu sets for its own interactive console.
if [ -t 0 ]; then
  saved=$(stty -g)
  trap 'stty "$saved" 2>/dev/null; echo' EXIT INT TERM
  stty -icanon -echo -icrnl
fi

echo "P8X on RTL -- Ctrl-D or Ctrl-C to quit"
# No `exec`: exec would replace this shell and the EXIT trap would never run,
# leaving the terminal with echo off after the simulation ends.
vvp console.vvp +con "${RTL_CF[@]+"${RTL_CF[@]}"}"
