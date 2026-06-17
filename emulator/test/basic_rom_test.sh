#!/bin/sh
# ROM-BASIC test: build the combined monitor+BASIC EEPROM, boot the monitor,
# launch BASIC with the X command, and run a tiny program.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/tools/build_basic_rom.py eeprom.bin >/dev/null

out=$(printf 'X\r10 PRINT "ROM BASIC OK"\r20 PRINT 6*7\rRUN\r' | \
      ../p8xemu -l 90000000 eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0')
fail() { echo "BASIC-ROM TEST: FAIL — $1"; echo "$out"; exit 1; }
echo "$out" | grep -q 'P8X BASIC'    || fail "X did not launch BASIC"
echo "$out" | grep -q 'ROM BASIC OK' || fail "program did not print"
echo "$out" | grep -q '42'           || fail "6*7 != 42"
echo "BASIC-ROM TEST: PASS"
