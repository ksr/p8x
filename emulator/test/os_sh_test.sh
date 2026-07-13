#!/bin/sh
# `sh FILE` — the shell script runner (os/p8xos.asm). The shell streams the script
# a line at a time (its read-stream state is saved/restored around each command, so
# a script of ANY length works), running each line through the normal DISPATCH
# (built-ins, /bin programs, >, <, | all work), then returns to the console at EOF.
# Checks: (1) a two-line script creates both dirs + hands back to the prompt;
# (2) a >512-byte script (50 mkdirs) runs fully, proving there is no size cap.
#   (the cc+asm build-a-command use case is exercised manually / in os_mk_test)
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode
fail() { echo "OS-SH TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o ossh.bin --base 0x2000 >/dev/null

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

# ---- big script: 50 mkdirs (~550 bytes) must ALL run (past the old 512 cap) ----
rm -f big.img big.scr
python3 $ROOT/tools/p8xfs.py create big.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   big.img ossh.bin >/dev/null
i=0; : > big.scr
while [ $i -lt 50 ]; do printf 'mkdir /D%02d\r' "$i" >> big.scr; i=$((i+1)); done
python3 $ROOT/tools/p8xfs.py put big.img big.scr --name /b >/dev/null
printf 'B\rsh b\r' | ../p8xemu -l 900000000 -c big.img eeprom.bin >/dev/null 2>&1
n=$(python3 $ROOT/tools/p8xfs.py ls big.img / 2>/dev/null | grep -cE '^D[0-9][0-9] ')
[ "$n" -eq 50 ] || fail "big script: only $n/50 dirs created (streaming past 512B broken)"

echo "OS-SH TEST: PASS"
