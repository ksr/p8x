#!/bin/sh
# man(1): the MAN command reads /man/<name> and prints it. Build the OS, the
# man /bin program, install every os/man/* page under /man, boot, and check
# that `man <cmd>` prints the right page for a /bin command and an OS built-in,
# and that an unknown name reports "no manual entry".
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osm.bin --base 0x4000 >/dev/null

# man.bin (no //#use, so clib is a passthrough)
python3 $ROOT/tools/clib.py $ROOT/os/commands/man.c -o man.pp.c
python3 $ROOT/compiler/p8cc.py man.pp.c -o man.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py man.asm -o man.bin --base 0x7A00 >/dev/null

rm -f man.img
python3 $ROOT/tools/p8xfs.py create man.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   man.img osm.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  man.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    man.img man.bin --name /bin/man.bin --load 0x7A00 --exec 0x7A00 >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  man.img /man >/dev/null
for page in $ROOT/os/man/*; do
    base=$(basename "$page")
    [ "$base" = "README.md" ] && continue
    python3 $ROOT/tools/p8xfs.py put man.img "$page" --name "/man/$base" >/dev/null
done

out=$(printf 'B\rman dir\rman cd\rman nope\rman\r' | \
      ../p8xemu -l 300000000 -c man.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')
fail() { echo "OS-MAN TEST: FAIL — $1"; echo "$out" | tail -40; exit 1; }

# a /bin command's page
echo "$out" | grep -q 'dir - list directory contents' || fail "man dir wrong"
echo "$out" | grep -q 'dir \[-R\]'                     || fail "man dir SYNOPSIS missing"
# an OS built-in's page
echo "$out" | grep -q 'cd - change the working directory' || fail "man cd wrong"
# unknown name
echo "$out" | grep -q 'no manual entry for nope'       || fail "unknown-page message wrong"
# no argument -> usage
echo "$out" | grep -q 'usage: MAN name'                || fail "bare man usage missing"
echo "OS-MAN TEST: PASS"
