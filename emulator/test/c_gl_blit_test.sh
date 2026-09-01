#!/bin/sh
# BLIT x y w h (opcode $64) -- the single-interface DMA verb (2026-09-01):
# a 9-byte header, then 2*w*h RAW RGB565 bytes through the same FIFO,
# rows TOP-DOWN, little-endian (the P8I file layout verbatim). (x,y) is
# the image's BOTTOM-LEFT in window coords, mapped through the current
# window; w,h are DEVICE pixels (unscaled, the CIRCLE-radius precedent);
# off-screen pixels clip by the device's unsigned rule; always replaces.
# Checked: a 4x3 blit lands row-exact; the screen edge clips without
# wrapping; w=0 owes no payload; w>512 is err2 with no payload owed; a
# BLIT inside CLBEG is err2 with the payload eaten AND DISCARDED (the
# stream stays in sync); a mapped window moves the anchor, not the size.
set -e
set -o pipefail
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-GL-BLIT TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null

cat > gl_bl.c <<'EOF'
char pb[8];
int pnum(int u) {
    int i;
    if (u & 32768) { putchar(45); u = 0 - u; }
    i = 0;
    if (u == 0) { putchar(48); }
    while (u) { pb[i] = 48 + (u % 10); u = u / 10; i = i + 1; }
    while (i) { i = i - 1; putchar(pb[i]); }
    putchar(10);
    return 0;
}
int glb(int v) { while (peek(65361) & 128) { } poke(65360, v); return 0; }
int glw(int v) { glb(v & 255); glb((v / 256) & 255); return 0; }
int rbb() { while ((peek(65361) & 1) == 0) { } return peek(65362); }
int rbw() { int l; l = rbb(); return l + 256 * rbb(); }
int prd(int x, int y) {                    /* PIXRD read-back */
    glb(99); glw(x); glw(y);
    return rbw();
}
int blit(int x, int y, int w, int h) {
    glb(100); glw(x); glw(y); glw(w); glw(h);
    return 0;
}
int main() {
    int r; int c;
    glb(4);                                    /* RESETF */
    glb(179); glw(0); glw(479); glw(0); glw(271);   /* WINDOW  */
    glb(178); glw(0); glw(479); glw(0); glw(271);   /* VWPORT  */
    glb(15); glb(0); glb(0); glb(0);           /* CLEARS black */
    /* 4x3 blit at (100,50): payload row 0 is the TOP row (wy 52) */
    blit(100, 50, 4, 3);
    r = 0;
    while (r < 12) { glw(1000 + r); r = r + 1; }
    r = 0;
    while (r < 3) {
        c = 0;
        while (c < 4) {
            pnum(prd(100 + c, 52 - r));        /* 1000 + r*4 + c */
            c = c + 1;
        }
        r = r + 1;
    }
    pnum(prd(99, 51)); pnum(prd(104, 51));     /* borders: 0 0 */
    pnum(prd(100, 53)); pnum(prd(100, 49));    /* above/below: 0 0 */
    /* clip at the right edge: 4 wide at x=478 -> 478,479 land, rest gone */
    blit(478, 50, 4, 1);
    glw(2001); glw(2002); glw(2003); glw(2004);
    pnum(prd(478, 50)); pnum(prd(479, 50));    /* 2001 2002 */
    pnum(prd(0, 50)); pnum(prd(1, 50));        /* no wrap: 0 0 */
    /* w=0: no payload owed -- the NEXT command must execute */
    blit(10, 10, 0, 5);
    glb(6); glb(31); glb(0); glb(0);           /* COLOR red */
    glb(16); glw(10); glw(10); glb(8);         /* MOVE + POINT */
    pnum(prd(10, 10));                          /* -2048 red */
    /* w>512: err2, no payload owed, stream lives */
    blit(10, 20, 600, 1);
    pnum(peek(65363)); pnum(peek(65363));      /* 2 then 0 */
    glb(16); glw(12); glw(10); glb(8);         /* another POINT lands */
    pnum(prd(12, 10));                          /* -2048 */
    /* recording refusal: err2, payload DISCARDED, stream in sync */
    glb(112); glb(9);                          /* CLBEG 9 */
    blit(30, 30, 2, 2);
    glw(3001); glw(3002); glw(3003); glw(3004);
    glb(113);                                  /* CLEND */
    pnum(peek(65363)); pnum(peek(65363));      /* 2 then 0 */
    glb(114); glb(9);                          /* CLRUN 9: empty list */
    pnum(prd(30, 30));                          /* nothing drawn: 0 */
    /* a mapped window moves the ANCHOR only; w,h stay device pixels */
    glb(179); glw(0-120); glw(120); glw(0-120); glw(120);
    glb(178); glw(104); glw(375); glw(0); glw(271);
    blit(0, 0, 2, 1);                          /* world origin */
    glw(4001); glw(4002);
    /* world (0,0) maps to device (239,136) = window wy 135 (the
       y-flip's truncation lands on the far side of centre) */
    glb(179); glw(0); glw(479); glw(0); glw(271);   /* identity again */
    glb(178); glw(0); glw(479); glw(0); glw(271);
    pnum(prd(239, 135)); pnum(prd(240, 135));  /* 4001 4002 */
    pnum(peek(65363));                          /* clean: 0 */
    puts("BLDONE");
    return 0;
}
EOF
python3 $ROOT/compiler/p8cc.py gl_bl.c -o gl_bl.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py gl_bl.asm -o gl_bl.bin --base 0x6A00 >/dev/null

rm -f gl_bl.img
python3 $ROOT/tools/p8xfs.py create gl_bl.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   gl_bl.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  gl_bl.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    gl_bl.img gl_bl.bin --name /bin/glbl.bin --load 0x6A00 --exec 0x6A00 >/dev/null
printf 'B\rrun /bin/glbl.bin\r' > gl_bl.in
../p8xemu -N -i gl_bl.in -c gl_bl.img -l 600000000 -g gl_bl.ppm eeprom.bin > gl_bl.out 2>/dev/null || true
grep -q "BLDONE" gl_bl.out || fail "harness did not finish"

got=$(LC_ALL=C tr -d '\0\r' < gl_bl.out | grep -E '^-?[0-9]+$' | tr '\n' ' ' | sed 's/ $//')
want="1000 1001 1002 1003 1004 1005 1006 1007 1008 1009 1010 1011 0 0 0 0 2001 2002 0 0 -2048 2 0 -2048 2 0 0 4001 4002 0"
[ "$got" = "$want" ] || fail "read sequence
  got:  $got
  want: $want"

echo "C-GL-BLIT TEST: PASS (row-exact 4x3, edge clip, zero dims, err2 dims, recording refusal + sync, mapped anchor)"
