#!/bin/sh
# DIR wildcard/glob filtering (os/commands/dir.c + lib_glob.c): a path whose last
# component has '*' or '?' is a case-insensitive pattern; the part before the
# last '/' (or the CWD) is scanned and only matching names are printed. -R
# applies the filter at every level. Built by BOTH p8cc.py and the native p8cc.c.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode
fail() { echo "C-DIRGLOB TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o dgos.bin --base 0x4000 >/dev/null

build_disk() {   # $1 = py|host
    python3 $ROOT/tools/clib.py $ROOT/os/commands/dir.c -o dg.pp.c   # splice //#use glob
    if [ "$1" = host ]; then ./p8cc_host < dg.pp.c > dg.asm
    else python3 $ROOT/compiler/p8cc.py dg.pp.c -o dg.asm >/dev/null; fi
    python3 $ROOT/assembler/p8xasm.py dg.asm -o dg.bin --base 0xB000 >/dev/null
    rm -f dg.img
    python3 $ROOT/tools/p8xfs.py create dg.img --v2 >/dev/null
    python3 $ROOT/tools/p8xfs.py boot   dg.img dgos.bin >/dev/null
    python3 $ROOT/tools/p8xfs.py mkdir  dg.img /BIN >/dev/null
    python3 $ROOT/tools/p8xfs.py put    dg.img dg.bin --name /BIN/DIR.BIN --load 0xB000 --exec 0xB000 >/dev/null
    printf x > dgf
    for n in A.ASM B.ASM C.TXT READ.ME; do
        python3 $ROOT/tools/p8xfs.py put dg.img dgf --name /$n >/dev/null
    done
    python3 $ROOT/tools/p8xfs.py mkdir dg.img /SUB >/dev/null
    python3 $ROOT/tools/p8xfs.py put   dg.img dgf --name /SUB/D.ASM >/dev/null
}

# R: run a command line, return the listing lines (between boot banner and the
# next prompt), stripped of prompts/blanks.
R() { printf "B\r$1\r" | ../p8xemu -l 250000000 -c dg.img eeprom.bin 2>/dev/null \
        | LC_ALL=C tr -d '\0\r' | awk 'f&&/^\/> $/{exit} f; /v1.0/{f=1}' \
        | grep -vE '^/> ' | grep -v '^$'; }

check() {   # $1 = compiler tag
    out=$(R 'DIR *.ASM')
    echo "$out" | grep -qx 'A.ASM' && echo "$out" | grep -qx 'B.ASM' || fail "$1: *.ASM missed A/B.ASM"
    echo "$out" | grep -qx 'C.TXT' && fail "$1: *.ASM wrongly matched C.TXT"
    echo "$out" | grep -qx 'BIN'   && fail "$1: *.ASM wrongly matched BIN"
    # case-insensitive
    R 'DIR *.asm' | grep -qx 'A.ASM' || fail "$1: lowercase *.asm did not match"
    # glob within another directory
    R 'DIR /BIN/*.BIN' | grep -qx 'DIR.BIN' || fail "$1: /BIN/*.BIN missed DIR.BIN"
    # '?' = exactly one char: ?.ASM matches A.ASM, not READ.ME
    out=$(R 'DIR ?.ASM')
    echo "$out" | grep -qx 'A.ASM' || fail "$1: ?.ASM missed A.ASM"
    # -R applies the filter at every level (D.ASM lives in /SUB, indented)
    out=$(R 'DIR -R *.ASM')
    echo "$out" | grep -qx 'A.ASM'    || fail "$1: -R *.ASM missed A.ASM"
    echo "$out" | grep -q  'D.ASM'    || fail "$1: -R *.ASM missed nested D.ASM"
    echo "$out" | grep -qx 'C.TXT'    && fail "$1: -R *.ASM wrongly matched C.TXT"
    # no glob: plain listing unchanged (lists everything, no '/' suffix)
    out=$(R 'DIR')
    echo "$out" | grep -qx 'A.ASM' && echo "$out" | grep -qx 'C.TXT' && echo "$out" | grep -qx 'BIN' \
        || fail "$1: plain DIR regressed"
    echo "C-DIRGLOB ($1): ok"
}

build_disk py;   check "p8cc.py"
cc -O2 -w $ROOT/compiler/p8cc.c -o p8cc_host 2>/dev/null || fail "cc could not build p8cc.c"
build_disk host; check "p8cc.c"
rm -f dgf dg.pp.c
echo "C-DIRGLOB TEST: PASS"
