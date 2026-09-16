#!/bin/sh
# Run the P8X with the GRAPHICS CARD's LCD as the display AND a browser MOUSE PAD
# as the pointer. CPU/OS/BASIC/disk live in the emulator; GL pixels cross the -B
# bridge to the card's panel; a localhost browser pad (tools/p8xwindow.py) is an
# absolute pointer surface -- move/click there and the emulator injects the xterm
# SGR that lib_ptr reads, so the pointer moves ON THE LCD. Keyboard stays HERE.
#
#   ./os/runcard-pad.sh [card-device] [scale]
#
# Needs the card personality loaded (build.sh card load) + os/run-disk.img. The
# pad opens in your default browser; keyboard/console are on this terminal.
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
dev=${1:-$(ls /dev/cu.usbserial-* 2>/dev/null | tail -1)}
scale=${2:-1}     # the pad is an input surface; 1 = 480x272. Pass e.g. 0.75 for smaller, 2 for bigger
[ -n "$dev" ] || { echo "runcard-pad: no serial device found (plug in the card)"; exit 1; }
[ -f "$root/os/run-disk.img" ] || { echo "runcard-pad: build os/run-disk.img first (P8X_BUILD_ONLY=1 sh os/run.sh)"; exit 1; }

build=$(mktemp -d)
cp "$root"/microcode/u?.bin "$build"/ 2>/dev/null || python3 "$root/microcode/genucode.py" >/dev/null 2>&1
cp "$root"/microcode/u?.bin "$build"/
python3 "$root/assembler/p8xasm.py" "$root/firmware/p8xmon.asm" -o "$build/eeprom.bin" >/dev/null
cc -O2 -o "$build/p8xemu" "$root/emulator/p8xemu.c"

sock="$build/pad.sock"
python3 "$root/tools/p8xwindow.py" --sock "$sock" --scale "$scale" &
padpid=$!
cleanup(){ kill "$padpid" 2>/dev/null; rm -f "$sock"; }
trap cleanup EXIT INT TERM

echo "--- card=$dev is the LCD DISPLAY; the browser tab is the MOUSE PAD; keyboard is HERE ---"
echo "--- type B to boot, then finder; move/click in the browser pad to drive the LCD pointer ---"
cd "$build"
./p8xemu -B "$dev" -W "$sock" -c "$root/os/run-disk.img" -c2 "$root/os/run-disk1.img" eeprom.bin
