#!/bin/sh
# Stage-10a graphics language (STAGE10-DESIGN.md): the GL port at $FF50 and
# the hex-mode interpreter.
#   1. Probe + errors: GLID reads 'G'; an unknown opcode logs error 1, CA
#      before stage 10d logs 3, POLY with n=0 logs 2; GLERR drains to 0 and
#      GLSTAT's error bit follows.
#   2. THE crown-jewel: one mixed scene (coloured 3D lines -- clipped,
#      near-clipped, plain -- and two filled TRIs) drawn twice, once through
#      lib_g3d's SOFTWARE pipeline (g3render; the record engine is retired,
#      and the stage-9 identity proof pinned software == engine pixels) and
#      once as a GL hex command stream (WINDOW/VWPORT/FLOOD/COLOR/MOVE3/
#      DRAW3/PRMFIL/POLY3). The two framebuffers must be BYTE-IDENTICAL:
#      the language is a new transport, not new pixels.
#   3. 2D verbs against an exact 1:1 window->viewport mapping (mapx(x)=x,
#      mapy(y)=135-y): CLEARS ground colour, DRAW/DRAWR lines, a PRMFIL
#      RECT, POINT -- spot-checked in the PPM by a host replica.
set -e
set -o pipefail
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-GL TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null

# ---- the scene, once as lib_g3d records (the stage-9 engine path) -----------
cat > gl_a_src.c <<'EOF'
//#use gfx
//#use g3d
int tp[9];
int main() {
    g3window(0 - 120, 0 - 120, 120, 120);
    g3view(104, 0, 375, 271);
    g3persp(256);
    g3clear();
    g3color(grgb(31, 63, 31));
    g3line(0 - 90, 0 - 90, 300, 90, 0 - 90, 300);
    g3color(grgb(31, 0, 0));
    g3line(90, 0 - 90, 300, 0, 90, 300);
    g3color(grgb(0, 63, 0));
    g3line(0 - 200, 0, 300, 200, 50, 300);      /* window-clipped */
    g3color(grgb(0, 0, 31));
    g3line(0, 0, 0 - 50, 0, 0, 300);            /* near-clipped */
    g3color(grgb(31, 63, 0));
    tp[0] = 0 - 80; tp[1] = 0 - 80; tp[2] = 300;
    tp[3] = 80;     tp[4] = 0 - 80; tp[5] = 300;
    tp[6] = 0;      tp[7] = 40;     tp[8] = 420;
    g3tri(tp, 1);
    g3color(grgb(0, 63, 31));
    tp[0] = 100;    tp[1] = 0 - 140; tp[2] = 260;
    tp[3] = 140;    tp[4] = 60;      tp[5] = 260;
    tp[6] = 0 - 40; tp[7] = 10;      tp[8] = 200;
    g3tri(tp, 1);
    g3render();                /* the lib's software walk: the record
                                  engine is RETIRED (stage 10b), and stage
                                  9 proved software == engine pixels */
    puts("ADONE");
    return 0;
}
EOF
cp gl_a_src.c $ROOT/os/commands/zz_gla.c
python3 $ROOT/tools/clib.py $ROOT/os/commands/zz_gla.c > gl_a.c
rm $ROOT/os/commands/zz_gla.c
python3 $ROOT/compiler/p8cc.py gl_a.c -o gl_a.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py gl_a.asm -o gl_a.bin --base 0x6A00 >/dev/null

