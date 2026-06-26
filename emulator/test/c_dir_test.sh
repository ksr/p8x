#!/bin/sh
# OS commands written in C (os/commands/dir.c, pwd.c), exercising:
#   - argstr()           the RUN command tail (P2)
#   - bios() carry flag  to terminate the FOPENDIR/FNEXT directory loop
#   - the OS syscall ABI SYS_CWDLBA ($4006) / SYS_GETCWD ($4003) for the current
#     working directory — via the published jump table, NOT by peeking OS RAM
# Compiled by BOTH p8cc.py and the native p8cc.c bootstrap.  One emulator session
# per compiler runs three scenarios on a disk with a /SUB subdirectory:
#   RUN DIR.BIN /     -> root listing (DIR.BIN, PWD.BIN, SUB)
#   CD /SUB; RUN DIR.BIN  (no arg) -> the CWD listing (X.DAT)
#   CD /SUB; RUN PWD.BIN  -> /SUB
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-DIR TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x4000 >/dev/null
printf 'inside-sub' > x.dat

build_disk() {   # $1 dir.bin  $2 pwd.bin -> dir.img with /SUB/X.DAT + both programs
    rm -f dir.img
    python3 $ROOT/tools/p8xfs.py create dir.img >/dev/null
    python3 $ROOT/tools/p8xfs.py boot   dir.img osc.bin >/dev/null
    python3 $ROOT/tools/p8xfs.py mkdir  dir.img /SUB >/dev/null
    python3 $ROOT/tools/p8xfs.py put    dir.img x.dat --name /SUB/X.DAT --load 0 --exec 0 >/dev/null
    python3 $ROOT/tools/p8xfs.py put    dir.img "$1" --name DIR.BIN --load 0xA700 --exec 0xA700 >/dev/null
    python3 $ROOT/tools/p8xfs.py put    dir.img "$2" --name PWD.BIN --load 0xA700 --exec 0xA700 >/dev/null
}

session() {   # echoes the combined console output of the three scenarios
    # programs are invoked by ABSOLUTE path so RUN finds them whatever the CWD
    printf 'B\rRUN /DIR.BIN /\rCD /SUB\rRUN /DIR.BIN\rRUN /PWD.BIN\r' \
        | ../p8xemu -l 200000000 -c dir.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r'
}

check() {   # $1 = label, $2 = combined output
    # DIR lines are now "<right-justified size>  NAME" (a '/' suffix marks a dir),
    # so a file NAME sits at end-of-line after the size column — match ' NAME$'.
    echo "$2" | grep -qE ' PWD\.BIN$' || fail "$1: root DIR did not list PWD.BIN"
    echo "$2" | grep -qE ' X\.DAT$'   || fail "$1: no-arg DIR did not list the CWD (/SUB) file X.DAT"
    # X.DAT holds 'inside-sub' (10 bytes) -> the size column must read 10.
    echo "$2" | grep -qE '^ *10  X\.DAT$' || fail "$1: X.DAT size column wrong (expected 10)"
    echo "$2" | grep -qx '/SUB'       || fail "$1: PWD did not print /SUB"
    # DIR buffers its listing, so it is redirectable: `RUN /DIR.BIN / >LIST.TXT`
    # must capture the same listing to a file (FNEXT and the write stream share
    # the BIOS sector buffer SBUF, hence collect-then-emit in dir.c).
    printf 'B\rRUN /DIR.BIN / >LIST.TXT\r' \
        | ../p8xemu -l 200000000 -c dir.img eeprom.bin 2>/dev/null >/dev/null
    python3 $ROOT/tools/p8xfs.py get dir.img LIST.TXT --out list.txt >/dev/null 2>&1 \
        || fail "$1: DIR redirect did not create LIST.TXT"
    grep -qE ' DIR\.BIN$' list.txt || fail "$1: redirected DIR listing missing DIR.BIN"
    grep -qE ' PWD\.BIN$' list.txt || fail "$1: redirected DIR listing missing PWD.BIN"
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
    python3 $ROOT/assembler/p8xasm.py d.asm -o d.bin --base 0xA700 >/dev/null
    python3 $ROOT/assembler/p8xasm.py p.asm -o p.bin --base 0xA700 >/dev/null
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
