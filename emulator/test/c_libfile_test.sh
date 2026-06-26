#!/bin/sh
# p8lib.c (the C-source libc) over the BIOS: prepend it to a program that uses
# strcpy/strlen/putdec and round-trips a file through savefile()/loadfile()
# (FWOPEN/FPUTB/FCLOSE -> FNORM/FFIND/FLOADAT).  Compiled by BOTH p8cc.py and the
# native p8cc.c bootstrap; both must save "DATA42", read it back, and print
# "DATA42" then its length "6"  ->  DATA426.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-LIBFILE TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x4000 >/dev/null

cat > prog.c <<'EOF'
char buf[512];                      /* >= 1 sector: FLOADAT reads whole sectors */
int main() {
    int n;
    strcpy(buf, "DATA42");
    savefile("T.DAT", buf, strlen(buf));    /* write 6 bytes */
    buf[0] = 0;                              /* clear, then read back */
    n = loadfile("T.DAT", buf);
    buf[n] = 0;                              /* terminate at the real length */
    puts(buf);                               /* DATA42 */
    putdec(n);                               /* 6 */
    putchar(10);
    return 0;
}
EOF
cat $ROOT/compiler/p8lib.c prog.c > lf.c        # prepend the library (no #include/linker)

run() {   # $1 = asm file -> emulator output (letters+digits)
    python3 $ROOT/assembler/p8xasm.py "$1" -o lf.bin --base 0x7A00 >/dev/null
    rm -f lf.img
    python3 $ROOT/tools/p8xfs.py create lf.img >/dev/null
    python3 $ROOT/tools/p8xfs.py boot   lf.img osc.bin >/dev/null
    python3 $ROOT/tools/p8xfs.py put    lf.img lf.bin --name LF.BIN --load 0x7A00 --exec 0x7A00 >/dev/null
    printf 'B\rRUN LF.BIN\r' | ../p8xemu -l 120000000 -c lf.img eeprom.bin 2>/dev/null \
        | LC_ALL=C tr -d '\0\r' | sed -n '/RUN LF.BIN/,$p' | grep -v 'RUN LF.BIN' | tr -dc 'A-Z0-9'
}

if command -v cc >/dev/null 2>&1; then
    cc -O2 -w $ROOT/compiler/p8cc.c -o p8cc_host 2>/dev/null || fail "cc could not build p8cc.c"
    ./p8cc_host < lf.c > lh.asm
    host_out=$(run lh.asm)
    [ "$host_out" = "DATA426" ] || fail "p8cc.c output '$host_out' != 'DATA426'"
fi

python3 $ROOT/compiler/p8cc.py lf.c -o lp.asm >/dev/null
py_out=$(run lp.asm)
[ "$py_out" = "DATA426" ] || fail "p8cc.py output '$py_out' != 'DATA426'"

echo "C-LIBFILE TEST: PASS"
