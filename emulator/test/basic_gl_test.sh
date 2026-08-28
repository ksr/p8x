#!/bin/sh
# The BASIC GL statement (stage 10d): GL string$ sends one ASCII
# graphics-language line, wrapped CA ... CX. The test builds a rotated
# filled triangle with string arithmetic (GL "MDY "+STR$(A)) and reads a
# pixel back with POINT -- statement, translator, matrix verbs and the
# hex machinery all in one round trip.
set -e
set -o pipefail
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "BASIC-GL TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/basic/p8xbasic.asm -o bgl_basic.bin \
        --base 0x6A00 -D BASORG=0x6A00 -D BASRAM=0xC500 -D PBUF=0xE000 -D MONITOR=0x2000 >/dev/null

rm -f bgl.img
python3 $ROOT/tools/p8xfs.py create bgl.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   bgl.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  bgl.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    bgl.img bgl_basic.bin --name /bin/basic.bin --load 0x6A00 --exec 0x6A00 >/dev/null

printf 'B\rbasic\r10 GL "RESETF CLEARS 0 0 0"\r20 GL "WINDOW -120 120 -120 120"\r30 GL "VWPORT 104 375 0 271"\r40 GL "COLOR 0 63 0 PRMFIL 1"\r50 A=35\r60 GL "MDY "+STR$(A)\r70 GL "POLY3 3 -8 -8 30 8 -8 30 0 4 42"\r80 PRINT POINT(364,204)\r90 END\rRUN\rNEW\r10 RESETF\r20 CLEARS 0,0,0\r30 WINDOW -120,120,-120,120\r40 VWPORT 104,375,0,271\r50 COLOR RGB(31,0,0)\r60 PRMFIL 1\r70 CLBEG 1\r80 MDROTY 5\r90 CLEND\r100 CLOOP 1,3+4\r110 POLY3 3,-80,-80,300,80,-80,300,0,40,420\r120 PRINT POINT(364,204)\r130 END\rRUN\rNEW\r10 RESETF\r20 CLEARS 0,0,0\r30 WINDOW 0,479,0,271\r40 VWPORT 0,479,0,271\r50 COLOR RGB(31,63,0)\r60 MOVE 100,100\r70 RECT 200,150\r80 MOVE 150,125\r90 AREA\r100 COLOR RGB(0,0,31)\r110 POLY 4,300,200,350,150,400,200,350,250\r120 COLOR RGB(0,63,31)\r130 MOVE 350,200\r140 AREABC 0,0,31\r150 PRINT POINT(150,146)\r160 PRINT POINT(320,71)\r170 END\rRUN\rBYE\r' > bgl.in
../p8xemu -N -i bgl.in -c bgl.img -l 1500000000 -g bgl.ppm eeprom.bin > bgl.out 2>/dev/null || true
grep -q "Ok" bgl.out || fail "program did not run"
# Both programs RESETF+CLEARS first: the OS boot splash paints its own GL
# scene, and this test once PASSED ON A SPLASH PIXEL -- its old probe
# (220,136) sat inside the splash's green triangle while its own POLY3
# string, 40 chars against BASIC's 32-char string cap, lost its last two
# coordinates and misaligned the stream. The string program therefore
# uses /10 coordinates (31 chars, same projected shape); the native
# program has no string in the path at all. (364,204) is inside the
# 35-degree triangle's visible sliver -- at 35 degrees two vertices
# leave the +/-120 window.
tr -d '\0\r' < bgl.out | grep -q "^2016$" || fail "POINT(364,204) != 2016 (string-form tri missing)"
# the NATIVE verb program: the same 35 degrees arrives as a recorded
# MDROTY 5 list CLOOP'd 3+4 times (deltas accumulate; CLOOP mixes a byte
# and a word param), the pen through COLOR RGB(31,0,0)'s GL bridge, and
# POLY3 takes its nine coordinates natively -- same pixel, now red.
tr -d '\0\r' < bgl.out | grep -q -- "^-2048$" || fail "POINT(364,204) != -2048 (native verbs missing)"
# the stage-10g statements: AREA fills the yellow rectangle outline from
# a MOVE'd seed (window (150,125) -> screen (150,146); yellow $FFE0 reads
# back as -32), and AREABC fills the blue diamond teal up to a STATED
# boundary (window (320,200) -> screen (320,71); teal $07FF = 2047).
tr -d '\0\r' < bgl.out | grep -q -- "^-32$" || fail "POINT(150,146) != -32 (AREA fill missing)"
tr -d '\0\r' < bgl.out | grep -q "^2047$" || fail "POINT(320,71) != 2047 (AREABC fill missing)"
python3 - <<'EOF' || exit 1
d=open("bgl.ppm","rb").read(); px=d.split(b"\n",3)[3]
def p(x,y): return px[(y*480+x)*3:(y*480+x)*3+3]
assert p(150,146)==b"\xff\xff\x00", "AREA pixel not yellow"
assert p(320, 71)==b"\x00\xff\xff", "AREABC pixel not teal"
EOF
echo "BASIC-GL TEST: PASS (GL statement + native verbs + recorded-list rotation + COLOR bridge + POINT + AREA/AREABC)"
