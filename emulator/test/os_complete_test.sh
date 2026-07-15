#!/bin/sh
# Tab autocomplete in the interactive shell line editor. Tab completes the word at
# the cursor: the command word against built-ins + /bin, other words against the
# directory the word implies. Fills the longest common prefix; a second Tab lists
# the matches. Arrow/Tab keys are read raw over the piped console.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode
fail() { echo "OS-COMPLETE TEST: FAIL — $1"; [ -f "$2" ] && { echo "--- transcript ---"; cat "$2"; }; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o oscmp.bin --base 0x2000 >/dev/null
rm -f cmp.img
python3 $ROOT/tools/p8xfs.py create cmp.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   cmp.img oscmp.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  cmp.img /bin >/dev/null
printf 'hi\n' > HELLO.TXT
python3 $ROOT/tools/p8xfs.py put cmp.img HELLO.TXT --name /HELLO.TXT >/dev/null
python3 $ROOT/tools/p8xfs.py put cmp.img HELLO.TXT --name /HELP.TXT  >/dev/null
TAB=$(printf '\t')

run() { printf "$1" | ../p8xemu -l 200000000 -c cmp.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r\010'; }

# 1) command word: 'ma' completes to the sole built-in 'make ' (adds a space);
#    running it here reports no Makefile in the CWD.
run "B\rma${TAB}\r" > c1.txt
grep -q 'make: no Makefile' c1.txt || fail "'ma'+Tab did not complete to the 'make' built-in" c1.txt

# 2) argument dir, no slash: 'cd b' -> 'cd bin/' (adds '/'); the prompt becomes /bin/.
run "B\rcd b${TAB}\r" > c2.txt
grep -q '/bin/' c2.txt || fail "'cd b'+Tab did not complete the CWD directory 'bin/'" c2.txt

# 3) path with a slash: 'cd /b' -> 'cd /bin/'.
run "B\rcd /b${TAB}\r" > c3.txt
grep -q '/bin/' c3.txt || fail "'cd /b'+Tab did not complete the path '/bin/'" c3.txt

# 4) ambiguous file: 'cat /HE' fills the common prefix '/HEL', a second Tab lists
#    both matches (HELLO.TXT and HELP.TXT).
run "B\rcat /HE${TAB}${TAB}" > c4.txt
grep -q 'HELLO.TXT' c4.txt && grep -q 'HELP.TXT' c4.txt \
    || fail "'cat /HE'+Tab+Tab did not list HELLO.TXT and HELP.TXT" c4.txt

echo "OS-COMPLETE TEST: PASS"