# ---- the SAME scene as a GL hex stream (no lib_g3d at all) ------------------
cat > gl_b.c <<'EOF'
int glb(int v) { poke(65360, v); return 0; }       /* GLDATA $FF50 */
int glw(int v) { glb(v & 255); glb(v >> 8); return 0; }
int line3(int x0, int y0, int z0, int x1, int y1, int z1) {
    glb(18); glw(x0); glw(y0); glw(z0);            /* MOVE3 */
    glb(42); glw(x1); glw(y1); glw(z1);            /* DRAW3 */
    return 0;
}
int main() {
    glb(179); glw(0 - 120); glw(120); glw(0 - 120); glw(120);  /* WINDOW */
    glb(178); glw(104); glw(375); glw(0); glw(271);            /* VWPORT */
    glb(7); glb(0); glb(0); glb(0);                /* FLOOD 0 0 0 = erase */
    glb(6); glb(31); glb(63); glb(31);             /* COLOR white */
    line3(0 - 90, 0 - 90, 300, 90, 0 - 90, 300);
    glb(6); glb(31); glb(0); glb(0);
    line3(90, 0 - 90, 300, 0, 90, 300);
    glb(6); glb(0); glb(63); glb(0);
    line3(0 - 200, 0, 300, 200, 50, 300);
    glb(6); glb(0); glb(0); glb(31);
    line3(0, 0, 0 - 50, 0, 0, 300);
    glb(224); glb(1);                              /* PRMFIL 1 */
    glb(6); glb(31); glb(63); glb(0);
    glb(50); glb(3);                               /* POLY3 n=3 */
    glw(0 - 80); glw(0 - 80); glw(300);
    glw(80);     glw(0 - 80); glw(300);
    glw(0);      glw(40);     glw(420);
    glb(6); glb(0); glb(63); glb(31);
    glb(50); glb(3);
    glw(100);    glw(0 - 140); glw(260);
    glw(140);    glw(60);      glw(260);
    glw(0 - 40); glw(10);      glw(200);
    puts("BDONE");
    return 0;
}
EOF
python3 $ROOT/compiler/p8cc.py gl_b.c -o gl_b.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py gl_b.asm -o gl_b.bin --base 0x6A00 >/dev/null

# ---- probe/error program ----------------------------------------------------
cat > gl_e.c <<'EOF'
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
int main() {
    pnum(peek(65364));               /* GLID: expect 71 'G' */
    poke(65360, 238);                /* unknown opcode $EE */
    poke(65360, 67); poke(65360, 65); poke(65360, 32);   /* "CA " */
    poke(65360, 48); poke(65360, 0); /* POLY n=0 */
    pnum(peek(65361) & 2);           /* GLSTAT error bit: expect 2 */
    pnum(peek(65363));               /* GLERR: expect 1 (unknown opcode) */
    pnum(peek(65363));               /* expect 3 (ASCII not fitted) */
    pnum(peek(65363));               /* expect 2 (bad parameter) */
    pnum(peek(65363));               /* expect 0 (drained) */
    pnum(peek(65361) & 2);           /* error bit clear: expect 0 */
    puts("EDONE");
    return 0;
}
EOF
python3 $ROOT/compiler/p8cc.py gl_e.c -o gl_e.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py gl_e.asm -o gl_e.bin --base 0x6A00 >/dev/null

# ---- 2D verbs program -------------------------------------------------------
cat > gl_2.c <<'EOF'
int glb(int v) { poke(65360, v); return 0; }
int glw(int v) { glb(v & 255); glb(v >> 8); return 0; }
int main() {
    glb(15); glb(8); glb(16); glb(8);              /* CLEARS grey */
    glb(179); glw(0); glw(239); glw(0); glw(135);  /* WINDOW 1:1 */
    glb(178); glw(0); glw(239); glw(0); glw(135);  /* VWPORT: mapy=135-y */
    glb(6); glb(31); glb(63); glb(31);             /* COLOR white */
    glb(16); glw(10); glw(10);                     /* MOVE 10 10 */
    glb(40); glw(50); glw(10);                     /* DRAW 50 10 */
    glb(41); glw(0); glw(30);                      /* DRAWR 0 30: up to y=40 */
    glb(224); glb(1);                              /* PRMFIL 1 */
    glb(6); glb(31); glb(0); glb(0);               /* COLOR red */
    glb(16); glw(60); glw(20);                     /* MOVE 60 20 */
    glb(52); glw(80); glw(40);                     /* RECT to 80 40 */
    glb(6); glb(0); glb(63); glb(0);               /* COLOR green */
    glb(17); glw(0 - 55); glw(0 - 15);             /* MOVER: to 5 5 */
    glb(8);                                        /* POINT at 5 5 */
    puts("2DONE");
    return 0;
}
EOF
python3 $ROOT/compiler/p8cc.py gl_2.c -o gl_2.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py gl_2.asm -o gl_2.bin --base 0x6A00 >/dev/null

