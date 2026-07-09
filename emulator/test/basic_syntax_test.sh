#!/bin/sh
# Entry-time syntax checking: BASIC's CHECKLINE rejects malformed lines the moment
# they are typed (?SYNTAX ERROR, program unchanged) instead of only failing at RUN.
# We feed three bad lines and then a good replacement for line 10, and confirm:
#   - each bad line produces ?SYNTAX ERROR at entry,
#   - the bad line 10 did NOT get stored (the good one runs and prints 9),
#   - a legal string containing ')' is not mistaken for an error,
#   - a valid immediate PRINT still works.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/basic/p8xbasic.asm -o basicdisk.bin \
        --base 0x4000 -D BASORG=0x4000 -D BASRAM=0xA000 >/dev/null

rm -f bsyn.img
python3 $ROOT/tools/p8xfs.py create bsyn.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot bsyn.img basicdisk.bin >/dev/null

# bad: unbalanced '(' ; unterminated string ; illegal leader (THEN)
# good: replace line 10 with a balanced expression; a string with ')' inside;
#       a bare immediate expression.
CMDS='10 PRINT (1+2\r20 PRINT "HI\r30 THEN 40\r10 PRINT (1+2)*3\r40 PRINT "OK)"\rRUN\rPRINT 2+3\r'
out=$(printf "B\r$CMDS" | ../p8xemu -l 120000000 -c bsyn.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0')
fail() { echo "BASIC-SYNTAX TEST: FAIL — $1"; echo "$out"; exit 1; }

echo "$out" | grep -q 'P8X BASIC' || fail "BASIC did not boot from disk"
# the three malformed lines must each be rejected at entry
n=$(echo "$out" | grep -c 'SYNTAX ERROR')
[ "$n" -eq 3 ] || fail "expected 3 ?SYNTAX ERROR at entry, got $n"
# the good line 10 replaced nothing bad and runs: (1+2)*3 = 9, then "OK)"
echo "$out" | grep -q '^9'   || fail "valid parenthesized expression did not run (expected 9)"
echo "$out" | grep -q 'OK)'  || fail "string containing ')' was mishandled"
# a valid immediate statement still works
echo "$out" | grep -q '^5'   || fail "valid immediate PRINT 2+3 did not print 5"
echo "BASIC-SYNTAX TEST: PASS"
