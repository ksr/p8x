#!/bin/sh
# help (os/commands/help.c): the command reference moved out of the OS shell
# into /bin -- ~1.4 KB of static text that had no business in the resident OS.
# A bare `help` (implicit-RUN of /bin/help.bin) must still print the reference.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-HELP TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null
python3 $ROOT/tools/clib.py $ROOT/os/commands/help.c -o help.pp.c
python3 $ROOT/compiler/p8cc.py help.pp.c -o help.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py help.asm -o help.bin --base 0x6A00 >/dev/null

rm -f hlp.img
python3 $ROOT/tools/p8xfs.py create hlp.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   hlp.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  hlp.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    hlp.img help.bin --name /bin/help.bin --load 0x6A00 --exec 0x6A00 >/dev/null

printf 'B\rhelp\r' > hlp.in      # BARE help (implicit run, not "run /bin/...")
../p8xemu -N -i hlp.in -c hlp.img -l 200000000 eeprom.bin > hlp.out 2>/dev/null || true

grep -q "P8X/OS COMMANDS" hlp.out || fail "help header missing"
grep -q "windowed GUI"    hlp.out || fail "help body missing (desk/wdesk line)"
grep -q "pipe a's output" hlp.out || fail "help tail missing (pipe line)"
echo "C-HELP TEST: PASS (help is a /bin command: bare 'help' prints the full command reference)"
