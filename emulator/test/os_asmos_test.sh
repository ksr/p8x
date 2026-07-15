#!/bin/sh
# Self-host the OS: the native assembler assembles the FULL OS source (p8xos.asm,
# the most symbol-heavy source in the tree — ~870 labels+equates once memmap is
# spliced in) on-target. This is the `make os` path in /src/os-bios. It regressed
# with "?too many symbols" when the OS outgrew the assembler's old symbol table;
# this test guards the enlarged table. Assert it reports OK (table did not
# overflow) and the on-target binary matches the host assembler's byte-for-byte.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode
fail() { echo "ASM-OS TEST: FAIL — $1"; echo "$out" | sed -n '/run ASM/,$p'; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o ossh.bin --base 0x2000 >/dev/null

# The fixed native assembler (host-built = the ASM.bin we run on-target).
python3 $ROOT/generators/gen_p8xopc.py aoopc.asm
cat $ROOT/apps/p8xasm.asm aoopc.asm > aofull.asm
python3 $ROOT/assembler/p8xasm.py aofull.asm -o asmgold.bin --base 0x6A00 >/dev/null

# Splice memmap.inc into the OS source so it's a single self-contained file
# (avoids reproducing the /src/os-bios/{asm,generators} include layout on disk).
# Symbol count is identical to the real .include, which is what we're stressing.
python3 - "$ROOT" > osfull.asm <<'PY'
import sys
root = sys.argv[1]
mm = open(root + "/generators/memmap.inc").read()
out = []
for line in open(root + "/os/p8xos.asm"):
    if ".include" in line and "memmap.inc" in line:
        out.append("; ---- memmap.inc spliced in for the on-target self-host test ----\n")
        out.append(mm)
    else:
        out.append(line)
open("osfull.asm", "w").write("".join(out))  # noop; we print below
sys.stdout.write("".join(out))
PY
# Golden on-target result = host-assembling the very same spliced source.
python3 $ROOT/assembler/p8xasm.py osfull.asm -o osgold.bin --base 0x2000 >/dev/null

rm -f ao.img
python3 $ROOT/tools/p8xfs.py create ao.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   ao.img ossh.bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    ao.img asmgold.bin --name ASM.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    ao.img osfull.asm  --name OSF.ASM >/dev/null

out=$(printf 'B\rrun ASM.bin OSF.ASM OSF.bin\r' | \
      ../p8xemu -l 4000000000 -c ao.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')

echo "$out" | grep -qi 'too many symbols' && fail "symbol table overflowed (the bug)"
echo "$out" | grep -q 'OK' || fail "on-target OS assembly did not report OK"
python3 $ROOT/tools/p8xfs.py get ao.img OSF.bin >/dev/null 2>&1 || fail "OSF.bin not produced"
# .org $2000 in the source drives the base on-target, so the self-assembled OS
# must match the host build byte-for-byte (the point of self-hosting).
cmp -s osgold.bin OSF.bin || fail "on-target OS binary differs from host build ($(wc -c <OSF.bin) vs $(wc -c <osgold.bin) bytes)"
echo "ASM-OS TEST: PASS"
