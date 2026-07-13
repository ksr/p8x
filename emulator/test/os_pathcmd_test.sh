#!/bin/sh
# PATH command: view/set the program search path used by implicit RUN.
#   PATH            -> prints the current PATH (default "/bin")
#   PATH /UTIL      -> sets it; a bare command name is then found in /UTIL
#   PATH /bin;/UTIL -> multiple ';'-separated dirs are all searched
# A program GREET.bin is placed in /UTIL (NOT /bin), so it is only runnable by
# bare name once PATH includes /UTIL.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "OS-PATHCMD TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null

cat > greetp.c <<'EOF'
int main() { puts("HIYA"); return 0; }
EOF
python3 $ROOT/compiler/p8cc.py greetp.c -o greetp.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py greetp.asm -o greetp.bin --base 0x7A00 >/dev/null

rm -f pc.img
python3 $ROOT/tools/p8xfs.py create pc.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   pc.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  pc.img /UTIL >/dev/null
python3 $ROOT/tools/p8xfs.py put    pc.img greetp.bin --name /UTIL/greet.bin --load 0x7A00 --exec 0x7A00 >/dev/null

run() { printf "B\r$1\r" | ../p8xemu -l 200000000 -c pc.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r'; }

# default PATH prints /bin
run 'path' | grep -qx '/bin' || fail "PATH (no arg) did not print /bin"
# GREET is in /UTIL, not /bin -> bare GREET is unknown under the default PATH
if run 'greet' | grep -q 'HIYA'; then fail "GREET ran under default PATH (should not)"; fi
# set PATH to /UTIL, then bare GREET resolves and prints HIYA
run 'path /UTIL\rgreet'        | grep -q 'HIYA' || fail "GREET not found after PATH /UTIL"
# and PATH now prints the new value
run 'path /UTIL\rpath'         | grep -qx '/UTIL' || fail "PATH did not update to /UTIL"
# multiple ';'-separated entries are searched
run 'path /bin;/UTIL\rgreet'   | grep -q 'HIYA' || fail "multi-entry PATH search failed"

echo "OS-PATHCMD TEST: PASS"
