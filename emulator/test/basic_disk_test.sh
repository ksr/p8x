#!/bin/sh
# Disk-BASIC test: assemble BASIC to run at $8000 (data at $A000), install it as
# a bootable P8XFS image, boot it through the monitor's B command, and run a
# program with a FOR loop.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/basic/p8xbasic.asm -o basicdisk.bin \
        --base 0x4000 -D BASORG=0x4000 -D BASRAM=0xA000 >/dev/null

rm -f bas.img
python3 $ROOT/tools/p8xfs.py create bas.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot bas.img basicdisk.bin >/dev/null

out=$(printf 'B\r10 FOR I=1 TO 3\r20 PRINT I\r30 NEXT\rRUN\r' | \
      ../p8xemu -l 90000000 -c bas.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0')
fail() { echo "BASIC-DISK TEST: FAIL — $1"; echo "$out"; exit 1; }
echo "$out" | grep -q 'P8X BASIC' || fail "BASIC did not boot from disk"
# FOR loop should print 1, 2, 3 on their own lines.
echo "$out" | grep -q '^1' && echo "$out" | grep -q '^2' && echo "$out" | grep -q '^3' \
    || fail "FOR loop output missing"
echo "BASIC-DISK TEST: PASS"
