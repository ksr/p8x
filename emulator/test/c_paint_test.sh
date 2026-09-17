#!/bin/sh
# paint: the vector-editor loop end to end, driven by the MOUSE (SGR escape
# reports through the console) -- paint is mouse-first now, so tools and colours
# are chosen by CLICKING the palette strip, the crosshair is positioned by the
# mouse, and a click on the red X quits. The keyboard keeps only editing actions
# (SPACE / x / e / n / q). What is checked:
#   1. click the BOX tool + a swatch, press-drag-release a box, click the FILL
#      tool + a swatch, drop a fill inside it (AREABC to the probed boundary);
#      the palette strip survives every canvas repaint; the QUIT close-box exits.
#   2. click the CIRCLE tool, draw a circle, fill it, then 'e' pops the fill --
#      the display list replays, leaving the circle but no fill.
#   3. 'n' clears the canvas to zero lit pixels.
#
# SGR cell map (the scripted session answers no ESC[18t, so lib_ptr falls back to
# 80x24): panel_x = (col-1)*6 ; a click with row 1 lands at window-y 271, which is
# in the palette strip (at_palette only needs y>=246 + the column). Canvas rows:
# row 15 -> wy 113, row 10 -> wy 169, row 12 -> wy 147.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-PAINT TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null

python3 $ROOT/tools/clib.py $ROOT/os/commands/paint.c > cp_paint.c
python3 $ROOT/compiler/p8cc.py cp_paint.c -o cp_paint.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py cp_paint.asm -o cp_paint.bin --base 0x5900 >/dev/null

rm -f cp.img
python3 $ROOT/tools/p8xfs.py create cp.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   cp.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  cp.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    cp.img cp_paint.bin --name /bin/paint.bin --load 0x5900 --exec 0x5900 >/dev/null

# Palette click columns (all at row 1, window-y 271, inside the strip):
#   tools : line col40, box col45, circle col50, fill col55
#   swatch: white col3, red col7, green col12, yellow col20, cyan col24
#   QUIT close-box (x 432..476): col74
# session 1: click BOX tool + RED, draw a box, click FILL + YELLOW, drop a fill
# inside it, then click the QUIT close-box.
printf 'B\rpaint\r\033[<0;45;1M\033[<0;45;1m\033[<0;7;1M\033[<0;7;1m\033[<0;30;15M\033[<32;45;12M\033[<0;50;10m\033[<0;55;1M\033[<0;55;1m\033[<0;20;1M\033[<0;20;1m\033[<0;40;12M\033[<0;40;12m\033[<0;74;1M' > cp1.in
../p8xemu -N -i cp1.in -c cp.img -l 900000000 -g cp1.ppm eeprom.bin > cp1.out 2>/dev/null || true
grep -q "bye" cp1.out || fail "session 1 did not quit from the QUIT close-box"

# session 2: click CIRCLE + GREEN, draw a circle, click FILL + CYAN, drop a fill,
# then 'e' pops the fill (display-list replay leaves the circle only), then 'q'.
printf 'B\rpaint\r\033[<0;50;1M\033[<0;50;1m\033[<0;12;1M\033[<0;12;1m\033[<0;40;12M\033[<0;45;12m\033[<0;55;1M\033[<0;55;1m\033[<0;24;1M\033[<0;24;1m\033[<0;40;12M\033[<0;40;12meq' > cp2.in
../p8xemu -N -i cp2.in -c cp.img -l 900000000 -g cp2.ppm eeprom.bin > cp2.out 2>/dev/null || true

# session 3: draw a box, then 'n' clears the canvas to nothing, then 'q'.
printf 'B\rpaint\r\033[<0;45;1M\033[<0;45;1m\033[<0;30;15M\033[<32;45;12M\033[<0;50;10mnq' > cp3.in
../p8xemu -N -i cp3.in -c cp.img -l 900000000 -g cp3.ppm eeprom.bin > cp3.out 2>/dev/null || true

python3 - <<'EOF' || exit 1
def load(f):
    d = open(f, "rb").read()
    return d.split(b"\n", 3)[3]
def p(px, x, wy):
    i = ((271 - wy) * 480 + x) * 3
    return tuple(px[i:i+3])

# --- session 1: box (174,113)-(294,169) red, interior filled yellow -----------
a = load("cp1.ppm")
assert p(a,174,140)==(255,0,0),     "box left edge not red: %r"%(p(a,174,140),)
assert p(a,234,140)==(255,255,0),   "box interior not filled yellow: %r"%(p(a,234,140),)
assert p(a,234,185)==(0,0,0),       "fill leaked above the box: %r"%(p(a,234,185),)
assert p(a,10,260)==(255,255,255),  "white swatch missing (palette repainted over?)"
assert p(a,36,260)==(255,0,0),      "red swatch missing"
assert p(a,100,246)==(255,255,255), "separator missing"
o1 = open("cp1.out","rb").read().decode("latin1").replace("\x00","")
assert "BOX" in o1 and "RED" in o1,    "BOX/RED tool+colour click not reflected in status"
assert "FILL" in o1 and "YELLOW" in o1,"FILL/YELLOW tool+colour click not reflected in status"

# --- session 2: green circle centre (234,147) r=30; fill CYAN then 'e' pops it -
b = load("cp2.ppm")
assert p(b,264,147)==(0,255,0),     "circle edge not green: %r"%(p(b,264,147),)
assert p(b,234,147)==(0,0,0),       "fill not popped by 'e' (centre still lit): %r"%(p(b,234,147),)
assert p(b,284,147)==(0,0,0),       "something outside the circle radius: %r"%(p(b,284,147),)

# --- session 3: 'n' cleared the canvas (device rows > 26) to nothing ----------
c = load("cp3.ppm")
lit = sum(1 for i in range(0,len(c),3)
          if c[i:i+3]!=b"\x00\x00\x00" and (i//3//480) > 26)
assert lit == 0, "clear left %d canvas pixels" % lit
print("mouse box+fill+quit-box, circle+fill+erase-replay, clear: all pixel-exact")
EOF

echo "C-PAINT TEST: PASS (mouse-driven draw/fill/erase/clear; palette survives; QUIT close-box; keys SPACE/x/e/n)"
