#!/bin/sh
# Program-argument ABI: RUN passes the command tail (after the program name) to
# the program in P2. A tiny TPA program echoes its argument and RTSes back to the
# OS shell — verifying both arg passing and clean return.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osa.bin --base 0x4000 >/dev/null
# echo the arg string at (P2), then RTS to the OS
cat > argv.asm <<'EOF'
        .org $7A00
ae_lp:  LDA  (P2)
        JZ   ae_end
        JSR  $0103
        INP2
        JMP  ae_lp
ae_end: RTS
EOF
python3 $ROOT/assembler/p8xasm.py argv.asm -o argv.bin --base 0x7A00 >/dev/null

rm -f av.img
python3 $ROOT/tools/p8xfs.py create av.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   av.img osa.bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    av.img argv.bin --name AE.BIN --load 0x7A00 --exec 0x7A00 >/dev/null

out=$(printf 'B\rRUN AE.BIN HELLO-ARG\rMKDIR /Z\r' | \
      ../p8xemu -l 60000000 -c av.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')
fail() { echo "OS-ARGV TEST: FAIL — $1"; echo "$out" | sed -n '/v1.0/,$p'; exit 1; }
# the program must print exactly its arg (tail after the program name), on its
# own line — not the program name, not the whole RUN line.
echo "$out" | grep -qx 'HELLO-ARG' || fail "program did not receive its arg tail in P2"
# and control must return to the OS shell afterwards. DIR is no longer a built-in
# (no /BIN on this disk), so prove the shell is alive with a native command:
# MKDIR /Z -> "DIR CREATED".
echo "$out" | sed -n '/HELLO-ARG/,$p' | grep -q 'DIR CREATED' || fail "did not RTS back to the OS shell"
echo "OS-ARGV TEST: PASS"
