#!/bin/sh
# The resident WM kernel, FOLDED INTO THE OS (syscalls $2027-$2036), end to end.
#   A stub app calls the WM syscalls -- SYS_WKINIT, SYS_WKOPEN x2,
#   SYS_WKREPAINT -- and EXITS. A second, separate program then calls
#   SYS_WKREPAINT again and nothing else: the two titled windows must reappear,
#   drawn entirely by the RESIDENT kernel from records the first app left
#   behind. Window state outlives the program that created it -- and the kernel
#   needs no loading, it is always present in the OS.
#   (Historical note: this once crashed because the shell's command-history
#   ring sat at $5800, inside the OS image once the kernel was folded in --
#   typing "run ..." overwrote wk_draw with ASCII. The ring now lives at $F800.)
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "WM-KERNEL TEST: FAIL — $1"; exit 1; }

# WM syscalls: JMP table entries in os/p8xos.asm right after SYS_EXEC ($2024)
WK_INIT=0x2027
WK_OPEN=0x202A
WK_PAINT=0x202D

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null

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
    /* the kernel is in the OS -- no load; just call the WM syscalls.
     * record SHAPES' content into card list 40 -- a red filled box in
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
    bios($WK_PAINT, 0, 0);                         /* SYS_WKREPAINT */
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
    # the SHAPES title strokes: BLACK stroke TEXT on the title bar (SHAPES is
    # not the top window, so its bar is grey), drawn by the resident kernel
    # -- needs PROJCT 0 so z=0 is not near-clipped. Sampled past the close
    # box (x >= kx+16 = 56) so only the text can contribute black pixels.
    tt = sum(1 for X in range(56,120) for Y in range(178,188)
             if p(a,X,Y)==(0,0,0))
    assert tt > 40, "%s: SHAPES title not drawn (%d black px)" % (name, tt)
    # the SHAPES content -- a red box from CARD LIST 40 -- must be present
    # in BOTH frames (in frame 2 the recording app is gone; the card holds it)
    red = sum(1 for i in range(0,len(a),3) if a[i:i+3]==bytes((255,0,0)))
    assert red > 2000, "%s: SHAPES card-list content missing (%d red px)" % (name, red)
print("both frames: two windows, desktop, titles, AND card-list content -- the")
print("content survives the app in frame 2 (redraw-only, stub GONE)")
EOF

echo "WM-KERNEL TEST: PASS (resident kernel: records + repaint outlive the app that set them)"
