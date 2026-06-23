#!/bin/sh
# BIOS filesystem API test: a planted program uses FCREATE/FFIND (monitor ROM)
# to create + find a root file on a fresh v2 card, reads it back, and the host
# then confirms the file is visible to p8xfs.py.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py hfs.asm -o hfs.bin --base 0x4000 >/dev/null

rm -f fs.img
python3 $ROOT/tools/p8xfs.py create fs.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   fs.img hfs.bin >/dev/null

out=$(printf 'B\r' | ../p8xemu -l 50000000 -c fs.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0')
case "$out" in
  *Y*) ;;
  *) echo "FS-BIOS TEST: FAIL — round-trip marker not 'Y' (got [$out])"; exit 1 ;;
esac

# Host confirms FCREATE wrote a valid directory entry the tool can see.
python3 $ROOT/tools/p8xfs.py ls fs.img 2>/dev/null | grep -q 'TEST' \
  || { echo "FS-BIOS TEST: FAIL — host p8xfs.py does not see file TEST"; exit 1; }
python3 $ROOT/tools/p8xfs.py fsck fs.img >/dev/null 2>&1 \
  || { echo "FS-BIOS TEST: FAIL — volume invalid after FCREATE"; exit 1; }

echo "FS-BIOS TEST: PASS"
