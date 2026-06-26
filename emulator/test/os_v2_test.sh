#!/bin/sh
# P8X/OS v2 (hierarchical) navigation test. Build a v2 disk on the host with a
# subdirectory and a runnable program inside it, boot the OS, and exercise the
# path layer: DIR of root and a path, CD (relative, absolute, '..'), the path
# prompt, and RUN both from the CWD and via an absolute path.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o p8xos.bin --base 0x4000 >/dev/null

# A position-independent program at $B000: print "V2" then RTS.
cat > v2prog.asm <<'EOF'
        .org $B000
        LDA  #'V'
        JSR  $0103
        LDA  #'2'
        JSR  $0103
        LDA  #$0D
        JSR  $0103
        LDA  #$0A
        JSR  $0103
        RTS
EOF
python3 $ROOT/assembler/p8xasm.py v2prog.asm -o v2prog.bin --base 0xB000 >/dev/null

rm -f v2.img
python3 $ROOT/tools/p8xfs.py create v2.img --v2 >/dev/null
python3 $ROOT/tools/p8xfs.py boot   v2.img p8xos.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  v2.img /BIN >/dev/null
python3 $ROOT/tools/p8xfs.py put    v2.img v2prog.bin --name /BIN/HELLO.BIN >/dev/null
# CAT is no longer a built-in; install the C cat (os/commands/cat.c) so a bare
# `CAT /README` resolves via PATH (/BIN) — this doubles as an implicit-RUN check.
python3 $ROOT/tools/clib.py $ROOT/os/commands/cat.c -o v2cat.pp.c   # splice //#use glob,globx
python3 $ROOT/compiler/p8cc.py v2cat.pp.c -o v2cat.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py v2cat.asm -o v2cat.bin --base 0xB000 >/dev/null
python3 $ROOT/tools/p8xfs.py put    v2.img v2cat.bin --name /BIN/CAT.BIN --load 0xB000 --exec 0xB000 >/dev/null
# DIR/PWD/TREE are no longer built-ins either — install their C versions so the
# bare names resolve via PATH (/BIN).
for c in dir pwd tree; do
    python3 $ROOT/tools/clib.py $ROOT/os/commands/$c.c -o v2$c.pp.c   # splice //#use (dir: glob)
    python3 $ROOT/compiler/p8cc.py v2$c.pp.c -o v2$c.asm >/dev/null
    python3 $ROOT/assembler/p8xasm.py v2$c.asm -o v2$c.bin --base 0xB000 >/dev/null
    up=$(echo $c | tr a-z A-Z)
    python3 $ROOT/tools/p8xfs.py put v2.img v2$c.bin --name /BIN/$up.BIN --load 0xB000 --exec 0xB000 >/dev/null
done
printf 'readme' > v2r.tmp
python3 $ROOT/tools/p8xfs.py put    v2.img v2r.tmp --name /README >/dev/null
rm -f v2r.tmp v2prog.asm

# Navigate + manipulate: list root, cd into BIN, run from CWD and via absolute
# path, cd back, reject a bad cd; then make a directory on-target, save a file
# into it, reject RMDIR on the non-empty dir, delete the file, and RMDIR it.
# ...then PACK to reclaim the leaked TMP/T.BIN extents, and confirm the kept
# tree still navigates (CD into BIN, RUN HELLO.BIN -> a 3rd "V2") after the move.
out=$(printf 'B\rDIR\rTREE\rCAT /README\rCD BIN\rPWD\rRUN HELLO.BIN\rRUN /BIN/HELLO.BIN\rCD ..\rCD NOPE\rMKDIR /TMP\rCD TMP\rDEP B000 7A\rSAVE T.BIN B000 B010\rCD ..\rRMDIR TMP\rDEL /TMP/T.BIN\rRMDIR TMP\rPACK\rFSCK\rRUN /BIN/HELLO.BIN\rTREE\rDIR\r' | \
      ../p8xemu -l 400000000 -c v2.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')
fail() { echo "OS-V2 TEST: FAIL — $1"; echo "$out" | sed -n '/v1.0/,$p'; exit 1; }
echo "$out" | grep -q 'P8X/OS v1.0'   || fail "OS did not boot"
echo "$out" | grep -q '^readme'       || fail "CAT did not print file contents"
echo "$out" | grep -q '^/BIN$'        || fail "PWD did not print the working path"
# /BIN/DIR.BIN lists "<size>  NAME" with a '/' suffix on dirs — root shows BIN/
# (the leading space distinguishes it from TREE's column-0 'BIN/' below).
echo "$out" | grep -qE ' BIN/$'       || fail "root DIR missing BIN"
# /BIN/TREE.BIN indents 2 spaces/level from depth 0: BIN/ at root, HELLO.BIN under it.
echo "$out" | grep -qx 'BIN/'         || fail "TREE missing BIN/"
echo "$out" | grep -qx '  HELLO.BIN'  || fail "TREE missing nested HELLO.BIN"
echo "$out" | grep -q '/BIN> '        || fail "CD BIN: prompt path not updated"
# RUN from CWD and via absolute path should each print V2 (two occurrences).
[ "$(echo "$out" | grep -c '^V2')" -ge 2 ] || fail "RUN (cwd and absolute) did not both run"
echo "$out" | grep -q '?NO DIR'       || fail "bad CD not rejected"
echo "$out" | grep -q 'DIR CREATED'   || fail "MKDIR failed"
echo "$out" | grep -q '?DIR NOT EMPTY' || fail "RMDIR did not refuse a non-empty dir"
echo "$out" | grep -q 'DIR REMOVED'   || fail "RMDIR (empty) failed"
echo "$out" | grep -q 'PACKED'        || fail "PACK did not run"
# on-target FSCK must pass on the clean (post-PACK) volume
echo "$out" | grep -q 'FSCK OK'       || fail "FSCK reported problems on a clean volume"
# RUN must still work after PACK relocated extents (3rd V2 in the output).
[ "$(echo "$out" | grep -c '^V2')" -ge 3 ] || fail "RUN failed after PACK (relocation broke a file)"
echo "OS-V2 TEST: PASS"
# After PACK the volume must be consistent AND fully compacted ('..' links
# checked by fsck; nothing left to reclaim).
python3 $ROOT/tools/p8xfs.py fsck v2.img >v2_fsck.tmp 2>&1 || { cat v2_fsck.tmp; echo "OS-V2 TEST: FAIL — fsck"; exit 1; }
grep -q '0 reclaimable' v2_fsck.tmp || { cat v2_fsck.tmp; echo "OS-V2 TEST: FAIL — PACK left reclaimable space"; exit 1; }
rm -f v2_fsck.tmp

# Negative: corrupt the boot-block free pointer and confirm on-target FSCK
# flags it (proves FSCK isn't trivially always-OK).
cp v2.img v2bad.img
printf '\001' | dd of=v2bad.img bs=1 seek=4 count=1 conv=notrunc 2>/dev/null
bad=$(printf 'B\rFSCK\r' | ../p8xemu -l 400000000 -c v2bad.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')
echo "$bad" | grep -q 'FSCK: PROBLEMS' || { echo "OS-V2 TEST: FAIL — FSCK did not flag a corrupted volume"; exit 1; }
rm -f v2bad.img
