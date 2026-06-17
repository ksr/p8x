#!/bin/sh
# CF-IDE + P8XFS round-trip test: drives the ROM monitor's filesystem hooks
# against the emulator's CF model (p8xemu -c <img>).
#   1. F (format)  -> writes the 'P8' boot block + zeroed directory
#   2. plant a tiny position-independent "OS" at LBA 1 and set OSCNT=1
#   3. B (boot)    -> loads the OS to $8000, jumps; the OS prints "K!"
# Halts PASS only if the booted OS actually ran.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null

# A tiny position-independent OS: print "K!" then HLT.
printf "        LDA  #'K'\n        STA  \$FF05\n        LDA  #'!'\n        STA  \$FF05\n        HLT\n" > tinyos.asm
python3 $ROOT/assembler/p8xasm.py tinyos.asm -o tinyos.bin >/dev/null

# Format the card via the monitor, then verify the boot block signature.
rm -f cf.img
printf 'F\rY\r' | ../p8xemu -l 8000000 -c cf.img eeprom.bin >/dev/null 2>&1
sig=$(xxd -l 2 -p cf.img)
[ "$sig" = "5038" ] || { echo "CF TEST: FAIL — boot block signature '$sig' != '5038'"; exit 1; }

# Plant the OS image at LBA 1 and set OSCNT.
python3 - <<'PY'
img=bytearray(open('cf.img','rb').read())
os_=open('tinyos.bin','rb').read()
img[3]=1                       # OSCNT = 1 sector
img[512:512+len(os_)]=os_      # LBA 1 = OS image
open('cf.img','wb').write(img)
PY

# Boot it and confirm the OS ran.
out=$(printf 'B\r' | ../p8xemu -l 8000000 -c cf.img eeprom.bin 2>/dev/null | tr -d '\0')
case "$out" in
  *"K!"*) echo "CF TEST: PASS" ;;
  *) echo "CF TEST: FAIL — booted OS did not print 'K!'"; echo "$out" | tail -3; exit 1 ;;
esac
