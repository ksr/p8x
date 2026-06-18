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
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o p8xos.bin --base 0x8000 >/dev/null

# A position-independent program at $A000: print "V2" then RTS.
cat > v2prog.asm <<'EOF'
        .org $A000
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
python3 $ROOT/assembler/p8xasm.py v2prog.asm -o v2prog.bin --base 0xA000 >/dev/null

rm -f v2.img
python3 $ROOT/tools/p8xfs.py create v2.img --v2 >/dev/null
python3 $ROOT/tools/p8xfs.py boot   v2.img p8xos.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  v2.img /BIN >/dev/null
python3 $ROOT/tools/p8xfs.py put    v2.img v2prog.bin --name /BIN/HELLO.BIN >/dev/null
printf 'readme' > v2r.tmp
python3 $ROOT/tools/p8xfs.py put    v2.img v2r.tmp --name /README >/dev/null
rm -f v2r.tmp v2prog.asm

# Navigate + manipulate: list root, cd into BIN, run from CWD and via absolute
# path, cd back, reject a bad cd; then make a directory on-target, save a file
# into it, reject RMDIR on the non-empty dir, delete the file, and RMDIR it.
# ...then PACK to reclaim the leaked TMP/T.BIN extents, and confirm the kept
# tree still navigates (CD into BIN, RUN HELLO.BIN -> a 3rd "V2") after the move.
out=$(printf 'B\rDIR\rTREE\rCAT /README\rCD BIN\rPWD\rRUN HELLO.BIN\rRUN /BIN/HELLO.BIN\rCD ..\rCD NOPE\rMKDIR /TMP\rCD TMP\rDEP A000 7A\rSAVE T.BIN A000 A010\rCD ..\rRMDIR TMP\rDEL /TMP/T.BIN\rRMDIR TMP\rPACK\rRUN /BIN/HELLO.BIN\rTREE\rDIR\r' | \
      ../p8xemu -l 400000000 -c v2.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')
fail() { echo "OS-V2 TEST: FAIL — $1"; echo "$out" | sed -n '/v1.0/,$p'; exit 1; }
echo "$out" | grep -q 'P8X/OS v1.0'   || fail "OS did not boot"
echo "$out" | grep -q '^readme'       || fail "CAT did not print file contents"
echo "$out" | grep -q '^/BIN$'        || fail "PWD did not print the working path"
echo "$out" | grep -q 'BIN.*<DIR>'    || fail "root DIR missing BIN <DIR>"
# TREE indents the hierarchy: BIN/ under root, HELLO.BIN deeper still.
echo "$out" | grep -q '^  BIN/'       || fail "TREE missing indented BIN/"
echo "$out" | grep -q '^    HELLO.BIN' || fail "TREE missing nested HELLO.BIN"
echo "$out" | grep -q '/BIN> '        || fail "CD BIN: prompt path not updated"
# RUN from CWD and via absolute path should each print V2 (two occurrences).
[ "$(echo "$out" | grep -c '^V2')" -ge 2 ] || fail "RUN (cwd and absolute) did not both run"
echo "$out" | grep -q '?NO DIR'       || fail "bad CD not rejected"
echo "$out" | grep -q 'DIR CREATED'   || fail "MKDIR failed"
echo "$out" | grep -q '?DIR NOT EMPTY' || fail "RMDIR did not refuse a non-empty dir"
echo "$out" | grep -q 'DIR REMOVED'   || fail "RMDIR (empty) failed"
echo "$out" | grep -q 'PACKED'        || fail "PACK did not run"
# RUN must still work after PACK relocated extents (3rd V2 in the output).
[ "$(echo "$out" | grep -c '^V2')" -ge 3 ] || fail "RUN failed after PACK (relocation broke a file)"
echo "OS-V2 TEST: PASS"
# After PACK the volume must be consistent AND fully compacted ('..' links
# checked by fsck; nothing left to reclaim).
python3 $ROOT/tools/p8xfs.py fsck v2.img >v2_fsck.tmp 2>&1 || { cat v2_fsck.tmp; echo "OS-V2 TEST: FAIL — fsck"; exit 1; }
grep -q '0 reclaimable' v2_fsck.tmp || { cat v2_fsck.tmp; echo "OS-V2 TEST: FAIL — PACK left reclaimable space"; exit 1; }
rm -f v2_fsck.tmp
