#!/bin/sh
# p8cc (C cross-compiler) end to end: compile a C program to P8X asm, assemble
# it, RUN it under P8X/OS, and check its console output. Exercises while/if,
# arithmetic (+ - * / % <=), stack locals, parameters, RECURSION (factorial),
# pointers + arrays + & + * + indexing, and the putchar/puts builtins.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x4000 >/dev/null

cat > ctest.c <<'EOF'
int fact(int n) {            /* recursion + parameter */
    if (n < 2) return 1;
    return n * fact(n - 1);
}
int add(int a, int b) { return a + b; }   /* multiple parameters */
int setv(int *q, int v) { *q = v; return 0; }   /* store through a pointer */
int *idp(int *a) { return a; }                   /* returns int* (return-type tracking) */
int main() {
    char buf[8];
    char *p;
    int i;
    int x;
    int ia[3];
    i = 1;
    while (i <= 5) { putchar(i + 48); i = i + 1; }   /* stack local + loop */
    putchar(10);
    if (fact(5) == 120) puts("FACT-OK");             /* 5! via recursion */
    if (add(40, 9) == 49) puts("ADD-OK");
    p = buf; i = 0;                                  /* fill via char pointer */
    while (i < 5) { *p = 65 + i; p = p + 1; i = i + 1; }
    *p = 0;
    puts(buf);                                       /* "ABCDE" */
    setv(&x, 7);                                     /* &local + ptr param */
    if (x == 7) puts("PTR-OK");
    if (17 / 5 == 3) { if (17 % 5 == 2) puts("DIV-OK"); }
    x = 0;
    for (i = 0; i < 5; i = i + 1) x = x + i;             /* for loop: 0..4 = 10 */
    if (x == 10) puts("FOR-OK");
    if ((1 && 1) && !(0 && 1)) { if (0 || 1) puts("LOG-OK"); }   /* short-circuit */
    if ((6 & 3) == 2) { if ((5 | 2) == 7) { if ((5 ^ 1) == 4) puts("BIT-OK"); } }
    if ((1 << 4) == 16) { if ((64 >> 3) == 8) { if ((255 & ~240) == 15) puts("SHIFT-OK"); } }
    ia[0] = 1; ia[1] = 2; ia[2] = 3;
    if (*(idp(ia) + 2) == 3) puts("RET-OK");            /* call result int*: +2 scales by 2 */
    return 0;
}
EOF
python3 $ROOT/compiler/p8cc.py ctest.c -o ctest.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py ctest.asm -o ctest.bin --base 0xA700 >/dev/null

rm -f c.img
python3 $ROOT/tools/p8xfs.py create c.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   c.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    c.img ctest.bin --name CT.BIN --load 0xA700 --exec 0xA700 >/dev/null

out=$(printf 'B\rRUN CT.BIN\r' | ../p8xemu -l 120000000 -c c.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')
fail() { echo "C-COMPILE TEST: FAIL — $1"; echo "$out" | sed -n '/RUN CT/,$p'; exit 1; }

echo "$out" | grep -qx '12345'   || fail "loop/arith output not '12345'"
echo "$out" | grep -qx 'FACT-OK' || fail "recursion/parameter path failed"
echo "$out" | grep -qx 'ADD-OK'  || fail "multi-parameter call failed"
echo "$out" | grep -qx 'ABCDE'   || fail "char pointer/array fill failed"
echo "$out" | grep -qx 'PTR-OK'  || fail "&local + pointer-param store failed"
echo "$out" | grep -qx 'DIV-OK'  || fail "/ or % failed"
echo "$out" | grep -qx 'FOR-OK'  || fail "for loop failed"
echo "$out" | grep -qx 'LOG-OK'  || fail "short-circuit && / || failed"
echo "$out" | grep -qx 'BIT-OK'  || fail "bitwise & | ^ failed"
echo "$out" | grep -qx 'SHIFT-OK' || fail "shifts << >> or ~ failed"
echo "$out" | grep -qx 'RET-OK'  || fail "function return-type tracking (int* scaling) failed"
echo "C-COMPILE TEST: PASS"
