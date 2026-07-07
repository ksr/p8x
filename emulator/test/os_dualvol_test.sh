#!/bin/sh
# Full dual-volume: two CF cards (drive 0 boot + drive 1 data), each a P8XFS v2
# volume with its own current directory, addressed by a 0:/1: prefix and a
# switchable current drive. Exercises, entirely through the shell:
#   - one-shot prefix from drive 0:   MKDIR 1:/PFXDIR   -> lands on drive 1
#   - bare drive switch:              1:  (prompt becomes "1:/> ")
#   - per-drive write on the current: MKDIR /SWDIR      -> on drive 1
#   - switch back + write:            0: ; MKDIR /D0DIR -> on drive 0
# PASS iff each directory lands on the correct card (host-verified with p8xfs.py)
# and the two volumes stay isolated, and the prompt shows the active drive.
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

CMDS='MKDIR 1:/PFXDIR\r1:\rMKDIR /SWDIR\r0:\rMKDIR /D0DIR\r'
out=$(printf "B\r$CMDS" | ../p8xemu -l 60000000 -c dv0.img -c2 dv1.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0')

# the prompt must reflect the active drive after switching to 1:
echo "$out" | grep -q '1:/' || { echo "OS-DUALVOL TEST: FAIL — prompt never showed drive 1 (1:/)"; echo "[$out]" | tail -3; exit 1; }

# host-verify the two images: PFXDIR + SWDIR on drive 1, D0DIR on drive 0, isolated
d1=$(python3 $ROOT/tools/p8xfs.py tree dv1.img 2>/dev/null)
d0=$(python3 $ROOT/tools/p8xfs.py tree dv0.img 2>/dev/null)
echo "$d1" | grep -q PFXDIR || { echo "OS-DUALVOL TEST: FAIL — 'MKDIR 1:/PFXDIR' did not land on drive 1"; echo "$d1"; exit 1; }
echo "$d1" | grep -q SWDIR  || { echo "OS-DUALVOL TEST: FAIL — 'MKDIR /SWDIR' after '1:' did not land on drive 1"; echo "$d1"; exit 1; }
echo "$d0" | grep -q D0DIR  || { echo "OS-DUALVOL TEST: FAIL — 'MKDIR /D0DIR' after '0:' did not land on drive 0"; echo "$d0"; exit 1; }
echo "$d0" | grep -q PFXDIR && { echo "OS-DUALVOL TEST: FAIL — drive-1 dir leaked onto drive 0 (not isolated)"; exit 1; }
echo "$d0" | grep -q SWDIR  && { echo "OS-DUALVOL TEST: FAIL — drive-1 dir leaked onto drive 0 (not isolated)"; exit 1; }
echo "$d1" | grep -q D0DIR  && { echo "OS-DUALVOL TEST: FAIL — drive-0 dir leaked onto drive 1 (not isolated)"; exit 1; }

echo "OS-DUALVOL TEST: PASS"
