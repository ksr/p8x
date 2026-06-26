#!/bin/sh
# Regression: PACK and FSCK must handle extents (directories AND files) at LBA
# >=256. Both walk the directory tree with what used to be 8-bit cursors; PACK
# also relocates extents on disk, so a directory or file past sector 256 would be
# read/written at the wrong LBA — silently corrupting the volume on PACK, or
# mis-reporting it on FSCK. This builds a volume with a directory at LBA >=256
# holding a subdir + a file, deletes some low extents to open holes, PACKs (which
# relocates the high extents down across the 256 boundary), and verifies the tree
# survives byte-exact: on-target FSCK OK + DIR, and host-side fsck + a content read.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "OS-BIGPACK TEST: FAIL — $1"; [ -n "$out" ] && echo "$out" | sed -n '/v1.0/,$p'; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o bpos.bin --base 0x4000 >/dev/null
python3 $ROOT/tools/clib.py $ROOT/os/commands/dir.c -o bpdir.pp.c >/dev/null
python3 $ROOT/compiler/p8cc.py bpdir.pp.c -o bpdir.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py bpdir.asm -o bpdir.bin --base 0x7A00 >/dev/null

rm -f bp.img
python3 $ROOT/tools/p8xfs.py create bp.img --v2 >/dev/null
python3 $ROOT/tools/p8xfs.py boot   bp.img bpos.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  bp.img /BIN >/dev/null
python3 $ROOT/tools/p8xfs.py put    bp.img bpdir.bin --name /BIN/DIR.BIN --load 0x7A00 --exec 0x7A00 >/dev/null
head -c 30000 /dev/zero > bppad.bin
for i in 1 2 3 4 5 6 7 8; do python3 $ROOT/tools/p8xfs.py put bp.img bppad.bin --name /PAD$i >/dev/null; done
python3 $ROOT/tools/p8xfs.py mkdir bp.img /BIG >/dev/null
biglba=$(python3 $ROOT/tools/p8xfs.py ls bp.img / 2>/dev/null | awk '$1=="BIG"{print $3}')
[ -n "$biglba" ] && [ "$biglba" -ge 256 ] || { echo "premise broken: /BIG at LBA $biglba (<256)"; exit 1; }

# On-target: populate /BIG (a LBA>=256 dir), open holes by deleting some PADs, then
# PACK (relocates the high extents down), FSCK, and re-list the relocated tree.
out=$(printf 'B\rCD /BIG\rMKDIR SUB\rDEP B000 41 42 43\rSAVE F.BIN B000 B003\rCD /\rDEL /PAD2\rDEL /PAD4\rDEL /PAD6\rPACK\rFSCK\rCD /BIG\rDIR\r' | \
      ../p8xemu -l 600000000 -c bp.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')

echo "$out" | grep -q 'P8X/OS v1.0' || fail "OS did not boot"
echo "$out" | grep -q 'SAVED'        || fail "SAVE into the LBA>=256 dir failed"
echo "$out" | grep -q 'PACKED'       || fail "PACK did not complete"
echo "$out" | grep -q 'FSCK OK'      || fail "on-target FSCK flagged the packed volume"
# After PACK the relocated /BIG must still list its contents (proves its '.'/'..'
# and the parent entry that points at it were rewritten to the new LBA).
echo "$out" | sed -n '/CD \/BIG/,$p' | grep -qE ' SUB/$'   || fail "post-PACK DIR /BIG missing SUB"
echo "$out" | sed -n '/CD \/BIG/,$p' | grep -qE ' F\.BIN$' || fail "post-PACK DIR /BIG missing F.BIN"
if echo "$out" | LC_ALL=C grep -q '[^[:print:][:space:]]'; then fail "DIR produced garbage bytes"; fi

# Host cross-check: clean fsck, and F.BIN's bytes survived relocation byte-exact.
python3 $ROOT/tools/p8xfs.py fsck bp.img >bp_fsck.tmp 2>&1 || { cat bp_fsck.tmp; fail "host fsck failed after PACK"; }
python3 $ROOT/tools/p8xfs.py get bp.img /BIG/F.BIN --out bp_f.tmp >/dev/null 2>&1 || fail "host get /BIG/F.BIN failed"
got=$(od -An -tx1 bp_f.tmp | tr -s ' ' | sed 's/^ //;s/ $//')
[ "$got" = "41 42 43" ] || fail "F.BIN content changed by PACK: got '$got' (want 41 42 43)"
rm -f bp_fsck.tmp bp_f.tmp bppad.bin bpdir.asm

echo "OS-BIGPACK TEST: PASS"
