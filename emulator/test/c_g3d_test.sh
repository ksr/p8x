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

# ---- 2: cube frame 0 spot pixels -------------------------------------------
printf 'B\rcube 1\r' > g3_cube.in
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
def white(x, y):
    o = (y * w + x) * 3
    return px[o] > 200 and px[o+1] > 200 and px[o+2] > 200
bad = [c for c in corners if not white(*c)]
if bad: raise SystemExit("C-G3D: corners not white: %r (all: %r)" % (bad, corners))
for (x, y) in [(239, 136), (50, 136), (430, 136), (10, 10), (470, 260)]:
    o = (y * w + x) * 3
    if px[o] or px[o+1] or px[o+2]:
        raise SystemExit("C-G3D: expected black at (%d,%d)" % (x, y))
print("spot pixels OK: 8 corners white at", corners)
EOF

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

echo "C-G3D TEST: PASS (muldiv vectors, cube frame-0 spot pixels, native parity)"
