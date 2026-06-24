#!/bin/sh
# DIR-in-C (compiler/examples/dir.c): an OS command written as a loadable C
# program.  Exercises the two new primitives — argstr() (the RUN arg tail in P2)
# and bios()'s carry flag (bit 8) to terminate the FOPENDIR/FNEXT loop.  Compiled
# by BOTH p8cc.py and the native p8cc.c bootstrap; `RUN DIR.BIN /` must list the
# root entries, including the two data files we planted.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-DIR TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x4000 >/dev/null
printf 'hello'   > aaa.dat
printf 'worldXY' > bbb.dat

run() {   # $1 = dir.asm -> emulator output of `RUN DIR.BIN /`
    python3 $ROOT/assembler/p8xasm.py "$1" -o dir.bin --base 0xB000 >/dev/null
    rm -f dir.img
    python3 $ROOT/tools/p8xfs.py create dir.img >/dev/null
    python3 $ROOT/tools/p8xfs.py boot   dir.img osc.bin >/dev/null
    python3 $ROOT/tools/p8xfs.py put    dir.img aaa.dat --name AAA.DAT --load 0 --exec 0 >/dev/null
    python3 $ROOT/tools/p8xfs.py put    dir.img bbb.dat --name BBB.DAT --load 0 --exec 0 >/dev/null
    python3 $ROOT/tools/p8xfs.py put    dir.img dir.bin --name DIR.BIN --load 0xB000 --exec 0xB000 >/dev/null
    printf 'B\rRUN DIR.BIN /\r' | ../p8xemu -l 120000000 -c dir.img eeprom.bin 2>/dev/null \
        | LC_ALL=C tr -d '\0\r' | sed -n '/RUN DIR.BIN/,$p' | grep -v 'RUN DIR.BIN'
}

check() {   # $1 = label, $2 = output
    echo "$2" | grep -qx 'AAA.DAT' || fail "$1: AAA.DAT not listed"
    echo "$2" | grep -qx 'BBB.DAT' || fail "$1: BBB.DAT not listed"
    echo "$2" | grep -qx 'DIR.BIN' || fail "$1: DIR.BIN not listed"
}

if command -v cc >/dev/null 2>&1; then
    cc -O2 -w $ROOT/compiler/p8cc.c -o p8cc_host 2>/dev/null || fail "cc could not build p8cc.c"
    ./p8cc_host < $ROOT/compiler/examples/dir.c > dh.asm
    check "p8cc.c" "$(run dh.asm)"
fi

python3 $ROOT/compiler/p8cc.py $ROOT/compiler/examples/dir.c -o dp.asm >/dev/null
check "p8cc.py" "$(run dp.asm)"

echo "C-DIR TEST: PASS"
