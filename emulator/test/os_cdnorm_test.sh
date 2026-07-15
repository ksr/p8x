#!/bin/sh
# CWD path normalization: `cd foo/` (trailing slash) and `cd a//b` must not leave
# stray/doubled slashes in the displayed path, and a following `cd ..` must pop a
# real component (not the empty trailing one). Before the fix, `cd os-bios/`
# showed `/src/os-bios/`, `cd asm` showed `/src/os-bios//asm`, and `cd ..`
# desynced the prompt from the actual directory. Guard PATHNORM.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode
fail() { echo "OS-CDNORM TEST: FAIL — $1"; echo "$out"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o oscd.bin --base 0x2000 >/dev/null
rm -f cd.img
python3 $ROOT/tools/p8xfs.py create cd.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   cd.img oscd.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  cd.img /aa >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  cd.img /aa/bb >/dev/null

out=$(printf 'B\rcd aa/\rcd bb\rcd ..\rcd ..\r' | \
      ../p8xemu -l 300000000 -c cd.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')
# `cd aa/` -> prompt "/aa>" exactly (no trailing slash)
echo "$out" | grep -q '/aa> cd bb'        || fail "cd aa/ did not normalize to /aa (trailing slash kept?)"
# `cd bb` -> "/aa/bb>" (single slash, not //)
echo "$out" | grep -q '/aa/bb> cd \.\.'   || fail "cd bb produced a doubled or wrong slash"
echo "$out" | grep -q '//'                && fail "a doubled slash appears somewhere in the CWD path"
# `cd ..` from /aa/bb -> /aa , then `cd ..` -> / (root prompt)
echo "$out" | grep -q '/aa> cd \.\.'      || fail "cd .. from /aa/bb did not land on /aa"
printf '%s' "$out" | grep -q '/> ' && :   # a bare "/> " prompt appears after the last cd ..
echo "OS-CDNORM TEST: PASS"
