#!/bin/sh
# Dual-CF drive select (BIOS CFSEL $0148): prove sector I/O routes to the selected
# card and the two volumes are isolated. A tiny program booted from drive 0 writes
# marker $B0 to drive-0 LBA 40 and $A1 to drive-1 LBA 40 (same LBA, both cards),
# then reads each back — PASS iff drive 1 reads $A1 and drive 0 reads $B0 ("A1B0").
# Also checks an ABSENT drive 1 (no -c2) times out gracefully instead of hanging:
# CFINIT of the missing card fails, the read returns $FF, drive 0 is untouched
# ("FFB0"), and the program still reaches HLT.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null

cat > cf2.asm <<'EOF'
        ; Position-independent (fixed BIOS/ABI addresses only): assembles at org 0,
        ; planted at LBA 1, booted to $4000. drive 0 was CFINIT'd by the boot.
        ; Marker $B0 -> drive0 LBA 40.
        LDA  #40
        STA  $7047
        LDA  #0
        STA  $7048
        STA  $7049
        LDA  #$B0
        STA  $7100          ; SBUF[0]
        JSR  $010F          ; CFWRITE (drive 0)
        ; select + init drive 1, marker $A1 -> drive1 LBA 40 (same LBA)
        LDA  #1
        JSR  $0148          ; CFSEL(1)
        JSR  $0109          ; CFINIT drive 1 (bounded; C=1 if absent)
        LDA  #40
        STA  $7047
        LDA  #0
        STA  $7048
        STA  $7049
        LDA  #$A1
        STA  $7100
        JSR  $010F          ; CFWRITE (drive 1)
        ; read drive1 LBA 40 -> print byte
        LDA  #40
        STA  $7047
        LDP1 #$7100
        JSR  $010C          ; CFREAD (drive 1)
        LDA  $7100
        JSR  $0115          ; PHEX8 -> "A1" (or "FF" if drive 1 absent)
        ; select drive 0, read LBA 40 -> print byte (must still be $B0)
        LDA  #0
        JSR  $0148          ; CFSEL(0)
        LDA  #40
        STA  $7047
        LDP1 #$7100
        JSR  $010C          ; CFREAD (drive 0)
        LDA  $7100
        JSR  $0115          ; PHEX8 -> "B0"
        HLT
EOF
python3 $ROOT/assembler/p8xasm.py cf2.asm -o cf2.bin >/dev/null

# fresh drive-0 image with the test program planted at LBA 1
python3 -c "open('d1.img','wb').write(bytes(512*256))"
printf 'F\rY\r' | ../p8xemu -l 8000000 -c d1.img eeprom.bin >/dev/null 2>&1
python3 - <<'PY'
img=bytearray(open('d1.img','rb').read())
prog=open('cf2.bin','rb').read()
img[3]=1                      # OSCNT = 1
img[512:512+len(prog)]=prog   # LBA 1 = program
open('d1.img','wb').write(img)
PY
# a second (blank) card for drive 1
python3 -c "open('d2.img','wb').write(bytes(512*256))"

# present drive 1: expect A1B0 (routing + isolation)
out=$(printf 'B\r' | ../p8xemu -l 8000000 -c d1.img -c2 d2.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r\n')
case "$out" in
  *A1B0*) ;;
  *) echo "CF2 TEST: FAIL — present drive 1 expected 'A1B0', got [$out]"; exit 1 ;;
esac
# confirm the markers really landed on the two separate images
d2=$(xxd -s $((40*512)) -l 1 -p d2.img); d1=$(xxd -s $((40*512)) -l 1 -p d1.img)
[ "$d2" = "a1" ] || { echo "CF2 TEST: FAIL — drive-1 image LBA40 != a1 (got $d2)"; exit 1; }
[ "$d1" = "b0" ] || { echo "CF2 TEST: FAIL — drive-0 image LBA40 != b0 (got $d1)"; exit 1; }

# absent drive 1 (no -c2): must not hang; drive 1 read = FF, drive 0 still B0
python3 -c "open('d1.img','wb').write(bytes(512*256))"
printf 'F\rY\r' | ../p8xemu -l 8000000 -c d1.img eeprom.bin >/dev/null 2>&1
python3 - <<'PY'
img=bytearray(open('d1.img','rb').read())
prog=open('cf2.bin','rb').read()
img[3]=1; img[512:512+len(prog)]=prog
open('d1.img','wb').write(img)
PY
out=$(printf 'B\r' | ../p8xemu -l 8000000 -c d1.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r\n')
case "$out" in
  *FFB0*) ;;
  *) echo "CF2 TEST: FAIL — absent drive 1 expected 'FFB0' (graceful), got [$out]"; exit 1 ;;
esac

echo "CF2 TEST: PASS"
