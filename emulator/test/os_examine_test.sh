#!/bin/sh
# examine: interactive memory examine/modify (the ROM monitor's `E` as a /bin
# command), shipped as C + hand-asm twins. Write a couple of bytes through
# examine, read them back with dump, and confirm the two twins produce identical
# output for the same keystrokes.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode
fail() { echo "OS-EXAMINE TEST: FAIL — $1"; [ -n "$2" ] && printf '%s\n' "$2"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osex.bin --base 0x2000 >/dev/null

# C twin: examine + dump
python3 $ROOT/tools/clib.py $ROOT/os/commands/examine.c -o examine.pp.c
python3 $ROOT/compiler/p8cc.py examine.pp.c -o examine.c.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py examine.c.asm -o examine.c.bin --base 0x6A00 >/dev/null
python3 $ROOT/tools/clib.py $ROOT/os/commands/dump.c -o dump.pp.c
python3 $ROOT/compiler/p8cc.py dump.pp.c -o dump.x.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py dump.x.asm -o dump.x.bin --base 0x6A00 >/dev/null
# asm twin: mkasm splices ;#use, then assemble
sh $ROOT/os/commands-asm/mkasm.sh examine > examine.a.asm
python3 $ROOT/assembler/p8xasm.py examine.a.asm -o examine.a.bin --base 0x6A00 >/dev/null

mkdisk() { # mkdisk <img> <examine.bin>
    rm -f "$1"
    python3 $ROOT/tools/p8xfs.py create "$1" >/dev/null
    python3 $ROOT/tools/p8xfs.py boot   "$1" osex.bin >/dev/null
    python3 $ROOT/tools/p8xfs.py mkdir  "$1" /bin >/dev/null
    python3 $ROOT/tools/p8xfs.py put    "$1" "$2"        --name /bin/examine.bin --load 0x6A00 --exec 0x6A00 >/dev/null
    python3 $ROOT/tools/p8xfs.py put    "$1" dump.x.bin  --name /bin/dump.bin    --load 0x6A00 --exec 0x6A00 >/dev/null
}
mkdisk exc.img examine.c.bin
mkdisk exa.img examine.a.bin

# $C000 is clear of the program at $6A00. examine auto-advances after each pair
# of hex digits, so AB5C writes AB at C000 and 5C at C001; '.' quits. Then dump
# reads them back. (A bare Enter would instead skip a byte -- not exercised here.)
SEQ='B\rexamine C000\rAB5C.\rdump C000\r.\r'
cout=$(printf "$SEQ" | ../p8xemu -l 250000000 -c exc.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')
aout=$(printf "$SEQ" | ../p8xemu -l 250000000 -c exa.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')

# the write landed: dump shows AB 5C at C000
echo "$cout" | grep -q '^C000: AB 5C' || fail "examine did not write AB,5C to C000 (C twin)" "$cout"
# the two twins behave identically
[ "$cout" = "$aout" ] || fail "C and asm twins produced different output" \
    "--- C ---
$cout
--- asm ---
$aout"

echo "OS-EXAMINE TEST: PASS"
