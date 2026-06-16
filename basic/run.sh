#!/bin/sh
# Build and run P8X BASIC interactively in the emulator.
#   ./basic/run.sh
# Assembles the interpreter, builds the microcode, compiles the emulator, and
# launches it attached to your terminal. The emulator detects the TTY and runs
# the console in raw/blocking mode, so you can type BASIC lines directly.
# Quit with Ctrl-C (or Ctrl-D at the prompt).
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
build=$(mktemp -d)
python3 "$root/assembler/p8xasm.py" "$root/basic/p8xbasic.asm" -o "$build/basic.bin" >/dev/null
( cd "$root/microcode" && python3 genucode.py >/dev/null )
cp "$root"/microcode/u?.bin "$build/"
cc -O2 -o "$build/p8xemu" "$root/emulator/p8xemu.c"
cd "$build"
exec ./p8xemu basic.bin
