#!/bin/sh
# Native C compiler (apps/p8xcc.asm): compile a program with MORE than 16
# functions on target. This is the regression guard for the function-table
# overflow bug — FNPAR/FSLOT/FPOOL were sized for only 16 functions, so a source
# with a 17th function silently corrupted the compiler's tables (FADD wrote past
# the arrays) and emitted a blank `JSR _f_`, which the assembler then rejected
# with `?undefined`. This bit every real command with 17+ functions after
# //#use splicing (wc, dir, grep, sed, cp, vi, ...).
#
# A compact 20-function source reproduces the exact fault far faster than
# compiling a real 16 KB spliced command, and runs to a deterministic output.
# main() calls the 17th and 20th functions (both past the old cap); if either
# table entry is corrupt the call goes to `_f_`/garbage and the run is wrong.
# f17 returns 'A' (65), f20 returns 'Z' (90) -> the program prints "AZ".
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode
fail() { echo "OS-CC-BIGCMD TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osbc.bin --base 0x2000 >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/apps/p8xcc.asm -o ccbc.bin --base 0x6A00 >/dev/null
python3 $ROOT/generators/gen_p8xopc.py > opctab.asm
cat $ROOT/apps/p8xasm.asm opctab.asm > asmfull.asm
python3 $ROOT/assembler/p8xasm.py asmfull.asm -o asmbc.bin --base 0x6A00 >/dev/null

# 20 functions f1..f20 (+ main = 21), well past the old 16-function cap.
{
  i=1
  while [ $i -le 20 ]; do printf 'int f%d() { return %d; }\n' "$i" "$i"; i=$((i+1)); done
  printf 'int main() { putchar(f17() + 48); putchar(f20() + 70); }\n'
} > bigf.c
# f17()=17 -> 17+48=65='A'; f20()=20 -> 20+70=90='Z'.

rm -f bc.img
python3 $ROOT/tools/p8xfs.py create bc.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   bc.img osbc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  bc.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    bc.img ccbc.bin  --name /bin/cc.bin  --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    bc.img asmbc.bin --name /bin/asm.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    bc.img bigf.c    --name /bigf.c >/dev/null

# Second guard: a program needing MORE than 255 variable slots. A 600-byte global
# array is 300 word-slots, so `after` lands at slot ~300 (>255). This exercises the
# 16-bit slot machinery (SLOTCNT/SLOTBASE/EMITNUM16, signed global-relative index)
# and the single __V storage array (slot n -> __V+2n; one asm symbol, not N — so
# the assembler's symbol table doesn't overflow on slot-heavy programs). Before the
# 16-bit rework this either wrapped the 8-bit slot counter (undefined `V232`) or
# blew the assembler's ~850-symbol table. main prints "AB".
printf 'char big[600];\nint after;\nint main() { big[0] = 66; after = 65; putchar(after); putchar(big[0]); }\n' > slots.c
python3 $ROOT/tools/p8xfs.py put bc.img slots.c --name /slots.c >/dev/null

# all on-target: cc /bigf.c >T.ASM ; asm T.ASM /BIGF.BIN ; run /BIGF.BIN ; then slots
printf 'B\rcc /bigf.c >T.ASM\rasm /T.ASM /BIGF.BIN\rrun /BIGF.BIN\rcc /slots.c >U.ASM\rasm /U.ASM /SLOTS.BIN\rrun /SLOTS.BIN\r' | \
    ../p8xemu -l 6000000000 -c bc.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r' > bc_out.txt

# the assemble steps must not have failed with an undefined symbol or a full symtab
grep -qE '\?undefined|too many symbols' bc_out.txt && { echo "--- transcript ---"; cat bc_out.txt; \
    fail "asm rejected cc's output (function-table overflow, or slot/symbol overflow)"; }
# bigf: f17 and f20 callable -> "AZ"
grep -q 'AZ' bc_out.txt || { echo "--- transcript ---"; cat bc_out.txt; \
    fail "on-target run did not print AZ (a high-index function call was corrupt)"; }
# slots: the >255-slot global resolves correctly -> "AB"
grep -q 'AB' bc_out.txt || { echo "--- transcript ---"; cat bc_out.txt; \
    fail "on-target run did not print AB (a >255 variable slot was miscompiled)"; }

echo "OS-CC-BIGCMD TEST: PASS"
