#!/bin/sh
# Recursive DIR (os/commands/dir.c with -R), exercising:
#   - argstr() flag parsing: a leading "-R" then an optional path
#   - per-level FNEXT loops that RECORD child-subdir LBAs and recurse AFTER the
#     loop closes — so the global FNEXT cursor (DILBA/DICNT/DIIDX) is never
#     re-entered mid-loop and no level loses its place
#   - the no-cap streaming property under recursion: RUN /DIR.BIN -R / >X must
#     capture the FULL multi-level listing to a file
# Compiled by BOTH p8cc.py and the native p8cc.c bootstrap.  Disk layout:
#   /                A.DAT, SUB/
#   /SUB             B.DAT, DEEP/
#   /SUB/DEEP        C.DAT
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-DIR-R TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x4000 >/dev/null
printf 'in-root' > a.dat
printf 'in-sub'  > b.dat
printf 'in-deep' > c.dat

build_disk() {   # $1 dir.bin -> rdir.img with a nested /SUB/DEEP tree + DIR.BIN
    rm -f rdir.img
    python3 $ROOT/tools/p8xfs.py create rdir.img >/dev/null
    python3 $ROOT/tools/p8xfs.py boot   rdir.img osc.bin >/dev/null
    python3 $ROOT/tools/p8xfs.py mkdir  rdir.img /SUB >/dev/null
    python3 $ROOT/tools/p8xfs.py mkdir  rdir.img /SUB/DEEP >/dev/null
    python3 $ROOT/tools/p8xfs.py put    rdir.img a.dat --name /A.DAT        --load 0 --exec 0 >/dev/null
    python3 $ROOT/tools/p8xfs.py put    rdir.img b.dat --name /SUB/B.DAT    --load 0 --exec 0 >/dev/null
    python3 $ROOT/tools/p8xfs.py put    rdir.img c.dat --name /SUB/DEEP/C.DAT --load 0 --exec 0 >/dev/null
    python3 $ROOT/tools/p8xfs.py put    rdir.img "$1" --name DIR.BIN --load 0xB000 --exec 0xB000 >/dev/null
}

session() {   # console output of a recursive listing from the root
    printf 'B\rRUN /DIR.BIN -R /\r' \
        | ../p8xemu -l 200000000 -c rdir.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r'
}

check() {   # $1 = label, $2 = console output of the recursive run
    # every level's entries must appear — depth 0, 1, and 2
    echo "$2" | grep -q 'A.DAT'  || fail "$1: -R did not list root file A.DAT"
    echo "$2" | grep -q 'SUB'    || fail "$1: -R did not list directory SUB"
    echo "$2" | grep -q 'B.DAT'  || fail "$1: -R did not descend into /SUB (B.DAT missing)"
    echo "$2" | grep -q 'DEEP'   || fail "$1: -R did not list directory /SUB/DEEP"
    echo "$2" | grep -q 'C.DAT'  || fail "$1: -R did not descend into /SUB/DEEP (C.DAT missing)"

    # redirection: the full recursive listing must stream to a file uncapped
    printf 'B\rRUN /DIR.BIN -R / >LIST.TXT\r' \
        | ../p8xemu -l 200000000 -c rdir.img eeprom.bin 2>/dev/null >/dev/null
    python3 $ROOT/tools/p8xfs.py get rdir.img LIST.TXT --out rlist.txt >/dev/null 2>&1 \
        || fail "$1: -R redirect did not create LIST.TXT"
    grep -q 'A.DAT' rlist.txt || fail "$1: redirected -R listing missing A.DAT"
    grep -q 'B.DAT' rlist.txt || fail "$1: redirected -R listing missing B.DAT"
    grep -q 'C.DAT' rlist.txt || fail "$1: redirected -R listing missing C.DAT (deep level lost)"
}

compile_one() {   # $1 = compiler tag
    if [ "$1" = "host" ]; then
        ./p8cc_host < $ROOT/os/commands/dir.c > d.asm
    else
        python3 $ROOT/compiler/p8cc.py $ROOT/os/commands/dir.c -o d.asm >/dev/null
    fi
    python3 $ROOT/assembler/p8xasm.py d.asm -o d.bin --base 0xB000 >/dev/null
    build_disk d.bin
}

if command -v cc >/dev/null 2>&1; then
    cc -O2 -w $ROOT/compiler/p8cc.c -o p8cc_host 2>/dev/null || fail "cc could not build p8cc.c"
    compile_one host
    check "p8cc.c" "$(session)"
fi

compile_one py
check "p8cc.py" "$(session)"

echo "C-DIR-R TEST: PASS"
