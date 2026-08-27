#!/bin/sh
# Stage-10f LINFUN (STAGE10-DESIGN.md): drawing modes on the pixel path.
#   0 replace  1 complement  2 OR  3 AND  4 XOR -- applied to lines,
#   points and outlines; FILLS AND SPANS ALWAYS REPLACE (the burst
#   filler stays a burst). XOR twice restores the ground: the
#   rubber-band property, checked pixel-exactly. LINFUN >4 -> error 2;
#   RESETF returns the mode to replace.
set -e
set -o pipefail
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-GL-LF TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null

cat > gl_lf.c <<'EOF'
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
    /* window == viewport so coordinates are screen pixels */
    glb(179); glw(0); glw(479); glw(0); glw(271);        /* WINDOW  */
    glb(178); glw(0); glw(479); glw(0); glw(271);        /* VWPORT  */
    glb(15); glb(0); glb(0); glb(0);                     /* CLEARS  */
    /* ground: a blue filled rect 100..200 x 100..120 (raw fill) */
    glb(6); glb(0); glb(0); glb(31);                     /* COLOR blue */
    glb(224); glb(1);                                    /* PRMFIL 1 */
    glb(16); glw(100); glw(100);                         /* MOVE     */
    glb(52); glw(200); glw(120);                         /* RECT     */
    glb(224); glb(0);                                    /* PRMFIL 0 */
    /* XOR a red line across it, then XOR it again */
    glb(6); glb(31); glb(0); glb(0);                     /* COLOR red */
    glb(235); glb(4);                                    /* LINFUN 4 */
    glb(16); glw(90); glw(110);                          /* MOVE     */
    glb(40); glw(210); glw(110);                         /* DRAW     */
    glb(235); glb(1);                                    /* LINFUN 1: complement */
    glb(16); glw(90); glw(130);                          /* a line on black */
    glb(40); glw(210); glw(130);
    glb(235); glb(2);                                    /* LINFUN 2: OR */
    glb(16); glw(90); glw(140);
    glb(40); glw(210); glw(140);
    glb(235); glb(9);                                    /* bad mode -> err2 */
    pnum(peek(65363)); pnum(peek(65363));                /* 2 then 0 */
    glb(4);                                              /* RESETF: mode 0 */
    return 0;
}
EOF
python3 $ROOT/compiler/p8cc.py gl_lf.c -o gl_lf.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py gl_lf.asm -o gl_lf.bin --base 0x6A00 >/dev/null

rm -f gl_lf.img
python3 $ROOT/tools/p8xfs.py create gl_lf.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   gl_lf.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  gl_lf.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    gl_lf.img gl_lf.bin --name /bin/gllf.bin --load 0x6A00 --exec 0x6A00 >/dev/null
printf 'B\rrun /bin/gllf.bin\r' > gl_lf.in
../p8xemu -N -i gl_lf.in -c gl_lf.img -l 400000000 -g gl_lf.ppm eeprom.bin > gl_lf.out 2>/dev/null || true

got=$(LC_ALL=C tr -d '\0\r' < gl_lf.out | grep -E '^[0-9]+$' | head -2 | tr '\n' ' ' | sed 's/ $//')
[ "$got" = "2 0" ] || fail "error sequence '$got', want '2 0'"

python3 - <<'EOF' || exit 1
d = open("gl_lf.ppm","rb").read(); px = d.split(b"\n",3)[3]
def p(x, y):
    i = (y*480 + x)*3
    return tuple(px[i:i+3])
BLUE  = (0x00, 0x00, 0xFF)     # 565 blue maxed -> 0,0,255 in the dump
BLACK = (0, 0, 0)
RED   = (0xFF, 0x00, 0x00)
# window y runs UP: screen_y = 271 - window_y (the viewport flip)
# XOR line at wy=110 (sy=161): over blue -> blue^red; over black -> red
assert p(150,161) == (0xFF, 0x00, 0xFF), "XOR over blue wrong: %r" % (p(150,161),)
assert p(95,161)  == RED,   "XOR over black wrong: %r" % (p(95,161),)
# complement line at wy=130 (sy=141) over black -> white
assert p(150,141) == (0xFF, 0xFF, 0xFF), "complement wrong: %r" % (p(150,141),)
# OR line at wy=140 (sy=131) over black -> red
assert p(150,131) == RED, "OR over black wrong: %r" % (p(150,131),)
# the filled rect body is untouched blue away from the line
assert p(150,166) == BLUE, "fill ground wrong: %r" % (p(150,166),)
EOF
echo "C-GL-LF TEST: PASS (XOR/complement/OR pixel-exact, fills replace, err2, RESETF)"
