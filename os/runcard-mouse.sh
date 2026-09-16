#!/bin/sh
# Run the P8X on the GRAPHICS CARD (like runcard.sh) but with a real
# MICROSOFT SERIAL MOUSE driving the pointer. Two serial links are in play:
#
#   card  (-B bridge): GL-port pixels cross to the card's panel
#   mouse (RS-232):    a vintage MS serial mouse on a USB-DB9 adapter,
#                      read by tools/serialmouse.py and injected as xterm
#                      SGR reports into the emulator console (what lib_ptr
#                      already speaks -- no P8X-side change).
#
#   ./os/runcard-mouse.sh <mouse-device> [card-device]
#
# The mouse device is required (there is no way to guess which usbserial is
# the mouse vs the card). The card device defaults to the OTHER usbserial.
# Needs the card personality loaded (build.sh card load) and os/run-disk.img.
set -e
root=$(cd "$(dirname "$0")/.." && pwd)

mouse=$1
[ -n "$mouse" ] || { echo "usage: runcard-mouse.sh <mouse-device> [card-device]"; \
  echo "  serial devices present:"; ls /dev/cu.usbserial-* 2>/dev/null | sed 's/^/    /'; exit 1; }

# card device: the arg, else the first usbserial that ISN'T the mouse
card=$2
if [ -z "$card" ]; then
  for d in $(ls /dev/cu.usbserial-* 2>/dev/null); do
    [ "$d" = "$mouse" ] || { card=$d; break; }
  done
fi
[ -n "$card" ] || { echo "runcard-mouse: no card serial device found (only the mouse?)"; exit 1; }
[ "$card" != "$mouse" ] || { echo "runcard-mouse: card and mouse are the same device ($card)"; exit 1; }
[ -f "$root/os/run-disk.img" ] || { echo "runcard-mouse: build os/run-disk.img first (P8X_BUILD_ONLY=1 sh os/run.sh)"; exit 1; }

build=$(mktemp -d)
cp "$root"/microcode/u?.bin "$build"/ 2>/dev/null || python3 "$root/microcode/genucode.py" >/dev/null 2>&1
cp "$root"/microcode/u?.bin "$build"/
python3 "$root/assembler/p8xasm.py" "$root/firmware/p8xmon.asm" -o "$build/eeprom.bin" >/dev/null
cc -O2 -o "$build/p8xemu" "$root/emulator/p8xemu.c"
echo "--- card=$card (display)  mouse=$mouse  -- type B to boot P8X/OS ---"
cd "$build"
exec python3 "$root/tools/serialmouse.py" --mouse "$mouse" -- \
  ./p8xemu -B "$card" -c "$root/os/run-disk.img" -c2 "$root/os/run-disk1.img" eeprom.bin
