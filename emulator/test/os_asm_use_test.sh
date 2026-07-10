#!/bin/sh
# The on-target assembler's ;#use include support (apps/p8xasm.asm). A command
# source that declares `;#use stdin` must, when assembled ON-TARGET, produce the
# SAME binary as the host toolchain (mkasm.sh cat -> host p8xasm.py) — i.e. the
# assembler appends /lib/NAME.inc after the program body, mirroring mkasm.sh.
#   cat.asm (`;#use stdin`) -> asm cat.asm CATOUT.BIN  ==  host mkasm+assemble
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode
fail() { echo "OS-ASM-USE TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osu.bin --base 0x4000 >/dev/null
# the on-target assembler itself (logic + generated opcode table)
python3 $ROOT/generators/gen_p8xopc.py > opctab.asm
cat $ROOT/apps/p8xasm.asm opctab.asm > asmfull.asm
python3 $ROOT/assembler/p8xasm.py asmfull.asm -o asm.bin --base 0x7A00 >/dev/null

# host reference: what mkasm.sh + the host assembler produce for cat (= /bina/cat.bin)
sh $ROOT/os/commands-asm/mkasm.sh cat > cat.full.asm
python3 $ROOT/assembler/p8xasm.py cat.full.asm -o cat.ref.bin --base 0x7A00 >/dev/null

# on-target disk: asm.bin in /bin, the include at /lib/stdin.inc, raw cat.asm at /
rm -f use.img
python3 $ROOT/tools/p8xfs.py create use.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   use.img osu.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  use.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    use.img asm.bin --name /bin/asm.bin --load 0x7A00 --exec 0x7A00 >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  use.img /lib >/dev/null
python3 $ROOT/tools/p8xfs.py put    use.img $ROOT/os/commands-asm/lib_stdin.inc --name /lib/stdin.inc >/dev/null
python3 $ROOT/tools/p8xfs.py put    use.img $ROOT/os/commands-asm/cat.asm --name /cat.asm >/dev/null

# assemble on-target, extract, diff against the host reference
printf 'B\rrun /bin/asm.bin cat.asm CATOUT.BIN\r' \
    | ../p8xemu -l 1500000000 -c use.img eeprom.bin >/dev/null 2>&1
python3 $ROOT/tools/p8xfs.py get use.img CATOUT.BIN --out cat.tgt.bin >/dev/null 2>&1 \
    || fail "assembler did not create CATOUT.BIN (;#use stdin not spliced?)"
cmp -s cat.ref.bin cat.tgt.bin \
    || fail "on-target ;#use output differs from host mkasm+asm ($(cmp -l cat.ref.bin cat.tgt.bin 2>/dev/null | wc -l) bytes)"

echo "OS-ASM-USE TEST: PASS"
