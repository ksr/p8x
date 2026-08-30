#!/bin/sh
# Circle/ellipse device-level pixel proof: a C harness pokes the $FF20
# register interface directly (the BASIC statements' path) and the frame
# is dumped for the RTL cross-check (tb_gl_cpx.v renders the identical
# poke sequence through the real gfx + SDRAM stack). Radii chosen to
# walk BOTH midpoint regions in both aspect ratios, plus r=0/r=1 edges.
set -e
set -o pipefail
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-GFX-CE TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null

cat > gfx_ce.c <<'EOF'
int gw() { while (peek(65318) & 128) { } return 0; }   /* GSTAT busy */
int xy(int x, int y) {
    poke(65312, x & 255); poke(65321, (x / 256) & 255);
    poke(65313, y & 255); poke(65322, (y / 256) & 255);
    return 0;
}
int rr(int rx, int ry) { poke(65320, rx); poke(65327, ry); return 0; }
int pen(int c) { poke(65316, c & 255); poke(65325, (c / 256) & 255); return 0; }
int main() {
    /* CLS and CIRCLE are RETIRED (stage-10 diet): the clear is a
       full-screen BOXFILL and a circle is the ellipse rx=ry. r=0 draws
       NOTHING now (the ellipse convention; the old circle drew a dot). */
    pen(0); xy(0, 0);
    poke(65314, 223); poke(65323, 1);             /* X1 = 479           */
    poke(65315, 15); poke(65324, 1);              /* Y1 = 271           */
    poke(65317, 4); gw();                         /* BOXFILL: the clear */
    pen(65535); xy(100, 100); rr(50, 50);         /* white circle r=50  */
    poke(65317, 10); gw();
    pen(63488); xy(200, 80); rr(30, 30);          /* red fill r=30      */
    poke(65317, 11); gw();
    pen(2016); xy(300, 150); rr(80, 40);          /* green ellipse      */
    poke(65317, 10); gw();
    pen(31); xy(100, 200); rr(25, 60);            /* blue ellipse fill  */
    poke(65317, 11); gw();
    pen(65535); xy(20, 20); rr(1, 1);             /* r=1                */
    poke(65317, 10); gw();
    xy(30, 20); rr(0, 0);                         /* r=0: nothing       */
    poke(65317, 10); gw();
    puts("CEDONE");
    return 0;
}
EOF
python3 $ROOT/compiler/p8cc.py gfx_ce.c -o gfx_ce.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py gfx_ce.asm -o gfx_ce.bin --base 0x6A00 >/dev/null

rm -f gfx_ce.img
python3 $ROOT/tools/p8xfs.py create gfx_ce.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   gfx_ce.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  gfx_ce.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    gfx_ce.img gfx_ce.bin --name /bin/gfxce.bin --load 0x6A00 --exec 0x6A00 >/dev/null
printf 'B\rrun /bin/gfxce.bin\r' > gfx_ce.in
../p8xemu -N -i gfx_ce.in -c gfx_ce.img -l 400000000 -g gfx_ce.ppm eeprom.bin > gfx_ce.out 2>/dev/null || true
grep -q "CEDONE" gfx_ce.out || fail "harness did not finish"
[ -f gfx_ce.ppm ] || fail "no frame dumped"
echo "C-GFX-CE TEST: PASS (circle/ellipse frame dumped for the RTL cross-check)"
