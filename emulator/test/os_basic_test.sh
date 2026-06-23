#!/bin/sh
# Run BASIC as a P8X/OS program: build a TPA-resident BASIC (code+data+scratch all
# in $B000.., clear of the OS at $4000-$AFFF) whose BYE returns to the OS cold
# start ($4000) instead of the ROM monitor. Install it on the disk as BASIC.BIN
# (load/exec $B000), boot the OS, RUN it, run a tiny program, and BYE back to the
# OS shell — proving it round-trips without disturbing the resident OS.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osb.bin --base 0x4000 >/dev/null
# TPA build: code @ $B000, data @ $C500, rebuild scratch @ $E000, BYE -> OS ($4000).
python3 $ROOT/assembler/p8xasm.py $ROOT/basic/p8xbasic.asm -o basicrun.bin \
        --base 0xB000 -D BASORG=0xB000 -D BASRAM=0xC500 -D PBUF=0xE000 -D MONITOR=0x4000 >/dev/null

rm -f ob.img
python3 $ROOT/tools/p8xfs.py create ob.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   ob.img osb.bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    ob.img basicrun.bin --name BASIC.BIN --load 0xB000 --exec 0xB000 >/dev/null

out=$(printf 'B\rRUN BASIC.BIN\r10 PRINT "INBASIC"\rRUN\rBYE\rDIR\r' | \
      ../p8xemu -l 300000000 -c ob.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0')
fail() { echo "OS-BASIC TEST: FAIL — $1"; echo "$out" | sed -n '/v1.0/,$p'; exit 1; }

echo "$out" | grep -q 'P8X BASIC'  || fail "RUN BASIC.BIN did not launch BASIC"
echo "$out" | grep -q 'INBASIC'    || fail "program did not run inside BASIC"
# BYE must return to the OS (its banner appears a 2nd time) and the shell works.
[ "$(echo "$out" | grep -c 'P8X/OS v1.0')" -ge 2 ] || fail "BYE did not return to the OS"
echo "$out" | sed -n '/INBASIC/,$p' | grep -q 'BASIC.BIN' || fail "OS shell not usable after BYE (DIR)"
echo "OS-BASIC TEST: PASS"
