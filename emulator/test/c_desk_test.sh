#!/bin/sh
# desk: rung 1 of the window system, scripted end to end.
#   1. keyboard session: type into the focused TERM window (card TEXT
#      in window-local coords), TAB raises SHAPES -- focus renders as
#      title-bar colour; the deliberately-overrunning RECT in SHAPES
#      is clipped by the per-window WINDOW/VWPORT pair (ZERO escaped
#      pixels -- the mechanism the whole rung exists to prove).
#   2. mouse session: press a title bar, drag (complement outline),
#      release -- the window lands at the cell-mapped position and the
#      vacated desktop repaints. This session also pins two traps: the
#      size query hands a leading mouse report back intact (_pseq),
#      and no -1 sentinel survives p8cc's UNSIGNED compares.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-DESK TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null

python3 $ROOT/tools/clib.py $ROOT/os/commands/desk.c > cd_desk.c
python3 $ROOT/compiler/p8cc.py cd_desk.c -o cd_desk.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py cd_desk.asm -o cd_desk.bin --base 0x6A00 >/dev/null

rm -f cd.img
python3 $ROOT/tools/p8xfs.py create cd.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   cd.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  cd.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    cd.img cd_desk.bin --name /bin/desk.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    cd.img $ROOT/os/font.gl --name /FONT.GL --load 0 --exec 0 >/dev/null

# 1: type HI + ENTER into TERM, TAB to raise SHAPES, quit
printf 'B\rdesk\rHI\r\011\004' > cd1.in
../p8xemu -N -i cd1.in -c cd.img -l 900000000 -g cd1.ppm eeprom.bin > cd1.out 2>/dev/null || true
grep -q "bye" cd1.out || fail "keyboard session did not quit cleanly"

# 2: mouse -- press TERM's title (cell 51,5), drag, release at (31,5)
printf 'B\rdesk\r\033[<0;51;5M\033[<32;41;5M\033[<32;31;5M\033[<0;31;5m\004' > cd2.in
../p8xemu -N -i cd2.in -c cd.img -l 900000000 -g cd2.ppm eeprom.bin > cd2.out 2>/dev/null || true
grep -q "bye" cd2.out || fail "mouse session did not quit cleanly"

python3 - <<'EOF' || exit 1
def load(f):
    d = open(f, "rb").read()
    return d.split(b"\n", 3)[3]
def p(px, x, wy):
    i = ((271 - wy) * 480 + x) * 3
    return tuple(px[i:i+3])
DESK = (49, 48, 74)
a = load("cd1.ppm")
assert p(a,50,182)==(255,255,255),  "SHAPES title not focused-white after TAB"
assert p(a,300,222)==(132,130,132), "TERM title not unfocused-grey"
assert p(a,10,260)==DESK,           "desktop backdrop missing"
esc = 0
for X in range(0,480):
    for Y in range(0,272):
        if p(a,X,Y)==(255,255,0) and not (41<=X<=248 and 41<=Y<=175):
            esc += 1
assert esc == 0, "%d pixels ESCAPED the window clip" % esc
green = sum(1 for X in range(195,425) for Y in range(95,215)
            if p(a,X,Y)==(0,255,0))
assert green > 10, "TERM text missing (%d green px)" % green
b = load("cd2.ppm")
assert p(b,80,222)==(255,255,255),  "dragged TERM title not at the new x"
assert p(b,70,150)==(255,255,255),  "dragged TERM left border missing"
assert p(b,309,150)==(255,255,255), "dragged TERM right border missing"
assert p(b,350,222)==DESK,          "vacated area did not repaint"
print("clip (0 escapes), focus colours, TERM text, mouse drag: all pixel-exact")
EOF

echo "C-DESK TEST: PASS (per-window hardware clip, painter's repaint, focus, card-TEXT terminal, mouse title-bar drag)"
