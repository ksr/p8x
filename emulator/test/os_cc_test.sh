#!/bin/sh
# Native C compiler (apps/p8xcc.asm) — the from-scratch, hand-written-in-asm C
# compiler that runs ON the P8X (Milestone B, path B). This is the v0.1 walking
# skeleton: it compiles  int main() { putchar(<expr>); ... }  with + / - integer
# arithmetic. Verified BEHAVIOURALLY end to end, all on-target: cc compiles a
# source to asm, the native assembler assembles it, and the resulting program is
# RUN — its output must match what the source computes.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o oscc.bin --base 0x4000 >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/apps/p8xcc.asm -o cc.bin --base 0x7A00 >/dev/null
# the native assembler (cc's output is fed to it, on-target)
python3 $ROOT/generators/gen_p8xopc.py > opctab.asm
cat $ROOT/apps/p8xasm.asm opctab.asm > asmfull.asm
python3 $ROOT/assembler/p8xasm.py asmfull.asm -o asm.bin --base 0x7A00 >/dev/null

fail() { echo "OS-CC TEST: FAIL — $1"; exit 1; }

rm -f cc.img
python3 $ROOT/tools/p8xfs.py create cc.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   cc.img oscc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  cc.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    cc.img cc.bin  --name /bin/cc.bin  --load 0x7A00 --exec 0x7A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    cc.img asm.bin --name /bin/asm.bin --load 0x7A00 --exec 0x7A00 >/dev/null
# putchar(64+1) -> 'A' (65)
printf 'int main() { putchar(64+1); }\n' > t.c
python3 $ROOT/tools/p8xfs.py put cc.img t.c --name /t.c >/dev/null

# all on-target: cc t.c >t.asm ; asm t.asm PROG.BIN ; PROG
printf 'B\rcc t.c >t.asm\rasm t.asm PROG.BIN\rrun PROG.BIN\r' | \
    ../p8xemu -l 900000000 -c cc.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r' > cc_out.txt

grep -q 'P8X' cc_out.txt || fail "did not boot"
# the compiled+assembled+run program must print 'A'
grep -q '^A$' cc_out.txt || { echo "--- transcript ---"; sed -n '/PROG/,$p' cc_out.txt | head; fail "compiled program did not print A"; }
echo "OS-CC TEST: PASS"
