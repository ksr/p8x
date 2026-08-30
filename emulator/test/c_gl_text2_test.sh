#!/bin/sh
# Stage-10k text completion: TJUST h v justifies about the current point
# in MODEL units (so TSIZE/TANGLE transform the justification too);
# TEXTP is the same engine as TEXT (P8X text IS the PGC's "programmable"
# text); and TEXT records into command lists and replays (the glyph
# replay is its own context since 10k). The streamer pumps the font,
# then the scene, like c_gl_text_test.
set -e
set -o pipefail
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-GL-TEXT2 TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null
python3 $ROOT/generators/gen_font.py >/dev/null

cat > gl_t2.gl <<'EOF'
CA 
RF CLS 0 0 0
PRO 0
WI 0 479 0 271
VWP 0 479 0 271
C 31 63 0
TJ 2 1
M3 240 200 0
TX "CENTER"
TJ 3 1
M3 240 150 0
TXP "RIGHT"
TJ 1 1
CB 5
C 0 63 31
M3 100 100 0
TX "LIST"
CE 
CR 5
EOF
printf 'CX ' >> gl_t2.gl

cat > gl_t2.c <<'EOF'
//#use abi
int glb(int v) { while (peek(65361) & 128) { } poke(65360, v); return 0; }
int stream(char *path) {
    int c;
    bios(FRESOLVE, path, 0);
    if (bios(FOPEN, RDBUF, 0) & 256) { puts("?open"); return 1; }
    c = bios(FGETB, 0, 0);
    while ((c & 256) == 0) {
        glb(c & 255);
        c = bios(FGETB, 0, 0);
    }
    return 0;
}
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
    int e;
    if (stream("/FONT.GL")) { return 1; }
    if (stream("/GLT2.GL")) { return 1; }
    e = peek(65363);
    while (e) { pnum(e); e = peek(65363); }
    puts("T2DONE");
    return 0;
}
EOF
cp $ROOT/os/commands/lib_abi.c .
python3 $ROOT/tools/clib.py gl_t2.c -o gl_t2.pp.c
python3 $ROOT/compiler/p8cc.py gl_t2.pp.c -o gl_t2.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py gl_t2.asm -o gl_t2.bin --base 0x6A00 >/dev/null

rm -f gl_t2.img
python3 $ROOT/tools/p8xfs.py create gl_t2.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   gl_t2.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  gl_t2.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    gl_t2.img gl_t2.bin --name /bin/glt2.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    gl_t2.img $ROOT/os/font.gl --name /FONT.GL >/dev/null
python3 $ROOT/tools/p8xfs.py put    gl_t2.img gl_t2.gl --name /GLT2.GL >/dev/null
printf 'B\rrun /bin/glt2.bin\r' > gl_t2.in
../p8xemu -N -i gl_t2.in -c gl_t2.img -l 900000000 -g gl_t2.ppm eeprom.bin > gl_t2.out 2>/dev/null || true
grep -q "T2DONE" gl_t2.out || fail "streamer did not finish"
tr -d '\0\r' < gl_t2.out | grep -qE '^[0-9]+$' && fail "GL errors logged"

python3 - <<'EOF' || exit 1
d = open("gl_t2.ppm","rb").read(); px = d.split(b"\n",3)[3]
def ink_range(wy0, wy1, color):
    xs = []
    for wy in range(wy0, wy1+1):
        y = 271 - wy
        for x in range(480):
            if tuple(px[(y*480+x)*3:(y*480+x)*3+3]) == color: xs.append(x)
    return (min(xs), max(xs)) if xs else None
YEL, TEAL = (255,255,0), (0,255,255)
# "CENTER": 6 chars x 6 advance = 36 units at 1x, centred on x=240:
# glyph ink spans [222, 222+5*6+4] = [222, 256]
r = ink_range(200, 206, YEL)
assert r, "CENTER not drawn"
assert 220 <= r[0] <= 224, "CENTER left edge %r (want ~222)" % (r,)
assert 254 <= r[1] <= 258, "CENTER right edge %r (want ~256)" % (r,)
# "RIGHT": 5 chars, right-justified at 240: spans [210, 240-2]
r = ink_range(150, 156, YEL)
assert r, "RIGHT not drawn"
assert 208 <= r[0] <= 212, "RIGHT left edge %r (want ~210)" % (r,)
assert r[1] <= 240, "RIGHT overruns the anchor: %r" % (r,)
# the recorded list drew "LIST" teal from (100,100), left-justified
r = ink_range(100, 106, TEAL)
assert r, "LIST replay drew nothing"
assert r[0] == 100, "LIST left edge %r (want 100)" % (r,)
assert 120 <= r[1] <= 124, "LIST right edge %r (want ~122: ALL FOUR chars)" % (r,)
EOF
echo "C-GL-TEXT2 TEST: PASS (TJUST centre/right in model units, TEXTP alias, TEXT recorded + replayed from a list)"
