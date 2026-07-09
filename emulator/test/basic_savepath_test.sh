#!/bin/sh
# BASIC SAVE/LOAD and data-file OPEN are path-aware: they FRESOLVE the given name
# (client-side; the BIOS stays stateless, no CWD), so a bare name means the root
# and "/SUB/NAME" reaches a subdirectory. Pre-create /SUB and /LOGS on the image,
# then: SAVE a program to root and to /SUB, LOAD each back, and round-trip a data
# file in /LOGS. Host-side p8xfs confirms where each file landed.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/basic/p8xbasic.asm -o basicdisk.bin \
        --base 0x4000 -D BASORG=0x4000 -D BASRAM=0xA000 >/dev/null

rm -f sp.img
python3 $ROOT/tools/p8xfs.py create sp.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   sp.img basicdisk.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  sp.img /SUB  >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  sp.img /LOGS >/dev/null

prog='10 PRINT "ROOTPROG"\rSAVE "R"\r20 PRINT "X"\rSAVE "/SUB/P"\r'
prog="$prog"'NEW\rLOAD "/SUB/P"\rLIST\rNEW\rLOAD "R"\rLIST\r'
prog="$prog"'100 OPEN "/LOGS/DAT" FOR OUTPUT\r110 PRINT# 7\r120 CLOSE\r'
prog="$prog"'130 OPEN "/LOGS/DAT" FOR INPUT\r140 INPUT# N\r150 PRINT "GOT";N\r160 CLOSE\rRUN\r'
out=$(printf "B\r$prog" | \
      ../p8xemu -l 300000000 -c sp.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')
fail() { echo "BASIC-SAVEPATH TEST: FAIL — $1"; echo "$out" | sed -n '/P8X BASIC/,$p'; exit 1; }

echo "$out" | grep -q 'P8X BASIC' || fail "BASIC did not boot"
# LOAD "/SUB/P" brought back the 2-line program; LOAD "R" the 1-line one.
echo "$out" | grep -q '20 PRINT "X"' || fail "subdir SAVE/LOAD round-trip wrong"
# the data file round-tripped from /LOGS
echo "$out" | grep -q 'GOT7'          || fail "subdir data-file round-trip wrong"
# host-side: files landed in the right directories
tree=$(python3 $ROOT/tools/p8xfs.py tree sp.img 2>/dev/null)
echo "$tree" | grep -qE '^  R$'              || fail "root SAVE did not create /R"
echo "$tree" | grep -A1 'SUB/' | grep -q 'P'  || fail "subdir SAVE did not land in /SUB"
echo "$tree" | grep -A1 'LOGS/' | grep -q DAT || fail "data file did not land in /LOGS"
echo "BASIC-SAVEPATH TEST: PASS"
