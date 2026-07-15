#!/bin/sh
# BASIC FOR/NEXT STEP — which side of the limit ends the loop depends on the SIGN
# of STEP. DONEXT used to terminate on `var > limit` unconditionally, so a
# countdown (FOR I=10 TO 1 STEP -1) ran exactly ONE iteration and printed "10",
# even though STEP is an advertised feature (HELP text). Covers all three shapes
# so a future change can't fix one direction by breaking the other:
#   negative STEP, plain up-loop (implicit STEP 1), positive STEP != 1.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o stepeeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/basic/p8xbasic.asm -o stepbasic.bin \
        --base 0x2000 -D BASORG=0x2000 -D BASRAM=0xA000 >/dev/null

fail() { echo "BASIC-STEP TEST: FAIL — $1"; echo "$out" | sed -n '/RUN/,$p' | head; exit 1; }

rm -f step.img
python3 $ROOT/tools/p8xfs.py create step.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   step.img stepbasic.bin >/dev/null

# 10..1 countdown, 1..5 up-loop, 0..10 by 2 — printed with `;` so each loop is
# one contiguous digit run on its own line.
out=$(printf 'B\r10 FOR I=10 TO 1 STEP -1\r20 PRINT I;\r30 NEXT I\r40 PRINT\r50 FOR J=1 TO 5\r60 PRINT J;\r70 NEXT J\r80 PRINT\r90 FOR K=0 TO 10 STEP 2\r100 PRINT K;\r110 NEXT K\r120 PRINT\rRUN\r' | \
     ../p8xemu -l 900000000 -c step.img stepeeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')

echo "$out" | grep -q '^10987654321$' || fail "STEP -1 countdown wrong (want 10987654321)"
echo "$out" | grep -q '^12345$'       || fail "plain up-loop wrong (want 12345)"
echo "$out" | grep -q '^0246810$'     || fail "STEP 2 wrong (want 0246810)"
echo "BASIC-STEP TEST: PASS"
