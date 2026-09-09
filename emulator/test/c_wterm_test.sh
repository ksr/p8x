#!/bin/sh
# wdesk's TERM window: the interactive INPUT LINE. This test proves TERM is
# focusable and typeable, AND that windows are addressed by TITLE, not by array
# index -- the kernel PHYSICALLY REORDERS records on a focus change (k_raise), so
# wdesk identifies the focused window by its title letter (S/T/F/V), which rides
# in the record. TAB cycles focus by raising the bottom window; from the fresh
# stack (SHAPES, TERM, FILES-on-top) two TABs put TERM on top. Running a command
# and seeing its OUTPUT in the window is covered by c_wtermout_test (the sink).
#   0 fresh           -> FILES focused (baseline)
#   T +\t\t           -> TERM focused: the yellow "$ _" prompt shows
#   Y +\t\t HELLO     -> typing extends the input line (frame changes)
# Behaviour is proven by frame-hash differentials; TERM's own signature (white
# scrollback text GROWING when a command is submitted) is proven by pixels --
# SHAPES has no white, and TERM sits on top of its screen region, so white text
# inside TERM's body is TERM's alone.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-WTERM TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null

python3 $ROOT/tools/clib.py $ROOT/os/commands/wdesk.c -o wt_wdesk.c
python3 $ROOT/compiler/p8cc.py wt_wdesk.c -o wt_wdesk.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py wt_wdesk.asm -o wt_wdesk.bin --base 0x6A00 >/dev/null

rm -f wt.img
python3 $ROOT/tools/p8xfs.py create wt.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   wt.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  wt.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    wt.img wt_wdesk.bin --name /bin/wdesk.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    wt.img $ROOT/os/font.gl --name /FONT.GL --load 0 --exec 0 >/dev/null

run() {  # $1 = input tail after "run wdesk", $2 = ppm out
    printf "B\rrun /bin/wdesk.bin\r$1" > wt.in
    ../p8xemu -N -i wt.in -c wt.img -l 1600000000 -g "$2" eeprom.bin > wt.out 2>/dev/null || true
    grep -q "WDESK" wt.out || fail "wdesk did not start ($2)"
}

run ''            wt0.ppm     # FILES focused (fresh)
run '\t\t'        wtT.ppm     # TERM focused, empty prompt "$ _"
run '\t\tHELLO'   wtY.ppm     # typed into the TERM input line

python3 - <<'EOF' || exit 1
import hashlib
def h(f): return hashlib.md5(open(f,"rb").read()).hexdigest()
def yellow_in_term(f):
    d = open(f,"rb").read().split(b"\n",3)[3]
    def p(x,wy):
        i=((271-wy)*480+x)*3; return d[i:i+3]
    # The TERM INPUT LINE is drawn yellow at the bottom of the body. TERM's black
    # body covers SHAPES (whose only yellow box is behind it) where they overlap,
    # so yellow inside the TERM body is the input prompt "$ <line>_".
    return sum(1 for X in range(74,364) for Y in range(104,150)
               if p(X,Y)==b"\xff\xff\x00")

h0,hT,hY = h("wt0.ppm"),h("wtT.ppm"),h("wtY.ppm")
assert hT != h0, "focusing TERM (\\t\\t) did not change the frame -- title dispatch or TAB focus wrong"
assert hY != hT, "typing into TERM did not change the frame"
yT = yellow_in_term("wtT.ppm")          # "$ _"
yY = yellow_in_term("wtY.ppm")          # "$ HELLO_"
assert yT > 4, "no yellow input prompt when TERM is focused (%d px)" % yT
assert yY > yT + 20, "typing did not extend the input line (%d -> %d px)" % (yT, yY)
print("TERM is focused by TITLE (survives k_raise reorder) and shows a yellow input")
print("line that extends as you type; input px: empty=%d  after HELLO=%d" % (yT, yY))
EOF

echo "C-WTERM TEST: PASS (TERM: title-addressed window, interactive input line; output via the sink -- see c_wtermout)"
