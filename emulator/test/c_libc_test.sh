#!/bin/sh
# p8cc I/O + library: a C program reads a line with getchar() (BIOS CONIN),
# upper-cases it into a char buffer, echoes it with puts(), and prints its
# length using a strlen() written in C (char* param + pointer iteration). Feeds
# "abc\r" and expects "ABC" then the length digit "3".
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x4000 >/dev/null

cat > clibc.c <<'EOF'
int strlen(char *s) {              /* library function written in C */
    int n;
    n = 0;
    while (*s != 0) { n = n + 1; s = s + 1; }
    return n;
}
int main() {
    char line[16];
    char *p;
    int c;
    p = line;
    c = getchar();                 /* read a line until carriage return */
    while (c != 13) {
        if (c >= 97) { if (c <= 122) c = c - 32; }   /* to upper-case */
        *p = c;
        p = p + 1;
        c = getchar();
    }
    *p = 0;
    puts(line);                    /* "ABC" */
    putchar(48 + strlen(line));    /* length 3 -> '3' */
    putchar(10);
    return 0;
}
EOF
python3 $ROOT/compiler/p8cc.py clibc.c -o clibc.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py clibc.asm -o clibc.bin --base 0x7A00 >/dev/null

rm -f cl.img
python3 $ROOT/tools/p8xfs.py create cl.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   cl.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    cl.img clibc.bin --name CL.BIN --load 0x7A00 --exec 0x7A00 >/dev/null

# Boot, RUN, then feed "abc\r" to the program's getchar() loop.
out=$(printf 'B\rRUN CL.BIN\rabc\r' | ../p8xemu -l 150000000 -c cl.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')
fail() { echo "C-LIBC TEST: FAIL — $1"; echo "$out" | sed -n '/RUN CL/,$p'; exit 1; }

# console getchar now echoes each key, so the echoed "abc" precedes the puts
# output on the line (CRs are stripped); match 'ABC' as a substring, not a line.
echo "$out" | grep -q 'ABC' || fail "getchar/upcase/puts did not produce 'ABC'"
echo "$out" | grep -qx '3'  || fail "strlen('ABC') != 3"
echo "C-LIBC TEST: PASS"
