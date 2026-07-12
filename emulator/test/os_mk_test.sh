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
# cp is needed on-target to exercise `make installc` (publish c/bin -> /bin).
python3 $ROOT/tools/clib.py $ROOT/os/commands/cp.c -o cp.pp.c 2>/dev/null
python3 $ROOT/compiler/p8cc.py cp.pp.c -o cp.asm >/dev/null 2>&1
python3 $ROOT/assembler/p8xasm.py cp.asm -o cp.bin --base 0x7A00 >/dev/null 2>&1
python3 $ROOT/tools/p8xfs.py put    mk.img cp.bin  --name /bin/cp.bin  --load 0x7A00 --exec 0x7A00 >/dev/null
# source tree + output dirs (mirror run.sh's layout)
for d in /src /src/commands /src/commands/c /src/commands/c/bin /src/commands/asm /src/commands/asm/bin /src/mk; do
    python3 $ROOT/tools/p8xfs.py mkdir mk.img "$d" >/dev/null
done
python3 $ROOT/tools/p8xfs.py put mk.img $ROOT/os/commands/pwd.c      --name /src/commands/c/pwd.c     >/dev/null
python3 $ROOT/tools/p8xfs.py put mk.img $ROOT/os/commands-asm/pwd.asm --name /src/commands/asm/pwd.asm >/dev/null
# the build script: rebuild pwd from C (cc -> asm) and from asm
printf 'cd /\rcc /src/commands/c/pwd.c >T.ASM\rasm T.ASM /src/commands/c/bin/pwd.bin\rasm /src/commands/asm/pwd.asm /src/commands/asm/bin/pwd.bin\r' > mk.scr
python3 $ROOT/tools/p8xfs.py put mk.img mk.scr --name /mk >/dev/null
# the install target (as run.sh generates it): publish the C builds to /bin
printf 'cp /src/commands/c/bin/*.bin /bin\r' > mk_instc.scr
python3 $ROOT/tools/p8xfs.py put mk.img mk_instc.scr --name /src/mk/installc >/dev/null

# rebuild pwd (both twins), then `make installc` to publish the C build to /bin, then
# RUN the PUBLISHED /bin/pwd.bin — it must print the CWD "/" (exercises DEFADDR: the
# copied entry has load/exec 0, mapped to the TPA base $7A00).
printf 'B\rsh /mk\rmake installc\rrun /bin/pwd.bin\r' \
    | ../p8xemu -l 3000000000 -c mk.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r' > mk_out.txt

# both binaries must now exist on the image
python3 $ROOT/tools/p8xfs.py ls mk.img /src/commands/c/bin   2>/dev/null | grep -qE '^pwd\.bin ' \
    || fail "C rebuild produced no /src/commands/c/bin/pwd.bin (cc or asm step failed)"
python3 $ROOT/tools/p8xfs.py ls mk.img /src/commands/asm/bin 2>/dev/null | grep -qE '^pwd\.bin ' \
    || fail "asm rebuild produced no /src/commands/asm/bin/pwd.bin"
# `make installc` must have published the freshly-built C pwd to /bin
python3 $ROOT/tools/p8xfs.py ls mk.img /bin 2>/dev/null | grep -qE '^pwd\.bin ' \
    || fail "make installc did not publish /bin/pwd.bin"
# and the PUBLISHED /bin binary must run and print the CWD
grep -qE '^/$' mk_out.txt || { echo "--- transcript ---"; sed -n '/sh .mk/,$p' mk_out.txt | head; \
    fail "published /bin/pwd.bin did not run / print the CWD"; }

echo "OS-MK TEST: PASS"
