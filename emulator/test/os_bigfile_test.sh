#!/bin/sh
# >64 KB files — the BIOS file length is 24-bit (FLEN/ROREM/WOTOT/FLAREM), so a
# file may be up to 16 MB. This regresses the read AND write streams past the old
# 16-bit (64 KB) wall in one shot: put a >64 KB file host-side, then on-target
# `cat BIG.TXT > COPY.TXT` (read stream -> write stream -> FCOM_CORE), and verify
# COPY.TXT is byte-identical host-side and the volume stays FSCK-clean. Before the
# 24-bit widening the length wrapped mod 65536 and the copy truncated/corrupted.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "OS-BIGFILE TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o bfos.bin --base 0x4000 >/dev/null
python3 $ROOT/tools/clib.py $ROOT/os/commands/cat.c -o bfcat.c
python3 $ROOT/compiler/p8cc.py bfcat.c -o bfcat.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py bfcat.asm -o bfcat.bin --base 0x7A00 >/dev/null
# dir + wc: their size column / byte count must show a >64 KB value, not mod 65536
python3 $ROOT/tools/clib.py $ROOT/os/commands/dir.c -o bfdir.c
python3 $ROOT/compiler/p8cc.py bfdir.c -o bfdir.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py bfdir.asm -o bfdir.bin --base 0x7A00 >/dev/null
python3 $ROOT/tools/clib.py $ROOT/os/commands/wc.c -o bfwc.c
python3 $ROOT/compiler/p8cc.py bfwc.c -o bfwc.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py bfwc.asm -o bfwc.bin --base 0x7A00 >/dev/null

# 66000 bytes (>64 KB): 6000 distinct 11-char lines, so any wrap/truncation shows.
python3 -c "
f=open('bf_big.txt','w')
for i in range(6000): f.write('L%09d\n'%i)   # 11 chars/line * 6000 = 66000
f.close()
import os; assert os.path.getsize('bf_big.txt')==66000"

rm -f bf.img
python3 $ROOT/tools/p8xfs.py create bf.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   bf.img bfos.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  bf.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    bf.img bfcat.bin --name /bin/cat.bin --load 0x7A00 --exec 0x7A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    bf.img bfdir.bin --name /bin/dir.bin --load 0x7A00 --exec 0x7A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    bf.img bfwc.bin  --name /bin/wc.bin  --load 0x7A00 --exec 0x7A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    bf.img bf_big.txt --name /BIG.TXT >/dev/null

# read the 66 KB file and stream it back out to a new file (read + write past 64 KB)
printf 'B\rcat /BIG.TXT > COPY.TXT\r' | ../p8xemu -l 12000000000 -c bf.img eeprom.bin >/dev/null 2>&1

python3 $ROOT/tools/p8xfs.py get bf.img /COPY.TXT --out bf_copy.txt >/dev/null 2>&1 \
    || fail "COPY.TXT not created (>64 KB write failed)"
sz=$(wc -c < bf_copy.txt | tr -d ' ')
[ "$sz" -eq 66000 ] || fail "COPY.TXT is $sz bytes, expected 66000 (length wrapped?)"
cmp -s bf_big.txt bf_copy.txt || fail "COPY.TXT differs from the 66 KB source"
python3 $ROOT/tools/p8xfs.py fsck bf.img >/dev/null 2>&1 || fail "volume invalid after >64 KB write"

# PACK must relocate a >64 KB extent correctly (its sector count is 24-bit-derived,
# 16-bit SECCNT:SECCH). Free BIG.TXT to open a gap before COPY.TXT, compact, and
# confirm the 66 KB COPY.TXT survived byte-for-byte. Before the widening PACK copied
# only ceil((len mod 65536)/512) sectors and shredded the file.
printf 'B\rdel /BIG.TXT\rpack\r' | ../p8xemu -l 8000000000 -c bf.img eeprom.bin >/dev/null 2>&1
python3 $ROOT/tools/p8xfs.py get bf.img /COPY.TXT --out bf_packed.txt >/dev/null 2>&1 \
    || fail "COPY.TXT gone after PACK"
psz=$(wc -c < bf_packed.txt | tr -d ' ')
[ "$psz" -eq 66000 ] || fail "COPY.TXT is $psz bytes after PACK, expected 66000 (mis-packed)"
cmp -s bf_big.txt bf_packed.txt || fail "COPY.TXT corrupted by PACK (>64 KB extent mis-copied)"
python3 $ROOT/tools/p8xfs.py fsck bf.img >/dev/null 2>&1 || fail "volume invalid after PACK"

# dir size column + wc byte count must render the full 66000, not 66000 mod 65536
# (=464). COPY.TXT is 66000 bytes after the PACK above.
out=$(printf 'B\rdir\rwc /COPY.TXT\r' | ../p8xemu -l 4000000000 -c bf.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')
echo "$out" | grep -qE ' 66000  COPY.TXT' || fail "dir did not show the 24-bit size 66000 (wrapped?)"
echo "$out" | grep -qE '(^| )66000' || fail "wc did not show the 24-bit byte count 66000"

echo "OS-BIGFILE TEST: PASS"
