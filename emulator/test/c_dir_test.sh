#!/bin/sh
# OS commands written in C (os/commands/dir.c, pwd.c), exercising:
#   - argstr()           the RUN command tail (P2)
#   - bios() carry flag  to terminate the FOPENDIR/FNEXT directory loop
#   - the OS syscall ABI SYS_CWDLBA ($2006) / SYS_GETCWD ($2003) for the current
#     working directory — via the published jump table, NOT by peeking OS RAM
# Compiled by BOTH p8cc.py and the native p8cc.c bootstrap.  One emulator session
# per compiler runs three scenarios on a disk with a /SUB subdirectory:
#   RUN DIR.bin /     -> root listing (DIR.bin, PWD.bin, SUB)
#   CD /SUB; RUN DIR.bin  (no arg) -> the CWD listing (X.DAT)
#   CD /SUB; RUN PWD.bin  -> /SUB
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-DIR TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null
printf 'inside-sub' > x.dat
printf 'deep-rel'   > zrel.dat

build_disk() {   # $1 dir.bin  $2 pwd.bin -> dir.img with /SUB/X.DAT + both programs
    rm -f dir.img
    python3 $ROOT/tools/p8xfs.py create dir.img >/dev/null
    python3 $ROOT/tools/p8xfs.py boot   dir.img osc.bin >/dev/null
    python3 $ROOT/tools/p8xfs.py mkdir  dir.img /SUB >/dev/null
    python3 $ROOT/tools/p8xfs.py put    dir.img x.dat --name /SUB/X.DAT --load 0 --exec 0 >/dev/null
    # a nested dir so we can test a RELATIVE path arg from within /SUB
    python3 $ROOT/tools/p8xfs.py mkdir  dir.img /SUB/DEEP >/dev/null
    python3 $ROOT/tools/p8xfs.py put    dir.img zrel.dat --name /SUB/DEEP/ZREL.DAT --load 0 --exec 0 >/dev/null
    python3 $ROOT/tools/p8xfs.py put    dir.img "$1" --name DIR.bin --load 0x6A00 --exec 0x6A00 >/dev/null
    python3 $ROOT/tools/p8xfs.py put    dir.img "$2" --name PWD.bin --load 0x6A00 --exec 0x6A00 >/dev/null
}

session() {   # echoes the combined console output of the three scenarios
    # programs are invoked by ABSOLUTE path so RUN finds them whatever the CWD.
    # `run /DIR.bin DEEP` from within /SUB exercises a RELATIVE path arg: dir must
    # resolve it against the CWD (/SUB/DEEP), not the root (a bare FOPENDIR starts
    # at root, so dir prepends the CWD via abspath — the regression this guards).
    printf 'B\rrun /DIR.bin /\rcd /SUB\rrun /DIR.bin\rrun /DIR.bin DEEP\rrun /PWD.bin\r' \
        | ../p8xemu -l 200000000 -c dir.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r'
}

check() {   # $1 = label, $2 = combined output
    # DIR lines are now "<right-justified size>  NAME" (a '/' suffix marks a dir),
    # so a file NAME sits at end-of-line after the size column — match ' NAME$'.
    echo "$2" | grep -qE ' PWD\.bin$' || fail "$1: root DIR did not list PWD.bin"
    echo "$2" | grep -qE ' X\.DAT$'   || fail "$1: no-arg DIR did not list the CWD (/SUB) file X.DAT"
    # X.DAT holds 'inside-sub' (10 bytes) -> the size column must read 10.
    echo "$2" | grep -qE '^ *10  X\.DAT$' || fail "$1: X.DAT size column wrong (expected 10)"
    echo "$2" | grep -qx '/SUB'       || fail "$1: PWD did not print /SUB"
    # the regression: a RELATIVE path arg ('DIR DEEP' from /SUB) must resolve
    # against the CWD -> list /SUB/DEEP's ZREL.DAT, not fail as /DEEP not-found.
    echo "$2" | grep -qE ' ZREL\.DAT$' || fail "$1: relative 'DIR DEEP' from /SUB did not resolve against the CWD (no ZREL.DAT)"
    # DIR buffers its listing, so it is redirectable: `RUN /DIR.bin / >LIST.TXT`
    # must capture the same listing to a file (FNEXT and the write stream share
    # the BIOS sector buffer SBUF, hence collect-then-emit in dir.c).
    printf 'B\rrun /DIR.bin / >LIST.TXT\r' \
        | ../p8xemu -l 200000000 -c dir.img eeprom.bin 2>/dev/null >/dev/null
    python3 $ROOT/tools/p8xfs.py get dir.img LIST.TXT --out list.txt >/dev/null 2>&1 \
        || fail "$1: DIR redirect did not create LIST.TXT"
    grep -qE ' DIR\.bin$' list.txt || fail "$1: redirected DIR listing missing DIR.bin"
    grep -qE ' PWD\.bin$' list.txt || fail "$1: redirected DIR listing missing PWD.bin"
    # a missing directory is reported, not silently empty
    printf 'B\rrun /DIR.bin /NOPE\r' \
        | ../p8xemu -l 200000000 -c dir.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0' \
        | grep -qi 'not found' || fail "$1: DIR of a missing path did not report 'not found'"
}

compile_one() {   # $1 = compiler tag: build both programs with it
    python3 $ROOT/tools/clib.py $ROOT/os/commands/dir.c -o d.pp.c   # splice //#use glob
    if [ "$1" = "host" ]; then
        ./p8cc_host < d.pp.c > d.asm
        ./p8cc_host < $ROOT/os/commands/pwd.c > p.asm
    else
        python3 $ROOT/compiler/p8cc.py d.pp.c -o d.asm >/dev/null
        python3 $ROOT/compiler/p8cc.py $ROOT/os/commands/pwd.c -o p.asm >/dev/null
    fi
    python3 $ROOT/assembler/p8xasm.py d.asm -o d.bin --base 0x6A00 >/dev/null
    python3 $ROOT/assembler/p8xasm.py p.asm -o p.bin --base 0x6A00 >/dev/null
    build_disk d.bin p.bin
}

if command -v cc >/dev/null 2>&1; then
    cc -O2 -w $ROOT/compiler/p8cc.c -o p8cc_host 2>/dev/null || fail "cc could not build p8cc.c"
    compile_one host
    check "p8cc.c" "$(session)"
fi

compile_one py
check "p8cc.py" "$(session)"

echo "C-DIR TEST: PASS"
