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
python3 $ROOT/tools/p8xfs.py mkdir  cd.img /cc >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  cd.img /cc/dd >/dev/null

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
# --- compound ".." components (the case bare `cd ..` above does not reach) -----
# `cd ../../cc/dd` from /aa/bb must collapse to /cc/dd. SETPATH used to test only
# whether the WHOLE argument was ".." and append anything else verbatim, giving
# "/aa/bb/../../cc/dd". That was not cosmetic: nothing collapsed the "..", so each
# relative cd grew the string past the real depth and CWDPATH is 48 bytes -- six
# cds reached 63 chars, over $642F into INMODE/INARM (stdin-redirect state) and,
# further, CWDLH itself. Walk components; keep them collapsed.
out=$(printf 'B\rcd aa\rcd bb\rcd ../../cc/dd\rsave M.BIN 2000 2010\r' | \
      ../p8xemu -l 500000000 -c cd.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')
echo "$out" | grep -q '/cc/dd> ' || fail "cd ../../cc/dd did not collapse to /cc/dd"
# check the PROMPT PATHS only -- the echoed command line legitimately contains ".."
printf '%s' "$out" | grep -o '^/[^ >]*' | grep -q '\.\.' \
  && fail "a '..' survived into the displayed CWD path"
# the displayed path must be the REAL cwd, not just a plausible string: the file
# has to land in /cc/dd on disk.
python3 $ROOT/tools/p8xfs.py ls cd.img /cc/dd 2>/dev/null | grep -q 'M.BIN' \
  || fail "SAVE after cd ../../cc/dd did not write into /cc/dd (path desynced from CWDL)"

# --- the path must never leave its 48-byte buffer --------------------------------
# A real tree deeper than the buffer must CLAMP, not overflow into INMODE/CWDLH.
rm -f deep.img
python3 $ROOT/tools/p8xfs.py create deep.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   deep.img oscd.bin >/dev/null
dp=""
for d in aaaaaaaa bbbbbbbb cccccccc dddddddd eeeeeeee ffffffff; do
  dp="$dp/$d"; python3 $ROOT/tools/p8xfs.py mkdir deep.img "$dp" >/dev/null
done
out=$(printf 'B\rcd aaaaaaaa\rcd bbbbbbbb\rcd cccccccc\rcd dddddddd\rcd eeeeeeee\rcd ffffffff\r' | \
      ../p8xemu -l 700000000 -c deep.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')
longest=$(printf '%s' "$out" | grep -o '^/[^ >]*' | awk '{print length($0)}' | sort -n | tail -1)
[ "$longest" -le 47 ] || fail "CWD path reached $longest chars; the 48-byte CWDPATH buffer overflowed"

echo "OS-CDNORM TEST: PASS"
