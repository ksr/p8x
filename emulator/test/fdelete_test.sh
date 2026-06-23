#!/bin/sh
# BIOS FDELETE: a planted program creates root file TEST, deletes it via
# FDELETE, then confirms FFIND no longer finds it ('Y'). The host then confirms
# the volume is still structurally valid (fsck) and the tool no longer lists it.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py hdel.asm -o hdel.bin --base 0x4000 >/dev/null

rm -f fd.img
python3 $ROOT/tools/p8xfs.py create fd.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   fd.img hdel.bin >/dev/null

out=$(printf 'B\r' | ../p8xemu -l 50000000 -c fd.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0')
case "$out" in
  *Y*) ;;
  *) echo "FDELETE TEST: FAIL — delete round-trip marker not 'Y' (got [$out])"; exit 1 ;;
esac

# Host: file gone from the listing, volume still valid.
python3 $ROOT/tools/p8xfs.py ls fd.img 2>/dev/null | grep -q 'TEST' \
  && { echo "FDELETE TEST: FAIL — host still sees deleted file TEST"; exit 1; }
python3 $ROOT/tools/p8xfs.py fsck fd.img >/dev/null 2>&1 \
  || { echo "FDELETE TEST: FAIL — volume invalid after FDELETE"; exit 1; }

echo "FDELETE TEST: PASS"
