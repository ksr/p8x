#!/bin/sh
# Regression: directories whose extent starts at LBA >=256 must be fully usable.
# Historically the directory-LBA cursors (BIOS DIRLBA/DILBA, OS CWDL/SDIRL/DLBA,
# NEWLBA, CURLBA) were a single byte, so a directory allocated past sector 256 was
# truncated to its low byte: CD into it + DIR printed garbage, and creating files
# inside it corrupted the volume. This test fills a v2 volume so a freshly made
# directory lands at LBA >=256, then exercises the create/navigate/list/save path
# on-target and cross-checks the result host-side with p8xfs.py.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "OS-BIGDIR TEST: FAIL — $1"; [ -n "$out" ] && echo "$out" | sed -n '/v1.0/,$p'; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o bdos.bin --base 0x4000 >/dev/null
# The C DIR is a /BIN program (no longer a built-in); install it so a bare `DIR`
# resolves via PATH and lists the CWD through SYS_OPENCWD (the 16-bit CWD opener).
python3 $ROOT/tools/clib.py $ROOT/os/commands/dir.c -o bddir.pp.c >/dev/null
python3 $ROOT/compiler/p8cc.py bddir.pp.c -o bddir.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py bddir.asm -o bddir.bin --base 0xB000 >/dev/null

rm -f bd.img
python3 $ROOT/tools/p8xfs.py create bd.img --v2 >/dev/null
python3 $ROOT/tools/p8xfs.py boot   bd.img bdos.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  bd.img /BIN >/dev/null
python3 $ROOT/tools/p8xfs.py put    bd.img bddir.bin --name /BIN/DIR.BIN --load 0xB000 --exec 0xB000 >/dev/null
# Pad the volume so the next allocated extent is well past LBA 256.
head -c 30000 /dev/zero > bdpad.bin
for i in 1 2 3 4 5 6 7 8; do
    python3 $ROOT/tools/p8xfs.py put bd.img bdpad.bin --name /PAD$i >/dev/null
done
python3 $ROOT/tools/p8xfs.py mkdir bd.img /BIG >/dev/null
# Confirm the test premise: /BIG really is at LBA >=256 (else it proves nothing).
biglba=$(python3 $ROOT/tools/p8xfs.py ls bd.img / 2>/dev/null | awk '$1=="BIG"{print $3}')
[ -n "$biglba" ] && [ "$biglba" -ge 256 ] || { echo "premise broken: /BIG at LBA $biglba (<256)"; exit 1; }

# On-target: CD into the high-LBA dir, list it (must show only . / ..), then make
# a subdir and SAVE a file inside it, and list again (must show SUB and F.BIN).
out=$(printf 'B\rCD /BIG\rDIR\rMKDIR SUB\rDEP B000 41 42 43\rSAVE F.BIN B000 B003\rDIR\r' | \
      ../p8xemu -l 400000000 -c bd.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')

echo "$out" | grep -q 'P8X/OS v1.0' || fail "OS did not boot"
echo "$out" | grep -q '/BIG> '      || fail "CD into a LBA>=256 directory did not update the prompt"
echo "$out" | grep -q 'DIR CREATED'  || fail "MKDIR inside a LBA>=256 directory failed"
echo "$out" | grep -q 'SAVED'        || fail "SAVE inside a LBA>=256 directory failed"
# After the create, the final DIR must list both new entries (proves the listing
# reads the right sectors — the original bug printed garbage from sector LBA&255).
post=$(echo "$out" | sed -n 's/.*SAVED//; /SAVED/,$p')
echo "$out" | grep -qx 'SUB'   || fail "DIR of the LBA>=256 dir missing the new subdir"
echo "$out" | grep -qx 'F.BIN' || fail "DIR of the LBA>=256 dir missing the saved file"
# No garbage: the listing must contain no non-printable bytes (the original bug
# dumped raw sector data from LBA&255). LC_ALL=C makes the class byte-wise.
if echo "$out" | LC_ALL=C grep -q '[^[:print:][:space:]]'; then fail "DIR produced garbage bytes"; fi

# Host cross-check: the volume the OS wrote is consistent, and /BIG holds SUB+F.BIN.
python3 $ROOT/tools/p8xfs.py fsck bd.img >bd_fsck.tmp 2>&1 || { cat bd_fsck.tmp; fail "host fsck failed after on-target writes"; }
python3 $ROOT/tools/p8xfs.py ls bd.img /BIG >bd_ls.tmp 2>&1 || { cat bd_ls.tmp; fail "host ls /BIG failed"; }
grep -qi 'SUB'   bd_ls.tmp || { cat bd_ls.tmp; fail "host: /BIG missing SUB"; }
grep -qi 'F.BIN' bd_ls.tmp || { cat bd_ls.tmp; fail "host: /BIG missing F.BIN"; }
rm -f bd_fsck.tmp bd_ls.tmp bdpad.bin bddir.asm

echo "OS-BIGDIR TEST: PASS"
