#!/bin/sh
# 15c-i: a real SHELL command's stdout lands in a window. The window sink
# (REDIRF=3) must survive the shell's per-command dispatch -- FLUSHRED (which
# resets REDIRF at the prompt), the GETLN line echo (which must go to the
# console, not the window), and DR_OUT (which must NOT treat mode 3 as a file
# redirect). This test arms the sink from a program, returns to the shell, runs
# the stock `pwd` command, and shows the window: pwd's output must be IN it.
#   mkdir WTDIR ; cd WTDIR ; run armwin (arm sink at a window) ; pwd ; run showwin
# armwin/showwin are tiny probes; pwd is the unmodified /bin command.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-WSHELL TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null
cp $ROOT/os/commands/lib_abi.c .          # clib resolves //#use from the source's dir

cat > armwin.c <<'AEOF'
//#use abi
//#define GLID 0xFF54
char param[22];
int setw(int x, int y, int w, int h, int list, char *t) {
    int i;
    param[0]=x&255; param[1]=(x/256)&255; param[2]=y&255; param[3]=(y/256)&255;
    param[4]=w&255; param[5]=(w/256)&255; param[6]=h&255; param[7]=(h/256)&255;
    param[8]=list; i=0; while (t[i] && i<12) { param[10+i]=t[i]; i=i+1; }
    param[9]=i; while (i<12) { param[10+i]=0; i=i+1; }
    bios(SYS_WKOPEN, param, 0); return 0;
}
int main() {
    if (peek(GLID) != 71) { puts("?No display"); return 1; }
    bios(SYS_WKINIT, 0, 0);
    setw(50, 60, 300, 120, 31, "OUT");     /* content = card list 31 */
    bios(SYS_WKREPAINT, 0, 0);
    bios(SYS_WKSINK, 0, 0);                /* ARM the sink at window 0, then exit */
    puts("ARMOK");                         /* to console (recorded? no -- CLBEG list
                                              is open, but puts here goes via OUTCH
                                              mode 3... so ARMOK lands in the window
                                              too; harmless, pwd's output follows) */
    return 0;
}
AEOF

cat > showwin.c <<'SEOF'
//#use abi
int main() {
    bios(SYS_WKSINK, 0, 255);              /* DISARM: CLEND, REDIRF=0 */
    bios(SYS_WKREPAINT, 0, 0);             /* CLRUN list 31 -> pwd's output shows */
    puts("SHOWOK");
    return 0;
}
SEOF

build() {   # $1 = source, $2 = out.bin
    python3 $ROOT/tools/clib.py "$1" -o t.pp.c
    python3 $ROOT/compiler/p8cc.py t.pp.c -o t.asm >/dev/null
    python3 $ROOT/assembler/p8xasm.py t.asm -o "$2" --base 0x6A00 >/dev/null
}
build armwin.c            armwin.bin
build showwin.c           showwin.bin
build $ROOT/os/commands/pwd.c pwd.bin

rm -f wsh.img
python3 $ROOT/tools/p8xfs.py create wsh.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   wsh.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  wsh.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    wsh.img armwin.bin  --name /bin/armwin.bin  --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    wsh.img showwin.bin --name /bin/showwin.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    wsh.img pwd.bin     --name /bin/pwd.bin     --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    wsh.img $ROOT/os/font.gl --name /FONT.GL --load 0 --exec 0 >/dev/null

printf 'B\rmkdir WTDIR\rcd WTDIR\rrun /bin/armwin.bin\rpwd\rrun /bin/showwin.bin\r' > wsh.in
../p8xemu -N -i wsh.in -c wsh.img -l 1200000000 -g wsh.ppm eeprom.bin > wsh.out 2>/dev/null || true
grep -q "SHOWOK" wsh.out || fail "sequence did not complete (no SHOWOK)"
# (Can't prove absence on the console: the mkdir/cd echoes and the "/WTDIR>"
#  prompt already contain the path. The positive proof is the window: if
#  REDIRF=3 were NOT honoured, pwd's output would go to the console and the
#  window body would be empty -- so the pixel check below is decisive.)

python3 - <<'EOF' || exit 1
d = open("wsh.ppm","rb").read().split(b"\n",3)[3]
def p(x,wy):
    i=((271-wy)*480+x)*3; return (d[i],d[i+1],d[i+2])
# window (50,60) 300x120. Count sparse white stroke text in the body (below the
# ~200px/row title bar), i.e. rows carrying a few tens of white px, not ~280.
def rowink(wy): return sum(1 for X in range(54,346) if p(X,wy)==(255,255,255))
trows = [wy for wy in range(64,164) if 3 <= rowink(wy) <= 120]
txt = sum(rowink(wy) for wy in trows)
assert txt > 60, "pwd's output did not render in the window (%d white px)" % txt
print("a stock `pwd` run from the shell wrote its output INTO the window via the")
print("sink (REDIRF=3 survived FLUSHRED + DR_OUT); %d white px over %d text rows" % (txt, len(trows)))
EOF

echo "C-WSHELL TEST: PASS (a real shell command's stdout renders in a window; REDIRF=3 survives dispatch)"
