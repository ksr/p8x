#!/bin/sh
# cat with a FILENAME argument (Unix `cat file`): os/commands/cat.c opens the
# named file directly (FRESOLVE + FOPEN/FGETB) when given an argument, and falls
# back to the stdin filter when given none — so `cat file`, `cat <file` and
# `cat |` all work. Builds an ABSOLUTE path (CWD via SYS_GETCWD) so a relative
# argument resolves against the shell's CWD, not the BIOS root. Compiled by BOTH
# p8cc.py and the native p8cc.c. Programs are invoked by explicit RUN so the test
# exercises cat.c itself, not the (still-present) built-in CAT.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-CAT TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x4000 >/dev/null

build_disk() {   # $1 = cat.bin
    rm -f cat.img
    python3 $ROOT/tools/p8xfs.py create cat.img >/dev/null
    python3 $ROOT/tools/p8xfs.py boot   cat.img osc.bin >/dev/null
    python3 $ROOT/tools/p8xfs.py mkdir  cat.img /BIN >/dev/null
    python3 $ROOT/tools/p8xfs.py mkdir  cat.img /SUB >/dev/null
    python3 $ROOT/tools/p8xfs.py put    cat.img "$1" --name /BIN/CAT.BIN --load 0xB000 --exec 0xB000 >/dev/null
    printf 'ROOTOK\n' > rr.txt
    python3 $ROOT/tools/p8xfs.py put    cat.img rr.txt --name R.TXT --load 0 --exec 0 >/dev/null
    printf 'DEEPOK\n' > ss.txt
    python3 $ROOT/tools/p8xfs.py put    cat.img ss.txt --name /SUB/S.TXT --load 0 --exec 0 >/dev/null
}

R() { printf "B\r$1\r" | ../p8xemu -l 250000000 -c cat.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r'; }

check() {   # $1 = label
    R 'RUN /BIN/CAT.BIN R.TXT'          | grep -q 'ROOTOK'  || fail "$1: cat <file-arg> (CWD root)"
    R 'RUN /BIN/CAT.BIN /SUB/S.TXT'     | grep -q 'DEEPOK'  || fail "$1: cat <absolute path>"
    R 'CD /SUB\rRUN /BIN/CAT.BIN S.TXT' | grep -q 'DEEPOK'  || fail "$1: cat <relative> resolves against CWD"
    R 'RUN /BIN/CAT.BIN <R.TXT'         | grep -q 'ROOTOK'  || fail "$1: cat (no arg) still filters stdin"
    R 'RUN /BIN/CAT.BIN NOPE.TXT' | grep -qi 'not found'    || fail "$1: missing file not reported"
    R 'RUN /BIN/CAT.BIN -h'       | grep -qi 'usage'        || fail "$1: -h did not print usage"
    # file-arg cat piped into a stdin-filter cat: both modes in one line
    R 'RUN /BIN/CAT.BIN R.TXT | RUN /BIN/CAT.BIN' | grep -q 'ROOTOK' || fail "$1: cat file | cat"
    # arg-mode cat redirected to a file
    R 'RUN /BIN/CAT.BIN R.TXT >O.TXT' >/dev/null
    python3 $ROOT/tools/p8xfs.py get cat.img O.TXT --out co.txt >/dev/null 2>&1 || fail "$1: cat file >OUT did not write"
    grep -q 'ROOTOK' co.txt || fail "$1: redirected cat-file output wrong"
}

if command -v cc >/dev/null 2>&1; then
    cc -O2 -w $ROOT/compiler/p8cc.c -o p8cc_host 2>/dev/null || fail "cc could not build p8cc.c"
    ./p8cc_host < $ROOT/os/commands/cat.c > ch.asm
    python3 $ROOT/assembler/p8xasm.py ch.asm -o ch.bin --base 0xB000 >/dev/null
    build_disk ch.bin
    check "p8cc.c"
fi

python3 $ROOT/compiler/p8cc.py $ROOT/os/commands/cat.c -o cp.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py cp.asm -o cp.bin --base 0xB000 >/dev/null
build_disk cp.bin
check "p8cc.py"

echo "C-CAT TEST: PASS"
