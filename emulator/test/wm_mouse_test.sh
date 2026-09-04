#!/bin/sh
# The resident WM kernel's MOUSE events (wk_run's xterm SGR parsing).
#   A launcher opens one window and calls wk_run. An SGR mouse press is
#   fed on the console -- ESC [ < b ; x ; y M -- and the resident loop
#   parses it, maps the terminal cell to the panel via the MDU, and moves
#   the top window's bottom-left there. ^D exits. This proves the SGR
#   parse + cell->pixel map + MDU path in the resident kernel.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "WM-MOUSE TEST: FAIL — $1"; exit 1; }

WMBASE=$(python3 -c "import sys; sys.path.insert(0,'$ROOT/generators'); import memmap; print(memmap.WMBASE)")
WK_OPEN=$((WMBASE + 3))
WK_RUN=$((WMBASE + 9))

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/wmkernel.asm -o wmk.bin --base $WMBASE >/dev/null

cat > ms_run.c <<EOF
char param[22];
int setw(int x, int y, int w, int h, int list, char *t) {
    int i;
    param[0]=x&255; param[1]=(x/256)&255;
    param[2]=y&255; param[3]=(y/256)&255;
    param[4]=w&255; param[5]=(w/256)&255;
    param[6]=h&255; param[7]=(h/256)&255;
    param[8]=list;
    i=0; while (t[i] && i<12) { param[10+i]=t[i]; i=i+1; }
    param[9]=i;
    while (i<12) { param[10+i]=0; i=i+1; }
    bios($WK_OPEN, param, 0);
    return 0;
}
int main() {
    bios(0x0133, "/bin/wmk.bin", 0);
    if (bios(0x0118, 0, 0) & 256) { puts("?NOKERNEL"); return 1; }
    bios(0x013F, $WMBASE, 0);
    bios($WMBASE, 0, 0);
    setw(100, 100, 150, 100, 0, "WIN");
    bios($WK_RUN, 0, 0);
    puts("RUN-DONE");
    return 0;
}
EOF
python3 $ROOT/compiler/p8cc.py ms_run.c -o ms_run.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py ms_run.asm -o ms_run.bin --base 0x6A00 >/dev/null

rm -f ms.img
python3 $ROOT/tools/p8xfs.py create ms.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   ms.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  ms.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    ms.img wmk.bin --name /bin/wmk.bin --load $WMBASE --exec $WMBASE >/dev/null
python3 $ROOT/tools/p8xfs.py put    ms.img ms_run.bin --name /bin/ms.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    ms.img $ROOT/os/font.gl --name /FONT.GL --load 0 --exec 0 >/dev/null

# a mouse PRESS at cell (30,15): px=(30-1)*6=174, py=271-(15-1)*11=117
printf 'B\rrun /bin/ms.bin\r\033[<0;30;15M\004' > ms.in
../p8xemu -N -i ms.in -c ms.img -l 900000000 -g ms.ppm eeprom.bin > ms.out 2>/dev/null || true
grep -q "RUN-DONE" ms.out || fail "the event loop did not return on ^D"

python3 - <<'EOF' || exit 1
d = open("ms.ppm", "rb").read()
px = d.split(b"\n", 3)[3]
def p(x, wy):
    i = ((271 - wy) * 480 + x) * 3
    return tuple(px[i:i+3])
GREY = (49, 48, 74)
# the window's bottom-left border corner should now be at ~(174,117)
assert p(174,117)==(255,255,255), "window not at the mouse-mapped spot (174,117): %r" % (p(174,117),)
# and its start position (100,100) is vacated to desktop
assert p(100,100)==GREY,          "window did not leave its start (100,100): %r" % (p(100,100),)
print("the resident loop parsed an SGR mouse press and moved the window to the cursor")
EOF

echo "WM-MOUSE TEST: PASS (resident kernel: xterm SGR mouse parse + MDU cell->pixel map)"
