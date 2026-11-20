#!/usr/bin/env bash
# Interactive P8X console on the RTL -- type at the monitor running inside the
# Verilog simulation, before any hardware exists.
#
#   ./console.sh [ROM] [CFIMAGE]
#                             ROM defaults to the monitor (firmware/p8xmon.asm);
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
ROM="${1:-}"
CF="${2:-}"

# Microcode: the committed images in microcode/ (genucode.py's output, the same
# files `make rom` burns). emulator/u0-u3.bin are gitignored local copies, absent
# from a fresh clone and free to go stale, so the co-sim does not read them.
UC="$ROOT/microcode"
for f in u0.bin u1.bin u2.bin u3.bin; do
  if [ ! -f "$UC/$f" ]; then
    echo "console.sh: $UC/$f is missing. Rebuild it: cd emulator && make ucode" >&2
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

for f in u0.bin u1.bin u2.bin u3.bin; do ln -sf "$UC/$f" .; done

if [ -z "$ROM" ]; then
  # The monitor, assembled from firmware/p8xmon.asm on every run, as
  # tang-nano-20k/build.sh does: the committed emulator/eeprom.bin is refreshed
  # only by a board build, so it can lag the source by weeks.
  rm -f eeprom.bin
  python3 "$ROOT/assembler/p8xasm.py" "$ROOT/firmware/p8xmon.asm" -o eeprom.bin >/dev/null
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

python3 "$HERE/mk_ucode_mem.py" "$UC" ucode.hex >/dev/null
python3 - <<'PY'
b=open("eeprom.bin","rb").read()
open("eeprom.hex","w").write("".join("%02x\n"%x for x in b))
PY

command -v iverilog >/dev/null 2>&1 || { echo "iverilog not found (brew install icarus-verilog)"; exit 2; }

# no -DP8X_TRACE: stdout belongs to the console, not the trace
iverilog -g2012 -I "$ROOT/fpga/rtl" -o console.vvp "${RTL[@]}"

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
