#!/bin/sh
# Milestone B: the on-board C compiler self-hosts. The frame-model apps/cc.c,
# built with the host toolchain into /binc/cc.bin, compiles ITS OWN source on
# the machine; the native assembler (/bin/asm.bin) assembles that into CC2.BIN;
# CC2.BIN -- the self-compiled compiler -- then RUNS on the machine and (a)
# correctly compiles a small program and (b) recompiles cc.c to output that is
# BYTE-IDENTICAL to the original's, a fixed point. This needs everything the
# earlier milestones did not have: the P3-frame codegen (recursion-correct,
# ~13% smaller so the 30.8 KB image fits), the +2 KB TPA (TPABASE $5900) and the
# raised cc.c table layout so the self-compiled image clears its own tables, and
# the grown assembler symbol table (1,664, for the 1,548-symbol self-compile).
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode
fail() { echo "CC-SELFHOST TEST: FAIL — $1"; [ -f "$2" ] && { echo "--- transcript ---"; tail -15 "$2"; }; exit 1; }
cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o oshb.bin --base 0x2000 >/dev/null
python3 $ROOT/generators/gen_p8xopc.py > opctab.asm
cat $ROOT/apps/p8xasm.asm opctab.asm > asmfull.asm
python3 $ROOT/assembler/p8xasm.py asmfull.asm -o hbasm.bin --base 0x5900 >/dev/null
# the frame compiler /binc/cc.bin from apps/cc.c (host-built)
cp $ROOT/apps/cc.c $ROOT/os/commands/lib_abi.c .
python3 $ROOT/tools/clib.py cc.c -o hbcc_pp.c >/dev/null
python3 $ROOT/compiler/p8cc.py hbcc_pp.c -o hbcc.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py hbcc.asm -o hbcc.bin --base 0x5900 >/dev/null
# a small program: sum 1..5 = 15 -> putchar(15+48) = '?'
printf 'int main(){ int i; int s; s=0; i=1; while(i<=5){ s=s+i; i=i+1; } putchar(s+48); putchar(10); return 0; }\n' > hbprog.c
rm -f hb.img
python3 $ROOT/tools/p8xfs.py create hb.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   hb.img oshb.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  hb.img /binc >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  hb.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put hb.img hbcc.bin --name /binc/cc.bin --load 0x5900 --exec 0x5900 >/dev/null
python3 $ROOT/tools/p8xfs.py put hb.img hbasm.bin --name /bin/asm.bin --load 0x5900 --exec 0x5900 >/dev/null
python3 $ROOT/tools/p8xfs.py put hb.img hbcc_pp.c --name /cc.c >/dev/null
python3 $ROOT/tools/p8xfs.py put hb.img hbprog.c --name /prog.c >/dev/null
# STAGE 1: the compiler compiles its own source; the assembler assembles it -> CC2.BIN
printf 'B\rrun /binc/cc.bin /cc.c >SELF.ASM\rasm SELF.ASM CC2.BIN\r' | ../p8xemu -l 4000000000 -c hb.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r' > hb1.txt
python3 $ROOT/tools/p8xfs.py get hb.img SELF.ASM --out hb_self.asm >/dev/null 2>&1 || fail "the compiler did not compile its own source" hb1.txt
python3 $ROOT/tools/p8xfs.py get hb.img CC2.BIN  --out hb_cc2.bin  >/dev/null 2>&1 || fail "the assembler did not assemble the self-compile (symbol table? '?too many symbols'?)" hb1.txt
[ "$(wc -c < hb_cc2.bin | tr -d ' ')" -gt 20000 ] || fail "CC2.BIN is implausibly small ($(wc -c < hb_cc2.bin) B) -- truncated self-compile" hb1.txt
# STAGE 2: install CC2.BIN and RUN IT -- compile+run a program, and recompile cc.c
python3 $ROOT/tools/p8xfs.py put hb.img hb_cc2.bin --name /binc/cc2.bin --load 0x5900 --exec 0x5900 >/dev/null
printf 'B\rrun /binc/cc2.bin /prog.c >PROG.ASM\rasm PROG.ASM PROG.BIN\rrun PROG.BIN\rrun /binc/cc2.bin /cc.c >SELF2.ASM\r' | ../p8xemu -l 4000000000 -c hb.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r' > hb2.txt
# (a) the self-compiled compiler ran and its program prints '?' (sum 1..5 = 15, +48)
grep -q '?' hb2.txt || fail "the self-compiled compiler's program did not run (expected '?')" hb2.txt
# (b) fixed point: CC2 recompiling cc.c == the original compiler's output
python3 $ROOT/tools/p8xfs.py get hb.img SELF2.ASM --out hb_self2.asm >/dev/null 2>&1 || fail "the self-compiled compiler (CC2) did not run on cc.c -- image/layout does not fit" hb2.txt
cmp -s hb_self.asm hb_self2.asm || fail "NOT a fixed point: CC2's output of cc.c differs from the original's" hb2.txt
echo "CC-SELFHOST TEST: PASS (cc.c self-compiled+assembled to $(wc -c < hb_cc2.bin | tr -d ' ') B on-board; the self-compiled compiler runs and reproduces cc.c byte-identically -- a fixed point)"
