#!/bin/sh
# BIOS path resolution: a planted program resolves "/SUB/T" with FRESOLVE
# (descending into the subdirectory) and reads it via FOPEN/FGETB. Proves the
# file calls reach files in subdirectories, not just the root.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py hresolve.asm -o hresolve.bin --base 0x4000 >/dev/null

rm -f fr.img
python3 $ROOT/tools/p8xfs.py create fr.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   fr.img hresolve.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  fr.img /SUB >/dev/null
printf 'DEEP' > deep.tmp
python3 $ROOT/tools/p8xfs.py put    fr.img deep.tmp --name /SUB/T >/dev/null
rm -f deep.tmp

out=$(printf 'B\r' | ../p8xemu -l 50000000 -c fr.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')
case "$out" in
  *DEEP*) echo "FRESOLVE TEST: PASS" ;;
  *) echo "FRESOLVE TEST: FAIL — did not read /SUB/T (got [$out])"; exit 1 ;;
esac
