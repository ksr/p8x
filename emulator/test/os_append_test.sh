#!/bin/sh
# ">>" append redirection. P8XFS extents are contiguous (no in-place growth), so
# ">>" is copy-then-extend: stream the existing file's bytes into a fresh write
# stream, then the command's output, then register over the old entry (old extent
# reclaimed by PACK). Exercises all the paths that share the BIOS sector buffer:
#   - program stdout (REDIRF=2) append to a new file and to an existing file
#   - the "< in >> out" combo (stdin + append: both resolve their files BEFORE
#     FWOPEN, since an FFIND after FWOPEN would corrupt the unflushed output)
#   - append inside a subdirectory
#   - built-in capture path (HELP) append
# Verifies content host-side and that FSCK stays clean.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "OS-APPEND TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o apos.bin --base 0x4000 >/dev/null
python3 $ROOT/tools/clib.py $ROOT/os/commands/cat.c -o apcat.c
python3 $ROOT/compiler/p8cc.py apcat.c -o apcat.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py apcat.asm -o apcat.bin --base 0xB000 >/dev/null

rm -f ap.img
python3 $ROOT/tools/p8xfs.py create ap.img --v2 >/dev/null
python3 $ROOT/tools/p8xfs.py boot   ap.img apos.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  ap.img /BIN >/dev/null
python3 $ROOT/tools/p8xfs.py put    ap.img apcat.bin --name /BIN/CAT.BIN --load 0xB000 --exec 0xB000 >/dev/null
printf 'oneline\n' > apin.dat
python3 $ROOT/tools/p8xfs.py put    ap.img apin.dat --name /IN.TXT >/dev/null

# On-target: cat > then >> (program path); < + >> combo twice; >> to a new file;
# >> inside a subdir; HELP >> (built-in capture path).
printf 'B\rCAT >F.TXT\rAAAA\r\004CAT >>F.TXT\rBBBB\r\004CAT <IN.TXT >>LOG.TXT\rCAT <IN.TXT >>LOG.TXT\rCAT >>NEW.TXT\rzz\r\004MKDIR /S\rCD /S\rCAT >>A\rp\r\004CAT >>A\rq\r\004CD /\rFSCK\r' \
  | ../p8xemu -l 700000000 -c ap.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r' | grep -q 'FSCK OK' \
  || fail "on-target FSCK flagged the volume after the appends"

# Built-in capture path: HELP > then HELP >> doubles the file.
printf 'B\rHELP >H.TXT\rHELP >>H.TXT\r' | ../p8xemu -l 300000000 -c ap.img eeprom.bin 2>/dev/null >/dev/null
printf 'B\rHELP >H1.TXT\r'             | ../p8xemu -l 300000000 -c ap.img eeprom.bin 2>/dev/null >/dev/null

# --- host-side content checks ---
chk() { python3 $ROOT/tools/p8xfs.py get ap.img "$1" --out ap.tmp >/dev/null 2>&1 || fail "get $1 failed"; tr -d '\r' < ap.tmp; }
[ "$(chk /F.TXT)" = "$(printf 'AAAA\nBBBB')" ]       || fail "program >> to existing wrong (F.TXT)"
[ "$(chk /LOG.TXT)" = "$(printf 'oneline\noneline')" ] || fail "< + >> combo wrong (LOG.TXT)"
[ "$(chk /NEW.TXT)" = "zz" ]                          || fail ">> to a new file wrong (NEW.TXT)"
[ "$(chk /S/A)" = "$(printf 'p\nq')" ]                || fail ">> in a subdir wrong (/S/A)"
# built-in capture append: H.TXT == exactly twice H1.TXT
h2=$(python3 $ROOT/tools/p8xfs.py ls ap.img / 2>/dev/null | awk '$1=="H.TXT"{print $2}')
h1=$(python3 $ROOT/tools/p8xfs.py ls ap.img / 2>/dev/null | awk '$1=="H1.TXT"{print $2}')
[ -n "$h1" ] && [ "$h2" = "$((h1 * 2))" ] || fail "built-in HELP >> not 2x (h1=$h1 h2=$h2)"

python3 $ROOT/tools/p8xfs.py fsck ap.img >ap_fsck.tmp 2>&1 || { cat ap_fsck.tmp; fail "host fsck failed"; }
rm -f ap.tmp ap_fsck.tmp apin.dat apcat.c apcat.asm

echo "OS-APPEND TEST: PASS"
