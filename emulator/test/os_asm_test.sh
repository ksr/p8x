#!/bin/sh
# Native assembler (ASM, a TPA program): assemble a source on-target and (1)
# confirm the output is byte-identical to the host assembler (the strong check),
# and (2) RUN the freshly-assembled program and confirm it executes.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osa.bin --base 0x4000 >/dev/null
# Build the native ASM program: assembler logic + generated opcode table.
python3 $ROOT/generators/gen_p8xopc.py opctab.asm
cat $ROOT/apps/p8xasm.asm opctab.asm > asmfull.asm
python3 $ROOT/assembler/p8xasm.py asmfull.asm -o asm.bin --base 0xB000 >/dev/null

# A source exercising equates, labels, forward refs, the LDPn pseudo, pointer
# modes, branches, char literals, </> and the data directives — and which RUNs.
cat > prog.asm <<'EOF'
CR = $0D
LF = $0A
        .org $B000
        LDP1 #msg
lp:     LDA (P1)+
        JZ   done
        JSR  $0103
        JMP  lp
done:   LDA  #<msg
        LDB  #>msg
        ADD
        RTS
msg:    .asciiz "HELLO-ASM"
        .byte CR,LF
EOF
# host golden
python3 $ROOT/assembler/p8xasm.py prog.asm -o golden.bin --base 0xB000 >/dev/null

rm -f as.img
python3 $ROOT/tools/p8xfs.py create as.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   as.img osa.bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    as.img asm.bin --name ASM.BIN --load 0xB000 --exec 0xB000 >/dev/null
python3 $ROOT/tools/p8xfs.py put    as.img prog.asm --name PROG.ASM >/dev/null

# Assemble on-target, then run the result.
out=$(printf 'B\rRUN ASM.BIN PROG.ASM PROG.BIN\rRUN PROG.BIN\r' | \
      ../p8xemu -l 250000000 -c as.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')
fail() { echo "OS-ASM TEST: FAIL — $1"; echo "$out" | sed -n '/RUN ASM/,$p'; exit 1; }

echo "$out" | grep -q 'OK' || fail "assembler did not report OK"

# (1) byte-for-byte vs the host assembler
python3 $ROOT/tools/p8xfs.py get as.img PROG.BIN >/dev/null 2>&1 || fail "PROG.BIN not created"
# p8xfs writes the gotten file to ./PROG.BIN
cmp -s golden.bin PROG.BIN || fail "on-target output differs from host assembler"

# (2) the freshly-assembled program runs and prints its string
echo "$out" | grep -q 'HELLO-ASM' || fail "assembled program did not run/print"

echo "OS-ASM TEST: PASS"
