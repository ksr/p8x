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

# Navigate: list root, cd into BIN, run from CWD, run via absolute path,
# cd back up, and confirm a bad cd is rejected.
out=$(printf 'B\rDIR\rCD BIN\rRUN HELLO.BIN\rRUN /BIN/HELLO.BIN\rCD ..\rCD NOPE\rDIR\r' | \
      ../p8xemu -l 150000000 -c v2.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0')
fail() { echo "OS-V2 TEST: FAIL — $1"; echo "$out" | sed -n '/v0.6/,$p'; exit 1; }
echo "$out" | grep -q 'P8X/OS v0.6'   || fail "OS did not boot"
echo "$out" | grep -q 'BIN.*<DIR>'    || fail "root DIR missing BIN <DIR>"
echo "$out" | grep -q '/BIN> '        || fail "CD BIN: prompt path not updated"
# RUN from CWD and via absolute path should each print V2 (two occurrences).
[ "$(echo "$out" | grep -c '^V2')" -ge 2 ] || fail "RUN (cwd and absolute) did not both run"
echo "$out" | grep -q '?NO DIR'       || fail "bad CD not rejected"
# After CD .. the prompt returns to root.
echo "$out" | sed -n '/NO DIR/,$p' | grep -q '/> '  || fail "CD .. did not return to root"
echo "OS-V2 TEST: PASS"
