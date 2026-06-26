#!/bin/sh
# Self-host: the native assembler assembles ITS OWN source (apps/p8xasm.asm +
# the generated opcode table, ~37 KB) on-target and produces a binary identical
# to the host assembler's. Proves streamed source (source > RAM) + the large
# symbol table work end to end. Slow (assembles 37 KB twice under emulation),
# so it is a separate target, not part of `make test`.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o ossh.bin --base 0x4000 >/dev/null
python3 $ROOT/generators/gen_p8xopc.py shopc.asm
cat $ROOT/apps/p8xasm.asm shopc.asm > shfull.asm
# host build = the golden reference AND the ASM.BIN we run
python3 $ROOT/assembler/p8xasm.py shfull.asm -o shgold.bin --base 0x7A00 >/dev/null

rm -f sh.img
python3 $ROOT/tools/p8xfs.py create sh.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   sh.img ossh.bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    sh.img shgold.bin --name ASM.BIN --load 0x7A00 --exec 0x7A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    sh.img shfull.asm --name SELF.ASM >/dev/null

out=$(printf 'B\rRUN ASM.BIN SELF.ASM SELF.BIN\r' | \
      ../p8xemu -l 3000000000 -c sh.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')
fail() { echo "ASM-SELFHOST TEST: FAIL — $1"; echo "$out" | sed -n '/RUN ASM/,$p'; exit 1; }

echo "$out" | grep -q 'OK' || fail "on-target assembly did not report OK"
python3 $ROOT/tools/p8xfs.py get sh.img SELF.BIN >/dev/null 2>&1 || fail "SELF.BIN not produced"
cmp -s shgold.bin SELF.BIN || fail "self-assembled binary differs from host build"
echo "ASM-SELFHOST TEST: PASS"
