#!/bin/sh
# tree (os/commands/tree.c) — the C version of the former TREE built-in
# (minimal-kernel split). Depth-first indented listing of the CWD tree.
# Compiled by BOTH p8cc.py and the native p8cc.c; invoked via explicit RUN.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-TREE TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x4000 >/dev/null

build_disk() {   # $1 = py|host
    if [ "$1" = host ]; then ./p8cc_host < $ROOT/os/commands/tree.c > tree.asm
    else python3 $ROOT/compiler/p8cc.py $ROOT/os/commands/tree.c -o tree.asm >/dev/null; fi
    python3 $ROOT/assembler/p8xasm.py tree.asm -o tree.bin --base 0xB000 >/dev/null
    rm -f tr.img
    python3 $ROOT/tools/p8xfs.py create tr.img >/dev/null
    python3 $ROOT/tools/p8xfs.py boot   tr.img osc.bin >/dev/null
    python3 $ROOT/tools/p8xfs.py mkdir  tr.img /BIN >/dev/null
    python3 $ROOT/tools/p8xfs.py mkdir  tr.img /SUB >/dev/null
    python3 $ROOT/tools/p8xfs.py put tr.img tree.bin --name /BIN/TREE.BIN --load 0xB000 --exec 0xB000 >/dev/null
    printf 'z' > tr_z.dat
    python3 $ROOT/tools/p8xfs.py put tr.img tr_z.dat --name /SUB/F.TXT --load 0 --exec 0 >/dev/null
}

R() { printf "B\r$1\r" | ../p8xemu -l 400000000 -c tr.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r'; }

check() {   # $1 = label
    out=$(R 'RUN /BIN/TREE.BIN')
    echo "$out" | grep -qx 'SUB/'    || fail "$1: tree missing SUB/"
    echo "$out" | grep -qx '  F.TXT' || fail "$1: tree missing indented F.TXT"
    R 'RUN /BIN/TREE.BIN -h' | grep -qi usage || fail "$1: tree -h"
}

if command -v cc >/dev/null 2>&1; then
    cc -O2 -w $ROOT/compiler/p8cc.c -o p8cc_host 2>/dev/null || fail "cc could not build p8cc.c"
    build_disk host
    check "p8cc.c"
fi
build_disk py
check "p8cc.py"

echo "C-TREE TEST: PASS"
