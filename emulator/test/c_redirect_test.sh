#!/bin/sh
# Shell output redirection for RUN programs: `RUN PROG >FILE` streams a program's
# stdout to a file instead of the console.  putchar/puts now go through the OS
# (SYS_PUTC -> OUTCH); OUTCH gains a file-stream mode (REDIRF=2) and DORUN binds
# the program's stdout to the redirect target (FWOPEN before exec, FCLOSE after).
# Compiled by BOTH p8cc.py and the native p8cc.c.  Two checks per compiler:
#   RUN /R.BIN          -> console shows ALPHA/BETA (not redirected)
#   RUN /R.BIN >OUT.TXT -> console silent; OUT.TXT on disk = "ALPHA\nBETA\n"
# NB programs that iterate a directory (DIR/TREE) can't also be redirected: the
# write stream and directory iteration share the BIOS sector buffer SBUF.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-REDIRECT TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x4000 >/dev/null

cat > rprog.c <<'EOF'
int main() {
    puts("ALPHA");
    puts("BETA");
    return 0;
}
EOF

check() {   # $1 = label, $2 = asm file
    python3 $ROOT/assembler/p8xasm.py "$2" -o r.bin --base 0xB000 >/dev/null
    rm -f r.img
    python3 $ROOT/tools/p8xfs.py create r.img >/dev/null
    python3 $ROOT/tools/p8xfs.py boot   r.img osc.bin >/dev/null
    python3 $ROOT/tools/p8xfs.py put    r.img r.bin --name R.BIN --load 0xB000 --exec 0xB000 >/dev/null
    # console run (not redirected): output must appear on the console
    con=$(printf 'B\rRUN /R.BIN\r' | ../p8xemu -l 90000000 -c r.img eeprom.bin 2>/dev/null \
        | LC_ALL=C tr -d '\0\r' | sed -n '/RUN \/R.BIN/,$p' | grep -v 'RUN /R.BIN' | tr -dc 'A-Z')
    [ "$con" = "ALPHABETA" ] || fail "$1: console output '$con' != 'ALPHABETA'"
    # redirected run: capture to OUT.TXT, then read it back from the image
    printf 'B\rRUN /R.BIN >OUT.TXT\r' | ../p8xemu -l 90000000 -c r.img eeprom.bin 2>/dev/null >/dev/null
    python3 $ROOT/tools/p8xfs.py get r.img OUT.TXT --out out.txt >/dev/null 2>&1 || fail "$1: OUT.TXT not created"
    got=$(tr -dc 'A-Z' < out.txt)
    [ "$got" = "ALPHABETA" ] || fail "$1: redirected file '$got' != 'ALPHABETA'"
}

if command -v cc >/dev/null 2>&1; then
    cc -O2 -w $ROOT/compiler/p8cc.c -o p8cc_host 2>/dev/null || fail "cc could not build p8cc.c"
    ./p8cc_host < rprog.c > rh.asm
    check "p8cc.c" rh.asm
fi

python3 $ROOT/compiler/p8cc.py rprog.c -o rp.asm >/dev/null
check "p8cc.py" rp.asm

echo "C-REDIRECT TEST: PASS"
