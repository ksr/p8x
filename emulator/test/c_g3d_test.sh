#!/bin/sh
# Stage-7 wireframe 3D (os/commands/lib_g3d.c + lib_gfx.c + cube.c):
#   1. muldiv vectors on-target vs a host reference -- the signed 32-bit-
#      intermediate contract (truncate toward zero, saturate +/-32767, /0
#      saturates, 0* is 0), through BOTH the native-*// fast path and the
#      m3mul/u3div slow path.
#   2. cube frame 0 spot pixels -- a host replica of the whole pipeline
#      (rotation, near clip, projection, window clip, viewport map) computes
#      the 8 projected corners; the emulator framebuffer must be white
#      there and black at points no edge crosses. Frame 0 is angle 0, so
#      the run is bit-deterministic forever.
#   3. native-compiler parity: lib_gfx + lib_g3d must compile ERROR-free
#      under p8cc.c too (cube.c itself is p8cc.py-only -- its sine/edge
#      tables are brace-initialized arrays, which the native subset lacks;
#      the disasm/lib_distab precedent).
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-G3D TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null

# ---- build cube.bin (p8cc.py) and the muldiv vector program -----------------
python3 $ROOT/tools/clib.py $ROOT/os/commands/cube.c > g3_cube.c
python3 $ROOT/compiler/p8cc.py g3_cube.c -o g3_cube.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py g3_cube.asm -o g3_cube.bin --base 0x6A00 >/dev/null

cat > g3_md_src.c <<'EOF'
//#use gfx
//#use g3d
char pb[8];
int pnum(int v) {
    int i; int u;
    if (v & 32768) { putchar(45); u = 0 - v; } else { u = v; }
    i = 0;
    if (u == 0) { putchar(48); }
    while (u) { pb[i] = 48 + (u % 10); u = u / 10; i = i + 1; }
    while (i) { i = i - 1; putchar(pb[i]); }
    putchar(10);
    return 0;
}
int vecs() {
    pnum(muldiv(240, 271, 240));
    pnum(muldiv(12345, 271, 240));
    pnum(muldiv(30000, 30000, 7));
    pnum(muldiv(0 - 300, 250, 100));
    pnum(muldiv(300, 0 - 250, 100));
    pnum(muldiv(0 - 300, 0 - 250, 100));
    pnum(muldiv(25000, 4, 100));
    pnum(muldiv(100, 0, 5));
    pnum(muldiv(5, 7, 0));
    pnum(muldiv(0 - 5, 7, 0));
    pnum(muldiv(32767, 1, 1));
    pnum(muldiv(511, 513, 2));
    pnum(muldiv(90, 120, 128));
    pnum(muldiv(0 - 90, 120, 128));
    return 0;
}
int main() {
    m3has = 2;      /* force the stage-7 all-software path */
    vecs();
    m3has = 0;      /* re-probe: the MDU path where one is fitted (emulator) */
    vecs();
    puts("MDONE");
    return 0;
}
EOF
cp g3_md_src.c $ROOT/os/commands/zz_g3md.c        # clib resolves libs by dir
python3 $ROOT/tools/clib.py $ROOT/os/commands/zz_g3md.c > g3_md.c
rm $ROOT/os/commands/zz_g3md.c
python3 $ROOT/compiler/p8cc.py g3_md.c -o g3_md.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py g3_md.asm -o g3_md.bin --base 0x6A00 >/dev/null

rm -f g3d.img
python3 $ROOT/tools/p8xfs.py create g3d.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   g3d.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  g3d.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    g3d.img g3_cube.bin --name /bin/cube.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    g3d.img g3_md.bin   --name /bin/g3md.bin --load 0x6A00 --exec 0x6A00 >/dev/null

