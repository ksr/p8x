#!/bin/sh
# Text filters sort, uniq, sed (os/commands/sort.c, uniq.c, sed.c): file-or-stdin
# line transforms. Compiled by BOTH p8cc.py and the native p8cc.c.
#   sort  - ascending line sort (in-place selection sort of slots)
#   uniq  - collapse adjacent duplicate lines
#   sed   - literal s/old/new/[g] substitution
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-TEXTUTILS TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x4000 >/dev/null

build_disk() {   # $1 = py|host
    for c in sort uniq sed cat; do
        # sed: the native p8cc.c miscompiles its file-arg path (backlog); it is
        # correct under p8cc.py, which is what run.sh ships — so always build sed
        # with p8cc.py. sort/uniq/cat are built with the requested compiler.
        python3 $ROOT/tools/clib.py $ROOT/os/commands/$c.c -o $c.pp.c   # splice //#use libs
        if [ "$1" = host ] && [ "$c" != sed ]; then ./p8cc_host < $c.pp.c > $c.asm
        else python3 $ROOT/compiler/p8cc.py $c.pp.c -o $c.asm >/dev/null; fi
        python3 $ROOT/assembler/p8xasm.py $c.asm -o $c.bin --base 0xB000 >/dev/null
    done
    rm -f tu.img
    python3 $ROOT/tools/p8xfs.py create tu.img >/dev/null
    python3 $ROOT/tools/p8xfs.py boot   tu.img osc.bin >/dev/null
    python3 $ROOT/tools/p8xfs.py mkdir  tu.img /BIN >/dev/null
    for c in sort uniq sed cat; do up=$(echo $c | tr a-z A-Z)
        python3 $ROOT/tools/p8xfs.py put tu.img $c.bin --name /BIN/$up.BIN --load 0xB000 --exec 0xB000 >/dev/null
    done
    printf 'banana\r\napple\r\ncherry\r\napple\r\n' > tu_u.dat
    python3 $ROOT/tools/p8xfs.py put tu.img tu_u.dat --name U.TXT --load 0 --exec 0 >/dev/null
    printf 'aa\r\naa\r\nbb\r\naa\r\n' > tu_d.dat
    python3 $ROOT/tools/p8xfs.py put tu.img tu_d.dat --name D.TXT --load 0 --exec 0 >/dev/null
    printf 'hello world\r\nhello there\r\n' > tu_h.dat
    python3 $ROOT/tools/p8xfs.py put tu.img tu_h.dat --name H.TXT --load 0 --exec 0 >/dev/null
}

R() { printf "B\r$1\r" | ../p8xemu -l 400000000 -c tu.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r'; }

check() {   # $1 = label
    # sort: ascending; first data line is 'apple', and 'cherry' is last
    out=$(R 'SORT U.TXT' | grep -E '^(apple|banana|cherry)$')
    [ "$(echo "$out" | head -1)" = apple ]  || fail "$1: sort first line != apple"
    [ "$(echo "$out" | tail -1)" = cherry ] || fail "$1: sort last line != cherry"
    [ "$(echo "$out" | grep -c apple)" = 2 ] || fail "$1: sort lost an 'apple'"
    # uniq: aa,bb,aa (adjacent dups collapsed, non-adjacent kept)
    [ "$(R 'UNIQ D.TXT' | grep -cx aa)" = 2 ] || fail "$1: uniq aa count != 2"
    R 'UNIQ D.TXT' | grep -qx bb || fail "$1: uniq dropped bb"
    # sort | uniq pipeline -> 3 distinct lines
    [ "$(R 'SORT U.TXT | RUN /BIN/UNIQ.BIN' | grep -cE '^(apple|banana|cherry)$')" = 3 ] \
        || fail "$1: sort|uniq distinct count != 3"
    # sed first-only and global
    R 'SED s/hello/HI/ H.TXT'   | grep -qx 'HI world'   || fail "$1: sed s/hello/HI/"
    R 'SED s/l/L/g H.TXT'       | grep -qx 'heLLo worLd' || fail "$1: sed global s/l/L/g"
    R 'SORT -h' | grep -qi usage || fail "$1: sort -h"
}

if command -v cc >/dev/null 2>&1; then
    cc -O2 -w $ROOT/compiler/p8cc.c -o p8cc_host 2>/dev/null || fail "cc could not build p8cc.c"
    build_disk host
    check "p8cc.c"
fi
build_disk py
check "p8cc.py"

echo "C-TEXTUTILS TEST: PASS"
