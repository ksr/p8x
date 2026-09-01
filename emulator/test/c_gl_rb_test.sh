#!/bin/sh
# Stage-10e read-back (STAGE10-DESIGN.md): FLAGRD/MATXRD stream state to
# the RB FIFO (GLRB $FF52, GLSTAT bit0), CLRD streams a stored list back
# (length halfword then bytes -- the clsave path). CLMOD, the one-byte
# in-place patch, was REMOVED 2026-09-01 (its 342 LUT4 funded BLIT):
# opcode 78 is err1/skip, asserted here; the ASCII keyword is gone from
# the ROM. Errors: 2 for a bad flag, 6 for an undefined list.
set -e
set -o pipefail
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-GL-RB TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null

cat > gl_rb.c <<'EOF'
char pb[8];
int pnum(int u) {
    int i;
    if (u & 32768) { putchar(45); u = 0 - u; }   /* signed print */
    i = 0;
    if (u == 0) { putchar(48); }
    while (u) { pb[i] = 48 + (u % 10); u = u / 10; i = i + 1; }
    while (i) { i = i - 1; putchar(pb[i]); }
    putchar(10);
    return 0;
}
int glb(int v) { while (peek(65361) & 128) { } poke(65360, v); return 0; }
int glw(int v) { glb(v & 255); glb((v / 256) & 255); return 0; }
int gls(char *s) { while (*s) { glb(*s); s = s + 1; } return 0; }
int rbb() { while ((peek(65361) & 1) == 0) { } return peek(65362); }
int rbw() { int l; l = rbb(); return l + 256 * rbb(); }
int main() {
    /* known state */
    glb(224); glb(1);                          /* PRMFIL 1 */
    glb(6); glb(31); glb(63); glb(0);          /* COLOR 31 63 0 */
    glb(179); glw(0-120); glw(120); glw(0-100); glw(100);  /* WINDOW */
    glb(177); glw(400);                        /* DISTAN 400 */
    glb(97); glb(1); pnum(rbw());              /* FLAGRD 1: PRMFIL -> 1 */
    glb(97); glb(2); pnum(rbw());              /* FLAGRD 2: COLOR -> -32 */
    glb(97); glb(3); pnum(rbw());              /* FLAGRD 3: native -> -1 */
    glb(97); glb(4); pnum(rbw());              /* FLAGRD 4: DISTAN -> 400 */
    glb(97); glb(5);                           /* FLAGRD 5: WINDOW 4 words */
    pnum(rbw()); pnum(rbw()); pnum(rbw()); pnum(rbw());
    glb(97); glb(9);                           /* FLAGRD 9: near, far */
    pnum(rbw()); pnum(rbw());
    glb(97); glb(7);                           /* dropped flag -> err2 */
    pnum(peek(65363));
    /* matrices */
    glb(144);                                  /* MDIDEN */
    glb(150); glw(10); glw(20); glw(30);       /* MDTRAN 10 20 30 */
    glb(98); glb(1);                           /* MATXRD 1: 12 words */
    { int i; i = 0; while (i < 12) { pnum(rbw()); i = i + 1; } }
    glb(160);                                  /* VWIDEN */
    glb(98); glb(2);                           /* MATXRD 2: 9 words */
    { int i; i = 0; while (i < 9) { pnum(rbw()); i = i + 1; } }
    /* CLRD round-trip */
    glb(112); glb(3);                          /* CLBEG 3 */
    glb(18); glw(1); glw(2); glw(3);           /* MOVE3 1 2 3 */
    glb(113);                                  /* CLEND */
    glb(118); glb(3);                          /* CLRD 3: len halfword + bytes */
    { int L; int i; L = rbw(); pnum(L);
      i = 0; while (i < L) { pnum(rbb()); i = i + 1; } }
    /* retired CLMOD: err1, ONE byte skipped, its old params execute
       as garbage-free NOOP-ish bytes? NO -- send just the opcode and
       let the errored skip prove the stream survives */
    glb(120);                                  /* CLMOD opcode -> err1 */
    glb(118); glb(3);                          /* CLRD 3 again: unchanged */
    { int L; int i; L = rbw();
      i = 0; while (i < L) { pnum(rbb()); i = i + 1; } }
    pnum(peek(65361) & 1);                     /* RB drained -> 0 */
    /* errors: the retired opcode, bad flag, undefined list */
    glb(97); glb(0);                           /* FLAGRD 0 -> err2 */
    glb(118); glb(9);                          /* CLRD 9 -> err6 */
    pnum(peek(65363)); pnum(peek(65363));
    pnum(peek(65363)); pnum(peek(65363));      /* 1 2 6 0 */
    puts("RBDONE");
    return 0;
}
EOF
python3 $ROOT/compiler/p8cc.py gl_rb.c -o gl_rb.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py gl_rb.asm -o gl_rb.bin --base 0x6A00 >/dev/null

rm -f gl_rb.img
python3 $ROOT/tools/p8xfs.py create gl_rb.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   gl_rb.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  gl_rb.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    gl_rb.img gl_rb.bin --name /bin/glrb.bin --load 0x6A00 --exec 0x6A00 >/dev/null
printf 'B\rrun /bin/glrb.bin\r' > gl_rb.in
../p8xemu -N -i gl_rb.in -c gl_rb.img -l 400000000 eeprom.bin > gl_rb.out 2>/dev/null || true
grep -q "RBDONE" gl_rb.out || fail "harness did not finish"

want="1 -32 -1 400 -120 120 -100 100 16 32767 2 \
256 0 0 0 256 0 0 0 256 10 20 30 \
256 0 0 0 256 0 0 0 256 \
7 18 1 0 2 0 3 0 \
18 1 0 2 0 3 0 \
0 1 2 6 0"
got=$(LC_ALL=C tr -d '\0\r' < gl_rb.out | grep -E '^-?[0-9]+$' | tr '\n' ' ' | sed 's/ $//')
want=$(echo $want)
[ "$got" = "$want" ] || { echo "want: $want"; echo "got:  $got"; fail "read-back values differ"; }
echo "C-GL-RB TEST: PASS (FLAGRD state, MATXRD both matrices, CLRD round-trip, retired-CLMOD err1, RB drain, errors 2/6)"
