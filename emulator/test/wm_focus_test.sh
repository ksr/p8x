#!/bin/sh
# Focus + close boxes in the RESIDENT kernel (migrated from desk's lib_wm).
#   A launcher opens A (40,40 210x150) then B (190,90 240x140); B is on top.
#   Focus IS the top record: it draws a WHITE title bar, the others GREY.
#   Run 1: TAB raises the bottom window (A) to the top. At (200,180) -- inside
#          A's title bar AND inside B's body -- B's black body must have been
#          replaced by A's now-WHITE bar; and B's bar at (300,220) must have
#          gone GREY (it lost focus).
#   Run 2: TAB, then a mouse press+release on A's close box (cell 9,9 ->
#          panel 48,183, inside the 9x9 box at 43..51 x 178..186). The kernel
#          raises A (already top), sees the box, and POPS the record: A's old
#          corner (45,45) shows desktop grey, and B -- sole window again -- is
#          focused, its bar white.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "WM-FOCUS TEST: FAIL — $1"; exit 1; }

# WM syscalls: JMP table in os/p8xos.asm right after SYS_EXEC ($2024)
WK_INIT=0x2027
WK_OPEN=0x202A
WK_RUN=0x2030

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null

cat > fc_run.c <<EOF
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
    bios($WK_INIT, 0, 0);
    setw(40, 40, 210, 150, 0, "AAA");
    setw(190, 90, 240, 140, 0, "BBB");          /* B is on top (focused) */
    bios($WK_RUN, 0, 0);
    puts("RUN-DONE");
    return 0;
}
EOF
python3 $ROOT/compiler/p8cc.py fc_run.c -o fc_run.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py fc_run.asm -o fc_run.bin --base 0x6A00 >/dev/null

rm -f fc.img
python3 $ROOT/tools/p8xfs.py create fc.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   fc.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  fc.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    fc.img fc_run.bin --name /bin/fc.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    fc.img $ROOT/os/font.gl --name /FONT.GL --load 0 --exec 0 >/dev/null

# run 1: TAB (raise A over B), then ^D
printf 'B\rrun /bin/fc.bin\r\011\004' > fc1.in
../p8xemu -N -i fc1.in -c fc.img -l 900000000 -g fc1.ppm eeprom.bin > fc1.out 2>/dev/null || true
grep -q "RUN-DONE" fc1.out || fail "run 1: the event loop did not return on ^D"

# run 2: TAB, press+release the close box of A (now on top), then ^D
printf 'B\rrun /bin/fc.bin\r\011\033[<0;9;9M\033[<0;9;9m\004' > fc2.in
../p8xemu -N -i fc2.in -c fc.img -l 1100000000 -g fc2.ppm eeprom.bin > fc2.out 2>/dev/null || true
grep -q "RUN-DONE" fc2.out || fail "run 2: the event loop did not return on ^D"

python3 - <<'EOF' || exit 1
def load(f):
    return open(f, "rb").read().split(b"\n", 3)[3]
def p(px, x, wy):
    i = ((271 - wy) * 480 + x) * 3
    return tuple(px[i:i+3])
WHITE = (255,255,255); GREY = (132,130,132); DESK = (49,48,74); BLACK = (0,0,0)
a = load("fc1.ppm")
# TAB raised A: its (focused, white) title bar now covers B's body at (200,180)
assert p(a,200,180)==WHITE, "TAB: A's white bar not on top of B at (200,180): %r" % (p(a,200,180),)
# ...and B, no longer focused, draws a GREY bar
assert p(a,300,220)==GREY,  "TAB: B's bar did not go grey (unfocused): %r" % (p(a,300,220),)
# A's close box is black on its bar
assert p(a,47,182)==BLACK,  "A's close box not drawn: %r" % (p(a,47,182),)
b = load("fc2.ppm")
# the close box press POPPED A: its old corner is desktop again...
assert p(b,45,45)==DESK,    "close: A still present at (45,45): %r" % (p(b,45,45),)
# ...and B, the sole window, is focused (white bar) and intact
assert p(b,300,220)==WHITE, "close: B not refocused (bar not white): %r" % (p(b,300,220),)
assert p(b,190,90)==WHITE,  "close: B's border corner missing: %r" % (p(b,190,90),)
print("TAB raised A over B (white bar on top, B's bar grey); the close box popped A;")
print("B was refocused -- focus and close boxes live in the resident kernel")
EOF

echo "WM-FOCUS TEST: PASS (resident kernel: TAB focus cycling, focused/grey title bars, close boxes)"
