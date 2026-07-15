#!/bin/sh
# Command-line history in the interactive shell line editor. Arrow keys arrive as
# ESC '[' 'A' (up) / 'B' (down); GETLN recalls previous lines into LINEBUF and
# redraws. This drives the emulator's console over a pipe (the OS echoes what it
# recalls), stripping backspaces so the recalled text shows plainly.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode
fail() { echo "OS-HIST TEST: FAIL — $1"; [ -f "$2" ] && { echo "--- transcript ---"; cat "$2"; }; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o oshist.bin --base 0x2000 >/dev/null
rm -f hist.img
python3 $ROOT/tools/p8xfs.py create hist.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   hist.img oshist.bin >/dev/null

ESC=$(printf '\033')
run() { # run <keystrokes> -> transcript (NULs, CRs, backspaces stripped)
    printf "$1" | ../p8xemu -l 200000000 -c hist.img eeprom.bin 2>/dev/null \
        | LC_ALL=C tr -d '\0\r\010'
}

# 1) Up recalls most-recent-first: type aaa,bbb then Up Up -> bbb then aaa on one
#    redrawn prompt line.
run 'B\raaa\rbbb\r'"$ESC"'[A'"$ESC"'[A\r' > h1.txt
grep -qE 'bbb.*aaa' h1.txt || fail "up-arrow did not recall bbb then aaa" h1.txt

# 2) Down walks back toward the newest: Up Up Up (zzz,yyy,xxx) then Down (yyy).
run 'B\rxxx\ryyy\rzzz\r'"$ESC"'[A'"$ESC"'[A'"$ESC"'[A'"$ESC"'[B\r' > h2.txt
grep -qE 'zzz.*yyy.*xxx.*yyy' h2.txt || fail "down-arrow did not step from xxx back to yyy" h2.txt

# 3) Consecutive duplicates are stored once: one,dup,dup then Up (dup) Up (one).
run 'B\rone\rdup\rdup\r'"$ESC"'[A'"$ESC"'[A\r' > h3.txt
grep -qE 'dup.*one' h3.txt || fail "dedup failed: second Up should reach 'one', not 'dup'" h3.txt

echo "OS-HIST TEST: PASS"
