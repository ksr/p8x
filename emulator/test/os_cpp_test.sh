#!/bin/sh
# Self-host pass 1: the native CPP (//#use splicer, os/commands/cpp.c) run ON the
# P8X must preprocess a command source equivalently to the host tools/clib.py.
# Build cpp.bin, put cat.c + the libs it pulls in on a disk, run `cpp cat.c >OUT.c`
# on-target, then compile the on-target output AND the host clib.py output with
# p8cc.py and assert the two binaries are byte-identical.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o oscpp.bin --base 0x2000 >/dev/null

# cpp itself is built on the host (it //#use apath); it becomes /bin/cpp.bin.
python3 $ROOT/tools/clib.py $ROOT/os/commands/cpp.c -o cpp.pp.c
python3 $ROOT/compiler/p8cc.py cpp.pp.c -o cpp.cc.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py cpp.cc.asm -o cpp.cc.bin --base 0x6A00 >/dev/null

rm -f cpp.img
python3 $ROOT/tools/p8xfs.py create cpp.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   cpp.img oscpp.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  cpp.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    cpp.img cpp.cc.bin --name /bin/cpp.bin --load 0x6A00 --exec 0x6A00 >/dev/null
# cat.c uses //#use glob + globx; globx uses glob + dirent — put them all at root
for f in cat.c lib_glob.c lib_globx.c lib_dirent.c; do
    python3 $ROOT/tools/p8xfs.py put cpp.img $ROOT/os/commands/$f --name /$f >/dev/null
done

# run the native cpp, capturing its combined source to /OUT.c on the card
printf 'B\rcpp cat.c >OUT.c\r' | ../p8xemu -l 400000000 -c cpp.img eeprom.bin 2>/dev/null >/dev/null
python3 $ROOT/tools/p8xfs.py get cpp.img OUT.c --out cpp_out.c >/dev/null 2>&1
fail() { echo "OS-CPP TEST: FAIL — $1"; exit 1; }
[ -s cpp_out.c ] || fail "cpp produced no /OUT.c"

# compile the on-target output and the host clib.py output; they must match
python3 $ROOT/tools/clib.py $ROOT/os/commands/cat.c -o clib_out.c
python3 $ROOT/compiler/p8cc.py cpp_out.c  -o a.asm >/dev/null 2>&1 || fail "cpp output did not compile"
python3 $ROOT/compiler/p8cc.py clib_out.c -o b.asm >/dev/null 2>&1
python3 $ROOT/assembler/p8xasm.py a.asm -o a.bin --base 0x6A00 >/dev/null
python3 $ROOT/assembler/p8xasm.py b.asm -o b.bin --base 0x6A00 >/dev/null
cmp -s a.bin b.bin || fail "cpp-preprocessed binary differs from clib.py-preprocessed binary"
echo "OS-CPP TEST: PASS"
