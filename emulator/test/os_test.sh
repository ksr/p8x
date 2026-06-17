#!/bin/sh
# P8X/OS boot test: build a P8XFS image with the OS installed plus two files,
# boot it through the ROM monitor (B), and confirm the OS shell's DIR lists
# both files. Exercises the whole stack: assembler --base, p8xfs.py, the BIOS
# jump table, the CF model, and the OS itself.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o p8xos.bin --base 0x8000 >/dev/null

# Build the disk: format, install the OS, add two files.
rm -f os.img
python3 $ROOT/tools/p8xfs.py create os.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot os.img p8xos.bin >/dev/null
printf 'hi' > os_h.tmp
python3 $ROOT/tools/p8xfs.py put os.img os_h.tmp --name HELLO.TXT >/dev/null
head -c 700 /dev/zero | tr '\0' 'Z' > os_g.tmp
python3 $ROOT/tools/p8xfs.py put os.img os_g.tmp --name GAME.BIN >/dev/null
rm -f os_h.tmp os_g.tmp

# Boot and run DIR.
out=$(printf 'B\rDIR\r' | ../p8xemu -l 40000000 -c os.img eeprom.bin 2>/dev/null | tr -d '\0')
echo "$out" | grep -q 'P8X/OS v0.1' || { echo "OS TEST: FAIL — OS did not boot"; exit 1; }
echo "$out" | grep -q 'HELLO.TXT'   || { echo "OS TEST: FAIL — DIR missing HELLO.TXT"; exit 1; }
echo "$out" | grep -q 'GAME.BIN'    || { echo "OS TEST: FAIL — DIR missing GAME.BIN"; exit 1; }
echo "OS TEST: PASS"
