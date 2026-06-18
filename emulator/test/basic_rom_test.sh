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
out=$(printf 'X\r10 PRINT "ROM BASIC OK"\r20 PRINT 6*7\rRUN\rPRINT 17%%5\rPRINT 0xFF\rHELP\rBYE\r?\r' | \
      ../p8xemu -l 90000000 eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0')
fail() { echo "BASIC-ROM TEST: FAIL — $1"; echo "$out"; exit 1; }
echo "$out" | grep -q 'P8X BASIC'    || fail "X did not launch BASIC"
echo "$out" | grep -q 'ROM BASIC OK' || fail "program did not print"
echo "$out" | grep -q '42'           || fail "6*7 != 42"
echo "$out" | grep -q '^2'           || fail "17%5 modulus != 2"
echo "$out" | grep -q '^255'         || fail "0xFF hex literal != 255"
echo "$out" | grep -q 'STATEMENTS:'  || fail "HELP did not print"
# BYE should re-enter the monitor: its banner appears a second time, and the
# help text (only the monitor prints it) shows up after BYE.
[ "$(echo "$out" | grep -c 'P8X MONITOR')" -ge 2 ] || fail "BYE did not return to monitor"
echo "$out" | sed -n '/BYE/,$p' | grep -q 'EXAMINE/MODIFY' || fail "monitor not usable after BYE"
echo "BASIC-ROM TEST: PASS"
