#!/bin/sh
# Run the P8X in the emulator with a live Mac DISPLAY WINDOW and MOUSE, no card.
# The emulator (CPU/OS/BASIC/disk, all local) renders the 480x272 panel and
# streams it to tools/p8xwindow.py, which shows it in a window and sends mouse
# events back -- so finder and the desktop are mouse-driven. Keyboard and console
# stay on THIS terminal (type B to boot, then `finder`).
#
#   ./os/run-window.sh [scale]        (scale = pixel zoom, default 2)
#
# Uses the same persistent os/run-disk.img as run.sh; build it there first.
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
scale=${1:-2}
[ -f "$root/os/run-disk.img" ] || { echo "run-window: build os/run-disk.img first (P8X_BUILD_ONLY=1 sh os/run.sh)"; exit 1; }

build=$(mktemp -d)
cp "$root"/microcode/u?.bin "$build"/ 2>/dev/null || python3 "$root/microcode/genucode.py" >/dev/null 2>&1
cp "$root"/microcode/u?.bin "$build"/
python3 "$root/assembler/p8xasm.py" "$root/firmware/p8xmon.asm" -o "$build/eeprom.bin" >/dev/null
cc -O2 -o "$build/p8xemu" "$root/emulator/p8xemu.c"

sock="$build/p8x.sock"
# the window listens first; the emulator retries the connect for ~5s
python3 -u "$root/tools/p8xwindow.py" --sock "$sock" --scale "$scale" &
winpid=$!
cleanup(){ kill "$winpid" 2>/dev/null; rm -f "$sock"; }
trap cleanup EXIT INT TERM

echo "--- P8X in a window (mouse there); keyboard is HERE -- type B to boot, then finder ---"
cd "$build"
./p8xemu -W "$sock" -c "$root/os/run-disk.img" -c2 "$root/os/run-disk1.img" eeprom.bin
