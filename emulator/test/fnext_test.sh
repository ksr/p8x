#!/bin/sh
# BIOS directory iteration: a planted program lists the root with FOPENDIR/FNEXT
# and prints each entry's first character. With files A and B on the volume the
# output is "AB" — proving iteration walks live entries and stops at the end.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py hdir.asm -o hdir.bin --base 0x4000 >/dev/null

rm -f fx.img
python3 $ROOT/tools/p8xfs.py create fx.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   fx.img hdir.bin >/dev/null
printf 'a' > a.tmp; printf 'b' > b.tmp
python3 $ROOT/tools/p8xfs.py put fx.img a.tmp --name /A >/dev/null
python3 $ROOT/tools/p8xfs.py put fx.img b.tmp --name /B >/dev/null
rm -f a.tmp b.tmp

out=$(printf 'B\r' | ../p8xemu -l 50000000 -c fx.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')
case "$out" in
  *AB*) echo "FNEXT TEST: PASS" ;;
  *) echo "FNEXT TEST: FAIL — root listing not 'AB' (got [$out])"; exit 1 ;;
esac
