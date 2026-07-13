#!/bin/sh
# BIOS FNORM: a planted program formats the string "hi.c" into FNAME with FNORM
# and creates a file by that name. Confirms the name is CASE-PRESERVED and
# space-padded (the directory holds "hi.c") — filenames are case-sensitive.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py hnorm.asm -o hnorm.bin --base 0x2000 >/dev/null

rm -f fn.img
python3 $ROOT/tools/p8xfs.py create fn.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   fn.img hnorm.bin >/dev/null

out=$(printf 'B\r' | ../p8xemu -l 50000000 -c fn.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')
case "$out" in
  *Y*) ;;
  *) echo "FNORM TEST: FAIL — FCREATE after FNORM did not succeed (got [$out])"; exit 1 ;;
esac
python3 $ROOT/tools/p8xfs.py ls fn.img 2>/dev/null | grep -q 'hi.c' \
  || { echo "FNORM TEST: FAIL — directory does not hold case-preserved 'hi.c'"; exit 1; }
echo "FNORM TEST: PASS"
