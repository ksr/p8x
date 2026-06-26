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
    python3 $ROOT/tools/p8xfs.py put    cat.img "$1" --name /BIN/CAT.BIN --load 0xA700 --exec 0xA700 >/dev/null
    printf 'ROOTOK\n' > rr.txt
    python3 $ROOT/tools/p8xfs.py put    cat.img rr.txt --name R.TXT --load 0 --exec 0 >/dev/null
    printf 'DEEPOK\n' > ss.txt
    python3 $ROOT/tools/p8xfs.py put    cat.img ss.txt --name /SUB/S.TXT --load 0 --exec 0 >/dev/null
    # three files for glob: A.LOG/B.LOG match *.LOG, X.DAT does not
    printf 'AAA\n' > a.log
    python3 $ROOT/tools/p8xfs.py put    cat.img a.log --name A.LOG --load 0 --exec 0 >/dev/null
    printf 'BBB\n' > b.log
    python3 $ROOT/tools/p8xfs.py put    cat.img b.log --name B.LOG --load 0 --exec 0 >/dev/null
    printf 'ZZZ\n' > x.dat
    python3 $ROOT/tools/p8xfs.py put    cat.img x.dat --name X.DAT --load 0 --exec 0 >/dev/null
}

R() { printf "B\r$1\r" | ../p8xemu -l 250000000 -c cat.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r'; }

check() {   # $1 = label
    R 'RUN /BIN/CAT.BIN R.TXT'          | grep -q 'ROOTOK'  || fail "$1: cat <file-arg> (CWD root)"
    R 'RUN /BIN/CAT.BIN /SUB/S.TXT'     | grep -q 'DEEPOK'  || fail "$1: cat <absolute path>"
    R 'CD /SUB\rRUN /BIN/CAT.BIN S.TXT' | grep -q 'DEEPOK'  || fail "$1: cat <relative> resolves against CWD"
    R 'RUN /BIN/CAT.BIN <R.TXT'         | grep -q 'ROOTOK'  || fail "$1: cat (no arg) still filters stdin"
    R 'RUN /BIN/CAT.BIN NOPE.TXT' | grep -qi 'not found'    || fail "$1: missing file not reported"
    R 'RUN /BIN/CAT.BIN -h'       | grep -qi 'usage'        || fail "$1: -h did not print usage"
    # console stdin -> file, terminated by Ctrl-D ($04): type "ZAPPED" then ^D
    printf 'B\rRUN /BIN/CAT.BIN >CAP.TXT\rZAPPED\004' \
        | ../p8xemu -l 250000000 -c cat.img eeprom.bin 2>/dev/null >/dev/null
    python3 $ROOT/tools/p8xfs.py get cat.img CAP.TXT --out cap.txt >/dev/null 2>&1 \
        || fail "$1: console capture (Ctrl-D) did not create the file"
    grep -q 'ZAPPED' cap.txt || fail "$1: console stdin not captured up to Ctrl-D"
    # an Enter keypress is captured as CR+LF: type "AB"<CR>"CD" then ^D -> AB\r\nCD
    printf 'B\rRUN /BIN/CAT.BIN >CR.TXT\rAB\rCD\004' \
        | ../p8xemu -l 250000000 -c cat.img eeprom.bin 2>/dev/null >/dev/null
    python3 $ROOT/tools/p8xfs.py get cat.img CR.TXT --out cr.txt >/dev/null 2>&1 \
        || fail "$1: CRLF capture did not create the file"
    printf 'AB\r\nCD' > cr.exp
    cmp -s cr.txt cr.exp || fail "$1: typed CR not captured as CR+LF"
    # file-arg cat piped into a stdin-filter cat: both modes in one line
    R 'RUN /BIN/CAT.BIN R.TXT | RUN /BIN/CAT.BIN' | grep -q 'ROOTOK' || fail "$1: cat file | cat"
    # arg-mode cat redirected to a file
    R 'RUN /BIN/CAT.BIN R.TXT >O.TXT' >/dev/null
    python3 $ROOT/tools/p8xfs.py get cat.img O.TXT --out co.txt >/dev/null 2>&1 || fail "$1: cat file >OUT did not write"
    grep -q 'ROOTOK' co.txt || fail "$1: redirected cat-file output wrong"
    # glob: `cat *.LOG` concatenates A.LOG + B.LOG but not X.DAT
    R 'RUN /BIN/CAT.BIN *.LOG' | grep -q 'AAA' || fail "$1: cat *.LOG missed A.LOG"
    R 'RUN /BIN/CAT.BIN *.LOG' | grep -q 'BBB' || fail "$1: cat *.LOG missed B.LOG"
    R 'RUN /BIN/CAT.BIN *.LOG' | grep -q 'ZZZ' && fail "$1: cat *.LOG wrongly included X.DAT"
    # glob to a file: `cat *.LOG >GLB.TXT` captures both matches
    R 'RUN /BIN/CAT.BIN *.LOG >GLB.TXT' >/dev/null
    python3 $ROOT/tools/p8xfs.py get cat.img GLB.TXT --out glb.txt >/dev/null 2>&1 || fail "$1: cat glob >OUT did not write"
    grep -q 'AAA' glb.txt && grep -q 'BBB' glb.txt || fail "$1: cat glob >OUT missing a match"
}

python3 $ROOT/tools/clib.py $ROOT/os/commands/cat.c -o cat.pp.c   # splice //#use glob,globx

if command -v cc >/dev/null 2>&1; then
    cc -O2 -w $ROOT/compiler/p8cc.c -o p8cc_host 2>/dev/null || fail "cc could not build p8cc.c"
    ./p8cc_host < cat.pp.c > ch.asm
    python3 $ROOT/assembler/p8xasm.py ch.asm -o ch.bin --base 0xA700 >/dev/null
    build_disk ch.bin
    check "p8cc.c"
fi

python3 $ROOT/compiler/p8cc.py cat.pp.c -o cp.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py cp.asm -o cp.bin --base 0xA700 >/dev/null
build_disk cp.bin
check "p8cc.py"

echo "C-CAT TEST: PASS"
