#!/bin/sh
# BIOS path-aware writes: a planted program resolves "/SUB/W", writes it via the
# write stream, and reads it back via the read stream. The host then confirms the
# file landed inside the subdirectory with the right contents and the volume is
# still valid.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py hwrdir.asm -o hwrdir.bin --base 0x4000 >/dev/null

rm -f wd.img
python3 $ROOT/tools/p8xfs.py create wd.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   wd.img hwrdir.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  wd.img /SUB >/dev/null

out=$(printf 'B\r' | ../p8xemu -l 60000000 -c wd.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')
case "$out" in
  *HI*) ;;
  *) echo "FWRDIR TEST: FAIL — read-back of /SUB/W not 'HI' (got [$out])"; exit 1 ;;
esac

# host: the file is inside /SUB with the right contents, volume valid
python3 $ROOT/tools/p8xfs.py get wd.img /SUB/W >/dev/null 2>&1 || { echo "FWRDIR TEST: FAIL — /SUB/W not created"; exit 1; }
test "$(cat W)" = "HI" || { echo "FWRDIR TEST: FAIL — /SUB/W contents wrong ($(cat W))"; rm -f W; exit 1; }
rm -f W
python3 $ROOT/tools/p8xfs.py fsck wd.img >/dev/null 2>&1 || { echo "FWRDIR TEST: FAIL — volume invalid"; exit 1; }
echo "FWRDIR TEST: PASS"
