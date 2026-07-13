#!/bin/sh
# dump/dep offloaded to /bin: they are no longer OS built-ins, so typing `dep`
# or `dump` by bare name must resolve on PATH to /bin/{dep,dump}.bin. Deposit
# some bytes with dep, read them back with dump, and confirm the hex+ASCII row.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osdd.bin --base 0x2000 >/dev/null

for c in dep dump; do
    python3 $ROOT/tools/clib.py $ROOT/os/commands/$c.c -o $c.pp.c
    python3 $ROOT/compiler/p8cc.py $c.pp.c -o $c.dd.asm >/dev/null
    python3 $ROOT/assembler/p8xasm.py $c.dd.asm -o $c.dd.bin --base 0x7A00 >/dev/null
done

rm -f dd.img
python3 $ROOT/tools/p8xfs.py create dd.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   dd.img osdd.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  dd.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    dd.img dep.dd.bin  --name /bin/dep.bin  --load 0x7A00 --exec 0x7A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    dd.img dump.dd.bin --name /bin/dump.bin --load 0x7A00 --exec 0x7A00 >/dev/null

# bare-name dep/dump (no `run`), proving the built-ins are gone. $9000 is clear
# of the program at $7A00. '.' exits dump's pager.
out=$(printf 'B\rdep 9000 41 42 43 44\rdump 9000\r.\r' | \
      ../p8xemu -l 250000000 -c dd.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')
fail() { echo "OS-DEPDUMP TEST: FAIL — $1"; echo "$out" | tail -20; exit 1; }

echo "$out" | grep -q '^9000: 41 42 43 44' || fail "dep+dump round-trip wrong (bare-name dispatch?)"
echo "$out" | grep -q 'ABCD'                || fail "ASCII column wrong"
echo "OS-DEPDUMP TEST: PASS"
