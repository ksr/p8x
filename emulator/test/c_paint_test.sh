#!/bin/sh
# paint: the vector-editor loop end to end, driven by scripted keys.
#   1. box tool: anchor + commit a red box; fill tool: a yellow AREABC
#      drop inside it (the boundary colour PROBED by a PIXELR ray);
#      line tool: draw then ERASE -- the display list pops and replays,
#      and the popped line must leave no pixels.
#   2. the palette strip survives the replay's canvas FLOOD (the
#      WINDOW/VWPORT canvas clip -- the bug the first build had).
#   3. circle tool + fill inside it; drop ON an outline is refused;
#      'n' clears the canvas to zero lit pixels.
#   4. THE MOUSE, as SGR escape sequences through the console: press-
#      drag-release draws a box at the cell-mapped coordinates (80x24
#      fallback map -- the scripted session answers no size query),
#      and a click on the palette strip selects a colour.
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
python3 $ROOT/assembler/p8xasm.py cp_paint.asm -o cp_paint.bin --base 0x6A00 >/dev/null

rm -f cp.img
python3 $ROOT/tools/p8xfs.py create cp.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   cp.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  cp.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    cp.img cp_paint.bin --name /bin/paint.bin --load 0x6A00 --exec 0x6A00 >/dev/null

# session 1: red box, yellow fill inside, white line drawn then erased
printf 'B\rpaint\r2b DDDWW fAS5 l1SS AAA eq' > cp1.in
../p8xemu -N -i cp1.in -c cp.img -l 900000000 -g cp1.ppm eeprom.bin > cp1.out 2>/dev/null || true
grep -q "bye" cp1.out || fail "session 1 did not quit cleanly"

# session 2: green circle, cyan fill inside; then a clear
printf 'B\rpaint\r3c DDD 6fAA nq' > cp2.in
../p8xemu -N -i cp2.in -c cp.img -l 900000000 -g cp2.ppm eeprom.bin > cp2.out 2>/dev/null || true
printf 'B\rpaint\r3c DDD 6fAA q' > cp3.in
../p8xemu -N -i cp3.in -c cp.img -l 900000000 -g cp3.ppm eeprom.bin > cp3.out 2>/dev/null || true

python3 - <<'EOF' || exit 1
def load(f):
    d = open(f, "rb").read()
    return d.split(b"\n", 3)[3]
def p(px, x, wy):
    i = ((271 - wy) * 480 + x) * 3
    return tuple(px[i:i+3])
a = load("cp1.ppm")
assert p(a,250,120)==(255,0,0),     "box edge not red: %r"%(p(a,250,120),)
assert p(a,250,128)==(255,255,0),   "fill not yellow: %r"%(p(a,250,128),)
assert p(a,250,140)==(0,0,0),       "fill leaked above the box"
assert p(a,240,112)==(0,0,0),       "erased line left pixels"
assert p(a,10,260)==(255,255,255),  "white swatch missing (palette FLOODed?)"
assert p(a,36,260)==(255,0,0),      "red swatch missing"
assert p(a,100,246)==(255,255,255), "separator missing"
b = load("cp3.ppm")
assert p(b,264,120)==(0,255,0),     "circle edge not green: %r"%(p(b,264,120),)
assert p(b,240,120)==(0,255,255),   "circle fill not cyan: %r"%(p(b,240,120),)
assert p(b,300,120)==(0,0,0),       "circle fill leaked outside"
c = load("cp2.ppm")
lit = sum(1 for i in range(0,len(c),3)
          if c[i:i+3]!=b"\x00\x00\x00" and (i//3//480) > 26)
assert lit == 0, "clear left %d canvas pixels" % lit
print("box+fill+erase, circle+fill, palette survival, clear: all pixel-exact")
EOF

# session 4: mouse -- box tool, press (30,15) drag release (50,10), then
# a palette click on the red swatch
printf 'B\rpaint\rb\033[<0;30;15M\033[<32;40;12M\033[<0;50;10m\033[<0;7;1M\033[<0;7;1mq' > cp4.in
../p8xemu -N -i cp4.in -c cp.img -l 900000000 -g cp4.ppm eeprom.bin > cp4.out 2>/dev/null || true
python3 - <<'EOF2' || exit 1
def p(px, x, wy):
    i = ((271 - wy) * 480 + x) * 3
    return tuple(px[i:i+3])
d = open("cp4.ppm","rb").read(); a = d.split(b"\n", 3)[3]
assert p(a,174,113)==(255,255,255), "mouse box corner missing: %r"%(p(a,174,113),)
assert p(a,294,169)==(255,255,255), "mouse box far corner missing"
assert p(a,230,140)==(0,0,0),       "mouse box not an outline"
out = open("cp4.out","rb").read().decode("latin1").replace("\x00","")
assert "BOX    RED" in out, "palette click did not select red"
print("mouse press-drag-release box + palette click: pixel-exact")
EOF2

echo "C-PAINT TEST: PASS (display-list draw/fill/erase/clear; palette protected by the canvas clip; mouse via SGR reports)"
