#!/bin/sh
# BIOS write-stream API: a planted program writes a file with FWOPEN/FPUTB/
# FCLOSE, reads it back via FOPEN/FGETB ('HELLO'), and the host confirms the
# file is on the volume with the right contents and the volume is still valid.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py hwrite.asm -o hwrite.bin --base 0x4000 >/dev/null

rm -f fw.img
python3 $ROOT/tools/p8xfs.py create fw.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   fw.img hwrite.bin >/dev/null

out=$(printf 'B\r' | ../p8xemu -l 50000000 -c fw.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')
case "$out" in
  *HELLO*) ;;
  *) echo "FWRITE TEST: FAIL — read-back not 'HELLO' (got [$out])"; exit 1 ;;
esac

# host: the file exists, round-trips, volume valid
python3 $ROOT/tools/p8xfs.py get fw.img W >/dev/null 2>&1 || { echo "FWRITE TEST: FAIL — W not created"; exit 1; }
test "$(cat W)" = "HELLO" || { echo "FWRITE TEST: FAIL — host contents wrong ($(cat W))"; rm -f W; exit 1; }
rm -f W
python3 $ROOT/tools/p8xfs.py fsck fw.img >/dev/null 2>&1 || { echo "FWRITE TEST: FAIL — volume invalid"; exit 1; }
echo "FWRITE TEST: PASS"
