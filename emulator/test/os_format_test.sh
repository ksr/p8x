#!/bin/sh
# On-target FORMAT test. Boot the OS from a v2 card that already holds a
# subdirectory, then `FORMAT` it: the old tree must vanish, a fresh empty v2
# root must work (MKDIR + DIR + on-target FSCK), and the boot block must be a
# valid v2 (version 2, OSCNT preserved so the card stays bootable, free=37).
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o p8xos.bin --base 0x4000 >/dev/null

# A v2 card with the OS installed plus a pre-existing /OLD directory.
rm -f fmt.img
python3 $ROOT/tools/p8xfs.py create fmt.img --v2 >/dev/null
python3 $ROOT/tools/p8xfs.py boot   fmt.img p8xos.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  fmt.img /OLD >/dev/null

# Boot, list (OLD present), FORMAT (confirm Y), list (empty), MKDIR /NEW, list
# (NEW present), FSCK, then EXIT to the monitor.
out=$(printf 'B\rDIR\rFORMAT\rY\rDIR\rMKDIR /NEW\rDIR\rFSCK\rEXIT\r' | \
      ../p8xemu -l 200000000 -c fmt.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')
fail() { echo "OS-FORMAT TEST: FAIL — $1"; echo "$out" | sed -n '/v1.0/,$p'; exit 1; }

echo "$out" | grep -q 'P8X/OS v1.0'        || fail "OS did not boot"
echo "$out" | grep -q 'OLD.*<DIR>'         || fail "pre-format DIR missing /OLD"
echo "$out" | grep -q 'FORMATTED'          || fail "FORMAT did not report success"
# Everything after FORMATTED is the post-format world: /OLD gone, /NEW present.
post=$(echo "$out" | sed -n '/FORMATTED/,$p')
echo "$post" | grep -q 'OLD.*<DIR>'        && fail "/OLD survived FORMAT" || true
echo "$post" | grep -q 'DIR CREATED'       || fail "MKDIR failed on the fresh volume"
echo "$post" | grep -q 'NEW.*<DIR>'        || fail "freshly created /NEW not listed"
echo "$post" | grep -q 'FSCK OK'           || fail "on-target FSCK flagged the fresh volume"

# Host-side: the volume the OS wrote must be a clean v2, and the boot block must
# carry version 2, a preserved (nonzero) OSCNT, and free = 41 (37 + one MKDIR).
python3 $ROOT/tools/p8xfs.py fsck fmt.img >fmt_fsck.tmp 2>&1 || { cat fmt_fsck.tmp; fail "host fsck failed"; }
rm -f fmt_fsck.tmp
python3 - <<'PY' || exit 1
import struct,sys
b=open('fmt.img','rb').read()
if b[0:2]!=b'P8':        print("OS-FORMAT TEST: FAIL — bad signature");      sys.exit(1)
if b[2]!=2:              print("OS-FORMAT TEST: FAIL — version != 2");       sys.exit(1)
if b[3]==0:              print("OS-FORMAT TEST: FAIL — OSCNT not preserved");sys.exit(1)
free=struct.unpack_from("<H",b,4)[0]
if free!=41:             print("OS-FORMAT TEST: FAIL — free=%d (want 41)"%free); sys.exit(1)
PY

echo "OS-FORMAT TEST: PASS"
