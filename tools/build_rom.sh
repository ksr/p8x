#!/bin/sh
# Build the burnable image set so it persists at known paths, ready for an
# EEPROM programmer. Run after changing the microcode (genucode.py) or the
# firmware (firmware/p8xmon.asm, basic/p8xbasic.asm).
#
#   microcode control store (4x 28C64)  -> rom/p8x-ucode0..3.{bin,hex}
#   program ROM (28C256, monitor+BASIC) -> rom/p8x-prog-rom.{bin,hex}
# (microcode/ keeps the u0..u3.bin the emulator/tests load; rom/ is the single
#  grab-and-burn folder and the only home for the Intel HEX images.)
#
# See rom/README.md for the chip map. (Also: `make rom` from emulator/.)
set -e
cd "$(dirname "$0")/.."                       # repo root

mkdir -p rom

# microcode control store -> microcode/u0..u3.bin (what the emulator/tests load),
# then emit the burn copies (.bin + Intel HEX) into the rom/ folder
( cd microcode && python3 genucode.py >/dev/null )
for k in 0 1 2 3; do
    cp "microcode/u$k.bin" "rom/p8x-ucode$k.bin"
    python3 tools/bin2hex.py "microcode/u$k.bin" "rom/p8x-ucode$k.hex" >/dev/null
done

# program ROM = monitor + ROM BASIC -> rom/ (emits .bin and .hex)
python3 tools/build_basic_rom.py rom/p8x-prog-rom.bin >/dev/null

echo "Burnable images (rom/):"
ls -1 rom/*.bin rom/*.hex
