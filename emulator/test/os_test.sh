#!/bin/sh
# P8X/OS boot + shell test. Builds a P8XFS image with the OS, a runnable
# program (PROG.BIN, prints "RAN" then RTS to the shell), and a data file
# (HELLO.TXT), boots it through the ROM monitor (B), then exercises the shell:
#   DIR              -> lists both files
#   RUN PROG.BIN     -> prints RAN (program loaded to $A000 and JSR'd)
#   DEL HELLO.TXT    -> marks the entry deleted and writes the sector back
#   SAVE C.BIN 8000 8010 -> create a file from memory ($8000 = the OS image)
#   DIR              -> re-read from disk: HELLO.TXT gone, PROG.BIN + C.BIN kept
# Then on the host: get C.BIN back and confirm its bytes equal p8xos.bin[0:16].
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

out=$(printf 'B\rDIR\rRUN PROG.BIN\rDEL HELLO.TXT\rSAVE C.BIN 8000 8010\rDEP B000 41 42 43\rDUMP B000\rPACK\rDIR\r' | \
      ../p8xemu -l 80000000 -c os.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0')

fail() { echo "OS TEST: FAIL — $1"; echo "$out" | sed -n '/P8X\/OS/,$p'; exit 1; }
echo "$out" | grep -q 'P8X/OS v0.8' || fail "OS did not boot"
echo "$out" | grep -q 'PROG.BIN'    || fail "DIR missing PROG.BIN"
echo "$out" | grep -q 'HELLO.TXT'   || fail "DIR missing HELLO.TXT"
echo "$out" | grep -q 'RAN'         || fail "RUN did not execute the program"
echo "$out" | grep -q 'DELETED'     || fail "DEL did not report success"
echo "$out" | grep -q 'SAVED'       || fail "SAVE did not report success"
# DEP B000 41 42 43, then DUMP B000 -> the row shows the bytes and ASCII "ABC".
echo "$out" | grep -q 'B000: 41 42 43' || fail "DEP/DUMP did not show deposited bytes"
echo "$out" | grep -q 'ABC'            || fail "DUMP ASCII column wrong"
echo "$out" | grep -q 'PACKED'       || fail "PACK did not report success"
# After DEL+SAVE+PACK, the final DIR (re-read from disk): HELLO.TXT gone, C.BIN
# kept. (DEL HELLO left a gap that PACK reclaims by moving C.BIN down.)
tail=$(echo "$out" | sed -n '/PACKED/,$p')
echo "$tail" | grep -q 'HELLO.TXT' && fail "HELLO.TXT still listed after DEL" || true
echo "$tail" | grep -q 'PROG.BIN'  || fail "PROG.BIN lost"
echo "$tail" | grep -q 'C.BIN'     || fail "C.BIN lost after PACK"

# Host round-trip: SAVE'd C.BIN must equal the first 16 bytes of the OS image
# (it was saved straight from $8000, where the OS image is loaded verbatim) —
# and must still match AFTER PACK relocated its extent.
python3 $ROOT/tools/p8xfs.py get os.img C.BIN --out os_c.tmp >/dev/null
head -c 16 p8xos.bin > os_exp.tmp
cmp -s os_c.tmp os_exp.tmp || fail "C.BIN bytes wrong after PACK"
rm -f os_c.tmp os_exp.tmp
# PACK must leave a consistent volume with nothing reclaimable.
python3 $ROOT/tools/p8xfs.py fsck os.img >os_fsck.tmp 2>&1 || { cat os_fsck.tmp; fail "fsck failed after PACK"; }
grep -q '0 reclaimable' os_fsck.tmp || { cat os_fsck.tmp; fail "PACK left reclaimable space"; }
rm -f os_fsck.tmp
echo "OS TEST: PASS"
