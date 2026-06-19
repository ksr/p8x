#!/bin/sh
# I/O card model: switches ($FF00, set with -s) and LEDs ($FF02, trace with -L).
# A tiny program copies the switch byte to the LEDs and halts; we check the
# emulator presented our switch value to the program and surfaced the LED write.
set -e
cd "$(dirname "$0")"
UC=../../microcode
cp $UC/u?.bin .
ASM=../../assembler/p8xasm.py

printf '        .org $0000\n        LDA $FF00\n        STA $FF02\n        HLT\n' > io.asm
python3 $ASM io.asm -o io.bin >/dev/null

OUT=$(../p8xemu -L -s 0x5A -l 5000 io.bin 2>&1)

# program must have seen switches=$5A (ends in A=5A) and driven the LEDs to $5A
echo "$OUT" | grep -q 'A=5A .*LED=5A' || { echo "IO TEST: FAIL — switch/LED path"; echo "$OUT"; exit 1; }
# -L must have surfaced the $FF02 write
echo "$OUT" | grep -q '\[LED \$FF02\] \$5A' || { echo "IO TEST: FAIL — no LED trace"; echo "$OUT"; exit 1; }

# default: no -s means $FF00 reads 0, so A=00 and LEDs stay 00
../p8xemu -l 5000 io.bin 2>&1 | grep -q 'A=00 .*LED=00' || { echo "IO TEST: FAIL — default switches"; exit 1; }

rm -f io.asm io.bin
echo "IO TEST: PASS"
