#!/bin/sh
# Shell INPUT redirection (`RUN PROG <FILE`): the OS binds stdin to a file (read
# stream into IBUF), and SYS_GETC pulls from it; getchar() returns -1 at EOF.
# os/commands/cat.c is a stdin->stdout filter.  Compiled by BOTH p8cc.py
# and the native p8cc.c.  Two checks per compiler on a disk holding IN.TXT
# ("STDINOK"):
#   RUN /CAT.BIN <IN.TXT            -> console prints STDINOK
#   RUN /CAT.BIN <IN.TXT >OUT.TXT   -> OUT.TXT on disk = STDINOK  (< and > together)
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-STDIN TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x4000 >/dev/null
printf 'STDINOK' > in.txt

check() {   # $1 = label, $2 = cat.asm
    python3 $ROOT/assembler/p8xasm.py "$2" -o cat.bin --base 0x7A00 >/dev/null
    rm -f s.img
    python3 $ROOT/tools/p8xfs.py create s.img >/dev/null
    python3 $ROOT/tools/p8xfs.py boot   s.img osc.bin >/dev/null
    python3 $ROOT/tools/p8xfs.py put    s.img in.txt --name IN.TXT --load 0 --exec 0 >/dev/null
    python3 $ROOT/tools/p8xfs.py put    s.img cat.bin --name CAT.BIN --load 0x7A00 --exec 0x7A00 >/dev/null
    # console: cat the file to the screen
    con=$(printf 'B\rRUN /CAT.BIN <IN.TXT\r' | ../p8xemu -l 90000000 -c s.img eeprom.bin 2>/dev/null \
        | LC_ALL=C tr -d '\0\r' | sed -n '/RUN \/CAT.BIN/,$p' | grep -v 'RUN /CAT.BIN' | tr -dc 'A-Z')
    [ "$con" = "STDINOK" ] || fail "$1: console '$con' != 'STDINOK' (stdin redirect)"
    # < and > together: copy IN.TXT -> OUT.TXT
    printf 'B\rRUN /CAT.BIN <IN.TXT >OUT.TXT\r' | ../p8xemu -l 90000000 -c s.img eeprom.bin 2>/dev/null >/dev/null
    python3 $ROOT/tools/p8xfs.py get s.img OUT.TXT --out out.txt >/dev/null 2>&1 || fail "$1: OUT.TXT not created"
    got=$(tr -dc 'A-Z' < out.txt)
    [ "$got" = "STDINOK" ] || fail "$1: copied file '$got' != 'STDINOK' (< and >)"
}

python3 $ROOT/tools/clib.py $ROOT/os/commands/cat.c -o cat.pp.c   # splice //#use glob,globx

if command -v cc >/dev/null 2>&1; then
    cc -O2 -w $ROOT/compiler/p8cc.c -o p8cc_host 2>/dev/null || fail "cc could not build p8cc.c"
    ./p8cc_host < cat.pp.c > sh.asm
    check "p8cc.c" sh.asm
fi

python3 $ROOT/compiler/p8cc.py cat.pp.c -o sp.asm >/dev/null
check "p8cc.py" sp.asm

echo "C-STDIN TEST: PASS"
