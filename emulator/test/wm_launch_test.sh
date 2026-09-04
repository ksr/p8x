#!/bin/sh
# Launch-and-resume: the PAYOFF of the resident window manager.
#   A launcher opens two windows and enters the resident event loop
#   (wk_run). The 'l' key makes the loop SYS_EXEC a WM-client program
#   (wapp) into the TPA -- replacing the launcher. wapp opens a THIRD
#   window through the RESIDENT kernel and calls wk_run to resume the
#   desktop. Because the kernel and its window records live at WMBASE
#   (above the TPA), the launcher's two windows SURVIVE the launch
#   untouched -- so the resumed desktop shows all three. That is what
#   the whole resident architecture was for: launching an app no longer
#   destroys the window manager.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "WM-LAUNCH TEST: FAIL — $1"; exit 1; }

WMBASE=$(python3 -c "import sys; sys.path.insert(0,'$ROOT/generators'); import memmap; print(memmap.WMBASE)")
WK_OPEN=$((WMBASE + 3))
WK_RUN=$((WMBASE + 9))
WK_SIG=$((WMBASE + 12))

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/wmkernel.asm -o wmk.bin --base $WMBASE >/dev/null

# a shared setw + main tail; both programs open windows through the kernel
SETW='char param[22];
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
    bios('$WK_OPEN', param, 0);
    return 0;
}'

# the launcher: load the kernel, open two windows, run the loop
cat > wl_run.c <<EOF
$SETW
int main() {
    bios(0x0133, "/bin/wmk.bin", 0);
    if (bios(0x0118, 0, 0) & 256) { puts("?NOKERNEL"); return 1; }
    bios(0x013F, $WMBASE, 0);
    bios($WMBASE, 0, 0);                            /* wk_init */
    setw(40, 40, 210, 150, 0, "SHAPES");
    setw(190, 90, 240, 140, 0, "TERM");
    bios($WK_RUN, 0, 0);                            /* the resident loop */
    puts("RUN-DONE");
    return 0;
}
EOF

# the WM-client app: kernel is already resident -- add a window and RESUME.
# It must NOT wk_init (that would clear the launcher's windows).
cat > wl_app.c <<EOF
$SETW
int main() {
    if (peek($WK_SIG) != 0x57) { puts("?NOKERNEL"); return 1; }
    setw(300, 30, 140, 120, 0, "APP");             /* a third window */
    bios($WK_RUN, 0, 0);                            /* resume the desktop */
    puts("APP-DONE");
    return 0;
}
EOF

for p in wl_run wl_app; do
    python3 $ROOT/compiler/p8cc.py $p.c -o $p.asm >/dev/null
    python3 $ROOT/assembler/p8xasm.py $p.asm -o $p.bin --base 0x6A00 >/dev/null
done

rm -f wl.img
python3 $ROOT/tools/p8xfs.py create wl.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   wl.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  wl.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    wl.img wmk.bin --name /bin/wmk.bin --load $WMBASE --exec $WMBASE >/dev/null
python3 $ROOT/tools/p8xfs.py put    wl.img wl_run.bin --name /bin/wl.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    wl.img wl_app.bin --name /bin/wapp.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    wl.img $ROOT/os/font.gl --name /FONT.GL --load 0 --exec 0 >/dev/null

# run the launcher; press 'l' (launch wapp) inside the loop; then ^D
printf 'B\rrun /bin/wl.bin\rl\004' > wl.in
../p8xemu -N -i wl.in -c wl.img -l 1500000000 -g wl.ppm eeprom.bin > wl.out 2>/dev/null || true
grep -q "RUN-DONE\|APP-DONE" wl.out || fail "the session did not finish"

python3 - <<'EOF' || exit 1
d = open("wl.ppm", "rb").read()
px = d.split(b"\n", 3)[3]
def p(x, wy):
    i = ((271 - wy) * 480 + x) * 3
    return tuple(px[i:i+3])
# all THREE windows must be on screen after the launch+resume:
# the two the LAUNCHER opened (survived the app via the resident kernel)...
assert p(40,40)==(255,255,255),   "SHAPES gone after launch (resident records lost): %r" % (p(40,40),)
assert p(190,90)==(255,255,255),  "TERM gone after launch: %r" % (p(190,90),)
# ...and the one the LAUNCHED app added through the resident kernel.
assert p(300,30)==(255,255,255),  "APP window (from the launched program) missing: %r" % (p(300,30),)
print("launcher's two windows SURVIVED the app launch; the app added a third --")
print("the resident WM was not destroyed by launching a program")
EOF

echo "WM-LAUNCH TEST: PASS (launch-and-resume: the resident WM survives launching an app)"