rm -f gl.img
python3 $ROOT/tools/p8xfs.py create gl.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   gl.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  gl.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    gl.img gl_a.bin --name /bin/gla.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    gl.img gl_b.bin --name /bin/glb.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    gl.img gl_e.bin --name /bin/gle.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    gl.img gl_2.bin --name /bin/gl2.bin --load 0x6A00 --exec 0x6A00 >/dev/null

# ---- 1: probe + errors ------------------------------------------------------
printf 'B\rrun /bin/gle.bin\r' > gl_e.in
../p8xemu -N -i gl_e.in -c gl.img -l 300000000 eeprom.bin > gl_e.out 2>/dev/null || true
grep -q EDONE gl_e.out || fail "error program did not finish"
want="71 2 1 3 2 0 0"
got=$(LC_ALL=C tr -d '\0\r' < gl_e.out | grep -E '^[0-9]+$' | head -7 | tr '\n' ' ' | sed 's/ $//')
[ "$got" = "$want" ] || { echo "want: $want"; echo "got:  $got"; fail "probe/error sequence differs"; }
echo "GLID probe + error FIFO OK"

# ---- 2: record engine vs GL stream, byte-identical --------------------------
printf 'B\rrun /bin/gla.bin\r' > gl_a.in
../p8xemu -N -i gl_a.in -c gl.img -l 300000000 -g gl_a.ppm eeprom.bin > gl_a.out 2>/dev/null || true
grep -q ADONE gl_a.out || fail "software-lib scene did not finish"
printf 'B\rrun /bin/glb.bin\r' > gl_b.in
../p8xemu -N -i gl_b.in -c gl.img -l 300000000 -g gl_b.ppm eeprom.bin > gl_b.out 2>/dev/null || true
grep -q BDONE gl_b.out || fail "GL-stream scene did not finish"
cmp gl_a.ppm gl_b.ppm || fail "GL stream and software-lib framebuffers differ"
python3 - <<'EOF' || exit 1
# the scene must actually be THERE: the first tri's centroid is not black
data = open("gl_b.ppm","rb").read()
hdr = data.split(b"\n",3); w,h = map(int,hdr[1].split()); px = hdr[3]
o = (170*w + 239)*3          # inside tri 1 (screen ~239,170)
assert px[o:o+3] != b"\x00\x00\x00", "filled tri missing at probe point"
EOF
echo "software lib vs GL stream byte-identical (and non-empty)"

# ---- 3: 2D verbs spot pixels ------------------------------------------------
printf 'B\rrun /bin/gl2.bin\r' > gl_2.in
../p8xemu -N -i gl_2.in -c gl.img -l 300000000 -g gl_2.ppm eeprom.bin > gl_2.out 2>/dev/null || true
grep -q 2DONE gl_2.out || fail "2D program did not finish"
python3 - <<'EOF' || exit 1
data = open("gl_2.ppm","rb").read()
hdr = data.split(b"\n",3); w,h = map(int,hdr[1].split()); px = hdr[3]
def rgb(c):
    r5,g6,b5 = (c>>11)&31, (c>>5)&63, c&31
    return bytes(((r5<<3)|(r5>>2), (g6<<2)|(g6>>4), (b5<<3)|(b5>>2)))
def expect(x,y,c,what):
    o=(y*w+x)*3
    assert px[o:o+3]==rgb(c), "%s: (%d,%d) got %r want %r" % (what,x,y,px[o:o+3],rgb(c))
