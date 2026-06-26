#!/bin/sh
# File-op commands cp and mv (os/commands/cp.c, mv.c): copy a file with the BIOS
# read stream (FOPEN/FGETB) feeding the write stream (FWOPEN/FPUTB/FCLOSE); mv =
# copy + delete source. Both build absolute paths (CWD via SYS_GETCWD) so they
# work in the CWD and across subdirectories. Compiled by BOTH p8cc.py and the
# native p8cc.c. Uses a 720-byte (multi-sector) source to exercise buffering and
# the SBUF ordering (FRESOLVE dest before FWOPEN).
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-FILEOPS TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x4000 >/dev/null
python3 -c "import sys; sys.stdout.write(''.join('line%03d\r\n'%i for i in range(80)))" > fo_src.dat

build_disk() {   # $1 = py|host
    for c in cp mv; do
        python3 $ROOT/tools/clib.py $ROOT/os/commands/$c.c -o $c.pp.c   # splice //#use libs
        if [ "$1" = host ]; then ./p8cc_host < $c.pp.c > $c.asm
        else python3 $ROOT/compiler/p8cc.py $c.pp.c -o $c.asm >/dev/null; fi
        python3 $ROOT/assembler/p8xasm.py $c.asm -o $c.bin --base 0x7A00 >/dev/null
    done
    rm -f fo.img
    python3 $ROOT/tools/p8xfs.py create fo.img >/dev/null
    python3 $ROOT/tools/p8xfs.py boot   fo.img osc.bin >/dev/null
    python3 $ROOT/tools/p8xfs.py mkdir  fo.img /BIN >/dev/null
    python3 $ROOT/tools/p8xfs.py mkdir  fo.img /SUB >/dev/null
    python3 $ROOT/tools/p8xfs.py put    fo.img cp.bin --name /BIN/CP.BIN --load 0x7A00 --exec 0x7A00 >/dev/null
    python3 $ROOT/tools/p8xfs.py put    fo.img mv.bin --name /BIN/MV.BIN --load 0x7A00 --exec 0x7A00 >/dev/null
    python3 $ROOT/tools/p8xfs.py put    fo.img fo_src.dat --name SRC.TXT --load 0 --exec 0 >/dev/null
    python3 $ROOT/tools/p8xfs.py put    fo.img fo_src.dat --name MS.TXT  --load 0 --exec 0 >/dev/null
}

run() { printf "B\r$1\r" | ../p8xemu -l 400000000 -c fo.img eeprom.bin 2>/dev/null >/dev/null; }
got() { python3 $ROOT/tools/p8xfs.py get fo.img "$1" --out "$2" >/dev/null 2>&1; }

check() {   # $1 = label
    # cp into the CWD: DST identical to SRC, SRC still present
    run 'CP SRC.TXT DST.TXT'
    got DST.TXT fo_dst.out || fail "$1: cp did not create DST"
    cmp -s fo_dst.out fo_src.dat || fail "$1: cp DST != SRC (byte mismatch)"
    got SRC.TXT fo_s.out || fail "$1: cp removed the source"
    # cp into a subdirectory (absolute dest path)
    run 'CP SRC.TXT /SUB/C.TXT'
    got /SUB/C.TXT fo_sub.out || fail "$1: cp to /SUB did not create the file"
    cmp -s fo_sub.out fo_src.dat || fail "$1: cp to /SUB byte mismatch"
    # mv: MD.TXT identical, MS.TXT gone
    run 'MV MS.TXT MD.TXT'
    got MD.TXT fo_md.out || fail "$1: mv did not create the dest"
    cmp -s fo_md.out fo_src.dat || fail "$1: mv dest != source"
    if got MS.TXT fo_ms.out; then fail "$1: mv left the source behind"; fi
    # mv X X is refused and leaves the file intact
    run 'MV MD.TXT MD.TXT'
    got MD.TXT fo_md2.out || fail "$1: same-path mv lost the file"
    cmp -s fo_md2.out fo_src.dat || fail "$1: same-path mv corrupted the file"
}

if command -v cc >/dev/null 2>&1; then
    cc -O2 -w $ROOT/compiler/p8cc.c -o p8cc_host 2>/dev/null || fail "cc could not build p8cc.c"
    build_disk host
    check "p8cc.c"
fi
build_disk py
check "p8cc.py"

echo "C-FILEOPS TEST: PASS"
