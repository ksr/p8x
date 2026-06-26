#!/bin/sh
# head, tail, and more (os/commands/head.c, tail.c, more.c): each reads a named
# file (opened like cat) or stdin, taking an optional -N line count (head/tail).
# Compiled by BOTH p8cc.py and the native p8cc.c. Fixture N.TXT = L01..L30.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-PAGER TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x4000 >/dev/null

build_disk() {   # $1 = py|host
    for c in head tail more cat; do
        python3 $ROOT/tools/clib.py $ROOT/os/commands/$c.c -o $c.pp.c   # splice //#use libs
        if [ "$1" = host ]; then ./p8cc_host < $c.pp.c > $c.asm
        else python3 $ROOT/compiler/p8cc.py $c.pp.c -o $c.asm >/dev/null; fi
        python3 $ROOT/assembler/p8xasm.py $c.asm -o $c.bin --base 0x7A00 >/dev/null
    done
    rm -f pg.img
    python3 $ROOT/tools/p8xfs.py create pg.img >/dev/null
    python3 $ROOT/tools/p8xfs.py boot   pg.img osc.bin >/dev/null
    python3 $ROOT/tools/p8xfs.py mkdir  pg.img /BIN >/dev/null
    for c in head tail more cat; do up=$(echo $c | tr a-z A-Z)
        python3 $ROOT/tools/p8xfs.py put pg.img $c.bin --name /BIN/$up.BIN --load 0x7A00 --exec 0x7A00 >/dev/null
    done
    python3 -c "import sys; sys.stdout.write(''.join('L%02d\r\n'%i for i in range(1,31)))" > pg.dat
    python3 $ROOT/tools/p8xfs.py put pg.img pg.dat --name N.TXT --load 0 --exec 0 >/dev/null
}

R() { printf "B\r$1\r" | ../p8xemu -l 400000000 -c pg.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r'; }

check() {   # $1 = label
    # head -3 (file arg): exactly L01..L03, not L04
    out=$(R 'HEAD -3 N.TXT')
    echo "$out" | grep -qx 'L01' || fail "$1: head -3 missing L01"
    echo "$out" | grep -qx 'L03' || fail "$1: head -3 missing L03"
    echo "$out" | grep -qx 'L04' && fail "$1: head -3 included L04"
    # head default 10 -> L10 present, L11 not
    out=$(R 'HEAD N.TXT')
    echo "$out" | grep -qx 'L10' || fail "$1: head default missing L10"
    echo "$out" | grep -qx 'L11' && fail "$1: head default included L11"
    # tail -3: L28..L30, not L27
    out=$(R 'TAIL -3 N.TXT')
    echo "$out" | grep -qx 'L30' || fail "$1: tail -3 missing L30"
    echo "$out" | grep -qx 'L28' || fail "$1: tail -3 missing L28"
    echo "$out" | grep -qx 'L27' && fail "$1: tail -3 included L27"
    # tail via a pipe
    R 'CAT N.TXT | RUN /BIN/TAIL.BIN -2' | grep -qx 'L30' || fail "$1: cat | tail pipe"
    # head via stdin redirect
    R 'HEAD -1 <N.TXT' | grep -qx 'L01' || fail "$1: head <file"
    # more: 'q' at the first --More-- stops within the first page (L01 yes, L30 no)
    out=$(printf 'B\rMORE N.TXT\rq' | ../p8xemu -l 400000000 -c pg.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')
    echo "$out" | grep -q 'L01' || fail "$1: more did not show the first page"
    echo "$out" | grep -q 'L30' && fail "$1: more 'q' did not stop (showed L30)"
    # more auto-advancing to EOF shows the whole file (L30 present)
    printf 'B\rMORE N.TXT\r' | ../p8xemu -l 400000000 -c pg.img eeprom.bin 2>/dev/null \
        | LC_ALL=C tr -d '\0\r' | grep -q 'L30' || fail "$1: more did not page to EOF"
    R 'HEAD -h' | grep -qi usage || fail "$1: head -h"
    R 'TAIL -h' | grep -qi usage || fail "$1: tail -h"
}

if command -v cc >/dev/null 2>&1; then
    cc -O2 -w $ROOT/compiler/p8cc.c -o p8cc_host 2>/dev/null || fail "cc could not build p8cc.c"
    build_disk host
    check "p8cc.c"
fi
build_disk py
check "p8cc.py"

echo "C-PAGER TEST: PASS"
