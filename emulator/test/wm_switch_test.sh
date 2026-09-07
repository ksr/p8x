#!/bin/sh
# The switcher's core: PER-WINDOW STATE that the resident kernel holds
# across app launches. This machine runs one program in the TPA at a
# time, so a true suspend/resume switcher would swap whole ~37.9KB TPAs to
# disk per switch -- impractical. The realistic "state-only" variant: each
# window owns a small state blob (wk_save/wk_load) the resident kernel
# keeps, so an app can save where it was and pick up there next time it
# is launched into that window. Apps thus REMEMBER their state as you
# switch between them.
#
#   A launcher opens a window and runs the loop. Pressing 'l' three times
#   launches an app that LOADS window 0's counter, increments it, SAVES
#   it, and resumes. After three launches the counter is 3 -- proving the
#   state survived every launch, held by the resident kernel. A checker
#   program reads it back.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "WM-SWITCH TEST: FAIL — $1"; exit 1; }

WMBASE=$(python3 -c "import sys; sys.path.insert(0,'$ROOT/generators'); import memmap; print(memmap.WMBASE)")
WK_OPEN=$((WMBASE + 3))
WK_RUN=$((WMBASE + 9))
WK_SAVE=$((WMBASE + 12))
WK_LOAD=$((WMBASE + 15))
WK_SIG=$((WMBASE + 18))

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/wmkernel.asm -o wmk.bin --base $WMBASE >/dev/null

# the launcher: load the kernel, open one window, run the loop
cat > sw_run.c <<EOF
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
    bios($WMBASE, 0, 0);                            /* wk_init */
    setw(60, 60, 200, 150, 0, "COUNT");
    bios($WK_RUN, 0, 0);
    puts("RUN-DONE");
    return 0;
}
EOF

# the WM-client app: load window 0's counter, ++ it, save it, resume.
cat > sw_app.c <<EOF
char blob[4];
int main() {
    if (peek($WK_SIG) != 0x57) { return 1; }
    bios($WK_LOAD, blob, 0);                        /* window 0 state -> blob */
    blob[0] = blob[0] + 1;                          /* remember one more visit */
    bios($WK_SAVE, blob, 0);                        /* keep it in the kernel */
    bios($WK_RUN, 0, 0);                            /* resume the desktop */
    return 0;
}
EOF

# the checker: read window 0's counter back and print it
cat > sw_chk.c <<EOF
char blob[4];
int main() {
    if (peek($WK_SIG) != 0x57) { puts("?NOKERNEL"); return 1; }
    bios($WK_LOAD, blob, 0);
    putchar('N'); putchar('0' + (blob[0] & 255)); putchar(10);
    return 0;
}
EOF

for p in sw_run sw_app sw_chk; do
    python3 $ROOT/compiler/p8cc.py $p.c -o $p.asm >/dev/null
    python3 $ROOT/assembler/p8xasm.py $p.asm -o $p.bin --base 0x6A00 >/dev/null
done

rm -f sw.img
python3 $ROOT/tools/p8xfs.py create sw.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   sw.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  sw.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    sw.img wmk.bin --name /bin/wmk.bin --load $WMBASE --exec $WMBASE >/dev/null
python3 $ROOT/tools/p8xfs.py put    sw.img sw_run.bin --name /bin/sw.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    sw.img sw_app.bin --name /bin/wapp.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    sw.img sw_chk.bin --name /bin/chk.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    sw.img $ROOT/os/font.gl --name /FONT.GL --load 0 --exec 0 >/dev/null

# launch the app THREE times (l l l) from inside the resident loop, ^D to
# leave the loop, then run the checker -- the counter must read 3
printf 'B\rrun /bin/sw.bin\rlll\004run /bin/chk.bin\r' > sw.in
../p8xemu -N -i sw.in -c sw.img -l 2000000000 eeprom.bin > sw.out 2>/dev/null || true

got=$(tr -d '\0' < sw.out | grep -oE '^N[0-9]' | tail -1)
[ "$got" = "N3" ] || fail "counter read '$got', want 'N3' -- per-window state did not persist across the three launches"

echo "WM-SWITCH TEST: PASS (per-window state held resident: an app's counter survives 3 launches)"
