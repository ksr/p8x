#!/bin/sh
# The resident WM kernel skeleton (os/wmkernel.asm), end to end.
#   A stub app loads the kernel to WMBASE (FRESOLVE+FFIND+FLOADAT), calls
#   its bios()-style jump table -- wk_init, wk_open x2, wk_repaint -- and
#   EXITS. A second, separate program then calls wk_repaint again and
#   nothing else: the two titled windows must reappear, drawn entirely by
#   the RESIDENT kernel from records the first app left behind. That is
#   the whole point of the resident architecture -- window state outlives
#   the program that created it.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "WM-KERNEL TEST: FAIL — $1"; exit 1; }

WMBASE=$(python3 -c "import sys; sys.path.insert(0,'$ROOT/generators'); import memmap; print(memmap.WMBASE)")
WK_INIT=$WMBASE
WK_OPEN=$((WMBASE + 3))
WK_PAINT=$((WMBASE + 6))
WK_SIG=$((WMBASE + 12))

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/wmkernel.asm -o wmk.bin --base $WMBASE >/dev/null

# --- the stub: load the kernel, open two windows, repaint ---
cat > wk_stub.c <<EOF
char param[22];
int gp(int v) { while (peek(0xFF51) & 128) { } poke(0xFF50, v); return 0; }
int gw(int v) { gp(v & 255); gp((v / 256) & 255); return 0; }
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
    bios($WK_OPEN, param, 0);                       /* wk_open */
    return 0;
}
int main() {
    bios(0x0133, "/bin/wmk.bin", 0);               /* FRESOLVE */
    if (bios(0x0118, 0, 0) & 256) { puts("?NOKERNEL"); return 1; }  /* FFIND */
    bios(0x013F, $WMBASE, 0);                      /* FLOADAT -> WMBASE */
    /* record SHAPES' content into card list 40 -- a red filled box in
     * window-LOCAL content coordinates; the CARD keeps it */
    gp(112); gp(40);                               /* CLBEG 40 */
    gp(224); gp(1);                                /* PRMFIL 1 */
    gp(6); gp(31); gp(0); gp(0);                    /* COLOR red */
    gp(16); gw(20); gw(20);                         /* MOVE 20,20 */
    gp(52); gw(150); gw(100);                       /* RECT 150,100 */
    gp(224); gp(0);
    gp(113);                                        /* CLEND */
    bios($WK_INIT, 0, 0);                          /* wk_init */
    setw(40, 40, 210, 150, 40, "SHAPES");           /* SHAPES: content list 40 */
    setw(190, 90, 240, 140, 0, "TERM");             /* TERM: no content yet */
    bios($WK_PAINT, 0, 0);                          /* wk_repaint */
    puts("STUB-DONE");
    return 0;
}
EOF

# --- the redraw-only app: prove the resident kernel redraws with no records
#     set by THIS program (they belong to the departed stub) ---
cat > wk_redraw.c <<EOF
int main() {
    if (peek($WK_SIG) != 0x57) { puts("?NOKERNEL"); return 1; }       /* 'W' */
    bios($WK_PAINT, 0, 0);                         /* wk_repaint */
    puts("REDRAW-DONE");
    return 0;
}
EOF

for p in wk_stub wk_redraw; do
    python3 $ROOT/compiler/p8cc.py $p.c -o $p.asm >/dev/null
    python3 $ROOT/assembler/p8xasm.py $p.asm -o $p.bin --base 0x6A00 >/dev/null
done

rm -f wk.img
python3 $ROOT/tools/p8xfs.py create wk.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   wk.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  wk.img /bin >/dev/null
# the kernel is stored with its fixed load address; a plain FLOADAT to WMBASE
python3 $ROOT/tools/p8xfs.py put    wk.img wmk.bin --name /bin/wmk.bin --load $WMBASE --exec $WMBASE >/dev/null
python3 $ROOT/tools/p8xfs.py put    wk.img wk_stub.bin --name /bin/st.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    wk.img wk_redraw.bin --name /bin/rd.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    wk.img $ROOT/os/font.gl --name /FONT.GL --load 0 --exec 0 >/dev/null

# frame 1: the stub draws two windows, then exits
printf 'B\rrun /bin/st.bin\r' > wk1.in
../p8xemu -N -i wk1.in -c wk.img -l 700000000 -g wk1.ppm eeprom.bin > wk1.out 2>/dev/null || true
grep -q "STUB-DONE" wk1.out || fail "the stub did not finish (kernel load or jump failed)"

# frame 2: a DIFFERENT program repaints -- the stub is long gone
printf 'B\rrun /bin/st.bin\rrun /bin/rd.bin\r' > wk2.in
../p8xemu -N -i wk2.in -c wk.img -l 900000000 -g wk2.ppm eeprom.bin > wk2.out 2>/dev/null || true
grep -q "REDRAW-DONE" wk2.out || fail "the redraw-only app did not finish"

python3 - <<'EOF' || exit 1
def load(f):
    d = open(f, "rb").read()
    return d.split(b"\n", 3)[3]
def p(px, x, wy):
    i = ((271 - wy) * 480 + x) * 3
    return tuple(px[i:i+3])
GREY = (49, 48, 74)
for name in ("wk1.ppm", "wk2.ppm"):
    a = load(name)
    # SHAPES window: (40,40) 210x150 -> border corner white, body black inside
    assert p(a,40,40)==(255,255,255),   "%s: SHAPES border corner missing" % name
    assert p(a,45,45)==(0,0,0),         "%s: SHAPES body not black" % name
    # TERM window: (190,90) 240x140, drawn ON TOP where they overlap
    assert p(a,190,90)==(255,255,255),  "%s: TERM border corner missing" % name
    # desktop shows between/around the windows
    assert p(a,460,20)==GREY,           "%s: desktop backdrop missing" % name
    # the grey desktop fills the backdrop (the FLOOD ran)
    grey = sum(1 for i in range(0,len(a),3) if a[i:i+3]==bytes(GREY))
    assert grey > 40000, "%s: desktop FLOOD missing (%d grey px)" % (name, grey)
    # the SHAPES title strokes (white TEXT inside the window; card stroke
    # font, drawn by the resident kernel -- needs PROJCT 0 so z=0 is not
    # near-clipped) leave a cluster of white pixels in the interior
    tt = sum(1 for X in range(42,120) for Y in range(178,188)
             if p(a,X,Y)==(255,255,255))
    assert tt > 40, "%s: SHAPES title not drawn (%d px)" % (name, tt)
    # the SHAPES content -- a red box from CARD LIST 40 -- must be present
    # in BOTH frames (in frame 2 the recording app is gone; the card holds it)
    red = sum(1 for i in range(0,len(a),3) if a[i:i+3]==bytes((255,0,0)))
    assert red > 2000, "%s: SHAPES card-list content missing (%d red px)" % (name, red)
print("both frames: two windows, desktop, titles, AND card-list content -- the")
print("content survives the app in frame 2 (redraw-only, stub GONE)")
EOF

echo "WM-KERNEL TEST: PASS (resident kernel: records + repaint outlive the app that set them)"
