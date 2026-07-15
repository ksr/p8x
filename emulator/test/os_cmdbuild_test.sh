#!/bin/sh
# Build the HEAVIEST /bin command through each native toolchain on-target and
# check it against the host build — the command-Makefile analog of os_asmos.
#   - asm Makefile path:  the vi hand-asm twin (heaviest twin, ~314 symbols) is
#                         assembled by the native `asm` == host build, byte-for-byte.
#   - c Makefile path:    the vi C command (~448 symbols once compiled) is compiled
#                         by native `cc` then assembled by `asm`; the result must
#                         assemble without "?too many symbols" and RUN.
# Guards the assembler's enlarged symbol table (SYMTAB=$8400..$C000, ~1097) against
# the growing commands, the way os_asmos guards it against the growing OS.
# Slow (two native builds under emulation); on demand, not in `test`.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode
fail() { echo "CMDBUILD TEST: FAIL — $1"; echo "$out" | sed -n '/run /,$p'; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o oscb.bin --base 0x2000 >/dev/null

# Native toolchain binaries (host-built = what we run on-target).
python3 $ROOT/generators/gen_p8xopc.py cbopc.asm
cat $ROOT/apps/p8xasm.asm cbopc.asm > cbfull.asm
python3 $ROOT/assembler/p8xasm.py cbfull.asm -o cbasm.bin --base 0x6A00 >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/apps/p8xcc.asm -o cbcc.bin --base 0x6A00 >/dev/null

# --- asm path: the vi twin, spliced host-side (mkasm) so the disk is self-contained
sh $ROOT/os/commands-asm/mkasm.sh vi > vitwin.asm
python3 $ROOT/assembler/p8xasm.py vitwin.asm -o vigold.bin --base 0x6A00 >/dev/null

# --- c path: the vi C command, //#use spliced host-side (clib) into one source
python3 $ROOT/tools/clib.py $ROOT/os/commands/vi.c -o vicmd.c >/dev/null

rm -f cb.img
python3 $ROOT/tools/p8xfs.py create cb.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   cb.img oscb.bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    cb.img cbasm.bin --name ASM.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    cb.img cbcc.bin  --name CC.bin  --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    cb.img vitwin.asm --name VIT.ASM >/dev/null
python3 $ROOT/tools/p8xfs.py put    cb.img vicmd.c    --name VI.C    >/dev/null

out=$(printf 'B\rrun ASM.bin VIT.ASM VIT.BIN\rrun CC.bin VI.C >VIC.ASM\rrun ASM.bin VIC.ASM VIC.BIN\r' | \
      ../p8xemu -l 6000000000 -c cb.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')

echo "$out" | grep -qi 'too many symbols' && fail "assembler symbol table overflowed"
# asm path: byte-identical to the host build
python3 $ROOT/tools/p8xfs.py get cb.img VIT.BIN >/dev/null 2>&1 || fail "asm twin not produced"
cmp -s vigold.bin VIT.BIN || fail "on-target asm twin differs from host ($(wc -c <VIT.BIN) vs $(wc -c <vigold.bin))"
# c path: cc then asm both succeeded and produced a binary
echo "$out" | grep -q 'OK' || fail "native asm did not report OK on the compiled command"
python3 $ROOT/tools/p8xfs.py get cb.img VIC.BIN >/dev/null 2>&1 || fail "compiled command binary not produced"
[ -s VIC.BIN ] || fail "compiled command binary is empty"
echo "CMDBUILD TEST: PASS  (vi twin $(wc -c <VIT.BIN)B asm-match; vi.c -> $(wc -c <VIC.BIN)B via cc+asm)"