# ---- 1: muldiv vectors ------------------------------------------------------
python3 - > g3_md_want.txt <<'EOF'
def muldiv(a, b, c):
    if a == 0 or b == 0: return 0
    q = 32767 if c == 0 else min(abs(a) * abs(b) // abs(c), 32767)
    if (a < 0) ^ (b < 0) ^ (c < 0): q = -q
    return q
V = [(240,271,240),(12345,271,240),(30000,30000,7),(-300,250,100),
     (300,-250,100),(-300,-250,100),(25000,4,100),(100,0,5),(5,7,0),
     (-5,7,0),(32767,1,1),(511,513,2),(90,120,128),(-90,120,128)]
for a,b,c in V: print(muldiv(a,b,c))       # the software path...
for a,b,c in V: print(muldiv(a,b,c))       # ...and the MDU path, identical
print("MDONE")
EOF
printf 'B\rrun /bin/g3md.bin\r' | ../p8xemu -l 400000000 -c g3d.img eeprom.bin 2>/dev/null \
    | LC_ALL=C tr -d '\0\r' | grep -A99 -m1 '^[0-9-]' > g3_md_got.txt || true
head -29 g3_md_got.txt > g3_md_got29.txt
diff g3_md_want.txt g3_md_got29.txt >/dev/null || {
    echo "want:"; cat g3_md_want.txt; echo "got:"; cat g3_md_got29.txt
    fail "muldiv vectors differ (software or MDU path)"; }

# ---- 2: cube frame 0 spot pixels (SOFTWARE path: `cube 1 s`) ----------------
printf 'B\rcube 1 s\r' > g3_cube.in
../p8xemu -N -i g3_cube.in -c g3d.img -l 300000000 -g g3_cube.ppm eeprom.bin \
    > g3_cube.out 2>/dev/null || true
grep -q DONE g3_cube.out || fail "cube did not print DONE"

python3 - <<'EOF' || exit 1
# Host replica of the frame-0 pipeline (angle 0: cos=120, sin=0).
def sd7(v):  return -((-v) >> 7) if v < 0 else v >> 7
def muldiv(a, b, c):
    if a == 0 or b == 0: return 0
    q = 32767 if c == 0 else min(abs(a) * abs(b) // abs(c), 32767)
    if (a < 0) ^ (b < 0) ^ (c < 0): q = -q
    return q
W = (-120, -120, 120, 120); V = (104, 0, 375, 271); D = 256
def mapx(sx): return V[0] + muldiv(sx - W[0], V[2] - V[0], W[2] - W[0])
def mapy(sy): return V[3] - muldiv(sy - W[1], V[3] - V[1], W[3] - W[1])
corners = []
for i in range(8):
    k = i & 3
    x = 90 if k in (1, 2) else -90
    y = 90 if k & 2 else -90
    z = 90 if i & 4 else -90
    rx = sd7(x * 120); rz = sd7(z * 120)          # Y rot, c=120 s=0
    ry = sd7(y * 120); rz = sd7(rz * 120) + 400   # X rot, then push in
    sx = muldiv(rx, D, rz); sy = muldiv(ry, D, rz)
    corners.append((mapx(sx), mapy(sy)))

data = open("g3_cube.ppm", "rb").read()
hdr = data.split(b"\n", 3); w, h = map(int, hdr[1].split()); px = hdr[3]
def expand(c):
    r5,g6,b5 = (c>>11)&31, (c>>5)&63, c&31
    return ((r5<<3)|(r5>>2), (g6<<2)|(g6>>4), (b5<<3)|(b5>>2))
def expect(x, y, c):
    o = (y * w + x) * 3
    if tuple(px[o:o+3]) != expand(c):
        raise SystemExit("C-G3D: (%d,%d) = %r, want %04X" % (x, y, tuple(px[o:o+3]), c))
# stage 9: the FRONT face is red, the BACK face green, connecting edges
# blue -- and blue draws last, so every cube corner is blue
for c in corners: expect(c[0], c[1], 0x001F)
expect((corners[0][0]+corners[1][0])//2, corners[0][1], 0xF800)   # front face
expect((corners[4][0]+corners[5][0])//2, corners[4][1], 0x07E0)   # back face
for (x, y) in [(239, 136), (50, 136), (430, 136), (10, 10), (470, 260)]:
    o = (y * w + x) * 3
    if px[o] or px[o+1] or px[o+2]:
        raise SystemExit("C-G3D: expected black at (%d,%d)" % (x, y))
print("spot pixels OK: blue corners + red/green ring midpoints at", corners)
EOF

# ---- 4: engine vs software -- IDENTITY BIT-EXACTNESS ------------------------
# The same pool rendered by the stage-7 software walk and by the geometry
# engine with its identity matrix must be BYTE-IDENTICAL framebuffers: two
# full pipelines, one answer. The pool mixes plain, near-clip, window-clip
# and rejected edges so every pipeline branch is in the comparison.
cat > g3_id_src.c <<'EOF'
//#use gfx
//#use g3d
int main() {
    char *a;
    a = argstr();
    while (*a == 32) { a = a + 1; }
    g3window(0 - 120, 0 - 120, 120, 120);
    g3view(104, 0, 375, 271);
    g3persp(256);
    g3clear();
    g3line(0 - 80, 0 - 60, 300, 80, 60, 500);     /* plain */
    g3line(0 - 90, 40, 0 - 30, 90, 40, 600);      /* crosses the near plane */
    g3line(0 - 500, 0, 260, 500, 0, 260);         /* clipped left AND right */
    g3line(0, 0 - 400, 300, 0, 400, 300);         /* clipped top AND bottom */
    g3line(10, 10, 0 - 50, 20, 20, 0 - 90);       /* wholly behind: dropped */
    g3line(2000, 2000, 200, 3000, 3000, 200);     /* off-window: rejected */
    g3line(0 - 110, 0 - 110, 280, 110, 110, 700); /* corner to corner */
    if (*a == '0') { g3has = 2; }        /* force the software walk */
    g3render();
    puts("IDONE");
    return 0;
}
EOF
cp g3_id_src.c $ROOT/os/commands/zz_g3id.c
python3 $ROOT/tools/clib.py $ROOT/os/commands/zz_g3id.c > g3_id.c
rm $ROOT/os/commands/zz_g3id.c
python3 $ROOT/compiler/p8cc.py g3_id.c -o g3_id.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py g3_id.asm -o g3_id.bin --base 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put g3d.img g3_id.bin --name /bin/g3id.bin --load 0x6A00 --exec 0x6A00 >/dev/null

printf 'B\rg3id 0\r' > g3_id0.in
../p8xemu -N -i g3_id0.in -c g3d.img -l 400000000 -g g3_id0.ppm eeprom.bin > g3_id0.out 2>/dev/null || true
grep -q IDONE g3_id0.out || fail "identity test (software) did not finish"
printf 'B\rg3id 1\r' > g3_id1.in
../p8xemu -N -i g3_id1.in -c g3d.img -l 400000000 -g g3_id1.ppm eeprom.bin > g3_id1.out 2>/dev/null || true
grep -q IDONE g3_id1.out || fail "identity test (engine) did not finish"
cmp g3_id0.ppm g3_id1.ppm || fail "engine identity render differs from the software walk"

# ---- 5: engine-path cube frame 0 -- replica of the ENGINE arithmetic --------
# cube v2 composes ONE matrix (muldiv cross terms, trunc) and the engine
# transform floor-shifts the accumulator -- microscopically different
# rounding from the software path's two sequential shifts, so this replica
# models the engine's own math and checks the engine cube's corners.
printf 'B\rcube 1\r' > g3_ec.in
../p8xemu -N -i g3_ec.in -c g3d.img -l 300000000 -g g3_ec.ppm eeprom.bin > g3_ec.out 2>/dev/null || true
grep -q DONE g3_ec.out || fail "engine cube did not print DONE"
python3 - <<'EOF' || exit 1
def muldiv(a, b, c):
    if a == 0 or b == 0: return 0
    q = 32767 if c == 0 else min(abs(a) * abs(b) // abs(c), 32767)
    if (a < 0) ^ (b < 0) ^ (c < 0): q = -q
    return q
W = (-120, -120, 120, 120); V = (104, 0, 375, 271); D = 256
def mapx(sx): return V[0] + muldiv(sx - W[0], V[2] - V[0], W[2] - W[0])
def mapy(sy): return V[3] - muldiv(sy - W[1], V[3] - V[1], W[3] - W[1])
# frame 0 matrix: c1=c2=240, s1=s2=0 (8.8)
m = [240,0,0, 0,240,0, 0,0,muldiv(240,240,256)]; t = (0,0,400)
corners = []
for i in range(8):
    k = i & 3
    v = (90 if k in (1,2) else -90, 90 if k & 2 else -90, 90 if i & 4 else -90)
    w = [ (m[r*3]*v[0] + m[r*3+1]*v[1] + m[r*3+2]*v[2] >> 8) + t[r] for r in range(3) ]
    sx = muldiv(w[0], D, w[2]); sy = muldiv(w[1], D, w[2])
    corners.append((mapx(sx), mapy(sy)))
data = open("g3_ec.ppm", "rb").read()
hdr = data.split(b"\n", 3); w_, h_ = map(int, hdr[1].split()); px = hdr[3]
def expand(c):
    r5,g6,b5 = (c>>11)&31, (c>>5)&63, c&31
    return ((r5<<3)|(r5>>2), (g6<<2)|(g6>>4), (b5<<3)|(b5>>2))
def expect(x, y, c):
    o = (y * w_ + x) * 3
    if tuple(px[o:o+3]) != expand(c):
        raise SystemExit("C-G3D: engine (%d,%d) = %r, want %04X" % (x, y, tuple(px[o:o+3]), c))
for c in corners: expect(c[0], c[1], 0x001F)
expect((corners[0][0]+corners[1][0])//2, corners[0][1], 0xF800)   # front face
expect((corners[4][0]+corners[5][0])//2, corners[4][1], 0x07E0)   # back face
print("engine cube frame-0 colours OK:", corners)
EOF

# ---- 5b: flipped frames must not expose the second page's garbage ----------
# The emulator powers on BOTH framebuffer pages with a fixed garbage pattern
# (undefined DRAM, like the board). cube's engine path clears both pages once
# before flipping; without that, the displayed sidebands (outside the
# viewport) alternate splash-cleared page 0 with raw page 1 -- the flashing
# stripes seen on hardware. cube 2 ends displaying the second page.
printf 'B\rcube 2\r' > g3_sb.in
../p8xemu -N -i g3_sb.in -c g3d.img -l 400000000 -g g3_sb.ppm eeprom.bin > g3_sb.out 2>/dev/null || true
grep -q DONE g3_sb.out || fail "sideband test cube did not finish"
python3 - <<'EOF' || exit 1
data = open("g3_sb.ppm", "rb").read()
hdr = data.split(b"\n", 3); w, h = map(int, hdr[1].split()); px = hdr[3]
for (x, y) in [(50, 136), (20, 20), (430, 136), (460, 250)]:
    o = (y * w + x) * 3
    if px[o] or px[o+1] or px[o+2]:
        raise SystemExit("C-G3D: flipped page sideband not cleared at (%d,%d)" % (x, y))
print("flipped-page sidebands clear OK")
EOF

# ---- 6: page-flip semantics -------------------------------------------------
# Two renders with flip: the DISPLAY page must show the SECOND frame and not
# the first. A third manual FLIP (GECMD 3) swaps back to the first. Ortho
# projection keeps the expected pixels trivial: edge A -> the line y=68,
# edge B -> y=204, both x 67..203 (window +/-100 onto viewport 0..271).
cat > g3_fl_src.c <<'EOF'
//#use gfx
//#use g3d
int frame(int y) {
    g3clear();
    g3line(0 - 50, y, 0, 50, y, 0);
    g3up();
    g3go();
    return 0;
}
int main() {
    char *a;
    a = argstr();
    while (*a == 32) { a = a + 1; }
    if (g3probe() == 0) { puts("NOENGINE"); return 1; }
    g3window(0 - 100, 0 - 100, 100, 100);
    g3view(0, 0, 271, 271);
    g3persp(0);                       /* orthographic */
    g3flags(3);                       /* erase + flip */
    frame(50);                        /* frame A: the y=68 line */
    frame(0 - 50);                    /* frame B: the y=204 line */
    if (*a == '2') { poke(0xFF43, 3); }   /* manual FLIP back to A */
    puts("FDONE");
    return 0;
}
EOF
cp g3_fl_src.c $ROOT/os/commands/zz_g3fl.c
python3 $ROOT/tools/clib.py $ROOT/os/commands/zz_g3fl.c > g3_fl.c
rm $ROOT/os/commands/zz_g3fl.c
python3 $ROOT/compiler/p8cc.py g3_fl.c -o g3_fl.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py g3_fl.asm -o g3_fl.bin --base 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put g3d.img g3_fl.bin --name /bin/g3fl.bin --load 0x6A00 --exec 0x6A00 >/dev/null

flip_check() {   # $1 = arg, $2 = visible y, $3 = hidden y
    printf "B\rg3fl $1\r" > g3_fl.in
    ../p8xemu -N -i g3_fl.in -c g3d.img -l 400000000 -g g3_fl.ppm eeprom.bin > g3_fl.out 2>/dev/null || true
    grep -q FDONE g3_fl.out || fail "flip test run $1 did not finish"
    python3 - "$2" "$3" <<'EOF' || exit 1
import sys
vis, hid = int(sys.argv[1]), int(sys.argv[2])
data = open("g3_fl.ppm", "rb").read()
hdr = data.split(b"\n", 3); w, h = map(int, hdr[1].split()); px = hdr[3]
def lum(x, y):
    o = (y * w + x) * 3
    return px[o] + px[o+1] + px[o+2]
if lum(135, vis) < 600: raise SystemExit("flip: expected the y=%d line visible" % vis)
if lum(135, hid) > 0:   raise SystemExit("flip: expected the y=%d line hidden" % hid)
EOF
}
flip_check 1 204 68      # after two flipped renders: frame B shows
flip_check 2 68 204      # a manual FLIP swaps back to frame A
echo "page-flip semantics OK"

# ---- 3: native-compiler (p8cc.c) parity for the libraries -------------------
cc -O2 -w $ROOT/compiler/p8cc.c -o g3_p8cc_host 2>/dev/null || fail "host cc could not build p8cc.c"
cat > g3_min_src.c <<'EOF'
//#use gfx
//#use g3d
int main() {
    if (gpresent() == 0) { puts("?No display"); return 1; }
    g3window(0 - 100, 0 - 100, 100, 100);
    g3view(0, 0, 271, 271);
    g3persp(256);
    g3clear();
    g3line(0 - 50, 0 - 50, 300, 50, 50, 300);
    g3render();
    return 0;
}
EOF
cp g3_min_src.c $ROOT/os/commands/zz_g3min.c
python3 $ROOT/tools/clib.py $ROOT/os/commands/zz_g3min.c > g3_min.c
rm $ROOT/os/commands/zz_g3min.c
./g3_p8cc_host < g3_min.c > g3_min.asm
[ "$(grep -c ERROR g3_min.asm)" = "0" ] || fail "lib_gfx/lib_g3d not native-p8cc.c clean"
python3 $ROOT/assembler/p8xasm.py g3_min.asm -o g3_min.bin --base 0x6A00 >/dev/null

echo "C-G3D TEST: PASS (muldiv vectors, cube frame-0 spot pixels, engine identity, engine cube, page flip, native parity)"
