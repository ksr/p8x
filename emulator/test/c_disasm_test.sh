#!/bin/sh
# disasm (os/commands/disasm.c) — disassemble a memory range. Deposit a known byte
# sequence with `dep`, then `disasm` it and check the decoded mnemonics/operands.
# The opcode table (os/commands/lib_distab.c) is generated from genucode.OPC, so
# this also guards that the disassembler decode stays in step with the ISA.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode
fail() { echo "C-DISASM TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/generators/gen_p8xdis.py >/dev/null    # refresh the opcode table
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osdis.bin --base 0x4000 >/dev/null
build() {   # $1 = command name -> $1.bin
    python3 $ROOT/tools/clib.py "$ROOT/os/commands/$1.c" -o "$1.pp.c" >/dev/null
    python3 $ROOT/compiler/p8cc.py "$1.pp.c" -o "$1.d.asm" >/dev/null
    python3 $ROOT/assembler/p8xasm.py "$1.d.asm" -o "$1.d.bin" --base 0x7A00 >/dev/null
}
build disasm
build dep

rm -f disasm.img
python3 $ROOT/tools/p8xfs.py create disasm.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   disasm.img osdis.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  disasm.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put disasm.img disasm.d.bin --name /bin/disasm.bin --load 0x7A00 --exec 0x7A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put disasm.img dep.d.bin    --name /bin/dep.bin    --load 0x7A00 --exec 0x7A00 >/dev/null

# Deposit at $C000 (clear of disasm's own TPA image): LDA #$48 (10 48), JSR $0103
# (43 03 01), RTS (42), ADD (20), LDA (P1)+ (15) — one of each operand shape.
printf 'B\rdep C000 10 48 43 03 01 42 20 15\rdisasm C000 C008\r' \
    | ../p8xemu -l 900000000 -c disasm.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r' > disasm_out.txt

for want in 'LDA #\$48' 'JSR \$0103' '^C005: 42 *RTS' ' ADD' 'LDA \(P1\)\+'; do
    grep -qE "$want" disasm_out.txt || { echo "--- output ---"; sed -n '/disasm C000/,$p' disasm_out.txt | head; \
        fail "disassembly missing expected line: $want"; }
done
# addresses must advance by the right instruction lengths (C000, C002, C005, C006, C007)
for a in '^C000:' '^C002:' '^C005:' '^C006:' '^C007:'; do
    grep -qE "$a" disasm_out.txt || fail "wrong instruction length: no line at $a"
done

echo "C-DISASM TEST: PASS"
