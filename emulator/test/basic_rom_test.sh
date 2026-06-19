#!/bin/sh
# ROM-BASIC test: build the combined monitor+BASIC EEPROM, boot the monitor,
# launch BASIC with the X command, and run a tiny program.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/tools/build_basic_rom.py eeprom.bin >/dev/null

# X launches BASIC, run a program, then BYE returns to the monitor where a
# monitor command (?) works again.
# Lead with a monitor D (dump) paging exercise: dump $0000, CR pages to the next
# block ($0100), '.' exits — then the BASIC sequence as before.
out=$(printf 'D 0000\r\r.X\r10 PRINT "ROM BASIC OK"\r20 PRINT 6*7\rRUN\rPRINT 17%%5\rPRINT 0xFF\rLET COUNT=100\rPRINT COUNT+TOTAL+11\rPRINT 2^3\rPRINT 5*9\rHELP\rBYE\r?\r' | \
      ../p8xemu -l 90000000 eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0')
fail() { echo "BASIC-ROM TEST: FAIL — $1"; echo "$out"; exit 1; }
# D paging: first block ends at row 00F0, then CR paged into the next block
# (row 0100) before '.' exited — both row labels must appear.
echo "$out" | grep -q '00F0'         || fail "D dump first block incomplete"
echo "$out" | grep -q '0100'         || fail "D paging (CR=next block) did not advance"
echo "$out" | grep -q 'P8X BASIC'    || fail "X did not launch BASIC"
echo "$out" | grep -q 'ROM BASIC OK' || fail "program did not print"
echo "$out" | grep -q '42'           || fail "6*7 != 42"
echo "$out" | grep -q '^2'           || fail "17%5 modulus != 2"
echo "$out" | grep -q '^255'         || fail "0xFF hex literal != 255"
# multi-char names: COUNT=100, TOTAL (keyword-prefixed, undefined) defaults 0
echo "$out" | grep -q '^111'         || fail "multi-char variable name failed"
# an unsupported operator ('^') must report ?SYNTAX ERROR, not silently run
# off the end of the line — and the interpreter must recover (5*9 = 45 after).
echo "$out" | grep -q '?SYNTAX ERROR' || fail "2^3 did not report ?SYNTAX ERROR"
echo "$out" | grep -q '^45'           || fail "interpreter did not recover after syntax error"
echo "$out" | grep -q 'STATEMENTS:'  || fail "HELP did not print"
# BYE should re-enter the monitor: its banner appears a second time, and the
# help text (only the monitor prints it) shows up after BYE.
[ "$(echo "$out" | grep -c 'P8X MONITOR')" -ge 2 ] || fail "BYE did not return to monitor"
echo "$out" | sed -n '/BYE/,$p' | grep -q 'EXAMINE/MODIFY' || fail "monitor not usable after BYE"
echo "BASIC-ROM TEST: PASS"
