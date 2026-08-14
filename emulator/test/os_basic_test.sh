#!/bin/sh
# Run BASIC as a P8X/OS program: build a TPA-resident BASIC (code+data+scratch all
# in $B000.., clear of the OS at $2000-$AFFF) whose BYE returns to the OS cold
# start ($2000) instead of the ROM monitor. Install it on the disk as BASIC.bin
# (load/exec $B000), boot the OS, RUN it, run a tiny program, and BYE back to the
# OS shell — proving it round-trips without disturbing the resident OS.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osb.bin --base 0x2000 >/dev/null
# TPA build: code @ $B000, data @ $C500, rebuild scratch @ $E000, BYE -> OS ($2000).
python3 $ROOT/assembler/p8xasm.py $ROOT/basic/p8xbasic.asm -o basicrun.bin \
        --base 0x6A00 -D BASORG=0x6A00 -D BASRAM=0xC500 -D PBUF=0xE000 -D MONITOR=0x2000 >/dev/null

rm -f ob.img
python3 $ROOT/tools/p8xfs.py create ob.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   ob.img osb.bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    ob.img basicrun.bin --name BASIC.bin --load 0x6A00 --exec 0x6A00 >/dev/null

out=$(printf 'B\rrun BASIC.bin\r10 PRINT "INBASIC"\rRUN\rBYE\rmkdir /Z\r' | \
      ../p8xemu -l 300000000 -c ob.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0')
fail() { echo "OS-BASIC TEST: FAIL — $1"; echo "$out" | sed -n '/v1.0/,$p'; exit 1; }

echo "$out" | grep -q 'P8X BASIC'  || fail "RUN BASIC.bin did not launch BASIC"
echo "$out" | grep -q 'INBASIC'    || fail "program did not run inside BASIC"
# BYE must return to the OS shell -- WITHOUT rebooting it.
#
# This assertion used to require the banner to appear a SECOND time, which was
# encoding a bug as the pass condition: BYE did `JMP MONITOR`, and for the TPA
# build MONITOR is $2000 = the OS COLD entry, so leaving BASIC rebooted the OS.
# That reprinted the banner and, less visibly, threw away the current directory.
# BYE now restores the entry stack and RTSes back to the shell that ran it, so
# the banner appears exactly ONCE for the whole session.
[ "$(echo "$out" | grep -c 'P8X/OS v1.0')" = "1" ] \
    || fail "BYE rebooted the OS (banner printed more than once) instead of returning to the shell"
# DIR is no longer a built-in (and this disk has no /bin), so prove the shell is
# usable after BYE with a still-native command: MKDIR /Z -> "DIR CREATED".
echo "$out" | sed -n '/INBASIC/,$p' | grep -q 'DIR CREATED' || fail "OS shell not usable after BYE (MKDIR)"
echo "OS-BASIC TEST: PASS"
