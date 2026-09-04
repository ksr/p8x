#!/bin/sh
# The resident WM kernel's EVENT LOOP (wk_run, WMBASE+9), keyboard slice.
#   A launcher loads the kernel, opens one window, and calls wk_run -- the
#   RESIDENT event loop. Arrow keys (ESC [ C ...) are fed on the console;
#   the loop moves the top window and repaints, all from resident code.
#   ^D exits the loop. The window must end up shifted right by the arrows.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "WM-EVENTS TEST: FAIL — $1"; exit 1; }

WMBASE=$(python3 -c "import sys; sys.path.insert(0,'$ROOT/generators'); import memmap; print(memmap.WMBASE)")
WK_OPEN=$((WMBASE + 3))
WK_RUN=$((WMBASE + 9))

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/wmkernel.asm -o wmk.bin --base $WMBASE >/dev/null

cat > ev_run.c <<EOF
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
    bios(0x0133, "/bin/wmk.bin", 0);               /* FRESOLVE */
    if (bios(0x0118, 0, 0) & 256) { puts("?NOKERNEL"); return 1; }  /* FFIND */
    bios(0x013F, $WMBASE, 0);                       /* FLOADAT -> WMBASE */
    bios($WMBASE, 0, 0);                            /* wk_init */
    setw(100, 100, 150, 100, 0, "WIN");
    bios($WK_RUN, 0, 0);                            /* the resident event loop */
    puts("RUN-DONE");
    return 0;
}
EOF
python3 $ROOT/compiler/p8cc.py ev_run.c -o ev_run.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py ev_run.asm -o ev_run.bin --base 0x6A00 >/dev/null

rm -f ev.img
python3 $ROOT/tools/p8xfs.py create ev.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   ev.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  ev.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    ev.img wmk.bin --name /bin/wmk.bin --load $WMBASE --exec $WMBASE >/dev/null
python3 $ROOT/tools/p8xfs.py put    ev.img ev_run.bin --name /bin/ev.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    ev.img $ROOT/os/font.gl --name /FONT.GL --load 0 --exec 0 >/dev/null

# run the app; then FOUR right-arrows (ESC [ C) into the resident loop, then ^D
printf 'B\rrun /bin/ev.bin\r\033[C\033[C\033[C\033[C\004' > ev.in
../p8xemu -N -i ev.in -c ev.img -l 900000000 -g ev.ppm eeprom.bin > ev.out 2>/dev/null || true
grep -q "RUN-DONE" ev.out || fail "the event loop did not return on ^D"

python3 - <<'EOF' || exit 1
d = open("ev.ppm", "rb").read()
px = d.split(b"\n", 3)[3]
def p(x, wy):
    i = ((271 - wy) * 480 + x) * 3
    return tuple(px[i:i+3])
GREY = (49, 48, 74)
# WIN started at (100,100); 4 right arrows = +32 -> (132,100).
# The new bottom-left border corner is at (132,100), white...
assert p(132,100)==(255,255,255), "window not at the moved position (132,100): %r" % (p(132,100),)
# ...and the OLD corner column (x=100) is vacated to desktop grey.
assert p(100,100)==GREY,          "window did not leave its old spot (100,100): %r" % (p(100,100),)
print("the resident event loop moved the window right by 4 arrow keys (100 -> 132)")
EOF

echo "WM-EVENTS TEST: PASS (resident kernel event loop: arrow keys move the window, ^D exits)"
