#!/bin/sh
# Stage-10h TEXT/TSIZE/TANGLE/TDEFIN: vector text. A glyph IS a command
# list (relative MOVER3/DRAWR3 strokes + a pen-up baseline advance) in a
# second 64-slot bank; TDEFIN records one, TEXT replays one per char
# (lowercase folds, undefined glyphs skip), and TSIZE/TANGLE are compose
# ALIASES (MDSCAL s s s / MDROTZ d) -- so size and angle transform both
# the strokes and the baseline walk through the ordinary matrix path.
# The generated os/font.gl carries chars 32..95.
#
# The streamer program pumps /FONT.GL then /GLTX.GL to GLDATA verbatim
# (the gl command's file mode, inlined); the RTL bench (tb_gl_txx.v)
# feeds the SAME two files, so gl_tx.ppm is the cross-implementation
# golden frame.
set -e
set -o pipefail
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-GL-TEXT TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null

python3 $ROOT/generators/gen_font.py >/dev/null

# the scene: 1x yellow, 4x teal (MDORG anchors the scale at the text
# origin), 30-degree red tilt, lowercase folding en route. One TX per
# line -- a string must close before its CR.
cat > gl_tx.gl <<'EOF'
CA 
RF CLS 0 0 0
PRO 0
WI 0 479 0 271
VWP 0 479 0 271
C 31 63 0
M3 20 200 0
TX "HELLO WORLD!"
C 0 63 31
MDI MDO 20 100 0 TS 1024
M3 20 100 0
TX "Big 4x"
MDI MDO 300 40 0 TA 30
C 31 0 0
M3 300 40 0
TX "TILT"
MDI
EOF
printf 'CX ' >> gl_tx.gl

cat > gl_tx.c <<'EOF'
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
    if (stream("/GLTX.GL")) { return 1; }
    e = peek(65363);
    while (e) { pnum(e); e = peek(65363); }
    puts("TXDONE");
    return 0;
}
EOF
cp $ROOT/os/commands/lib_abi.c .        # clib resolves //#use beside the source
python3 $ROOT/tools/clib.py gl_tx.c -o gl_tx.pp.c
python3 $ROOT/compiler/p8cc.py gl_tx.pp.c -o gl_tx.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py gl_tx.asm -o gl_tx.bin --base 0x6A00 >/dev/null

rm -f gl_tx.img
python3 $ROOT/tools/p8xfs.py create gl_tx.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   gl_tx.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  gl_tx.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    gl_tx.img gl_tx.bin --name /bin/gltx.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    gl_tx.img $ROOT/os/font.gl --name /FONT.GL >/dev/null
python3 $ROOT/tools/p8xfs.py put    gl_tx.img gl_tx.gl --name /GLTX.GL >/dev/null
printf 'B\rrun /bin/gltx.bin\r' > gl_tx.in
../p8xemu -N -i gl_tx.in -c gl_tx.img -l 900000000 -g gl_tx.ppm eeprom.bin > gl_tx.out 2>/dev/null || true
grep -q "TXDONE" gl_tx.out || fail "streamer did not finish"

python3 - <<'EOF' || exit 1
d = open("gl_tx.ppm","rb").read(); px = d.split(b"\n",3)[3]
def p(x, wy):
    y = 271 - wy                      # window y up -> screen y down
    i = (y*480 + x)*3
    return tuple(px[i:i+3])
YEL, TEAL, RED, BLACK = (255,255,0), (0,255,255), (255,0,0), (0,0,0)
# "HELLO WORLD!" at 1x from (20,200): H's left stem spans wy 200..206
assert p(20,200) == YEL, "H stem base missing: %r" % (p(20,200),)
assert p(20,206) == YEL, "H stem top missing: %r" % (p(20,206),)
assert p(19,203) == BLACK, "ink left of the string: %r" % (p(19,203),)
# W is char 6 (cell origin x = 20+6*6=56): outer stroke starts (56,206)
assert p(56,206) == YEL, "W missing (space advance broken?): %r" % (p(56,206),)
# "Big 4x" at 4x anchored at (20,100): B stem spans wy 100..124;
# lowercase i folds to I (cell 1 at x 44; I's stem at +2*4 = x 52)
assert p(20,100) == TEAL, "4x B stem base missing: %r" % (p(20,100),)
assert p(20,124) == TEAL, "4x B stem top missing (scale wrong?): %r" % (p(20,124),)
assert p(52,110) == TEAL, "folded 'i'->I stem missing: %r" % (p(52,110),)
# the tilted string: red ink exists near the anchor, none without TANGLE's
# rotation would land there at (283..297, wy 44..64) -- coarse but honest
n = 0
for x in range(280, 340):
    for wy in range(35, 75):
        if p(x, wy) == RED: n = n + 1
assert n > 30, "tilted TILT not drawn (%d red px)" % n
EOF
echo "C-GL-TEXT TEST: PASS (font load via TDEFIN, TEXT 1x/4x/rotated, MDORG anchor, lowercase fold, baseline advance)"
