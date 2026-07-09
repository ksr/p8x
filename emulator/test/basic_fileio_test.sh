#!/bin/sh
# Sequential data files: OPEN "name" FOR OUTPUT|INPUT, PRINT# (one value + CR per
# record), INPUT# (one record -> numeric or string variable), CLOSE. Write a mix
# of numbers and strings — including from inside a FOR loop — then reopen and read
# them all back, and cross-check the file bytes host-side with p8xfs.py.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/basic/p8xbasic.asm -o basicdisk.bin \
        --base 0x4000 -D BASORG=0x4000 -D BASRAM=0xA000 >/dev/null

rm -f bio.img
python3 $ROOT/tools/p8xfs.py create bio.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot bio.img basicdisk.bin >/dev/null

prog='10 OPEN "DATA" FOR OUTPUT\r20 PRINT# 42\r30 PRINT# "HELLO"\r'
prog="$prog"'40 FOR I=1 TO 3 : PRINT# I*I : NEXT\r50 CLOSE\r'
prog="$prog"'60 OPEN "DATA" FOR INPUT\r70 INPUT# A\r80 INPUT# A$\r'
prog="$prog"'90 PRINT A;" ";A$\r100 FOR I=1 TO 3 : INPUT# X : PRINT X;" "; : NEXT\r'
prog="$prog"'110 PRINT\r120 CLOSE\r'
out=$(printf "B\r${prog}RUN\r" | \
      ../p8xemu -l 300000000 -c bio.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')
fail() { echo "BASIC-FILEIO TEST: FAIL — $1"; echo "$out" | sed -n '/P8X BASIC/,$p'; exit 1; }

echo "$out" | grep -q 'P8X BASIC'    || fail "BASIC did not boot"
echo "$out" | grep -q 'HELLO'        || fail "read-back of number+string record wrong"
echo "$out" | grep -q '42 HELLO'     || fail "INPUT# of A (42) and A\$ (HELLO) wrong"
echo "$out" | grep -q '1 4 9'        || fail "INPUT# in a loop (squares) wrong"
# host-side: the file holds one CR-delimited record per value.
python3 $ROOT/tools/p8xfs.py get bio.img DATA --out /tmp/bio_data.$$ >/dev/null 2>&1
want=$(printf '42\rHELLO\r1\r4\r9\r')
got=$(cat /tmp/bio_data.$$); rm -f /tmp/bio_data.$$
[ "$got" = "$want" ] || fail "on-disk bytes differ from expected records"
echo "BASIC-FILEIO TEST: PASS"
