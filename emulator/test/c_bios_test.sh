#!/bin/sh
# p8cc BIOS access: getchar (CONIN), peek/poke (memory-mapped I/O), and the
# general bios(addr, p1, a) intrinsic that calls any monitor routine (here PUTS
# $0112 and CONOUT $0103).  Differential: the program is compiled by BOTH the
# native p8cc.c bootstrap and p8cc.py and must run to identical output, with a
# char fed to getchar.  Expected: X (poke/peek) OK (PUTS) Z (CONOUT) QQ — the fed
# 'Q' appears twice: console getchar echoes the key, then the program putchar's it.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-BIOS TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x4000 >/dev/null

cat > cbios.c <<'EOF'
char cell;
int main() {
    char *m;
    poke(&cell, 88);            /* write 'X' to cell        */
    putchar(peek(&cell));       /* read it back -> X        */
    m = "OK";
    bios(0x0112, m, 0);         /* PUTS "OK" (no newline)   */
    bios(0x0103, 0, 90);        /* CONOUT 'Z'               */
    putchar(getchar());         /* echo the fed char -> Q   */
    putchar(10);
    return 0;
}
EOF

run() {   # $1 = asm file -> emulator output (letters only), feeding 'Q' to getchar
    python3 $ROOT/assembler/p8xasm.py "$1" -o cbios.bin --base 0xA700 >/dev/null
    rm -f cbios.img
    python3 $ROOT/tools/p8xfs.py create cbios.img >/dev/null
    python3 $ROOT/tools/p8xfs.py boot   cbios.img osc.bin >/dev/null
    python3 $ROOT/tools/p8xfs.py put    cbios.img cbios.bin --name CB.BIN --load 0xA700 --exec 0xA700 >/dev/null
    printf 'B\rRUN CB.BIN\rQ' | ../p8xemu -l 90000000 -c cbios.img eeprom.bin 2>/dev/null \
        | LC_ALL=C tr -d '\0\r' | sed -n '/RUN CB.BIN/,$p' | grep -v 'RUN CB.BIN' | tr -dc 'A-Z'
}

# native bootstrap (skip the host-build leg if no cc)
if command -v cc >/dev/null 2>&1; then
    cc -O2 -w $ROOT/compiler/p8cc.c -o p8cc_host 2>/dev/null || fail "cc could not build p8cc.c"
    ./p8cc_host < cbios.c > ch.asm
    host_out=$(run ch.asm)
    [ "$host_out" = "XOKZQQ" ] || fail "p8cc.c output '$host_out' != 'XOKZQQ'"
fi

python3 $ROOT/compiler/p8cc.py cbios.c -o cp.asm >/dev/null
py_out=$(run cp.asm)
[ "$py_out" = "XOKZQQ" ] || fail "p8cc.py output '$py_out' != 'XOKZQQ'"

echo "C-BIOS TEST: PASS"
