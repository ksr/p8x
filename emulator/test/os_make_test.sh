#!/bin/sh
# `make <target>` — the scaled-down make built-in (os/p8xos.asm). `make pwd` runs
# the pre-generated /src/mk/pwd through the `sh` streaming engine, rebuilding pwd
# from BOTH its C source (cc -> asm) and its asm source into /src/commands/{c,asm}/
# bin — always (no timestamps yet). Then we RUN the rebuilt C binary and check it
# prints the CWD. Proves the make built-in resolves /src/mk/<target> and drives the
# whole native toolchain.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode
fail() { echo "OS-MAKE TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osmk.bin --base 0x2000 >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/apps/p8xcc.asm -o cc.bin --base 0x6A00 >/dev/null
python3 $ROOT/generators/gen_p8xopc.py > opctab.asm
cat $ROOT/apps/p8xasm.asm opctab.asm > asmfull.asm
python3 $ROOT/assembler/p8xasm.py asmfull.asm -o asm.bin --base 0x6A00 >/dev/null

rm -f make.img
python3 $ROOT/tools/p8xfs.py create make.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   make.img osmk.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  make.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    make.img cc.bin  --name /bin/cc.bin  --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    make.img asm.bin --name /bin/asm.bin --load 0x6A00 --exec 0x6A00 >/dev/null
for d in /src /src/commands /src/commands/c /src/commands/c/bin /src/commands/asm /src/commands/asm/bin /src/mk; do
    python3 $ROOT/tools/p8xfs.py mkdir make.img "$d" >/dev/null
done
python3 $ROOT/tools/p8xfs.py put make.img $ROOT/os/commands/pwd.c        --name /src/commands/c/pwd.c     >/dev/null
python3 $ROOT/tools/p8xfs.py put make.img $ROOT/os/commands-asm/pwd.asm  --name /src/commands/asm/pwd.asm >/dev/null
# the per-command build script `make pwd` resolves + runs
printf 'cd /\rcc /src/commands/c/pwd.c >T.ASM\rasm T.ASM /src/commands/c/bin/pwd.bin\rasm /src/commands/asm/pwd.asm /src/commands/asm/bin/pwd.bin\r' > mkpwd.scr
python3 $ROOT/tools/p8xfs.py put make.img mkpwd.scr --name /src/mk/pwd.sh >/dev/null

printf 'B\rmake pwd\rrun /src/commands/c/bin/pwd.bin\r' \
    | ../p8xemu -l 3000000000 -c make.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r' > make_out.txt

python3 $ROOT/tools/p8xfs.py ls make.img /src/commands/c/bin   2>/dev/null | grep -qE '^pwd\.bin ' \
    || fail "make did not rebuild the C binary /src/commands/c/bin/pwd.bin"
python3 $ROOT/tools/p8xfs.py ls make.img /src/commands/asm/bin 2>/dev/null | grep -qE '^pwd\.bin ' \
    || fail "make did not rebuild the asm binary /src/commands/asm/bin/pwd.bin"
grep -qE '^/$' make_out.txt || { echo "--- transcript ---"; sed -n '/make pwd/,$p' make_out.txt | head; \
    fail "the rebuilt pwd.bin did not run / print the CWD"; }

echo "OS-MAKE TEST: PASS"
