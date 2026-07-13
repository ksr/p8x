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
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null

asm() { python3 $ROOT/assembler/p8xasm.py "$1" -o "$2" --base 0x6A00 >/dev/null; }

build_disk() {   # compile wc/grep/cat with $1 (py|host), build a disk
    for c in wc grep cat; do
        python3 $ROOT/tools/clib.py $ROOT/os/commands/$c.c -o $c.pp.c   # splice //#use libs
        if [ "$1" = host ]; then ./p8cc_host < $c.pp.c > $c.asm
        else python3 $ROOT/compiler/p8cc.py $c.pp.c -o $c.asm >/dev/null; fi
        asm $c.asm $c.bin
    done
    rm -f flt.img
    python3 $ROOT/tools/p8xfs.py create flt.img >/dev/null
    python3 $ROOT/tools/p8xfs.py boot   flt.img osc.bin >/dev/null
    python3 $ROOT/tools/p8xfs.py mkdir  flt.img /bin >/dev/null
    python3 $ROOT/tools/p8xfs.py put    flt.img wc.bin   --name /bin/wc.bin   --load 0x6A00 --exec 0x6A00 >/dev/null
    python3 $ROOT/tools/p8xfs.py put    flt.img grep.bin --name /bin/grep.bin --load 0x6A00 --exec 0x6A00 >/dev/null
    python3 $ROOT/tools/p8xfs.py put    flt.img cat.bin  --name /bin/cat.bin  --load 0x6A00 --exec 0x6A00 >/dev/null
    printf 'alpha\r\nbeta\r\ngamma alpha\r\n' > tf.dat
    python3 $ROOT/tools/p8xfs.py put    flt.img tf.dat --name T.TXT --load 0 --exec 0 >/dev/null
    # two .LOG files for the glob tests (read as one concatenated stream):
    # G1 = 2 lines/2 words/11 bytes, G2 = 1 line/2 words/11 bytes -> *.LOG = 3 4 22
    printf 'red\r\nblue\r\n' > g1.dat
    python3 $ROOT/tools/p8xfs.py put    flt.img g1.dat --name G1.LOG --load 0 --exec 0 >/dev/null
    printf 'green key\r\n' > g2.dat
    python3 $ROOT/tools/p8xfs.py put    flt.img g2.dat --name G2.LOG --load 0 --exec 0 >/dev/null
    # a subdirectory with a file, for the recursive content search (GREP -r)
    python3 $ROOT/tools/p8xfs.py mkdir  flt.img /DOCS >/dev/null
    printf 'alpha doc\r\nplain line\r\n' > d.dat
    python3 $ROOT/tools/p8xfs.py put    flt.img d.dat --name /DOCS/D.TXT --load 0 --exec 0 >/dev/null
}

R() { printf "B\r$1\r" | ../p8xemu -l 300000000 -c flt.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r'; }

check() {   # $1 = label
    R 'wc <T.TXT' | grep -qx '3 4 26' || fail "$1: wc count != '3 4 26'"
    # literal substring: lines containing 'alpha', not 'beta'
    out=$(R 'grep alpha <T.TXT')
    echo "$out" | grep -qx 'alpha'       || fail "$1: grep missed 'alpha'"
    echo "$out" | grep -qx 'gamma alpha' || fail "$1: grep missed 'gamma alpha'"
    echo "$out" | grep -qx 'beta'        && fail "$1: grep wrongly printed 'beta'"
    # regex: ^ anchors start (only the line beginning with 'beta')
    out=$(R 'grep ^beta <T.TXT')
    echo "$out" | grep -qx 'beta'        || fail "$1: grep ^beta missed 'beta'"
    echo "$out" | grep -qx 'alpha'       && fail "$1: grep ^beta wrongly matched 'alpha'"
    # regex: '.' any char — al.ha matches both alpha lines, not beta
    out=$(R 'grep al.ha <T.TXT')
    echo "$out" | grep -qx 'alpha'       || fail "$1: grep 'al.ha' missed 'alpha'"
    echo "$out" | grep -qx 'gamma alpha' || fail "$1: grep 'al.ha' missed 'gamma alpha'"
    echo "$out" | grep -qx 'beta'        && fail "$1: grep 'al.ha' wrongly matched 'beta'"
    # regex: '*' — 'g.*a' matches 'gamma alpha' (g … a), not the others
    out=$(R 'grep g.*a <T.TXT')
    echo "$out" | grep -qx 'gamma alpha' || fail "$1: grep 'g.*a' missed 'gamma alpha'"
    echo "$out" | grep -qx 'beta'        && fail "$1: grep 'g.*a' wrongly matched 'beta'"
    # + (one or more): 'mm+' needs a double-m -> only 'gamma alpha'
    out=$(R 'grep mm+ <T.TXT')
    echo "$out" | grep -qx 'gamma alpha' || fail "$1: grep 'mm+' missed 'gamma alpha'"
    echo "$out" | grep -qx 'alpha'       && fail "$1: grep 'mm+' wrongly matched 'alpha'"
    # ? (zero or one): 'be?ta' matches 'beta', not 'alpha'
    out=$(R 'grep be?ta <T.TXT')
    echo "$out" | grep -qx 'beta'        || fail "$1: grep 'be?ta' missed 'beta'"
    echo "$out" | grep -qx 'alpha'       && fail "$1: grep 'be?ta' wrongly matched 'alpha'"
    # grep with a FILE ARGUMENT (like cat) instead of stdin
    out=$(R 'grep ^beta T.TXT')
    echo "$out" | grep -qx 'beta'        || fail "$1: grep <regex> <file> missed 'beta'"
    echo "$out" | grep -qx 'alpha'       && fail "$1: grep file-arg wrongly matched 'alpha'"
    R 'grep x NOPE.TXT' | grep -qi 'not found' || fail "$1: grep missing-file not reported"
    # pipes: cat | grep, cat | wc
    R 'cat T.TXT | grep beta' | grep -qx 'beta'   || fail "$1: cat | grep pipe"
    R 'cat T.TXT | run /bin/wc.bin' | grep -qx '3 4 26' || fail "$1: cat | wc pipe"
    # glob: a `*`/`?` arg is read as ONE concatenated stream over all matches
    R 'wc *.LOG' | grep -qx '3 4 22' || fail "$1: WC *.LOG combined count (concatenated)"
    R 'grep key *.LOG' | grep -qx 'green key' || fail "$1: GREP over *.LOG glob"
    # recursive content search: -r walks the CWD tree and prints "path:line"
    out=$(R 'grep -r alpha')
    echo "$out" | grep -qx '/T.TXT:alpha'        || fail "$1: GREP -r missed /T.TXT:alpha"
    echo "$out" | grep -qx '/T.TXT:gamma alpha'  || fail "$1: GREP -r missed /T.TXT:gamma alpha"
    echo "$out" | grep -qx '/DOCS/D.TXT:alpha doc' || fail "$1: GREP -r missed subdir /DOCS/D.TXT"
    echo "$out" | grep -q  'plain line'          && fail "$1: GREP -r wrongly matched a non-matching line"
    R 'wc -h'   | grep -qi usage || fail "$1: wc -h"
    R 'grep -h' | grep -qi usage || fail "$1: grep -h"
}

if command -v cc >/dev/null 2>&1; then
    cc -O2 -w $ROOT/compiler/p8cc.c -o p8cc_host 2>/dev/null || fail "cc could not build p8cc.c"
    build_disk host
    check "p8cc.c"
fi
build_disk py
check "p8cc.py"

echo "C-FILTERS TEST: PASS"
