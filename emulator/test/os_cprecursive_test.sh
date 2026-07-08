#!/bin/sh
# cp -r: recursive directory copy, including across the /D1 mount. Supersedes the
# old IMPORT built-in (which was flat, one-level, drive-1->CWD). Drive 0 boots
# and holds CP.BIN; a source tree lives on drive 0 (/SRC) and one on drive 1
# (/D1/TREE). Through the shell:
#   CP /SRC/TOP.TXT /COPY.TXT   -> single-file copy still works
#   CP -r /SRC /DST             -> same-drive recursive copy (nested subdir)
#   CP -r /D1/TREE /IMP         -> cross-mount recursive copy (drive 1 -> drive 0)
# PASS iff every file lands at the right path on drive 0 with the source content
# (host-verified), including the nested files.
set -e
cd "$(dirname "$0")"
ROOT=../..

cp $ROOT/microcode/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x4000 >/dev/null

python3 $ROOT/tools/clib.py $ROOT/os/commands/cp.c -o cr_cp.pp.c
python3 $ROOT/compiler/p8cc.py cr_cp.pp.c -o cr_cp.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py cr_cp.asm -o cr_cp.bin --base 0x7A00 >/dev/null

rm -f cr0.img cr1.img
python3 $ROOT/tools/p8xfs.py create cr0.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   cr0.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  cr0.img /BIN >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  cr0.img /D1  >/dev/null
python3 $ROOT/tools/p8xfs.py put cr0.img cr_cp.bin --name /BIN/CP.BIN --load 0x7A00 --exec 0x7A00 >/dev/null
# drive-0 source tree /SRC with a file + a nested subdir file
python3 $ROOT/tools/p8xfs.py mkdir cr0.img /SRC >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir cr0.img /SRC/SUB >/dev/null
printf 'top file\r\n'    > cr_t.dat;  python3 $ROOT/tools/p8xfs.py put cr0.img cr_t.dat  --name /SRC/TOP.TXT      --load 0 --exec 0 >/dev/null
printf 'nested file\r\n' > cr_n.dat;  python3 $ROOT/tools/p8xfs.py put cr0.img cr_n.dat  --name /SRC/SUB/NEST.TXT --load 0 --exec 0 >/dev/null
# drive-1 tree /TREE with a file + a nested subdir file
python3 $ROOT/tools/p8xfs.py create cr1.img >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  cr1.img /TREE >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  cr1.img /TREE/DEEP >/dev/null
printf 'drive1 a\r\n' > cr_a.dat;  python3 $ROOT/tools/p8xfs.py put cr1.img cr_a.dat --name /TREE/A.TXT      --load 0 --exec 0 >/dev/null
printf 'drive1 b\r\n' > cr_b.dat;  python3 $ROOT/tools/p8xfs.py put cr1.img cr_b.dat --name /TREE/DEEP/B.TXT --load 0 --exec 0 >/dev/null

printf 'B\rCP /SRC/TOP.TXT /COPY.TXT\rCP -r /SRC /DST\rCP -r /D1/TREE /IMP\r' \
    | ../p8xemu -l 400000000 -c cr0.img -c2 cr1.img eeprom.bin 2>/dev/null >/dev/null

chk() {   # $1 = path on drive 0, $2 = expected substring
    python3 $ROOT/tools/p8xfs.py get cr0.img "$1" --out cr_got.out >/dev/null 2>&1 \
        || { echo "OS-CPRECURSIVE TEST: FAIL — $1 missing on drive 0"; exit 1; }
    grep -q "$2" cr_got.out \
        || { echo "OS-CPRECURSIVE TEST: FAIL — $1 content wrong:"; cat cr_got.out; exit 1; }
}
chk /COPY.TXT        'top file'      # single-file copy
chk /DST/TOP.TXT     'top file'      # same-drive -r, top level
chk /DST/SUB/NEST.TXT 'nested file'  # same-drive -r, nested
chk /IMP/A.TXT       'drive1 a'      # cross-mount -r, top level
chk /IMP/DEEP/B.TXT  'drive1 b'      # cross-mount -r, nested
# and the cross-mount copy must NOT have leaked back onto drive 1
python3 $ROOT/tools/p8xfs.py get cr1.img /IMP/A.TXT --out /dev/null >/dev/null 2>&1 \
    && { echo "OS-CPRECURSIVE TEST: FAIL — /IMP leaked onto drive 1"; exit 1; } || true

echo "OS-CPRECURSIVE TEST: PASS"
