#!/bin/sh
# Multi-byte LBA test: proves the BIOS CFREAD/CFWRITE honour LBA1 ($9D48), so
# sector numbers >255 don't wrap mod 256. Uses a >256-sector CF image.
#   - host seeds sector 300 with "LBAHI!" and plants hilba.bin as the OS at LBA 1
#   - boot it: it reads sector 300 (echoes "LBAHI!") and writes "WR301" to 301
#   - PASS iff the echo == "LBAHI!" AND the image shows "WR301" at sector 301
#     and sector 45 (301 mod 256) is still zero.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py hilba.asm -o hilba.bin >/dev/null

# A 512-sector (256 KB) image so sectors 300/301 exist, formatted by the monitor.
python3 - <<'PY'
open('cfbig.img','wb').write(bytes(512*512))
PY
printf 'F\rY\r' | ../p8xemu -l 8000000 -c cfbig.img eeprom.bin >/dev/null 2>&1

# Plant the test program at LBA 1, set OSCNT, seed sector 300 signature.
python3 - <<'PY'
img=bytearray(open('cfbig.img','rb').read())
prog=open('hilba.bin','rb').read()
img[3]=1                                   # OSCNT = 1 sector
img[512:512+len(prog)]=prog                # LBA 1 = the test program
img[300*512:300*512+6]=b'LBAHI!'           # seed sector 300
open('cfbig.img','wb').write(img)
PY

# Boot and capture the echoed signature.
out=$(printf 'B\r' | ../p8xemu -l 8000000 -c cfbig.img eeprom.bin 2>/dev/null | tr -d '\0')
case "$out" in
  *"LBAHI!"*) ;;
  *) echo "HILBA TEST: FAIL — sector-300 read did not echo 'LBAHI!' (LBA1 ignored?)"; echo "got: [$out]" | tail -2; exit 1 ;;
esac

# Verify the write landed at sector 301, not sector 45 (301 & 0xFF).
python3 - <<'PY'
import sys
img=open('cfbig.img','rb').read()
at301=img[301*512:301*512+5]
at45 =img[45*512:45*512+5]
if at301!=b'WR301':
    print("HILBA TEST: FAIL — sector 301 != 'WR301', got",at301); sys.exit(1)
if at45==b'WR301':
    print("HILBA TEST: FAIL — write wrapped to sector 45 (LBA1 ignored)"); sys.exit(1)
PY

echo "HILBA TEST: PASS"
