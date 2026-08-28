#!/bin/sh
# Run the P8X interactively with the GRAPHICS CARD as the display: the
# CPU, OS, BASIC and disk live in the emulator on this machine; every
# $FF20/$FF50 access crosses the serial bridge to the card, whose panel
# shows the pixels (CARD-EDGE-DESIGN.md -- idea 1's daily driver).
#
#   ./os/runcard.sh [serial-device]
#
# Needs the card personality loaded (build.sh card load) -- the emulator
# PINGs and refuses the lcd personality. Uses the same persistent
# os/run-disk.img as run.sh; build it there first.
set -e
root=$(cd "$(dirname "$0")/.." && pwd)
dev=${1:-$(ls /dev/cu.usbserial-* 2>/dev/null | tail -1)}
[ -n "$dev" ] || { echo "runcard: no serial device found"; exit 1; }
[ -f "$root/os/run-disk.img" ] || { echo "runcard: build os/run-disk.img first (P8X_BUILD_ONLY=1 sh os/run.sh)"; exit 1; }
build=$(mktemp -d)
cp "$root"/microcode/u?.bin "$build"/ 2>/dev/null || python3 "$root/microcode/genucode.py" >/dev/null 2>&1
cp "$root"/microcode/u?.bin "$build"/
python3 "$root/assembler/p8xasm.py" "$root/firmware/p8xmon.asm" -o "$build/eeprom.bin" >/dev/null
cc -O2 -o "$build/p8xemu" "$root/emulator/p8xemu.c"
echo "--- the card at $dev is the display; type B to boot P8X/OS ---"
cd "$build"
exec ./p8xemu -B "$dev" -c "$root/os/run-disk.img" -c2 "$root/os/run-disk1.img" eeprom.bin
