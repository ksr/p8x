#!/bin/sh
# tree and dump (os/commands/tree.c, dump.c), the C versions of the TREE and DUMP
# built-ins (part of moving pure viewers to /BIN). Compiled by BOTH p8cc.py and
# the native p8cc.c. Invoked via explicit RUN so the test works whether or not
# the built-ins still exist.
#   tree - depth-first indented listing of the CWD tree
#   dump - 256-byte hex+ASCII dump of memory from a hex address
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-TREEDUMP TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x4000 >/dev/null

build_disk() {   # $1 = py|host
    for c in tree dump; do
        if [ "$1" = host ]; then ./p8cc_host < $ROOT/os/commands/$c.c > $c.asm
        else python3 $ROOT/compiler/p8cc.py $ROOT/os/commands/$c.c -o $c.asm >/dev/null; fi
        python3 $ROOT/assembler/p8xasm.py $c.asm -o $c.bin --base 0xB000 >/dev/null
    done
    rm -f tdt.img
    python3 $ROOT/tools/p8xfs.py create tdt.img >/dev/null
    python3 $ROOT/tools/p8xfs.py boot   tdt.img osc.bin >/dev/null
    python3 $ROOT/tools/p8xfs.py mkdir  tdt.img /BIN >/dev/null
    python3 $ROOT/tools/p8xfs.py mkdir  tdt.img /SUB >/dev/null
    python3 $ROOT/tools/p8xfs.py put tdt.img tree.bin --name /BIN/TREE.BIN --load 0xB000 --exec 0xB000 >/dev/null
    python3 $ROOT/tools/p8xfs.py put tdt.img dump.bin --name /BIN/DUMP.BIN --load 0xB000 --exec 0xB000 >/dev/null
    printf 'z' > tdt_z.dat
    python3 $ROOT/tools/p8xfs.py put tdt.img tdt_z.dat --name /SUB/F.TXT --load 0 --exec 0 >/dev/null
}

R() { printf "B\r$1\r" | ../p8xemu -l 400000000 -c tdt.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r'; }

check() {   # $1 = label
    out=$(R 'RUN /BIN/TREE.BIN')
    echo "$out" | grep -qx 'SUB/'      || fail "$1: tree missing SUB/"
    echo "$out" | grep -qx '  F.TXT'   || fail "$1: tree missing indented F.TXT"
    # dump: a 16-byte row at the requested address, "AAAA: .. |....|"
    R 'RUN /BIN/DUMP.BIN 4000' | grep -qE '^4000: [0-9A-F][0-9A-F] ' || fail "$1: dump row format"
    R 'RUN /BIN/DUMP.BIN 4000' | grep -cE '^[0-9A-F]{4}: ' | grep -qx 16 || fail "$1: dump != 16 rows"
    R 'RUN /BIN/TREE.BIN -h' | grep -qi usage || fail "$1: tree -h"
    R 'RUN /BIN/DUMP.BIN -h' | grep -qi usage || fail "$1: dump -h"
}

if command -v cc >/dev/null 2>&1; then
    cc -O2 -w $ROOT/compiler/p8cc.c -o p8cc_host 2>/dev/null || fail "cc could not build p8cc.c"
    build_disk host
    check "p8cc.c"
fi
build_disk py
check "p8cc.py"

echo "C-TREEDUMP TEST: PASS"