GREY=(8<<11)|(16<<5)|8; WHITE=0xFFFF; RED=31<<11; GREEN=63<<5
# mapping is exact: sx = x, sy = 135 - y
expect(30, 125, WHITE, "DRAW horizontal at y=10")
expect(50, 110, WHITE, "DRAWR vertical x=50 midway")   # y=25 -> 110
expect(70, 105, RED,   "RECT fill centre")             # y=30 -> 105
expect(60, 115, RED,   "RECT fill corner")             # y=20 -> 115
expect(5, 130, GREEN,  "POINT at 5,5")
expect(200, 260, GREY, "CLEARS ground below viewport")
expect(300, 60, GREY,  "CLEARS ground right of viewport")
expect(100, 60, GREY,  "untouched viewport interior stays ground")
EOF
echo "2D verbs spot pixels OK"

# ---- 4: FLIP / PGSYNC semantics (the coverage the retired record-engine
#         suite carried): display shows the FLIPPED frame, drawing after a
#         flip lands on the hidden page, PGSYNC rejoins the pages ----------
cat > gl_f.c <<'EOF'
int glb(int v) { poke(65360, v); return 0; }
int glw(int v) { glb(v & 255); glb(v >> 8); return 0; }
int hline(int y) {
    glb(16); glw(20); glw(y);          /* MOVE 20 y  */
    glb(40); glw(220); glw(y);         /* DRAW 220 y */
    return 0;
}
int main() {
    int m;
    m = *argstr();
    glb(15); glb(0); glb(0); glb(0);               /* CLEARS black */
    glb(179); glw(0); glw(239); glw(0); glw(135);  /* WINDOW 1:1 */
    glb(178); glw(0); glw(239); glw(0); glw(135);
    glb(6); glb(31); glb(63); glb(31);             /* COLOR white */
    hline(10);                                     /* line A */
    glb(2);                                        /* FLIP */
    if (m == '2') { hline(20); }                   /* B: the hidden page */
    if (m == '3') { hline(20); glb(2); }           /* ...flipped in */
    if (m == '4') { glb(3); hline(30); }           /* PGSYNC, then C */
    puts("FDONE");
    return 0;
}
EOF
python3 $ROOT/compiler/p8cc.py gl_f.c -o gl_f.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py gl_f.asm -o gl_f.bin --base 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put gl.img gl_f.bin --name /bin/glf.bin --load 0x6A00 --exec 0x6A00 >/dev/null

glf_check() {   # $1 = mode, $2 = visible rows, $3 = hidden rows
    printf 'B\rrun /bin/glf.bin %s\r' "$1" > gl_f.in
    ../p8xemu -N -i gl_f.in -c gl.img -l 300000000 -g gl_f.ppm eeprom.bin > gl_f.out 2>/dev/null || true
    grep -q FDONE gl_f.out || fail "flip test run $1 did not finish"
    python3 - "$2" "$3" <<'PYEOF' || exit 1
import sys
data = open("gl_f.ppm","rb").read()
hdr = data.split(b"\n",3); W,H = map(int,hdr[1].split()); px = hdr[3]
def lum(y):
    return sum(px[(y*W+x)*3] for x in range(20,221))
for y in [int(v) for v in sys.argv[1].split(",") if v]:
    assert lum(y) > 600, "expected row %d visible" % y
for y in [int(v) for v in sys.argv[2].split(",") if v]:
    assert lum(y) == 0, "expected row %d hidden" % y
PYEOF
}
glf_check 1 125 115,105        # A flipped in; nothing else
glf_check 2 125 115            # B drawn after the flip stays hidden
glf_check 3 115 125            # second flip shows B, hides A
glf_check 4 125,105 115        # PGSYNC rejoins: C lands on the shown page
echo "FLIP/PGSYNC semantics OK"

echo "C-GL TEST: PASS (probe+errors, software-lib-vs-GL byte-identical scene, 2D verbs, FLIP/PGSYNC)"
