#!/bin/sh
# The C-written BASIC (basic/basic.c, the size/speed twin of basic/p8xbasic.asm):
# build it with the host toolchain, install it as /bin/basicc.bin on a fresh OS
# disk, and run the SAME programs the asm-BASIC tests use -- strings, STR$/VAL/
# EOF, FOR/STEP, entry-time syntax checking, data files, SAVE/LOAD, and BYE back
# to a live shell -- checking the same lines. Any behavioural drift between the
# two interpreters shows up here.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode
fail() { echo "BASIC-C TEST: FAIL — $1"; [ -f "$2" ] && { echo "--- transcript ---"; cat "$2"; }; exit 1; }
cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osbc.bin --base 0x2000 >/dev/null
# the C build: the generated GL verb tables + the source, //#use spliced, p8cc.py
python3 $ROOT/generators/gen_glkw.py >/dev/null
cat $ROOT/basic/glkwtab.c $ROOT/basic/basic.c > basicc_src.c
cp $ROOT/os/commands/lib_abi.c .
python3 $ROOT/tools/clib.py basicc_src.c -o basicc_pp.c >/dev/null
python3 $ROOT/compiler/p8cc.py basicc_pp.c -o basicc.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py basicc.asm -o basicc.bin --base 0x6100 >/dev/null
rm -f bcc.img
python3 $ROOT/tools/p8xfs.py create bcc.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   bcc.img osbc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  bcc.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    bcc.img basicc.bin --name /bin/basicc.bin --load 0x6100 --exec 0x6100 >/dev/null
run() { printf "B\rbasicc\r$1" | ../p8xemu -l 400000000 -c bcc.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r'; }
# --- 1. strings (basic_string_test's program) + BYE back to the shell ---------
prog='10 A$="HELLO"\r20 B$="WORLD"\r30 PRINT A$;" ";B$\r40 PRINT LEN(A$)\r'
prog="$prog"'50 PRINT LEFT$(A$,3)\r60 PRINT RIGHT$(B$,3)\r70 PRINT MID$(A$,2,3)\r'
prog="$prog"'80 PRINT CHR$(65)\r90 PRINT ASC("Z")\r100 C$=A$+B$\r110 PRINT C$\r'
prog="$prog"'120 IF A$="HELLO" THEN PRINT "EQ"\r130 IF A$<>B$ THEN PRINT "NE"\r'
prog="$prog"'140 IF "AA"<"AB" THEN PRINT "LT"\r150 INPUT N$\r160 PRINT "HI ";N$\r'
run "${prog}RUN\rAda\rBYE\rmkdir /Z\r" > bcc1.txt
grep -q 'P8X BASIC'    bcc1.txt || fail "the C BASIC did not start" bcc1.txt
grep -q 'HELLO WORLD'  bcc1.txt || fail "string var PRINT / separators wrong" bcc1.txt
grep -q '^5$'          bcc1.txt || fail "LEN wrong" bcc1.txt
grep -q '^HEL$'        bcc1.txt || fail "LEFT\$ wrong" bcc1.txt
grep -q '^RLD$'        bcc1.txt || fail "RIGHT\$ wrong" bcc1.txt
grep -q '^ELL$'        bcc1.txt || fail "MID\$ wrong" bcc1.txt
grep -q '^A$'          bcc1.txt || fail "CHR\$ wrong" bcc1.txt
grep -q '^90$'         bcc1.txt || fail "ASC wrong" bcc1.txt
grep -q '^HELLOWORLD$' bcc1.txt || fail "concatenation wrong" bcc1.txt
grep -q '^EQ$'         bcc1.txt || fail "string = wrong" bcc1.txt
grep -q '^NE$'         bcc1.txt || fail "string <> wrong" bcc1.txt
grep -q '^LT$'         bcc1.txt || fail "string < wrong" bcc1.txt
grep -q 'HI Ada'       bcc1.txt || fail "INPUT into a string variable wrong" bcc1.txt
grep -q 'DIR CREATED'  bcc1.txt || fail "BYE did not return to a live shell" bcc1.txt
[ "$(grep -c 'P8X/OS v' bcc1.txt)" = "1" ] || fail "BYE rebooted the OS" bcc1.txt
# --- 2. STR$ / VAL / EOF + data files (basic_strval_test's program) -----------
prog='10 A$="N=" + STR$(42)\r20 PRINT A$\r30 PRINT STR$(-7)\r40 PRINT STR$(0)\r'
prog="$prog"'50 PRINT VAL("123")\r60 PRINT VAL("-45")\r70 PRINT VAL("12ABC")\r'
prog="$prog"'80 B$="99" : PRINT VAL(B$)+1\r'
prog="$prog"'100 OPEN "D" FOR OUTPUT\r110 PRINT# 11\r120 PRINT# 22\r130 PRINT# 33\r140 CLOSE\r'
prog="$prog"'150 OPEN "D" FOR INPUT\r160 IF EOF(1) THEN 200\r170 INPUT# X\r180 PRINT X\r190 GOTO 160\r'
prog="$prog"'200 CLOSE\r210 PRINT "DONE"\r'
run "${prog}RUN\rBYE\r" > bcc2.txt
grep -q '^N=42$'  bcc2.txt || fail "STR\$ concat wrong" bcc2.txt
grep -q '^-7$'    bcc2.txt || fail "STR\$ negative wrong" bcc2.txt
grep -q '^0$'     bcc2.txt || fail "STR\$(0) wrong" bcc2.txt
grep -q '^123$'   bcc2.txt || fail "VAL wrong" bcc2.txt
grep -q '^-45$'   bcc2.txt || fail "VAL negative wrong" bcc2.txt
grep -q '^12$'    bcc2.txt || fail "VAL stop at non-digit wrong" bcc2.txt
grep -q '^100$'   bcc2.txt || fail "VAL(B\$)+1 wrong" bcc2.txt
grep -q '^DONE$'  bcc2.txt || fail "EOF loop did not terminate" bcc2.txt
n=$(grep -cE '^(11|22|33)$' bcc2.txt); [ "$n" = "3" ] || fail "EOF loop read $n records, expected 3" bcc2.txt
# --- 3. FOR/STEP + entry-time syntax check + the RUN-time error line ---------
prog='10 FOR I=10 TO 1 STEP -1\r20 PRINT I;\r30 NEXT I\r40 PRINT\r50 FOR J=1 TO 5\r60 PRINT J;\r70 NEXT J\r80 PRINT\r'
prog="$prog"'90 FOR K=0 TO 10 STEP 2\r100 PRINT K;\r110 NEXT K\r120 PRINT\rRUN\r'
prog="$prog"'NEW\r10 PRINT (1+2\r20 PRINT "HI\r30 THEN 40\r10 PRINT (1+2)*3\r40 PRINT "OK)"\rRUN\rPRINT 2+3\r'
prog="$prog"'NEW\r10 PRINT "A"\r20 print 100\r30 PRINT "C"\rRUN\rprint 9\rBYE\r'
run "$prog" > bcc3.txt
grep -q '^10987654321$' bcc3.txt || fail "STEP -1 countdown wrong" bcc3.txt
grep -q '^12345$'       bcc3.txt || fail "plain up-loop wrong" bcc3.txt
grep -q '^0246810$'     bcc3.txt || fail "STEP 2 wrong" bcc3.txt
grep -q '^9$'           bcc3.txt || fail "the good line 10 did not run (expected 9)" bcc3.txt
grep -q 'OK)'           bcc3.txt || fail "a string containing ')' was mishandled" bcc3.txt
grep -q '^5$'           bcc3.txt || fail "immediate PRINT 2+3 did not print 5" bcc3.txt
grep -q 'SYNTAX ERROR IN 20' bcc3.txt || fail "the RUN-time error did not name its line" bcc3.txt
n=$(grep -c '^?SYNTAX ERROR$' bcc3.txt); [ "$n" = "4" ] || fail "expected 4 bare ?SYNTAX ERROR (3 at entry + print 9), got $n" bcc3.txt
# --- 4. data-file records (basic_fileio_test's program) + SAVE/LOAD ----------
prog='10 OPEN "DATA" FOR OUTPUT\r20 PRINT# 42\r30 PRINT# "HELLO"\r'
prog="$prog"'40 FOR I=1 TO 3 : PRINT# I*I : NEXT\r50 CLOSE\r'
prog="$prog"'60 OPEN "DATA" FOR INPUT\r70 INPUT# A\r80 INPUT# A$\r'
prog="$prog"'90 PRINT A;" ";A$\r100 FOR I=1 TO 3 : INPUT# X : PRINT X;" "; : NEXT\r'
prog="$prog"'110 PRINT\r120 CLOSE\rRUN\rSAVE "PROG"\rNEW\rLIST\rLOAD "PROG"\rLIST\rBYE\r'
run "$prog" > bcc4.txt
grep -q '42 HELLO' bcc4.txt || fail "INPUT# of a number and a string wrong" bcc4.txt
grep -q '1 4 9'    bcc4.txt || fail "INPUT# in a loop wrong" bcc4.txt
grep -q 'Saved'    bcc4.txt || fail "SAVE did not report" bcc4.txt
grep -q 'Loaded'   bcc4.txt || fail "LOAD did not report" bcc4.txt
post=$(sed -n '/Loaded/,$p' bcc4.txt)
echo "$post" | grep -q '10 OPEN "DATA" FOR OUTPUT' || fail "LOAD did not restore the program" bcc4.txt
python3 $ROOT/tools/p8xfs.py get bcc.img DATA --out bcc_data.bin >/dev/null 2>&1 || fail "the data file was not written" bcc4.txt
[ "$(cat bcc_data.bin)" = "$(printf '42\rHELLO\r1\r4\r9\r')" ] || fail "on-disk records differ" bcc4.txt
echo "BASIC-C TEST: PASS ($(wc -c < basicc.bin | tr -d ' ') B, strings, STR\$/VAL/EOF, FOR/STEP, syntax check, files, SAVE/LOAD, BYE)"
