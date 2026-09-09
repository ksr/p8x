#!/bin/sh
# The OUTCH->window sink (rung 15b): SYS_WKSINK ($204E) arms OUTCH mode 3, which
# RECORDS every stdout byte as GL TEXT into a window's card list; the kernel
# replays that list on repaint, so command output lands -- and persists -- in a
# window with no CPU-side scrollback. sink_probe opens a window (content = list
# 40), arms the sink, prints "HELLO"/"WORLD", disarms, and repaints. Recording
# draws nothing live, so the ONLY way the text can be on the frame is the
# kernel's CLRUN of list 40 -- which proves the sink recorded into the list.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-WSINK TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null

# The probe source (test/*.c is gitignored build scratch, so generate it here to
# keep the test self-contained). It opens a window whose content is card list 40,
# arms the sink at it, prints two lines, disarms, and repaints.
cat > sink_probe.c <<'PROBEEOF'
//#use abi
//#define GLID 0xFF54
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
    bios(SYS_WKOPEN, param, 0);
    return 0;
}
int main() {
    if (peek(GLID) != 71) { puts("?No display"); return 1; }
    bios(SYS_WKINIT, 0, 0);
    setw(60, 60, 220, 110, 40, "OUT");     /* content = card list 40 */
    bios(SYS_WKREPAINT, 0, 0);
    bios(SYS_WKSINK, 0, 0);                /* ARM: route stdout into window 0 */
    puts("HELLO");                         /* -> recorded as TEXT into list 40 */
    puts("WORLD");
    bios(SYS_WKSINK, 0, 255);              /* DISARM: CLEND, REDIRF=0 */
    bios(SYS_WKREPAINT, 0, 0);             /* CLRUN list 40 -> the text appears */
    puts("SINKOK");                        /* console marker (REDIRF=0 again) */
    return 0;
}
PROBEEOF

cp $ROOT/os/commands/lib_abi.c .          # clib resolves //#use from the source's dir
python3 $ROOT/tools/clib.py sink_probe.c -o ws_probe.c
python3 $ROOT/compiler/p8cc.py ws_probe.c -o ws_probe.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py ws_probe.asm -o ws_probe.bin --base 0x6A00 >/dev/null

rm -f ws.img
python3 $ROOT/tools/p8xfs.py create ws.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   ws.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  ws.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    ws.img ws_probe.bin --name /bin/sink.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    ws.img $ROOT/os/font.gl --name /FONT.GL --load 0 --exec 0 >/dev/null

printf 'B\rrun /bin/sink.bin\r' > ws.in
../p8xemu -N -i ws.in -c ws.img -l 900000000 -g ws.ppm eeprom.bin > ws.out 2>/dev/null || true
grep -q "SINKOK" ws.out || fail "sink probe did not finish (no SINKOK marker)"

python3 - <<'EOF' || exit 1
d = open("ws.ppm","rb").read().split(b"\n",3)[3]
def p(x,wy):
    i=((271-wy)*480+x)*3; return (d[i],d[i+1],d[i+2])
# window (60,60) 220x110. Its chrome is white too: the focused title bar is a
# solid ~200px/row band near the top (wy ~156-169) and the border is a full
# ~212px line. The SINK TEXT is the sparse stroke ink in the body BELOW the
# title bar -- rows carrying a few tens of white px, not ~200. Count text rows
# (3..80 white px) in the body band and the total text ink.
def rowink(wy): return sum(1 for X in range(64,276) if p(X,wy)==(255,255,255))
trows = [wy for wy in range(64,154) if 3 <= rowink(wy) <= 80]
txt = sum(rowink(wy) for wy in trows)
assert txt > 100, "no sink text in the window body (%d white px) -- REDIRF=3 / list record failed" % txt
assert len(trows) >= 10, "too little stroke text recorded (%d text rows)" % len(trows)
# two lines: the inked text rows must SPAN more than one glyph height (~13px),
# i.e. HELLO on one line and WORLD on the next, not one line drawn twice.
span = max(trows) - min(trows)
assert span >= 11, "text did not advance to a second line (rows span %d px)" % span
print("SYS_WKSINK armed OUTCH mode 3; HELLO/WORLD were recorded as TEXT into the")
print("window's card list and appear on repaint via CLRUN -- %d white px over %d" % (txt, len(trows)))
print("text rows spanning %d px (two lines: a newline advanced the pen)" % span)
EOF

echo "C-WSINK TEST: PASS (OUTCH->window sink: stdout recorded into a window's card list, replayed on repaint)"
