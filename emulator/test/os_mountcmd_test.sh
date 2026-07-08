#!/bin/sh
# MOUNT / UMOUNT: swap the CF in the /D1 slot without rebooting. The filesystem
# caches no state for drive 1, so the only things to reset across a swap are the
# firmware CFINIT-once flag (so the new card gets its handshake) and the CWD if
# it is under /D1. UMOUNT does both; MOUNT re-inits the inserted card and reports
# by reading its boot block: P8 -> mounted, floating bus -> no card, else -> not
# P8XFS. Checks the command messages and that UMOUNT drops a /D1 CWD back to /.
set -e
cd "$(dirname "$0")"
ROOT=../..

cp $ROOT/microcode/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x4000 >/dev/null
for c in dir cat; do
    python3 $ROOT/tools/clib.py $ROOT/os/commands/$c.c -o mc_$c.pp.c
    python3 $ROOT/compiler/p8cc.py mc_$c.pp.c -o mc_$c.asm >/dev/null
    python3 $ROOT/assembler/p8xasm.py mc_$c.asm -o mc_$c.bin --base 0x7A00 >/dev/null
done

mk0() {   # fresh boot disk with /BIN/{DIR,CAT} + /D1 placeholder
    rm -f mc0.img
    python3 $ROOT/tools/p8xfs.py create mc0.img >/dev/null
    python3 $ROOT/tools/p8xfs.py boot   mc0.img osc.bin >/dev/null
    python3 $ROOT/tools/p8xfs.py mkdir  mc0.img /BIN >/dev/null
    python3 $ROOT/tools/p8xfs.py mkdir  mc0.img /D1  >/dev/null
    python3 $ROOT/tools/p8xfs.py put mc0.img mc_dir.bin --name /BIN/DIR.BIN --load 0x7A00 --exec 0x7A00 >/dev/null
    python3 $ROOT/tools/p8xfs.py put mc0.img mc_cat.bin --name /BIN/CAT.BIN --load 0x7A00 --exec 0x7A00 >/dev/null
}
# a formatted drive-1 card with a file, and an unformatted (zeroed) one
rm -f mc1.img mcbad.img
python3 $ROOT/tools/p8xfs.py create mc1.img >/dev/null
printf 'hello drive one\r\n' > mc_h.dat
python3 $ROOT/tools/p8xfs.py put mc1.img mc_h.dat --name /ROOTF.TXT --load 0 --exec 0 >/dev/null
head -c 131072 /dev/zero > mcbad.img

run() {   # $1 = shell line(s), $2 = extra emu args (drive 1)
    mk0
    printf "B\r$1\r" | ../p8xemu -l 250000000 -c mc0.img $2 eeprom.bin 2>/dev/null \
        | LC_ALL=C tr -d '\0' | tr '\r' '\n'
}

run 'MOUNT' '-c2 mc1.img'   | grep -q 'MOUNTED AT /D1'      || { echo "OS-MOUNTCMD TEST: FAIL — MOUNT present"; exit 1; }
run 'MOUNT' ''              | grep -q 'NO CARD'             || { echo "OS-MOUNTCMD TEST: FAIL — MOUNT absent"; exit 1; }
run 'MOUNT' '-c2 mcbad.img' | grep -q 'NOT P8XFS'           || { echo "OS-MOUNTCMD TEST: FAIL — MOUNT unformatted"; exit 1; }

# UMOUNT while inside /D1 drops the CWD back to the root, and drive 1 is still
# reachable afterwards (MKDIR would land on drive 0; CAT a /D1 file still works).
out=$(run 'CD /D1\rUMOUNT\rCAT /D1/ROOTF.TXT' '-c2 mc1.img')
echo "$out" | grep -q 'UNMOUNTED'        || { echo "OS-MOUNTCMD TEST: FAIL — UMOUNT message"; echo "$out"; exit 1; }
echo "$out" | grep -q 'hello drive one'  || { echo "OS-MOUNTCMD TEST: FAIL — /D1 unreadable after UMOUNT"; echo "$out"; exit 1; }
# after UMOUNT the prompt must be back at the root (not /D1)
echo "$out" | grep -qE '^/> CAT'         || { echo "OS-MOUNTCMD TEST: FAIL — UMOUNT did not reset the CWD to /"; echo "$out"; exit 1; }

echo "OS-MOUNTCMD TEST: PASS"
