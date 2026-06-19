#!/bin/sh
# Build the burnable image set so it persists at known paths, ready for an
# EEPROM programmer. Run after changing the microcode (genucode.py) or the
# firmware (firmware/p8xmon.asm, basic/p8xbasic.asm).
#
#   microcode control store (4x 28C64)  -> microcode/u0..u3.{bin,hex}
#   program ROM (28C256, monitor+BASIC) -> rom/p8x-prog-rom.{bin,hex}
#
# See rom/README.md for the chip map. (Also: `make rom` from emulator/.)
set -e
cd "$(dirname "$0")/.."                       # repo root

# microcode control store -> microcode/ (also emits .hex)
( cd microcode && python3 genucode.py >/dev/null )

# program ROM = monitor + ROM BASIC -> rom/ (emits .bin and .hex)
mkdir -p rom
python3 tools/build_basic_rom.py rom/p8x-prog-rom.bin >/dev/null

echo "Burnable images:"
ls -1 microcode/u?.hex rom/p8x-prog-rom.bin rom/p8x-prog-rom.hex
