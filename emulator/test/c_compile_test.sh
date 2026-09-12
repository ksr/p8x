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
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null

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
    wordops(ia);
    return 0;
}
int gw;                                   /* a global word: compared/updated in place */
int never_called(int q) { return q * 3; } /* dead-function elimination drops this */
int wordops(int *ia) {                    /* the inline word ops + CMPW conditions */
    int x; int y; int *ip; int ok;
    ok = 1;
    x = 300; y = 44;                      /* low bytes equal: a byte-wide == would lie */
    if (x == y) ok = 0;
    if (x == 44) ok = 0;
    if (x != 300) ok = 0;
    if ((x & 255) != 44) ok = 0;          /* ANDW a,# keeps the low byte, clears the high */
    if (x & 256) ok = ok + 1;             /* bit 8 of 300 is set: Z from ANDW a,# is 16-bit */
    if (x > 299) ok = ok + 1;             /* CMPW __ax,#300 (k+1 rule), C */
    if (x >= 301) ok = 0;
    if (x <= 300) ok = ok + 1;
    if (x < 300) ok = 0;
    if (299 < x) ok = ok + 1;             /* constant on the LEFT: k < x == x >= k+1 */
    if (300 < x) ok = 0;
    if (65535 >= x) ok = ok + 1;          /* always true (folded) */
    x = 65535;                            /* unsigned: 65535 > 0 */
    if (x > 0) ok = ok + 1;
    if (x < 1) ok = 0;
    x = 20 - 5;                           /* leaf - leaf */
    if (x != 15) ok = 0;
    y = 7;
    x = 100 - y;                          /* constant - variable: MOVW park path */
    if (x != 93) ok = 0;
    x = y - 10;                           /* wraps: 65533 */
    if (x != 65533) ok = 0;
    x = -y;                               /* negate: XORW #65535 + INCW */
    if (x + y != 0) ok = 0;
    x = ~y;
    if ((x & 15) != 8) ok = 0;            /* ~7 = ...11111000 */
    x = (y < 10);                         /* relop as a VALUE */
    if (x != 1) ok = 0;
    x = (y > 10) + (y == 7) + !y + !0;    /* 0 + 1 + 0 + 1 */
    if (x != 2) ok = 0;
    x = (y && 0) + (y || 0);              /* && / || as values: 0 + 1 */
    if (x != 1) ok = 0;
    ip = ia + 2;                          /* int pointer arithmetic, both directions */
    ip = ip - 1;                          /* &ia[1] */
    if (*ip != 2) ok = 0;
    if (ip - ia != 2) ok = 0;             /* pointer difference is in bytes */
    x = 1;
    if (*(ip - x) != 1) ok = 0;           /* p - i with a scaled variable */
    if (*(ia + x) != 2) ok = 0;
    gw = 1000;
    gw = gw + 300;                        /* in place: ADDW _g_gw,#300 (imm16) */
    if (gw != 1300) ok = 0;
    if (gw < 1300) ok = 0;                /* CMPW _g_gw,#1300 in place */
    if (1299 < gw) ok = ok + 1;           /* CMPW _g_gw,#1300, flipped */
    if (gw == 1300) ok = ok + 1;
    if (gw) ok = ok + 1;                  /* CMPW _g_gw,#0 */
    x = y & 1;                            /* 7 & 1 */
    if ((y & 8) == 0) ok = ok + 1;        /* Z straight from ANDW a,# */
    if (y & 8) ok = 0;
    if (y & 4) ok = ok + 1;
    if (x != 1) ok = 0;
    x = y | 256;
    if (x != 263) ok = 0;
    x = y ^ 65535;
    if (x != 65528) ok = 0;
    if (ok == 12) puts("WORD-OK");
    return ok;
}
EOF
grep -q '_f_never_called:' ctest.asm && { echo "C-COMPILE TEST: FAIL — dead function was compiled"; exit 1; }
python3 $ROOT/compiler/p8cc.py ctest.c -o ctest.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py ctest.asm -o ctest.bin --base 0x6A00 >/dev/null

rm -f c.img
python3 $ROOT/tools/p8xfs.py create c.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   c.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    c.img ctest.bin --name CT.bin --load 0x6A00 --exec 0x6A00 >/dev/null

out=$(printf 'B\rrun CT.bin\r' | ../p8xemu -l 120000000 -c c.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')
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
