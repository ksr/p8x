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

# Boot, FORMAT (confirm Y), MKDIR /NEW, FSCK, then EXIT. DIR is no longer a
# built-in and a just-FORMATted volume has no /BIN, so we don't type DIR here;
# the post-format tree (/OLD gone, /NEW present) is checked host-side below with
# p8xfs.py ls. MKDIR ("DIR CREATED") and FSCK are still native built-ins.
out=$(printf 'B\rFORMAT\rY\rMKDIR /NEW\rFSCK\rEXIT\r' | \
      ../p8xemu -l 200000000 -c fmt.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')
fail() { echo "OS-FORMAT TEST: FAIL — $1"; echo "$out" | sed -n '/v1.0/,$p'; exit 1; }

echo "$out" | grep -q 'P8X/OS v1.0'        || fail "OS did not boot"
echo "$out" | grep -q 'FORMATTED'          || fail "FORMAT did not report success"
echo "$out" | grep -q 'DIR CREATED'        || fail "MKDIR failed on the fresh volume"
echo "$out" | grep -q 'FSCK OK'            || fail "on-target FSCK flagged the fresh volume"
# Host-side: the post-format root has /NEW and no longer has /OLD.
python3 $ROOT/tools/p8xfs.py ls fmt.img / >fmt_ls.tmp 2>&1 || { cat fmt_ls.tmp; fail "host ls failed"; }
grep -qi 'NEW' fmt_ls.tmp || { cat fmt_ls.tmp; fail "freshly created /NEW not in the volume"; }
if grep -qi 'OLD' fmt_ls.tmp; then cat fmt_ls.tmp; fail "/OLD survived FORMAT"; fi
rm -f fmt_ls.tmp

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
