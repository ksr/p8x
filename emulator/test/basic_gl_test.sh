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

printf 'B\rbasic\r10 GL "WINDOW -120 120 -120 120"\r20 GL "VWPORT 104 375 0 271"\r30 GL "COLOR 0 63 0 PRMFIL 1"\r40 A=35\r50 GL "MDY "+STR$(A)\r60 GL "POLY3 3 -80 -80 300 80 -80 300 0 40 420"\r70 PRINT POINT(220,136)\r80 END\rRUN\rBYE\r' > bgl.in
../p8xemu -N -i bgl.in -c bgl.img -l 400000000 -g bgl.ppm eeprom.bin > bgl.out 2>/dev/null || true
grep -q "Ok" bgl.out || fail "program did not run"
tr -d '\0\r' < bgl.out | grep -q "^2016$" || fail "POINT(220,136) != 2016 (rotated tri missing)"
python3 - <<'EOF' || exit 1
d=open("bgl.ppm","rb").read(); px=d.split(b"\n",3)[3]
assert px[(136*480+220)*3:(136*480+220)*3+3]==b"\x00\xff\x00", "pixel not green"
EOF
echo "BASIC-GL TEST: PASS (GL statement + string arithmetic + rotated fill + POINT)"
