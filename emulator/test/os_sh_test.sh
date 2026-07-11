#!/bin/sh
# `sh FILE` — the shell script runner (os/p8xos.asm). The shell slurps the whole
# script into APBUF and runs each line through the normal DISPATCH (built-ins,
# /bin programs, >, <, | all work), then returns to the console at end-of-script.
# Fast mechanism check: a two-line script of built-ins (mkdir) must create BOTH
# directories and then hand control back to the interactive prompt.
#   (the cc+asm build-a-command use case is exercised manually / in os_mk_test)
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode
fail() { echo "OS-SH TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o ossh.bin --base 0x4000 >/dev/null

rm -f sh.img
python3 $ROOT/tools/p8xfs.py create sh.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   sh.img ossh.bin >/dev/null
# a script of two built-in commands (CR-separated, as an on-target editor writes)
printf 'mkdir /FOO\rmkdir /BAR\r' > s.scr
python3 $ROOT/tools/p8xfs.py put sh.img s.scr --name /s >/dev/null

# run the script, then prove the shell is back at the console by running one more
# interactive command (mkdir /BAZ) after it.
printf 'B\rsh s\rmkdir /BAZ\r' \
    | ../p8xemu -l 400000000 -c sh.img eeprom.bin >/dev/null 2>&1

# all three directories must exist: FOO+BAR from the script, BAZ from the console
for d in FOO BAR BAZ; do
    python3 $ROOT/tools/p8xfs.py ls sh.img / 2>/dev/null | grep -qE "^$d " \
        || fail "/$d missing (script line or post-script console command didn't run)"
done
# and they must be clean names (a botched line-split makes e.g. 'FOOmkdir')
python3 $ROOT/tools/p8xfs.py ls sh.img / 2>/dev/null | grep -qE '[A-Z]mkdir' \
    && fail "concatenated command — script line-splitting is broken" || true

echo "OS-SH TEST: PASS"
