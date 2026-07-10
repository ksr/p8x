#!/bin/sh
# STR$ / VAL / EOF: number->string (STR$), string->number (VAL, signed, stops at
# the first non-digit), and end-of-file detection (EOF) driving a read loop that
# stops at exactly the right record. Boot disk-BASIC and run a program that
# exercises each, checking the emitted lines.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/basic/p8xbasic.asm -o basicdisk.bin \
        --base 0x4000 -D BASORG=0x4000 -D BASRAM=0xA000 >/dev/null

rm -f bsv.img
python3 $ROOT/tools/p8xfs.py create bsv.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot bsv.img basicdisk.bin >/dev/null

# STR$ (incl. negative and zero), string concat with STR$, then VAL round-trips.
prog='10 A$="N=" + STR$(42)\r20 PRINT A$\r30 PRINT STR$(-7)\r40 PRINT STR$(0)\r'
prog="$prog"'50 PRINT VAL("123")\r60 PRINT VAL("-45")\r70 PRINT VAL("12ABC")\r'
prog="$prog"'80 B$="99" : PRINT VAL(B$)+1\r'
# EOF: write three records, then read with an EOF-guarded loop -> exactly 3 values.
prog="$prog"'100 OPEN "D" FOR OUTPUT\r110 PRINT# 11\r120 PRINT# 22\r130 PRINT# 33\r140 CLOSE\r'
prog="$prog"'150 OPEN "D" FOR INPUT\r160 IF EOF(1) THEN 200\r170 INPUT# X\r180 PRINT X\r190 GOTO 160\r'
prog="$prog"'200 CLOSE\r210 PRINT "DONE"\r'
out=$(printf "B\r${prog}RUN\r" | \
      ../p8xemu -l 300000000 -c bsv.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')
fail() { echo "BASIC-STRVAL TEST: FAIL — $1"; echo "$out" | sed -n '/P8X BASIC/,$p'; exit 1; }

echo "$out" | grep -q 'P8X BASIC'  || fail "BASIC did not boot"
echo "$out" | grep -q '^N=42$'     || fail "STR\$ concat wrong"
echo "$out" | grep -q '^-7$'       || fail "STR\$ of a negative number wrong"
echo "$out" | grep -q '^0$'        || fail "STR\$(0) wrong"
echo "$out" | grep -q '^123$'      || fail "VAL wrong"
echo "$out" | grep -q '^-45$'      || fail "VAL of a negative wrong"
echo "$out" | grep -q '^12$'       || fail "VAL stopping at non-digit wrong"
echo "$out" | grep -q '^100$'      || fail "VAL(B\$)+1 wrong"
echo "$out" | grep -q '^11$'       || fail "EOF loop: first record wrong"
echo "$out" | grep -q '^33$'       || fail "EOF loop: last record wrong"
echo "$out" | grep -q '^DONE$'     || fail "EOF loop did not terminate cleanly"
# the loop must read EXACTLY three records — no spurious 4th line before DONE
n=$(echo "$out" | grep -cE '^(11|22|33)$')
[ "$n" = "3" ] || fail "EOF loop read $n records, expected 3"
echo "BASIC-STRVAL TEST: PASS"
