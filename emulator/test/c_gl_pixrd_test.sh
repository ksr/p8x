#!/bin/sh
# PIXRD x y (opcode $63) -- the single-interface migration's first verb
# (2026-08-31): ONE pixel colour to the RB FIFO (GLRB $FF52, GLSTAT
# bit0, low byte then high). Window coordinates through the same map as
# every 2D verb; the device's rule off-screen (reads 0). Checked: an
# identity-window read of a drawn pixel, background 0, off-screen 0, a
# NON-identity window (the map is real, not a flip), the ASCII forms,
# agreement with the device PIXELR at the mapped screen pixel, and
# PIXRD recorded in a command list replaying its read at CLRUN time.
set -e
set -o pipefail
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-GL-PIXRD TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null

cat > gl_pr.c <<'EOF'
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
int gwt() { while (peek(65361) & 64) { } return 0; }
int devrd(int x, int y) {
    poke(65312, x & 255); poke(65321, (x / 256) & 255);
    poke(65313, y & 255); poke(65322, (y / 256) & 255);
    poke(65317, 9);                            /* device PIXELR */
    while (peek(65318) & 128) { }
    x = peek(65319);
    return x + 256 * peek(65319);
}
int main() {
    glb(4);                                    /* RESETF */
    glb(179); glw(0); glw(479); glw(0); glw(271);   /* WINDOW  */
    glb(178); glw(0); glw(479); glw(0); glw(271);   /* VWPORT  */
    glb(15); glb(0); glb(0); glb(0);           /* CLEARS black */
    glb(6); glb(31); glb(63); glb(0);          /* COLOR yellow */
    glb(16); glw(100); glw(50);                /* MOVE */
    glb(8);                                    /* POINT: one pixel */
    gwt();
    glb(99); glw(100); glw(50); pnum(rbw());   /* PIXRD hits it: -32   */
    glb(99); glw(101); glw(50); pnum(rbw());   /* neighbour: 0         */
    glb(99); glw(0-5);  glw(50); pnum(rbw());  /* off-window: 0        */
    glb(99); glw(100); glw(300); pnum(rbw());  /* above the window: 0  */
    /* the device agrees at the mapped screen pixel (y flip) */
    pnum(devrd(100, 221));                     /* screen (100, 271-50): -32 */
    /* a NON-identity window: same world point, kept through the map */
    glb(179); glw(0-120); glw(120); glw(0-120); glw(120);  /* WINDOW +-120 */
    glb(178); glw(104); glw(375); glw(0); glw(271);        /* VWPORT box  */
    glb(6); glb(0); glb(63); glb(31);          /* COLOR teal */
    glb(16); glw(60); glw(60);                 /* MOVE 60 60 (world) */
    glb(8); gwt();                             /* one pixel */
    glb(99); glw(60); glw(60); pnum(rbw());    /* PIXRD 60 60: 2047 */
    glb(99); glw(0); glw(0); pnum(rbw());      /* world origin: 0 */
    /* ASCII forms */
    gls("CA ");
    gls("PIXRD 60 60 ");
    gls("PXR 0 0 ");
    gls("CX ");
    pnum(rbw()); pnum(rbw());                  /* 2047 then 0 */
    /* recorded in a list: the read happens at CLRUN, not CLBEG */
    glb(112); glb(5);                          /* CLBEG 5 */
    glb(99); glw(60); glw(60);                 /*   PIXRD 60 60 */
    glb(113);                                  /* CLEND */
    glb(114); glb(5); gwt();                   /* CLRUN 5 */
    pnum(rbw());                               /* 2047 from the replay */
    pnum(peek(65363));                         /* GLERR: 0 end to end */
    puts("PRDONE");
    return 0;
}
EOF
python3 $ROOT/compiler/p8cc.py gl_pr.c -o gl_pr.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py gl_pr.asm -o gl_pr.bin --base 0x6A00 >/dev/null

rm -f gl_pr.img
python3 $ROOT/tools/p8xfs.py create gl_pr.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   gl_pr.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  gl_pr.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    gl_pr.img gl_pr.bin --name /bin/glpr.bin --load 0x6A00 --exec 0x6A00 >/dev/null
printf 'B\rrun /bin/glpr.bin\r' > gl_pr.in
../p8xemu -N -i gl_pr.in -c gl_pr.img -l 600000000 eeprom.bin > gl_pr.out 2>/dev/null || true
grep -q "PRDONE" gl_pr.out || fail "harness did not finish"

got=$(LC_ALL=C tr -d '\0\r' < gl_pr.out | grep -E '^-?[0-9]+$' | tr '\n' ' ' | sed 's/ $//')
want="-32 0 0 0 -32 2047 0 2047 0 2047 0"
[ "$got" = "$want" ] || fail "read sequence '$got', want '$want'"

echo "C-GL-PIXRD TEST: PASS (identity + mapped windows, off-screen 0, device agreement, ASCII forms, list replay)"
