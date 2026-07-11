#!/bin/sh
# On-target command rebuild: `sh` drives `cc` + `asm` to rebuild a command from its
# C source, and `asm` to rebuild it from its asm source, writing the binaries under
# /src/commands/{c,asm}/bin — then we RUN the freshly built C binary and check it
# behaves. This exercises the whole native toolchain (sh script runner + cc + asm
# with ;#use) the way `sh /src/mkall` does, but for one command so it's fast.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode
fail() { echo "OS-MK TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osmk.bin --base 0x4000 >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/apps/p8xcc.asm -o cc.bin --base 0x7A00 >/dev/null
python3 $ROOT/generators/gen_p8xopc.py > opctab.asm
cat $ROOT/apps/p8xasm.asm opctab.asm > asmfull.asm
python3 $ROOT/assembler/p8xasm.py asmfull.asm -o asm.bin --base 0x7A00 >/dev/null

rm -f mk.img
python3 $ROOT/tools/p8xfs.py create mk.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   mk.img osmk.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  mk.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    mk.img cc.bin  --name /bin/cc.bin  --load 0x7A00 --exec 0x7A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    mk.img asm.bin --name /bin/asm.bin --load 0x7A00 --exec 0x7A00 >/dev/null
# source tree + output dirs (mirror run.sh's layout)
for d in /src /src/commands /src/commands/c /src/commands/c/bin /src/commands/asm /src/commands/asm/bin; do
    python3 $ROOT/tools/p8xfs.py mkdir mk.img "$d" >/dev/null
done
python3 $ROOT/tools/p8xfs.py put mk.img $ROOT/os/commands/pwd.c      --name /src/commands/c/pwd.c     >/dev/null
python3 $ROOT/tools/p8xfs.py put mk.img $ROOT/os/commands-asm/pwd.asm --name /src/commands/asm/pwd.asm >/dev/null
# the build script: rebuild pwd from C (cc -> asm) and from asm
printf 'cd /\rcc /src/commands/c/pwd.c >T.ASM\rasm T.ASM /src/commands/c/bin/pwd.bin\rasm /src/commands/asm/pwd.asm /src/commands/asm/bin/pwd.bin\r' > mk.scr
python3 $ROOT/tools/p8xfs.py put mk.img mk.scr --name /mk >/dev/null

# run the build script, then RUN the freshly built C binary (should print the CWD "/")
printf 'B\rsh /mk\rrun /src/commands/c/bin/pwd.bin\r' \
    | ../p8xemu -l 3000000000 -c mk.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r' > mk_out.txt

# both binaries must now exist on the image
python3 $ROOT/tools/p8xfs.py ls mk.img /src/commands/c/bin   2>/dev/null | grep -qE '^pwd\.bin ' \
    || fail "C rebuild produced no /src/commands/c/bin/pwd.bin (cc or asm step failed)"
python3 $ROOT/tools/p8xfs.py ls mk.img /src/commands/asm/bin 2>/dev/null | grep -qE '^pwd\.bin ' \
    || fail "asm rebuild produced no /src/commands/asm/bin/pwd.bin"
# and the rebuilt C binary must run and print the CWD
grep -qE '^/$' mk_out.txt || { echo "--- transcript ---"; sed -n '/sh .mk/,$p' mk_out.txt | head; \
    fail "rebuilt pwd.bin did not run / print the CWD"; }

echo "OS-MK TEST: PASS"
