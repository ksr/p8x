#!/bin/sh
# Dual CF under the unified-namespace mount model: drive 0 is the root, drive 1
# is mounted at /D1. Exercises, entirely through the shell:
#   - absolute mount path from the root:  MKDIR /D1/PFXDIR  -> lands on drive 1
#   - CD into the mount:                  CD /D1  (prompt becomes "/D1> ")
#   - relative write under the mount:     MKDIR SWDIR       -> drive 1 (/D1/SWDIR)
#   - CD back to the root + write:        CD / ; MKDIR D0DIR -> drive 0
# PASS iff each directory lands on the correct card (host-verified) and the two
# volumes stay isolated, and the prompt shows the mount path.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x4000 >/dev/null

# drive 0: bootable OS volume;  drive 1: a blank data volume
rm -f dv0.img dv1.img
python3 $ROOT/tools/p8xfs.py create dv0.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   dv0.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py create dv1.img >/dev/null

CMDS='MKDIR /D1/PFXDIR\rCD /D1\rMKDIR SWDIR\rCD /\rMKDIR D0DIR\r'
out=$(printf "B\r$CMDS" | ../p8xemu -l 60000000 -c dv0.img -c2 dv1.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0')

# the prompt must show the mount path after CD /D1
echo "$out" | grep -q '/D1' || { echo "OS-DUALVOL TEST: FAIL — prompt never showed the /D1 mount"; echo "[$out]" | tail -3; exit 1; }

# host-verify the two images: PFXDIR + SWDIR on drive 1, D0DIR on drive 0, isolated
d1=$(python3 $ROOT/tools/p8xfs.py tree dv1.img 2>/dev/null)
d0=$(python3 $ROOT/tools/p8xfs.py tree dv0.img 2>/dev/null)
echo "$d1" | grep -q PFXDIR || { echo "OS-DUALVOL TEST: FAIL — 'MKDIR /D1/PFXDIR' did not land on drive 1"; echo "$d1"; exit 1; }
echo "$d1" | grep -q SWDIR  || { echo "OS-DUALVOL TEST: FAIL — 'MKDIR SWDIR' under /D1 did not land on drive 1"; echo "$d1"; exit 1; }
echo "$d0" | grep -q D0DIR  || { echo "OS-DUALVOL TEST: FAIL — 'MKDIR D0DIR' at the root did not land on drive 0"; echo "$d0"; exit 1; }
echo "$d0" | grep -q PFXDIR && { echo "OS-DUALVOL TEST: FAIL — drive-1 dir leaked onto drive 0 (not isolated)"; exit 1; }
echo "$d0" | grep -q SWDIR  && { echo "OS-DUALVOL TEST: FAIL — drive-1 dir leaked onto drive 0 (not isolated)"; exit 1; }
echo "$d1" | grep -q D0DIR  && { echo "OS-DUALVOL TEST: FAIL — drive-0 dir leaked onto drive 1 (not isolated)"; exit 1; }

echo "OS-DUALVOL TEST: PASS"
