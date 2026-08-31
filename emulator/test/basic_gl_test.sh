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

printf 'B\rbasic\r10 GL "RESETF CLEARS 0 0 0"\r20 GL "WINDOW -120 120 -120 120"\r30 GL "VWPORT 104 375 0 271"\r40 GL "COLOR 0 63 0 PRMFIL 1"\r50 A=35\r60 GL "MDY "+STR$(A)\r70 GL "POLY3 3 -8 -8 30 8 -8 30 0 4 42"\r73 GL "WINDOW 0 479 0 271"\r76 GL "VWPORT 0 479 0 271"\r80 PRINT PIXELR(364,67)\r90 END\rRUN\rNEW\r10 RESETF\r20 CLEARS 0,0,0\r30 WINDOW -120,120,-120,120\r40 VWPORT 104,375,0,271\r50 COLOR RGB(31,0,0)\r60 PRMFIL 1\r70 CLBEG 1\r80 MDROTY 5\r90 CLEND\r100 CLOOP 1,3+4\r110 POLY3 3,-80,-80,300,80,-80,300,0,40,420\r115 WINDOW 0,479,0,271 : VWPORT 0,479,0,271\r120 PRINT PIXELR(364,67)\r130 END\rRUN\rNEW\r10 RESETF\r20 CLEARS 0,0,0\r30 WINDOW 0,479,0,271\r40 VWPORT 0,479,0,271\r50 COLOR RGB(31,63,0)\r60 MOVE 100,100\r70 RECT 200,150\r80 MOVE 150,125\r90 AREA\r100 COLOR RGB(0,0,31)\r110 POLY 4,300,200,350,150,400,200,350,250\r120 COLOR RGB(0,63,31)\r130 MOVE 350,200\r140 AREABC 0,0,31\r150 PRINT PIXELR(150,125)\r160 PRINT PIXELR(320,200)\r170 END\rRUN\rNEW\r10 RESETF : CLEARS 0,0,0 : PROJCT 0\r20 WINDOW 0,479,0,271\r30 VWPORT 0,479,0,271\r40 TDEFIN 65\r50 MOVER3 0,0,0 : DRAWR3 0,6,0\r60 MOVER3 6,-6,0\r70 CLEND\r80 COLOR RGB(31,63,0)\r90 TSIZE 512 : TANGLE 0\r100 MOVE3 100,100,0\r110 TEXT "A"\r120 PRINT PIXELR(200,200)\r130 PRINT PEEK(65363)\r140 END\rRUN\rNEW\r10 RESETF : CLEARS 0,0,0 : PROJCT 0\r20 WINDOW 0,479,0,271\r30 VWPORT 0,479,0,271\r40 COLOR RGB(31,0,0)\r50 MOVE 100,136 : ELIPSE 60,30\r60 LINPAT -4096\r70 MOVE 100,60 : DRAW 300,60\r80 LINPAT -1\r90 COLOR RGB(0,63,0) : PRMFIL 1\r100 MOVE 350,136 : ELIPSE 30,30\r110 PRMFIL 0\r120 TJUST 2,2 : TJUST 1,1\r130 PRINT PEEK(65363)\r140 END\rRUN\rBYE\r' > bgl.in
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
tr -d '\0\r' < bgl.out | grep -q "^2016$" || fail "PIXELR(364,67) != 2016 (string-form tri missing)"
# the NATIVE verb program: the same 35 degrees arrives as a recorded
# MDROTY 5 list CLOOP'd 3+4 times (deltas accumulate; CLOOP mixes a byte
# and a word param), the pen through COLOR RGB(31,0,0)'s GL bridge, and
# POLY3 takes its nine coordinates natively -- same pixel, now red.
tr -d '\0\r' < bgl.out | grep -q -- "^-2048$" || fail "PIXELR(364,67) != -2048 (native verbs missing)"
# (both probe blocks RESTORE the identity window first: PIXELR is the GL
# PIXRD verb now and maps through the CURRENT window like PIXELW -- the
# fully symmetric read)
# the stage-10g statements: AREA fills the yellow rectangle outline from
# a MOVE'd seed (window (150,125) -> screen (150,146); yellow $FFE0 reads
# back as -32), and AREABC fills the blue diamond teal up to a STATED
# boundary (window (320,200) -> screen (320,71); teal $07FF = 2047).
tr -d '\0\r' < bgl.out | grep -q -- "^-32$" || fail "PIXELR(150,125) != -32 (AREA fill missing)"
tr -d '\0\r' < bgl.out | grep -q "^2047$" || fail "PIXELR(320,200) != 2047 (AREABC fill missing)"
# the stage-10h statements: TDEFIN records a one-stroke glyph through the
# native verbs, TSIZE 512 (2x) scales it through the compose alias, and
# TEXT "A" replays it -- the stem's base lands at model (100,100) scaled
# to (200,200), screen (200,71), yellow (-32 again, distinct pixel). The
# trailing PEEK(65363) proves the whole session errored nowhere.
n32=$(tr -d '\0\r' < bgl.out | grep -c -- "^-32$")
[ "$n32" = "2" ] || fail "TEXT stem probe: -32 seen $n32 times, want 2"
# program 5 owns the final frame: ELIPSE outline, a dashed LINPAT line,
# a filled ELIPSE 30,30 (the circle), and TJUST round-tripping without
# error -- all native statements (ARC/SECTOR left the language
# 2026-08-30, placement headroom)
python3 - <<'EOF' || exit 1
d=open("bgl.ppm","rb").read(); px=d.split(b"\n",3)[3]
def p(x,wy):
    y=271-wy
    return px[(y*480+x)*3:(y*480+x)*3+3]
RED,GREEN,BLACK=b"\xff\x00\x00",b"\x00\xff\x00",b"\x00\x00\x00"
assert p(160,136)==RED,   "ELIPSE right point: %r"%(p(160,136),)
assert p(100,166)==RED,   "ELIPSE top point: %r"%(p(100,166),)
assert p(100,136)==BLACK, "ELIPSE centre not hollow"
assert p(100,60)==RED,    "LINPAT dash px0 missing: %r"%(p(100,60),)
assert p(105,60)==BLACK,  "LINPAT gap px5 painted: %r"%(p(105,60),)
assert p(350,156)==GREEN, "filled ELIPSE interior: %r"%(p(350,156),)
assert p(350,100)==BLACK, "filled ELIPSE leaked past its radius"
EOF
echo "BASIC-GL TEST: PASS (GL statement + native verbs + recorded-list rotation + COLOR bridge + PIXELR + AREA/AREABC + TDEFIN/TSIZE/TEXT + ELIPSE/LINPAT/TJUST)"
