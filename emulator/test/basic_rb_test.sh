#!/bin/sh
# Stage-10e read-back from BASIC: the native FLAGRD/MATXRD statements
# push onto the RB FIFO and the GLRD factor (bare token, no parens)
# pops it -- byte value 0-255, -1 when empty.
set -e
set -o pipefail
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "BASIC-RB TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/basic/p8xbasic.asm -o brb_basic.bin \
        --base 0x6A00 -D BASORG=0x6A00 -D BASRAM=0xC500 -D PBUF=0xE000 -D MONITOR=0x2000 >/dev/null

rm -f brb.img
python3 $ROOT/tools/p8xfs.py create brb.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   brb.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  brb.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    brb.img brb_basic.bin --name /bin/basic.bin --load 0x6A00 --exec 0x6A00 >/dev/null

printf 'B\rbasic\r10 PRMFIL 1\r20 FLAGRD 1\r30 PRINT GLRD\r40 PRINT GLRD\r50 PRINT GLRD\r60 MDIDEN\r70 MDTRAN 5,6,7\r80 MATXRD 1\r90 FOR I=1 TO 18\r100 V=GLRD\r110 NEXT I\r120 A=GLRD\r130 B=GLRD\r140 PRINT A+256*B\r150 END\rRUN\rBYE\r' > brb.in
../p8xemu -N -i brb.in -c brb.img -l 400000000 eeprom.bin > brb.out 2>/dev/null || true
grep -q "Ok" brb.out || fail "program did not run"

want="1 0 -1 5"
got=$(LC_ALL=C tr -d '\0\r' < brb.out | grep -E '^-?[0-9]+$' | tr '\n' ' ' | sed 's/ $//')
[ "$got" = "$want" ] || { echo "want: $want"; echo "got:  $got"; fail "GLRD sequence differs"; }
echo "BASIC-RB TEST: PASS (native FLAGRD/MATXRD statements + the GLRD factor, empty -> -1)"
