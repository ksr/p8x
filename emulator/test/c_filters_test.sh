#!/bin/sh
# Stdin-filter commands wc and grep (os/commands/wc.c, grep.c): pure
# getchar->putchar filters that compose with redirection (`<`) and pipes (`|`).
# Compiled by BOTH p8cc.py and the native p8cc.c. A 3-line fixture T.TXT
# ("alpha / beta / gamma alpha", CRLF) gives wc = "3 4 26" and grep finds the
# matching lines; both are also exercised through a CAT pipe.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-FILTERS TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x4000 >/dev/null

asm() { python3 $ROOT/assembler/p8xasm.py "$1" -o "$2" --base 0xB000 >/dev/null; }

build_disk() {   # compile wc/grep/cat with $1 (py|host), build a disk
    for c in wc grep cat; do
        if [ "$1" = host ]; then ./p8cc_host < $ROOT/os/commands/$c.c > $c.asm
        else python3 $ROOT/compiler/p8cc.py $ROOT/os/commands/$c.c -o $c.asm >/dev/null; fi
        asm $c.asm $c.bin
    done
    rm -f flt.img
    python3 $ROOT/tools/p8xfs.py create flt.img >/dev/null
    python3 $ROOT/tools/p8xfs.py boot   flt.img osc.bin >/dev/null
    python3 $ROOT/tools/p8xfs.py mkdir  flt.img /BIN >/dev/null
    python3 $ROOT/tools/p8xfs.py put    flt.img wc.bin   --name /BIN/WC.BIN   --load 0xB000 --exec 0xB000 >/dev/null
    python3 $ROOT/tools/p8xfs.py put    flt.img grep.bin --name /BIN/GREP.BIN --load 0xB000 --exec 0xB000 >/dev/null
    python3 $ROOT/tools/p8xfs.py put    flt.img cat.bin  --name /BIN/CAT.BIN  --load 0xB000 --exec 0xB000 >/dev/null
    printf 'alpha\r\nbeta\r\ngamma alpha\r\n' > tf.dat
    python3 $ROOT/tools/p8xfs.py put    flt.img tf.dat --name T.TXT --load 0 --exec 0 >/dev/null
}

R() { printf "B\r$1\r" | ../p8xemu -l 300000000 -c flt.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r'; }

check() {   # $1 = label
    R 'WC <T.TXT' | grep -qx '3 4 26' || fail "$1: wc count != '3 4 26'"
    # literal substring: lines containing 'alpha', not 'beta'
    out=$(R 'GREP alpha <T.TXT')
    echo "$out" | grep -qx 'alpha'       || fail "$1: grep missed 'alpha'"
    echo "$out" | grep -qx 'gamma alpha' || fail "$1: grep missed 'gamma alpha'"
    echo "$out" | grep -qx 'beta'        && fail "$1: grep wrongly printed 'beta'"
    # regex: ^ anchors start (only the line beginning with 'beta')
    out=$(R 'GREP ^beta <T.TXT')
    echo "$out" | grep -qx 'beta'        || fail "$1: grep ^beta missed 'beta'"
    echo "$out" | grep -qx 'alpha'       && fail "$1: grep ^beta wrongly matched 'alpha'"
    # regex: '.' any char — al.ha matches both alpha lines, not beta
    out=$(R 'GREP al.ha <T.TXT')
    echo "$out" | grep -qx 'alpha'       || fail "$1: grep 'al.ha' missed 'alpha'"
    echo "$out" | grep -qx 'gamma alpha' || fail "$1: grep 'al.ha' missed 'gamma alpha'"
    echo "$out" | grep -qx 'beta'        && fail "$1: grep 'al.ha' wrongly matched 'beta'"
    # regex: '*' — 'g.*a' matches 'gamma alpha' (g … a), not the others
    out=$(R 'GREP g.*a <T.TXT')
    echo "$out" | grep -qx 'gamma alpha' || fail "$1: grep 'g.*a' missed 'gamma alpha'"
    echo "$out" | grep -qx 'beta'        && fail "$1: grep 'g.*a' wrongly matched 'beta'"
    # pipes: cat | grep, cat | wc
    R 'CAT T.TXT | GREP beta' | grep -qx 'beta'   || fail "$1: cat | grep pipe"
    R 'CAT T.TXT | RUN /BIN/WC.BIN' | grep -qx '3 4 26' || fail "$1: cat | wc pipe"
    R 'WC -h'   | grep -qi usage || fail "$1: wc -h"
    R 'GREP -h' | grep -qi usage || fail "$1: grep -h"
}

if command -v cc >/dev/null 2>&1; then
    cc -O2 -w $ROOT/compiler/p8cc.c -o p8cc_host 2>/dev/null || fail "cc could not build p8cc.c"
    build_disk host
    check "p8cc.c"
fi
build_disk py
check "p8cc.py"

echo "C-FILTERS TEST: PASS"
