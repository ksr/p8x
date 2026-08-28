#!/bin/sh
# Stage-10g AREA/AREABC: scanline boundary seed fill. AREA fills from
# the 2D current point with the pen, bounded by pen-coloured pixels;
# AREABC r g b bounds on a stated colour instead. The algorithm (span
# probe, paint, one push per interior run above/below, 16384-entry
# stack) is the emulator/RTL contract. Off-window seed -> error 2.
set -e
set -o pipefail
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-GL-AREA TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null

cat > gl_ar.c <<'EOF'
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
    /* a red rectangle outline, then AREA from inside it */
    glb(6); glb(31); glb(0); glb(0);                     /* COLOR red */
    glb(16); glw(100); glw(100);                         /* MOVE      */
    glb(52); glw(200); glw(150);                         /* RECT      */
    glb(16); glw(150); glw(125);                         /* MOVE in   */
    glb(192);                                            /* AREA      */
    /* a blue diamond outline, green AREABC inside it */
    glb(6); glb(0); glb(0); glb(31);                     /* COLOR blue */
    glb(48); glb(4);                                     /* POLY 4     */
    glw(300); glw(200); glw(350); glw(150);
    glw(400); glw(200); glw(350); glw(250);
    glb(6); glb(0); glb(63); glb(0);                     /* COLOR green */
    glb(16); glw(350); glw(200);                         /* MOVE centre */
    glb(193); glb(0); glb(0); glb(31);                   /* AREABC blue */
    /* off-window seed -> error 2 */
    glb(16); glw(0 - 500); glw(0);                       /* MOVE off   */
    glb(192);                                            /* AREA       */
    pnum(peek(65363)); pnum(peek(65363));                /* 2 then 0   */
    puts("ARDONE");
    return 0;
}
EOF
python3 $ROOT/compiler/p8cc.py gl_ar.c -o gl_ar.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py gl_ar.asm -o gl_ar.bin --base 0x6A00 >/dev/null

rm -f gl_ar.img
python3 $ROOT/tools/p8xfs.py create gl_ar.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   gl_ar.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  gl_ar.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    gl_ar.img gl_ar.bin --name /bin/glar.bin --load 0x6A00 --exec 0x6A00 >/dev/null
printf 'B\rrun /bin/glar.bin\r' > gl_ar.in
../p8xemu -N -i gl_ar.in -c gl_ar.img -l 600000000 -g gl_ar.ppm eeprom.bin > gl_ar.out 2>/dev/null || true
grep -q "ARDONE" gl_ar.out || fail "harness did not finish"
got=$(LC_ALL=C tr -d '\0\r' < gl_ar.out | grep -E '^[0-9]+$' | head -2 | tr '\n' ' ' | sed 's/ $//')
[ "$got" = "2 0" ] || fail "error sequence '$got', want '2 0'"

python3 - <<'EOF' || exit 1
d = open("gl_ar.ppm","rb").read(); px = d.split(b"\n",3)[3]
def p(x, wy):
    y = 271 - wy                      # window y up -> screen y down
    i = (y*480 + x)*3
    return tuple(px[i:i+3])
RED, GREEN, BLUE, BLACK = (255,0,0), (0,255,0), (0,0,255), (0,0,0)
assert p(150,125) == RED,   "rect interior not filled: %r" % (p(150,125),)
assert p(101,101) == RED,   "fill missed a corner: %r" % (p(101,101),)
assert p(90,125)  == BLACK, "fill leaked left: %r" % (p(90,125),)
assert p(150,160) == BLACK, "fill leaked above: %r" % (p(150,160),)
assert p(350,200) == GREEN, "diamond interior not green: %r" % (p(350,200),)
assert p(350,150) == BLUE,  "diamond boundary overwritten: %r" % (p(350,150),)
assert p(300,200) == BLUE,  "diamond left vertex gone: %r" % (p(300,200),)
assert p(301,200) == GREEN, "fill missed the tip interior: %r" % (p(301,200),)
assert p(290,200) == BLACK, "fill escaped the diamond: %r" % (p(290,200),)
EOF
echo "C-GL-AREA TEST: PASS (AREA pen-bounded, AREABC colour-bounded, corners filled, no leaks, off-window err2)"
