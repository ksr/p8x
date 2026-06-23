#!/bin/sh
# BIOS read-stream API: a planted program creates a root file, opens it with
# FOPEN, and reads it back byte-by-byte via FGETB — echoing the bytes. Verifies
# the sequential read stream returns the file contents and stops at EOF.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py hopen.asm -o hopen.bin --base 0x4000 >/dev/null

rm -f fo.img
python3 $ROOT/tools/p8xfs.py create fo.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   fo.img hopen.bin >/dev/null

out=$(printf 'B\r' | ../p8xemu -l 50000000 -c fo.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')
case "$out" in
  *FSOK*) echo "FOPEN TEST: PASS" ;;
  *) echo "FOPEN TEST: FAIL — read stream did not return 'FSOK' (got [$out])"; exit 1 ;;
esac
