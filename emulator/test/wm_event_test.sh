#!/bin/sh
# SYS_WKEVENT: the CLIENT-DRIVEN loop -- the split that lets the rich desktop
# live in the client while the kernel stays a small resident core.
#   A client opens a window, then runs ITS OWN loop over SYS_WKEVENT. The
#   kernel handles the events it owns (here: a right-arrow moves the window)
#   and returns 0 for them; it returns an unowned key byte for the client to
#   act on (here: 'x', which the client echoes to the console); and it returns
#   carry set for quit (^D). We feed arrow, 'x', ^D and check: the window
#   MOVED (kernel handled the arrow) AND the console shows the client saw 'x'.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "WM-EVENT TEST: FAIL — $1"; exit 1; }

# WM syscalls: JMP table in os/p8xos.asm right after SYS_EXEC ($2024)
WK_INIT=0x2027
WK_OPEN=0x202A
WK_PAINT=0x202D
WK_EVENT=0x203C
WK_ARG=0x2042

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null

cat > ep_run.c <<EOF
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
    int k; int going;
    bios($WK_INIT, 0, 0);
    setw(100, 100, 150, 100, 0, "WIN");
    bios($WK_PAINT, 0, 0);
    going = 1;
    while (going) {
        k = bios($WK_EVENT, 0, 0);        /* one event */
        if (k & 256) { going = 0; }       /* carry set -> quit */
        else if (k == 0) { }              /* 0 -> the kernel handled it */
        else if (k == 1) { putchar(bios($WK_ARG, 0, 0)); }  /* 1 -> unowned key */
    }
    puts("EV-DONE");
    return 0;
}
EOF
python3 $ROOT/compiler/p8cc.py ep_run.c -o ep_run.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py ep_run.asm -o ep_run.bin --base 0x6A00 >/dev/null

rm -f ep.img
python3 $ROOT/tools/p8xfs.py create ep.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   ep.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  ep.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    ep.img ep_run.bin --name /bin/ep.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    ep.img $ROOT/os/font.gl --name /FONT.GL --load 0 --exec 0 >/dev/null

# right-arrow (kernel: move the window +8) ; 'x' (unowned: client echoes) ; ^D
printf 'B\rrun /bin/ep.bin\r\033[C\033[Cx\004' > ep.in
../p8xemu -N -i ep.in -c ep.img -l 1100000000 -g ep.ppm eeprom.bin > ep.out 2>/dev/null || true
grep -q "EV-DONE" ep.out || fail "the client loop did not finish"

# the client must have seen the unowned 'x' and echoed it
tr -d '\0' < ep.out | grep -q "x" || fail "the client did not receive the unowned key 'x'"

python3 - <<'EOF' || exit 1
d = open("ep.ppm", "rb").read()
px = d.split(b"\n", 3)[3]
def p(x, wy):
    i = ((271 - wy) * 480 + x) * 3
    return tuple(px[i:i+3])
GREY = (49, 48, 74)
# WIN started at x=100; two right-arrows = +16, so its border corner is at
# (116,100) -- the kernel handled those arrow events inside SYS_WKEVENT.
assert p(116,100)==(255,255,255), "window not moved by kernel-handled arrows (116,100): %r" % (p(116,100),)
assert p(100,100)==GREY,          "window did not leave its start (100,100): %r" % (p(100,100),)
print("the client drove the loop over SYS_WKEVENT: the kernel handled the arrows")
print("(window moved) and handed the client the unowned 'x' key (echoed)")
EOF

echo "WM-EVENT TEST: PASS (SYS_WKEVENT: client-driven loop; kernel handles its events, returns unowned keys)"
