#!/bin/sh
# String variables and functions: A$-style variables, assignment, '+' concat,
# =/<> and ordering comparisons in IF, PRINT/INPUT of strings, and the built-in
# functions LEN, CHR$, ASC, LEFT$, RIGHT$, MID$. Boot disk-BASIC and run a
# program that exercises each, checking the emitted lines.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/basic/p8xbasic.asm -o basicdisk.bin \
        --base 0x2000 -D BASORG=0x2000 -D BASRAM=0xA000 >/dev/null

rm -f bstr.img
python3 $ROOT/tools/p8xfs.py create bstr.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot bstr.img basicdisk.bin >/dev/null

prog='10 A$="HELLO"\r20 B$="WORLD"\r30 PRINT A$;" ";B$\r40 PRINT LEN(A$)\r'
prog="$prog"'50 PRINT LEFT$(A$,3)\r60 PRINT RIGHT$(B$,3)\r70 PRINT MID$(A$,2,3)\r'
prog="$prog"'80 PRINT CHR$(65)\r90 PRINT ASC("Z")\r100 C$=A$+B$\r110 PRINT C$\r'
prog="$prog"'120 IF A$="HELLO" THEN PRINT "EQ"\r130 IF A$<>B$ THEN PRINT "NE"\r'
prog="$prog"'140 IF "AA"<"AB" THEN PRINT "LT"\r150 INPUT N$\r160 PRINT "HI ";N$\r'
out=$(printf "B\r${prog}RUN\rAda\r" | \
      ../p8xemu -l 250000000 -c bstr.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')
fail() { echo "BASIC-STRING TEST: FAIL — $1"; echo "$out" | sed -n '/P8X BASIC/,$p'; exit 1; }

echo "$out" | grep -q 'P8X BASIC'    || fail "BASIC did not boot"
echo "$out" | grep -q 'HELLO WORLD'  || fail "string var PRINT / separators wrong"
echo "$out" | grep -q '^5$'          || fail "LEN(A\$) wrong"
echo "$out" | grep -q '^HEL$'        || fail "LEFT\$ wrong"
echo "$out" | grep -q '^RLD$'        || fail "RIGHT\$ wrong"
echo "$out" | grep -q '^ELL$'        || fail "MID\$ wrong"
echo "$out" | grep -q '^A$'          || fail "CHR\$ wrong"
echo "$out" | grep -q '^90$'         || fail "ASC wrong"
echo "$out" | grep -q '^HELLOWORLD$' || fail "concatenation wrong"
echo "$out" | grep -q '^EQ$'         || fail "string = comparison wrong"
echo "$out" | grep -q '^NE$'         || fail "string <> comparison wrong"
echo "$out" | grep -q '^LT$'         || fail "string < ordering wrong"
echo "$out" | grep -q 'HI Ada'       || fail "INPUT into a string variable wrong"
echo "BASIC-STRING TEST: PASS"
