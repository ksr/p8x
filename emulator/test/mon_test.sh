#!/bin/sh
# Monitor smoke test: with just the monitor EEPROM (no OS, no card), exercise the
# D (dump) command's paging and the ?/H help. This is the bare-monitor coverage
# that used to ride along in basic_rom_test.sh before ROM BASIC was removed.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null

fail() { echo "MONITOR TEST: FAIL — $1"; echo "$out"; exit 1; }

# D 0000 dumps a 256-byte block (rows $0000..$00F0); CR pages to the next block
# ($0100..); '.' exits. Then ? prints the help. (No card needed.)
out=$(printf 'D 0000\r\r.?\r' | ../p8xemu -l 40000000 eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0')

echo "$out" | grep -q '00F0'             || fail "D dump first block incomplete"
echo "$out" | grep -q '0100'             || fail "D paging (CR=next block) did not advance"
echo "$out" | grep -q 'P8XMON COMMANDS'  || fail "? did not print the help"
echo "$out" | grep -q 'EXAMINE/MODIFY'   || fail "help text incomplete"
# ROM BASIC is gone: there must be no 'X' launch line in the help any more.
echo "$out" | grep -q 'RUN ROM BASIC'    && fail "stale ROM BASIC help line still present"
echo "MONITOR TEST: PASS"
