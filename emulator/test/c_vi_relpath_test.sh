#!/bin/sh
# vi (os/commands/vi.c + os/commands-asm/vi.asm) must resolve a RELATIVE filename
# argument against the CWD, not the root: FRESOLVE/FOPEN start at the root, so a
# bare `vi NOTES` from within /SUB must open /SUB/NOTES (via abspath), not /NOTES.
# Regression for the bug where vi FRESOLVE'd the raw arg (it opened /NOTES and, on
# save, wrote to the wrong place). Read-side check: put /SUB/READ.TXT = HELLOSUB,
# `cd /SUB; vi READ.TXT; :q`, and assert vi displayed HELLOSUB (it loaded the
# CWD-relative file). A buggy vi opens the non-existent /READ.TXT -> empty screen.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode
fail() { echo "C-VI-RELPATH TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osvi.bin --base 0x2000 >/dev/null

build_disk() {   # $1 = vi binary -> vi.img with /SUB/READ.TXT + /VI.bin
    rm -f vi.img
    python3 $ROOT/tools/p8xfs.py create vi.img >/dev/null
    python3 $ROOT/tools/p8xfs.py boot   vi.img osvi.bin >/dev/null
    python3 $ROOT/tools/p8xfs.py mkdir  vi.img /SUB >/dev/null
    printf 'HELLOSUB\n' > read.dat
    python3 $ROOT/tools/p8xfs.py put vi.img read.dat --name /SUB/READ.TXT --load 0 --exec 0 >/dev/null
    python3 $ROOT/tools/p8xfs.py put vi.img "$1" --name /VI.bin --load 0x6A00 --exec 0x6A00 >/dev/null
}

run_vi() {   # echoes vi's console output for: cd /SUB; vi READ.TXT; :q
    printf 'B\rcd /SUB\rrun /VI.bin READ.TXT\r:q\r' \
        | ../p8xemu -l 800000000 -c vi.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0'
}

check() {   # $1 = label
    out=$(run_vi)
    echo "$out" | grep -q 'HELLOSUB' \
        || fail "$1: vi did not load the CWD-relative /SUB/READ.TXT (no HELLOSUB on screen)"
    echo "$1: relative filename resolved against CWD — OK"
}

# C twin (p8cc.py)
python3 $ROOT/tools/clib.py $ROOT/os/commands/vi.c -o vi.pp.c   # splice //#use apath
python3 $ROOT/compiler/p8cc.py vi.pp.c -o vi.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py vi.asm -o vi.bin --base 0x6A00 >/dev/null
build_disk vi.bin
check "vi.c (p8cc)"

# asm twin
sh $ROOT/os/commands-asm/mkasm.sh vi > via.asm
python3 $ROOT/assembler/p8xasm.py via.asm -o via.bin --base 0x6A00 >/dev/null
build_disk via.bin
check "vi.asm (hand)"

echo "C-VI-RELPATH TEST: PASS"
