#!/bin/sh
# wdesk's TERM window: a command line with scrollback, drawn by the CLIENT in a
# kernel-owned window (the same content model as FILES). This test proves TERM
# is interactive AND that windows are addressed by TITLE, not by array index --
# the kernel PHYSICALLY REORDERS records on a focus change (k_raise), so wdesk
# identifies the focused window by its title letter (S/T/F), which rides in the
# record. TAB cycles focus by raising the bottom window; from the fresh stack
# (SHAPES, TERM, FILES-on-top) two TABs put TERM on top.
#   0 fresh           -> FILES focused (baseline)
#   T +\t\t           -> TERM focused: its scrollback + prompt now show
#   Y +\t\t HELLO     -> typing echoes into the input line (frame changes)
#   X +\t\t zz\r      -> a bogus command: "$ zz" + "?EXEC" join the scrollback
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
run '\t\t'        wtT.ppm     # TERM focused, empty prompt
run '\t\tHELLO'   wtY.ppm     # typed into TERM
run '\t\tzz\r'    wtX.ppm     # a bogus command -> ?EXEC

python3 - <<'EOF' || exit 1
import hashlib
def h(f): return hashlib.md5(open(f,"rb").read()).hexdigest()
def px(f):
    return open(f,"rb").read().split(b"\n",3)[3]
def white_in_term(f):
    d = px(f)
    def p(x,wy):
        i=((271-wy)*480+x)*3; return d[i:i+3]
    # TERM window is (70,100)+300x150; count WHITE stroke pixels strictly INSIDE
    # its body (below the ~14px title bar, inside the borders). SHAPES (red +
    # yellow, no white) sits BEHIND TERM here, so this white is TERM's own.
    return sum(1 for X in range(74,364) for Y in range(120,240)
               if p(X,Y)==b"\xff\xff\xff")

h0,hT,hY,hX = h("wt0.ppm"),h("wtT.ppm"),h("wtY.ppm"),h("wtX.ppm")
assert hT != h0, "focusing TERM (\\t\\t) did not change the frame -- title dispatch or TAB focus wrong"
assert hY != hT, "typing HELLO into TERM did not change the frame"
assert hX != hT and hX != hY, "submitting a command did not change the frame"

wT = white_in_term("wtT.ppm")           # 1 white line: the greeting
wX = white_in_term("wtX.ppm")           # +2 white lines: "$ zz" and "?EXEC"
assert wT > 20, "TERM body shows no white scrollback text when focused (%d px)" % wT
assert wX > wT + 40, "submitting a command did not grow the white scrollback (%d -> %d px)" % (wT, wX)
print("TERM is focused by TITLE (survives k_raise reorder), shows its scrollback,")
print("echoes typed input, and a failed command appends '$ zz' + '?EXEC'")
print("  white scrollback px: focus=%d  after-command=%d  (grew by %d)" % (wT, wX, wX-wT))
EOF

echo "C-WTERM TEST: PASS (TERM: title-addressed window, scrollback, typed input, command launch via the shell resolver)"
