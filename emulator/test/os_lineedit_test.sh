#!/bin/sh
# Shell line editing in GETLN: backspace ($08) and DEL ($7F) erase the last
# typed character (and rub it out on screen with BS/space/BS), and the input is
# capped at the 64-byte LINEBUF so a long line can't overrun CMDBUF.
#   typed "XYZ" + 3 backspaces + "PWD"  -> runs PWD (no "?" unknown-command line)
#   typed "PWDQ" + DEL                  -> runs PWD
#   control: "XYZPWD" (no edit)         -> unknown command, a lone "?" line
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "OS-LINEEDIT TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x4000 >/dev/null

rm -f le.img
python3 $ROOT/tools/p8xfs.py create le.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   le.img osc.bin >/dev/null

run() {  # $1 = bytes to type (printf escapes ok) -> stripped console output
    printf "B\r$1\r" | ../p8xemu -l 150000000 -c le.img eeprom.bin 2>/dev/null \
        | LC_ALL=C tr -d '\0\r'
}

# control: an uncorrected bad command must produce a lone "?" (the unknown-command
# marker; the banner's "? FOR HELP" is not a lone line, so -x distinguishes it).
run 'XYZPWD' | grep -qx '?' || fail "control: unknown command did not print '?'"

# backspace: "XYZ" + 3x BS clears the word, leaving "PWD" -> valid, no lone "?"
if run 'XYZ\b\b\bPWD' | grep -qx '?'; then fail "backspace did not erase (got '?')"; fi

# DEL key ($7F=\177): "PWDQ" + DEL -> "PWD" -> valid, no lone "?"
if run 'PWDQ\177' | grep -qx '?'; then fail "DEL did not erase (got '?')"; fi

# backspace at the start of an empty line must be harmless, then a real command runs
if run '\b\b\bPWD' | grep -qx '?'; then fail "backspace past start of line corrupted input"; fi

echo "OS-LINEEDIT TEST: PASS"
