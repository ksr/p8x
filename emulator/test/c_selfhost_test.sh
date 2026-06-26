#!/bin/sh
# Milestone A (self-hosting p8cc): compiler/p8cc.c is BOTH standard C and
# p8cc-subset C.  Three checks:
#   1. a host C compiler (cc) builds p8cc.c -> a native bootstrap compiler;
#   2. SELF-ACCEPT: p8cc.py compiles p8cc.c to asm without error (the subset
#      accepts its own source).  NB we do NOT assemble that asm: the full
#      compiler is larger than the $B000 TPA, which is Milestone B's concern.
#   3. DIFFERENTIAL: a sample program compiled by BOTH the host bootstrap and
#      p8cc.py produces byte-identical console output when run on the P8X.
# p8cc.c is built incrementally; the sample covers the operator set, globals,
# control flow, params/locals, recursion, multi-arg calls, pointers (int*/char*
# with & and *, char vs int width, pointer arithmetic), arrays + indexing,
# string literals with puts, and structs (. and -> member access).
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-SELFHOST TEST: FAIL — $1"; exit 1; }

if ! command -v cc >/dev/null 2>&1; then
    echo "C-SELFHOST TEST: SKIP (no host cc)"; exit 0
fi

# 1. host bootstrap build
cc -w $ROOT/compiler/p8cc.c -o p8cc_host 2>/dev/null || fail "cc could not build p8cc.c"

# 2. self-accept: p8cc.py compiles its own source to asm
python3 $ROOT/compiler/p8cc.py $ROOT/compiler/p8cc.c -o selfacc.asm >/dev/null \
    || fail "p8cc.py could not compile p8cc.c (subset does not accept itself)"

# 3. differential behaviour on a sample program
cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x4000 >/dev/null

cat > diff.c <<'EOF'
int s;
int i;
int gv;
int *gp;
char gc;
char *gpc;
int ia[3];
char ca[4];
struct Pt { int x; int y; };                           /* struct definition     */
int fact(int n) {                                      /* params + recursion    */
    if (n < 2) return 1;
    return n * fact(n - 1);
}
int compute() {                                        /* no-arg call + globals */
    s = 0;
    for (i = 0; i < 5; i = i + 1) s = s + i;           /* 0+1+2+3+4 = 10        */
    return s;
}
int main() {
    int x;                                             /* a local               */
    putchar(48 + 3*4 - 11);                            /* 1: * - precedence    */
    putchar(48 + (17%5));                              /* 2: %                 */
    putchar(48 + (1<<3) - 5);                          /* 3: <<                */
    putchar(48 + (20/5));                              /* 4: /                 */
    putchar(48 + (6&3) + 3);                           /* 5: &                 */
    putchar(48 + (3==3) + (5>2) + (1!=1) + 4);         /* 6: == > !=           */
    putchar(48 + ((1&&0)||1) + ((2<1)||(3>=3)) + 5);   /* 7: && || < >=        */
    putchar(48 + (~0 & 8));                            /* 8: ~ &               */
    if (compute() == 10) putchar(89); else putchar(78);/* Y: for/if/call       */
    x = fact(5);                                       /* 120: recursion        */
    putchar(48 + x/100); putchar(48 + (x/10)%10); putchar(48 + x%10);
    gv = 64; gp = &gv; *gp = *gp + 1;                  /* int* &/*: gv = 65 'A'  */
    putchar(*gp);                                      /* A                     */
    gc = 90; gpc = &gc;                                /* char* : 'Z'           */
    putchar(*gpc);                                     /* Z                     */
    ia[0] = 4; ia[1] = 9;                              /* int array index       */
    putchar(48 + ia[1] - ia[0]);                       /* 9-4 = 5               */
    ca[0] = 81; ca[1] = 0; puts(ca);                   /* char[] + puts: Q      */
    puts("RS");                                        /* string literal: RS    */
    putchar("T"[0]);                                   /* indexed literal: T    */
    struct Pt pt;
    struct Pt *pq;
    pt.x = 70; pt.y = 1;                               /* struct . member       */
    pq = &pt;
    putchar(pq->x + pq->y);                            /* -> : 70+1 = 71 'G'    */
    putchar(10);
    return 0;
}
EOF

# host bootstrap reads from stdin
host_out=$(./p8cc_host < diff.c > d.asm; \
    python3 $ROOT/assembler/p8xasm.py d.asm -o d.bin --base 0x7A00 >/dev/null; \
    rm -f d.img; python3 $ROOT/tools/p8xfs.py create d.img >/dev/null; \
    python3 $ROOT/tools/p8xfs.py boot d.img osc.bin >/dev/null; \
    python3 $ROOT/tools/p8xfs.py put d.img d.bin --name D.BIN --load 0x7A00 --exec 0x7A00 >/dev/null; \
    printf 'B\rRUN D.BIN\r' | ../p8xemu -l 80000000 -c d.img eeprom.bin 2>/dev/null \
        | LC_ALL=C tr -d '\0\r' | sed -n '/RUN D.BIN/,$p' | grep -v 'RUN D.BIN' | tr -dc '0-9A-Z')

py_out=$(python3 $ROOT/compiler/p8cc.py diff.c -o d.asm >/dev/null; \
    python3 $ROOT/assembler/p8xasm.py d.asm -o d.bin --base 0x7A00 >/dev/null; \
    rm -f d.img; python3 $ROOT/tools/p8xfs.py create d.img >/dev/null; \
    python3 $ROOT/tools/p8xfs.py boot d.img osc.bin >/dev/null; \
    python3 $ROOT/tools/p8xfs.py put d.img d.bin --name D.BIN --load 0x7A00 --exec 0x7A00 >/dev/null; \
    printf 'B\rRUN D.BIN\r' | ../p8xemu -l 80000000 -c d.img eeprom.bin 2>/dev/null \
        | LC_ALL=C tr -d '\0\r' | sed -n '/RUN D.BIN/,$p' | grep -v 'RUN D.BIN' | tr -dc '0-9A-Z')

[ "$host_out" = "12345678Y120AZ5QRSTG" ] || fail "host bootstrap output '$host_out' != '12345678Y120AZ5QRSTG'"
[ "$py_out" = "12345678Y120AZ5QRSTG" ]   || fail "p8cc.py output '$py_out' != '12345678Y120AZ5QRSTG'"
[ "$host_out" = "$py_out" ]  || fail "host '$host_out' != p8cc.py '$py_out' (differential)"

echo "C-SELFHOST TEST: PASS"
