#!/bin/sh
# Native assembler (ASM, a TPA program). Three checks:
#  (1) COVERAGE: assemble a generated source that uses EVERY (mnemonic,shape) in
#      the opcode table + LDPn + every directive/expression form on-target, and
#      confirm it is byte-identical to the host assembler. This locks the native
#      and host encodings together so neither can drift (the opcode table is
#      generated from genucode.OPC for both).
#  (2) byte-for-byte match on a small feature program, and
#  (3) RUN the freshly-assembled program and confirm it executes.
# (A true self-host — ASM assembling its own ~26 KB source — is impossible: the
# source text is larger than the whole TPA. This coverage check is the strongest
# feasible consistency guarantee.)
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

# COVER source: one line per (mnemonic,shape) from genucode.OPC, plus LDPn,
# every directive, and every expression form. Deterministic (sorted) so the
# host golden and the on-target output are directly comparable.
PYTHONPATH=$UC python3 - cover.asm <<'PYEOF'
import sys
from genucode import OPC
ops={'':'', '#':' #1', 'a':' $1234',
     '(P1)':' (P1)','(P1)+':' (P1)+','(P2)':' (P2)','(P2)+':' (P2)+',
     '(P3)':' (P3)','(P3)+':' (P3)+'}
L=["VAL = $1234", "CH  = 'Q'", "        .org $B000", "begin:"]
for k in sorted(OPC):                       # every opcode/shape exactly as defined
    L.append("        %s%s"%(k[0],ops[k[1]]))
for n in (1,2,3):
    L.append("        LDP%d #fwd"%n)         # LDPn pseudo, all pointers
L += ["        LDA #<VAL","        LDB #>VAL","        LDA #CH",
      "        LDA #VAL-$1000+2","        STA VAL+16",
      "        JMP begin","        JZ  fwd",
      "        .byte 1,2,$FF,CH,CR","        .word VAL,begin,$BEEF",
      '        .ascii "hello"','        .asciiz "world"',
      "        .fill 5,$AA","        .fill 3","fwd:    RTS","CR = $0D"]
open(sys.argv[1],"w").write("\n".join(L)+"\n")
PYEOF
python3 $ROOT/assembler/p8xasm.py cover.asm -o covgold.bin --base 0xB000 >/dev/null

# A small program that exercises forward refs / pointer modes / strings AND runs.
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
python3 $ROOT/assembler/p8xasm.py prog.asm -o golden.bin --base 0xB000 >/dev/null

rm -f as.img
python3 $ROOT/tools/p8xfs.py create as.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   as.img osa.bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    as.img asm.bin --name ASM.BIN --load 0xB000 --exec 0xB000 >/dev/null
python3 $ROOT/tools/p8xfs.py put    as.img cover.asm --name COVER.ASM >/dev/null
python3 $ROOT/tools/p8xfs.py put    as.img prog.asm  --name PROG.ASM  >/dev/null

# Assemble both on-target, then run the small program.
out=$(printf 'B\rRUN ASM.BIN COVER.ASM COVER.BIN\rRUN ASM.BIN PROG.ASM PROG.BIN\rRUN PROG.BIN\r' | \
      ../p8xemu -l 350000000 -c as.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')
fail() { echo "OS-ASM TEST: FAIL — $1"; echo "$out" | sed -n '/RUN ASM/,$p'; exit 1; }

# (1) full opcode-table coverage: on-target == host, byte for byte
python3 $ROOT/tools/p8xfs.py get as.img COVER.BIN >/dev/null 2>&1 || fail "COVER.BIN not created"
cmp -s covgold.bin COVER.BIN || fail "all-opcode coverage differs from host assembler"
# streamed output must leave the volume structurally intact
python3 $ROOT/tools/p8xfs.py fsck as.img >/dev/null 2>&1 || fail "volume invalid after streamed output"

# (2) byte-for-byte on the feature program
python3 $ROOT/tools/p8xfs.py get as.img PROG.BIN >/dev/null 2>&1 || fail "PROG.BIN not created"
cmp -s golden.bin PROG.BIN || fail "on-target output differs from host assembler"

# (3) the freshly-assembled program runs and prints its string
echo "$out" | grep -q 'HELLO-ASM' || fail "assembled program did not run/print"

echo "OS-ASM TEST: PASS"
