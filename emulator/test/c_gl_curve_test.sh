#!/bin/sh
# Stage-10i curves: CIRCLE/ELIPSE map their radii through the window->
# viewport scale and draw as the device ellipse (PRMFIL fills); negative
# radius = error 2; neither moves the current point. ARC/SECTOR (3C/3D)
# were REMOVED 2026-08-30 for placement headroom: both opcodes are
# err1/skip now, exercised here.
set -e
set -o pipefail
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-GL-CURVE TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null

cat > gl_cv.c <<'EOF'
char pb[8];
int pnum(int u) {
    int i;
    i = 0;
    if (u == 0) { putchar(48); }
    while (u) { pb[i] = 48 + (u % 10); u = u / 10; i = i + 1; }
    while (i) { i = i - 1; putchar(pb[i]); }
    putchar(10);
    return 0;
}
int glb(int v) { while (peek(65361) & 128) { } poke(65360, v); return 0; }
int glw(int v) { glb(v & 255); glb((v / 256) & 255); return 0; }
int main() {
    glb(179); glw(0); glw(479); glw(0); glw(271);        /* WINDOW  */
    glb(178); glw(0); glw(479); glw(0); glw(271);        /* VWPORT  */
    glb(15); glb(0); glb(0); glb(0);                     /* CLEARS  */
    /* red circle outline r=60 at (100,136) */
    glb(6); glb(31); glb(0); glb(0);
    glb(16); glw(100); glw(136);                         /* MOVE */
    glb(56); glw(60);                                    /* CIRCLE */
    /* green filled circle r=40 at (300,136) */
    glb(6); glb(0); glb(63); glb(0);
    glb(224); glb(1);                                    /* PRMFIL 1 */
    glb(16); glw(300); glw(136);
    glb(56); glw(40);
    glb(224); glb(0);                                    /* PRMFIL 0 */
    /* blue ellipse outline 80x30 at (100,60) */
    glb(6); glb(0); glb(0); glb(31);
    glb(16); glw(100); glw(60);
    glb(57); glw(80); glw(30);                           /* ELIPSE */
    /* TALL filled ellipse 25x60 (the OTHER aspect's region walk) plus
       the r=1 and r=0 edges -- coverage inherited from the retired
       device-door ce test */
    glb(6); glb(31); glb(63); glb(0);
    glb(224); glb(1);
    glb(16); glw(420); glw(90);
    glb(57); glw(25); glw(60);                           /* ELIPSE fill */
    glb(224); glb(0);
    glb(6); glb(31); glb(63); glb(31);
    glb(16); glw(20); glw(250);
    glb(56); glw(1);                                     /* r=1 */
    glb(16); glw(30); glw(250);
    glb(56); glw(0);                                     /* r=0: nothing */
    /* retired ARC then SECTOR: err1 each, one byte skipped, stream
       lives -- the teal fill after them must land */
    glb(60);                                             /* ARC: unknown */
    glb(61);                                             /* SECTOR: unknown */
    glb(6); glb(0); glb(63); glb(31);
    glb(224); glb(1);
    glb(16); glw(240); glw(200);
    glb(56); glw(30);                                    /* CIRCLE fill */
    glb(224); glb(0);
    /* negative radius -> error 2 */
    glb(56); glw(0 - 5);                                 /* CIRCLE -5 */
    pnum(peek(65363)); pnum(peek(65363));                /* the two err1s */
    pnum(peek(65363)); pnum(peek(65363));                /* 2 then 0  */
    puts("CVDONE");
    return 0;
}
EOF
python3 $ROOT/compiler/p8cc.py gl_cv.c -o gl_cv.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py gl_cv.asm -o gl_cv.bin --base 0x6A00 >/dev/null

rm -f gl_cv.img
python3 $ROOT/tools/p8xfs.py create gl_cv.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   gl_cv.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  gl_cv.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    gl_cv.img gl_cv.bin --name /bin/glcv.bin --load 0x6A00 --exec 0x6A00 >/dev/null
printf 'B\rrun /bin/glcv.bin\r' > gl_cv.in
../p8xemu -N -i gl_cv.in -c gl_cv.img -l 600000000 -g gl_cv.ppm eeprom.bin > gl_cv.out 2>/dev/null || true
grep -q "CVDONE" gl_cv.out || fail "harness did not finish"
got=$(LC_ALL=C tr -d '\0\r' < gl_cv.out | grep -E '^[0-9]+$' | head -4 | tr '\n' ' ' | sed 's/ $//')
[ "$got" = "1 1 2 0" ] || fail "error sequence '$got', want '1 1 2 0'"

python3 - <<'EOF' || exit 1
d = open("gl_cv.ppm","rb").read(); px = d.split(b"\n",3)[3]
def p(x, wy):
    y = 271 - wy
    i = (y*480 + x)*3
    return tuple(px[i:i+3])
RED,GREEN,BLUE,YEL,TEAL,BLACK = (255,0,0),(0,255,0),(0,0,255),(255,255,0),(0,255,255),(0,0,0)
assert p(160,136)==RED,   "circle right point: %r"%(p(160,136),)
assert p(100,196)==RED,   "circle top point: %r"%(p(100,196),)
assert p(100,136)==BLACK, "circle centre not hollow: %r"%(p(100,136),)
assert p(300,136)==GREEN, "filled circle centre: %r"%(p(300,136),)
assert p(300,176)==GREEN, "filled circle top edge: %r"%(p(300,176),)
assert p(300,178)==BLACK, "fill leaked above circle: %r"%(p(300,178),)
assert p(180,60)==BLUE,   "ellipse right point: %r"%(p(180,60),)
assert p(100,90)==BLUE,   "ellipse top point: %r"%(p(100,90),)
assert p(100,60)==BLACK,  "ellipse centre not hollow: %r"%(p(100,60),)
assert p(380,60)==BLACK,  "retired ARC drew something: %r"%(p(380,60),)
assert p(240,200)==TEAL,  "fill after retired opcodes missing: %r"%(p(240,200),)
assert p(255,215)==TEAL,  "fill after retired opcodes short: %r"%(p(255,215),)
YELG = (255,255,0)
assert p(420,90)==YELG,   "tall ellipse fill centre: %r"%(p(420,90),)
assert p(420,149)==YELG,  "tall ellipse fill top: %r"%(p(420,149),)
assert p(446,90)==BLACK,  "tall ellipse leaked right: %r"%(p(446,90),)
WHITE = (255,255,255)
assert p(21,250)==WHITE,  "r=1 circle right point: %r"%(p(21,250),)
assert p(30,250)==BLACK,  "r=0 drew a dot: %r"%(p(30,250),)
EOF
echo "C-GL-CURVE TEST: PASS (circle/ellipse outline+fill, both aspects, r=1/r=0 edges, radius mapping, retired-3C/3D err1 skip, err2)"
