#!/bin/sh
# P8X/OS boot + shell test. Builds a P8XFS image with the OS, a runnable
# program (PROG.BIN, prints "RAN" then RTS to the shell), and a data file
# (HELLO.TXT), boots it through the ROM monitor (B), then exercises the shell:
#   DIR            -> lists both files
#   RUN PROG.BIN   -> prints RAN (program loaded to $A000 and JSR'd)
#   DEL HELLO.TXT  -> marks the entry deleted and writes the sector back
#   DIR            -> re-read from disk shows HELLO.TXT gone, PROG.BIN kept
# Exercises the whole stack: assembler --base, p8xfs.py, the BIOS jump table,
# the CF model, and the OS shell / filesystem code.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o p8xos.bin --base 0x8000 >/dev/null

# A position-independent program at its load address $A000: print "RAN\r\n"
# via the BIOS CONOUT vector, then RTS back to the shell.
cat > prog.asm <<'EOF'
        .org $A000
        LDA  #'R'
        JSR  $0103
        LDA  #'A'
        JSR  $0103
        LDA  #'N'
        JSR  $0103
        LDA  #$0D
        JSR  $0103
        LDA  #$0A
        JSR  $0103
        RTS
EOF
python3 $ROOT/assembler/p8xasm.py prog.asm -o prog.bin --base 0xA000 >/dev/null

rm -f os.img
python3 $ROOT/tools/p8xfs.py create os.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot os.img p8xos.bin >/dev/null
python3 $ROOT/tools/p8xfs.py put os.img prog.bin --name PROG.BIN >/dev/null
printf 'hi' > os_h.tmp
python3 $ROOT/tools/p8xfs.py put os.img os_h.tmp --name HELLO.TXT >/dev/null
rm -f os_h.tmp prog.asm

out=$(printf 'B\rDIR\rRUN PROG.BIN\rDEL HELLO.TXT\rDIR\r' | \
      ../p8xemu -l 60000000 -c os.img eeprom.bin 2>/dev/null | tr -d '\0')

fail() { echo "OS TEST: FAIL — $1"; echo "$out" | sed -n '/P8X\/OS/,$p'; exit 1; }
echo "$out" | grep -q 'P8X/OS v0.2' || fail "OS did not boot"
echo "$out" | grep -q 'PROG.BIN'    || fail "DIR missing PROG.BIN"
echo "$out" | grep -q 'HELLO.TXT'   || fail "DIR missing HELLO.TXT"
echo "$out" | grep -q 'RAN'         || fail "RUN did not execute the program"
echo "$out" | grep -q 'DELETED'     || fail "DEL did not report success"
# After DEL, the final DIR (re-read from disk) must not list HELLO.TXT.
echo "$out" | sed -n '/DELETED/,$p' | grep -q 'HELLO.TXT' && \
    fail "HELLO.TXT still listed after DEL" || true
echo "$out" | sed -n '/DELETED/,$p' | grep -q 'PROG.BIN' || \
    fail "PROG.BIN lost after DEL"
echo "OS TEST: PASS"
