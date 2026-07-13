#!/bin/sh
# rev-D 16-bit memory ops: PHW/PLW (push/pop a memory word), LPW1 (load a pointer
# from a memory word), and MOVW (16-bit mem->mem move via PT2). Booted as a tiny
# "OS" at $2000; prints AB CD 5A EF BE iff all four work. (These collapse the
# compiler's byte-by-byte 16-bit moves; the C suite exercises them heavily — this
# is the isolated microcode check, incl. the 2nd scratch pointer PT2.)
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null

cat > wordops.asm <<'EOF'
        .org $2000
        ; PHW/PLW: push the word $CDAB at $5000, pop it to $5010
        LDA #$AB
        STA $5000
        LDA #$CD
        STA $5001
        PHW $5000
        PLW $5010
        LDA $5010
        JSR $0103        ; -> AB  (low byte survived)
        LDA $5011
        JSR $0103        ; -> CD  (high byte survived, order preserved)
        ; LPW1: word $5020 at $5012 -> P1, store $5A through P1, read it back
        LDA #$20
        STA $5012
        LDA #$50
        STA $5013
        LPW1 $5012       ; P1 := $5020
        LDA #$5A
        STA (P1)         ; mem[$5020] := $5A
        LDA $5020
        JSR $0103        ; -> 5A  (P1 loaded from the word correctly)
        ; MOVW: copy the word $BEEF from $5030 to $5040 (mem->mem, both scratch ptrs)
        LDA #$EF
        STA $5030
        LDA #$BE
        STA $5031
        MOVW $5040,$5030
        LDA $5040
        JSR $0103        ; -> EF  (low byte moved)
        LDA $5041
        JSR $0103        ; -> BE  (high byte moved, order preserved)
        HLT
EOF
python3 $ROOT/assembler/p8xasm.py wordops.asm -o wordops.bin --base 0x2000 >/dev/null
python3 -c "open('wordops.img','wb').write(bytes(512*64))"
python3 $ROOT/tools/p8xfs.py create wordops.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   wordops.img wordops.bin >/dev/null

out=$(printf 'B\r' | ../p8xemu -l 5000000 -c wordops.img eeprom.bin 2>/dev/null | LC_ALL=C od -An -tx1 | tr -s ' \n' ' ')
case "$out" in
  *"ab cd 5a ef be"*) echo "ISA-WORDOPS TEST: PASS" ;;
  *) echo "ISA-WORDOPS TEST: FAIL — expected 'ab cd 5a ef be', got [$out]"; exit 1 ;;
esac
