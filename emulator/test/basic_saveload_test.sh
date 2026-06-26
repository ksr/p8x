#!/bin/sh
# BASIC SAVE/LOAD round-trip: boot disk BASIC (monitor B) from a v2 CF card,
# enter a program, SAVE it, NEW (wipe), LOAD it back, LIST + RUN to prove it
# round-tripped through the P8XFS filesystem (via the BIOS FFIND/FCREATE calls).
# (BASIC is no longer ROM-resident — it boots from the card like any OS image.)
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/basic/p8xbasic.asm -o basicdisk.bin \
        --base 0x4000 -D BASORG=0x4000 -D BASRAM=0xA000 >/dev/null
rm -f sl.img
python3 $ROOT/tools/p8xfs.py create sl.img >/dev/null            # empty v2 volume
python3 $ROOT/tools/p8xfs.py boot   sl.img basicdisk.bin >/dev/null   # bootable BASIC

out=$(printf 'B\r10 PRINT "SLOK"\r20 END\rSAVE "PROG"\rNEW\rLIST\rLOAD "PROG"\rLIST\rRUN\r' | \
      ../p8xemu -l 120000000 -c sl.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0')
fail() { echo "BASIC-SAVELOAD TEST: FAIL — $1"; echo "$out"; exit 1; }

echo "$out" | grep -q 'P8X BASIC' || fail "B did not boot BASIC"
echo "$out" | grep -q 'Saved'     || fail "SAVE did not report success"
echo "$out" | grep -q 'Loaded'    || fail "LOAD did not report success"
# Everything after 'Loaded' is the restored program: LIST must show the line and
# RUN must print SLOK (proving NEW wiped it and LOAD brought it back).
post=$(echo "$out" | sed -n '/Loaded/,$p')
echo "$post" | grep -q '10 PRINT "SLOK"' || fail "LOAD did not restore the program (LIST empty)"
echo "$post" | grep -q '^SLOK'           || fail "RUN of the loaded program did not print"

# Host confirms BASIC wrote the file into the v2 root.
python3 $ROOT/tools/p8xfs.py ls sl.img 2>/dev/null | grep -q 'PROG' \
  || fail "host p8xfs.py does not see the SAVEd file PROG"

echo "BASIC-SAVELOAD TEST: PASS"
