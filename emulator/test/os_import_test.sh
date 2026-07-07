#!/bin/sh
# IMPORT (cross-drive bulk copy): provision a fresh card's /BIN from a "master"
# CF in drive 1, with no host — the field-provisioning use case.
#   drive 0 = fresh boot volume with an empty /BIN
#   drive 1 = master with /BIN/{ALPHA.TXT,BETA.TXT}
#   MKDIR /BIN ; CD /BIN ; IMPORT 1:/BIN   -> both files land on drive 0 /BIN
# PASS iff drive 0 /BIN now holds both files with the master's exact content
# (host-verified), proving the cross-drive read(src)+write(dst) copy is correct.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x4000 >/dev/null

# drive 0: bootable, empty
rm -f im0.img im1.img
python3 $ROOT/tools/p8xfs.py create im0.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   im0.img osc.bin >/dev/null
# drive 1: master with /BIN and two files
python3 $ROOT/tools/p8xfs.py create im1.img >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  im1.img /BIN >/dev/null
printf 'alpha contents\r\n'      > a.dat
printf 'the beta file here\r\n'  > b.dat
python3 $ROOT/tools/p8xfs.py put im1.img a.dat --name /BIN/ALPHA.TXT --load 0 --exec 0 >/dev/null
python3 $ROOT/tools/p8xfs.py put im1.img b.dat --name /BIN/BETA.TXT  --load 0 --exec 0 >/dev/null

printf 'B\rMKDIR /BIN\rCD /BIN\rIMPORT 1:/BIN\r' \
    | ../p8xemu -l 80000000 -c im0.img -c2 im1.img eeprom.bin 2>/dev/null >/dev/null

# host-verify: drive 0 /BIN now has both files with the master's content
t=$(python3 $ROOT/tools/p8xfs.py tree im0.img 2>/dev/null)
echo "$t" | grep -q ALPHA || { echo "OS-IMPORT TEST: FAIL — ALPHA.TXT not imported to drive 0"; echo "$t"; exit 1; }
echo "$t" | grep -q BETA  || { echo "OS-IMPORT TEST: FAIL — BETA.TXT not imported to drive 0"; echo "$t"; exit 1; }
python3 $ROOT/tools/p8xfs.py get im0.img /BIN/ALPHA.TXT --out ga.out >/dev/null 2>&1
python3 $ROOT/tools/p8xfs.py get im0.img /BIN/BETA.TXT  --out gb.out >/dev/null 2>&1
grep -q 'alpha contents'     ga.out || { echo "OS-IMPORT TEST: FAIL — ALPHA.TXT content wrong:"; xxd ga.out | head -2; exit 1; }
grep -q 'the beta file here' gb.out || { echo "OS-IMPORT TEST: FAIL — BETA.TXT content wrong:";  xxd gb.out | head -2; exit 1; }

echo "OS-IMPORT TEST: PASS"
