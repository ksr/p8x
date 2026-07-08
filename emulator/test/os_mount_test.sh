#!/bin/sh
# Unified-namespace mount: drive 1 is mounted at /D1, so ordinary paths reach it
# with no drive-prefix syntax and drive-unaware /BIN commands. Drive 0 boots and
# holds the command binaries in /BIN. From the root we:
#   CAT /D1/HELLO.TXT        -> read a file on the mounted drive
#   DIR /D1/SUB              -> list a directory on the mounted drive
#   CP /D1/HELLO.TXT /GOT.TXT -> cross-mount copy (read drive 1, write drive 0)
# PASS iff each targets the right card and the cross-mount copy lands on drive 0
# with drive 1's content (host-verified) without leaking onto drive 1.
set -e
cd "$(dirname "$0")"
ROOT=../..

cp $ROOT/microcode/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x4000 >/dev/null

build_cmd() {   # $1 = command name -> $1.BIN in /BIN of mn0
    python3 $ROOT/tools/clib.py $ROOT/os/commands/$1.c -o mn_$1.pp.c
    python3 $ROOT/compiler/p8cc.py mn_$1.pp.c -o mn_$1.asm >/dev/null
    python3 $ROOT/assembler/p8xasm.py mn_$1.asm -o mn_$1.bin --base 0x7A00 >/dev/null
}

# drive 0: bootable, /BIN with the three commands + the /D1 mount placeholder
rm -f mn0.img mn1.img
python3 $ROOT/tools/p8xfs.py create mn0.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   mn0.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  mn0.img /BIN >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  mn0.img /D1 >/dev/null
for c in cat dir cp; do
    build_cmd $c
    U=$(echo $c | tr a-z A-Z)
    python3 $ROOT/tools/p8xfs.py put mn0.img mn_$c.bin --name /BIN/$U.BIN --load 0x7A00 --exec 0x7A00 >/dev/null
done

# drive 1: a data card with a file at root and a file in /SUB (appear under /D1)
python3 $ROOT/tools/p8xfs.py create mn1.img >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  mn1.img /SUB >/dev/null
printf 'hello from drive one\r\n' > mn_hello.dat
python3 $ROOT/tools/p8xfs.py put mn1.img mn_hello.dat --name /HELLO.TXT --load 0 --exec 0 >/dev/null
printf 'inside sub\r\n' > mn_sub.dat
python3 $ROOT/tools/p8xfs.py put mn1.img mn_sub.dat --name /SUB/INNER.TXT --load 0 --exec 0 >/dev/null

R() {   # run one shell line on the two-drive machine, strip NULs/CR
    printf "B\r$1\r" | ../p8xemu -l 200000000 -c mn0.img -c2 mn1.img eeprom.bin 2>/dev/null \
        | LC_ALL=C tr -d '\0' | tr '\r' '\n'
}

# 1) CAT a mounted file
R 'CAT /D1/HELLO.TXT' | grep -q 'hello from drive one' \
    || { echo "OS-MOUNT TEST: FAIL — CAT /D1/HELLO.TXT"; R 'CAT /D1/HELLO.TXT'; exit 1; }

# 2) DIR a mounted subdirectory
R 'DIR /D1/SUB' | grep -q 'INNER.TXT' \
    || { echo "OS-MOUNT TEST: FAIL — DIR /D1/SUB"; R 'DIR /D1/SUB'; exit 1; }

# 3) cross-mount copy drive1 -> drive0, then host-verify it landed on drive 0
R 'CP /D1/HELLO.TXT /GOT.TXT' >/dev/null
python3 $ROOT/tools/p8xfs.py get mn0.img /GOT.TXT --out mn_got.out >/dev/null 2>&1 \
    || { echo "OS-MOUNT TEST: FAIL — GOT.TXT not on drive 0"; exit 1; }
grep -q 'hello from drive one' mn_got.out \
    || { echo "OS-MOUNT TEST: FAIL — GOT.TXT content wrong:"; cat mn_got.out; exit 1; }
# and confirm it did NOT write to drive 1
python3 $ROOT/tools/p8xfs.py get mn1.img /GOT.TXT --out /dev/null >/dev/null 2>&1 \
    && { echo "OS-MOUNT TEST: FAIL — GOT.TXT leaked onto drive 1"; exit 1; } || true

echo "OS-MOUNT TEST: PASS"
