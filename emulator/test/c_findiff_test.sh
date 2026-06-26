#!/bin/sh
# find and diff (os/commands/find.c, diff.c):
#   find PATTERN  - recursively print CWD paths whose name contains PATTERN
#   diff A B      - prefix/suffix-anchored line diff (< only-in-A, > only-in-B)
# Compiled by BOTH p8cc.py and the native p8cc.c.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-FINDIFF TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x4000 >/dev/null

build_disk() {   # $1 = py|host
    for c in find diff; do
        python3 $ROOT/tools/clib.py $ROOT/os/commands/$c.c -o $c.pp.c   # splice //#use libs
        if [ "$1" = host ]; then ./p8cc_host < $c.pp.c > $c.asm
        else python3 $ROOT/compiler/p8cc.py $c.pp.c -o $c.asm >/dev/null; fi
        python3 $ROOT/assembler/p8xasm.py $c.asm -o $c.bin --base 0xA700 >/dev/null
    done
    rm -f fd.img
    python3 $ROOT/tools/p8xfs.py create fd.img >/dev/null
    python3 $ROOT/tools/p8xfs.py boot   fd.img osc.bin >/dev/null
    python3 $ROOT/tools/p8xfs.py mkdir  fd.img /BIN >/dev/null
    python3 $ROOT/tools/p8xfs.py put fd.img find.bin --name /BIN/FIND.BIN --load 0xA700 --exec 0xA700 >/dev/null
    python3 $ROOT/tools/p8xfs.py put fd.img diff.bin --name /BIN/DIFF.BIN --load 0xA700 --exec 0xA700 >/dev/null
    # a small tree for find: /A.TXT, /SUB/B.TXT, /SUB/DEEP/C.TXT
    python3 $ROOT/tools/p8xfs.py mkdir fd.img /SUB >/dev/null
    python3 $ROOT/tools/p8xfs.py mkdir fd.img /SUB/DEEP >/dev/null
    printf 'x' > fd_z.dat
    python3 $ROOT/tools/p8xfs.py put fd.img fd_z.dat --name /A.TXT --load 0 --exec 0 >/dev/null
    python3 $ROOT/tools/p8xfs.py put fd.img fd_z.dat --name /SUB/B.TXT --load 0 --exec 0 >/dev/null
    python3 $ROOT/tools/p8xfs.py put fd.img fd_z.dat --name /SUB/DEEP/C.TXT --load 0 --exec 0 >/dev/null
    # two files for diff: middle line differs
    printf 'one\r\ntwo\r\nthree\r\n'  > fd_a.dat
    printf 'one\r\nTWO\r\nthree\r\n'  > fd_b.dat
    printf 'one\r\ntwo\r\nthree\r\n'  > fd_c.dat
    python3 $ROOT/tools/p8xfs.py put fd.img fd_a.dat --name A1.TXT --load 0 --exec 0 >/dev/null
    python3 $ROOT/tools/p8xfs.py put fd.img fd_b.dat --name B1.TXT --load 0 --exec 0 >/dev/null
    python3 $ROOT/tools/p8xfs.py put fd.img fd_c.dat --name C1.TXT --load 0 --exec 0 >/dev/null
}

R() { printf "B\r$1\r" | ../p8xemu -l 500000000 -c fd.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r'; }

check() {   # $1 = label
    out=$(R 'FIND .TXT')
    echo "$out" | grep -qx '/A.TXT'          || fail "$1: find missed /A.TXT"
    echo "$out" | grep -qx '/SUB/B.TXT'      || fail "$1: find missed /SUB/B.TXT"
    echo "$out" | grep -qx '/SUB/DEEP/C.TXT' || fail "$1: find missed nested /SUB/DEEP/C.TXT"
    R 'FIND DEEP' | grep -qx '/SUB/DEEP'     || fail "$1: find missed the /SUB/DEEP directory"
    # glob mode (pattern has * or ?): *.TXT matches the files, not the dirs
    out=$(R 'FIND *.TXT')
    echo "$out" | grep -qx '/A.TXT'          || fail "$1: find *.TXT missed /A.TXT"
    echo "$out" | grep -qx '/SUB/DEEP/C.TXT' || fail "$1: find *.TXT missed nested C.TXT"
    echo "$out" | grep -qx '/SUB/DEEP'       && fail "$1: find *.TXT wrongly matched the DEEP dir"
    # 'B*' is a GLOB (name starts with B), not the literal substring "B*"
    R 'FIND B*' | grep -qx '/SUB/B.TXT'      || fail "$1: find B* (glob) missed /SUB/B.TXT"
    # diff: changed middle line
    out=$(R 'DIFF A1.TXT B1.TXT')
    echo "$out" | grep -qx '< two' || fail "$1: diff missing '< two'"
    echo "$out" | grep -qx '> TWO' || fail "$1: diff missing '> TWO'"
    # diff identical -> no < / > lines
    if R 'DIFF A1.TXT C1.TXT' | grep -qE '^[<>] '; then fail "$1: diff of identical files printed a diff"; fi
    R 'FIND -h' | grep -qi usage || fail "$1: find -h"
    R 'DIFF -h' | grep -qi usage || fail "$1: diff -h"
}

if command -v cc >/dev/null 2>&1; then
    cc -O2 -w $ROOT/compiler/p8cc.c -o p8cc_host 2>/dev/null || fail "cc could not build p8cc.c"
    build_disk host
    check "p8cc.c"
fi
build_disk py
check "p8cc.py"

echo "C-FINDIFF TEST: PASS"
