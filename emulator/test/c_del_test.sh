#!/bin/sh
# del (os/commands/del.c): the DEL command moved out of the OS shell into /bin.
# A self-contained file op -- abspath the arg (CWD-relative, since FRESOLVE
# starts at root), then FDELETE. Proves a bare `del NAME` (implicit-RUN of
# /bin/del.bin) removes files, handles several at once, reports a missing one,
# and works CWD-relative -- exactly as the old built-in did, now off the OS.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-DEL TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null
python3 $ROOT/tools/clib.py $ROOT/os/commands/del.c -o del.pp.c
python3 $ROOT/compiler/p8cc.py del.pp.c -o del.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py del.asm -o del.bin --base 0x6A00 >/dev/null

rm -f dlt.img
python3 $ROOT/tools/p8xfs.py create dlt.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   dlt.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  dlt.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  dlt.img /sub >/dev/null
python3 $ROOT/tools/p8xfs.py put    dlt.img del.bin --name /bin/del.bin --load 0x6A00 --exec 0x6A00 >/dev/null
printf 'x\n' > f.txt
python3 $ROOT/tools/p8xfs.py put dlt.img f.txt --name /A.TXT >/dev/null
python3 $ROOT/tools/p8xfs.py put dlt.img f.txt --name /B.TXT >/dev/null
python3 $ROOT/tools/p8xfs.py put dlt.img f.txt --name /sub/REL.TXT >/dev/null

# bare `del` (implicit RUN via PATH): two files at once, a missing one, and a
# CWD-relative name (cd into /sub first).
printf 'B\rdel /A.TXT /B.TXT\rdel /NOPE.TXT\rcd /sub\rdel REL.TXT\r' > dlt.in
../p8xemu -N -i dlt.in -c dlt.img -l 400000000 eeprom.bin > dlt.out 2>/dev/null || true

python3 $ROOT/tools/p8xfs.py ls dlt.img /    2>/dev/null | grep -qi "A.TXT"   && fail "A.TXT not deleted"
python3 $ROOT/tools/p8xfs.py ls dlt.img /    2>/dev/null | grep -qi "B.TXT"   && fail "B.TXT not deleted (multi-arg)"
python3 $ROOT/tools/p8xfs.py ls dlt.img /sub 2>/dev/null | grep -qi "REL.TXT" && fail "REL.TXT not deleted (CWD-relative)"
grep -qi "No such file" dlt.out || fail "missing file did not report ?No such file"

echo "C-DEL TEST: PASS (del is a /bin command: multi-arg, CWD-relative, and reports a missing file)"
