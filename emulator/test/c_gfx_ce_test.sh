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
int pen(int c) { poke(65316, c & 255); poke(65325, (c / 256) & 255); return 0; }
int main() {
    pen(0); poke(65317, 5); gw();                 /* CLS black          */
    pen(65535); xy(100, 100); poke(65320, 50);    /* white circle r=50  */
    poke(65317, 7); gw();
    pen(63488); xy(200, 80); poke(65320, 30);     /* red fill r=30      */
    poke(65317, 8); gw();
    pen(2016); xy(300, 150);                      /* green ellipse      */
    poke(65320, 80); poke(65327, 40);             /*   rx=80 ry=40      */
    poke(65317, 10); gw();
    pen(31); xy(100, 200);                        /* blue ellipse fill  */
    poke(65320, 25); poke(65327, 60);             /*   rx=25 ry=60      */
    poke(65317, 11); gw();
    pen(65535); xy(20, 20); poke(65320, 1);       /* r=1 circle         */
    poke(65317, 7); gw();
    xy(30, 20); poke(65320, 0);                   /* r=0 circle         */
    poke(65317, 7); gw();
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
