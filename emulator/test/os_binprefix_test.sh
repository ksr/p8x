#!/bin/sh
# Inline "N:" drive prefix on /BIN commands (dual-CF). Drive 0 boots and holds
# the command binaries in /BIN; drive 1 is a data card. From drive 0 we:
#   CAT 1:/HELLO.TXT        -> read a file on the other drive
#   DIR 1:/SUB              -> list a directory on the other drive
#   CP 1:/HELLO.TXT 0:/GOT.TXT  -> cross-drive copy (read drive1, write drive0)
# PASS iff each targets the right card and the cross-drive copy lands on drive 0
# with drive 1's content (host-verified).
set -e
cd "$(dirname "$0")"
ROOT=../..

cp $ROOT/microcode/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x4000 >/dev/null

build_cmd() {   # $1 = command name -> $1.BIN in /BIN of im0
    python3 $ROOT/tools/clib.py $ROOT/os/commands/$1.c -o bp_$1.pp.c
    python3 $ROOT/compiler/p8cc.py bp_$1.pp.c -o bp_$1.asm >/dev/null
    python3 $ROOT/assembler/p8xasm.py bp_$1.asm -o bp_$1.bin --base 0x7A00 >/dev/null
}

# drive 0: bootable, /BIN with the three commands under test
rm -f bp0.img bp1.img
python3 $ROOT/tools/p8xfs.py create bp0.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   bp0.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  bp0.img /BIN >/dev/null
for c in cat dir cp; do
    build_cmd $c
    U=$(echo $c | tr a-z A-Z)
    python3 $ROOT/tools/p8xfs.py put bp0.img bp_$c.bin --name /BIN/$U.BIN --load 0x7A00 --exec 0x7A00 >/dev/null
done

# drive 1: data card with a file at root and a file in /SUB
python3 $ROOT/tools/p8xfs.py create bp1.img >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  bp1.img /SUB >/dev/null
printf 'hello from drive one\r\n' > bp_hello.dat
python3 $ROOT/tools/p8xfs.py put bp1.img bp_hello.dat --name /HELLO.TXT --load 0 --exec 0 >/dev/null
printf 'inside sub\r\n' > bp_sub.dat
python3 $ROOT/tools/p8xfs.py put bp1.img bp_sub.dat --name /SUB/INNER.TXT --load 0 --exec 0 >/dev/null

R() {   # run one shell line on the two-drive machine, strip NULs/CR
    printf "B\r$1\r" | ../p8xemu -l 200000000 -c bp0.img -c2 bp1.img eeprom.bin 2>/dev/null \
        | LC_ALL=C tr -d '\0' | tr '\r' '\n'
}

# 1) CAT the drive-1 file from drive 0
R 'CAT 1:/HELLO.TXT' | grep -q 'hello from drive one' \
    || { echo "OS-BINPREFIX TEST: FAIL — CAT 1:/HELLO.TXT"; R 'CAT 1:/HELLO.TXT'; exit 1; }

# 2) DIR the drive-1 subdirectory from drive 0
R 'DIR 1:/SUB' | grep -q 'INNER.TXT' \
    || { echo "OS-BINPREFIX TEST: FAIL — DIR 1:/SUB"; R 'DIR 1:/SUB'; exit 1; }

# 3) cross-drive copy drive1 -> drive0, then host-verify it landed on drive 0
R 'CP 1:/HELLO.TXT 0:/GOT.TXT' >/dev/null
python3 $ROOT/tools/p8xfs.py get bp0.img /GOT.TXT --out bp_got.out >/dev/null 2>&1 \
    || { echo "OS-BINPREFIX TEST: FAIL — GOT.TXT not on drive 0"; exit 1; }
grep -q 'hello from drive one' bp_got.out \
    || { echo "OS-BINPREFIX TEST: FAIL — GOT.TXT content wrong:"; cat bp_got.out; exit 1; }
# and confirm it did NOT accidentally write to drive 1
python3 $ROOT/tools/p8xfs.py get bp1.img /GOT.TXT --out /dev/null >/dev/null 2>&1 \
    && { echo "OS-BINPREFIX TEST: FAIL — GOT.TXT leaked onto drive 1"; exit 1; } || true

echo "OS-BINPREFIX TEST: PASS"
