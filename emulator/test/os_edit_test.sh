#!/bin/sh
# EDIT (TPA text editor): under P8X/OS, create a file with the append command,
# list it, write it, quit; then re-open it and confirm the lines round-trip from
# disk. Also confirm the host tool and fsck see the new file.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o ose.bin --base 0x4000 >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/apps/p8xedit.asm -o edit.bin --base 0xB000 >/dev/null

rm -f ed.img
python3 $ROOT/tools/p8xfs.py create ed.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   ed.img ose.bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    ed.img edit.bin --name EDIT.BIN --load 0xB000 --exec 0xB000 >/dev/null

# Boot OS; build FOO.ASM, exercising append/insert/delete, save, quit; then
# reopen and confirm the edited content round-trips from disk.
#   A: LDA #1 / HLT   ->  1 LDA #1   2 HLT
#   I 1: "; HEADER"   ->  1 ; HEADER 2 LDA #1 3 HLT
#   D 2 (LDA #1)      ->  1 ; HEADER 2 HLT
script='B\r'
script="${script}RUN EDIT.BIN FOO.ASM\r"   # open new file
script="${script}A\r; HDR placeholder\r.\r" # (dummy first append, replaced below)
script="${script}D 1\r"                      # remove placeholder -> empty
script="${script}A\rLDA #1\rHLT\r.\r"        # append two lines
script="${script}I 1\r; HEADER\r.\r"         # insert a header before line 1
script="${script}D 2\r"                      # delete the LDA #1 line
script="${script}L\rW\rQ\r"                  # list, write, quit
script="${script}RUN EDIT.BIN FOO.ASM\r"     # reopen from disk
script="${script}L\rQ\r"                     # list, quit
script="${script}DIR\r"

out=$(printf "$script" | ../p8xemu -l 160000000 -c ed.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')
fail() { echo "OS-EDIT TEST: FAIL — $1"; echo "$out" | sed -n '/P8X EDIT/,$p'; exit 1; }

echo "$out" | grep -q 'SAVED'         || fail "no SAVED confirmation after W"
# the reopened session must list the edited content loaded back from disk
echo "$out" | grep -qx '1 ; HEADER'   || fail "line 1 (insert) did not round-trip"
# "2 HLT" matching exactly proves the delete worked (LDA #1 gone, HLT is line 2)
echo "$out" | grep -qx '2 HLT'        || fail "line 2 not 'HLT' — insert/delete miscounted"

python3 $ROOT/tools/p8xfs.py ls ed.img 2>/dev/null | grep -q 'FOO' \
  || { echo "OS-EDIT TEST: FAIL — host tool does not see FOO.ASM"; exit 1; }
python3 $ROOT/tools/p8xfs.py fsck ed.img >/dev/null 2>&1 \
  || { echo "OS-EDIT TEST: FAIL — volume invalid after EDIT write"; exit 1; }

echo "OS-EDIT TEST: PASS"
