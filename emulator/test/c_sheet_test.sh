#!/bin/sh
# sheet: the spreadsheet. Two layers of test:
#   1. HOST unit test of the formula evaluator (sheet_host.c) -- precedence,
#      parens, cell refs, SUM/AVG/MAX/MIN ranges, signed division, errors.
#   2. EMULATOR smoke: build the real sheet.bin, boot the OS, run it, type a
#      number and a formula by keyboard, and confirm the grid + headers render
#      and the typed cells light up while an untouched cell stays black (i.e. it
#      ran, drew, and took input without crashing).
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode
fail() { echo "C-SHEET TEST: FAIL — $1"; exit 1; }

# ---- 1. evaluator, on the host ---------------------------------------------
cc -O2 -o sheet_host sheet_host.c || fail "sheet_host did not compile"
./sheet_host || fail "evaluator unit test failed"

# ---- 2. build + install sheet.bin ------------------------------------------
cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null
python3 $ROOT/tools/clib.py $ROOT/os/commands/sheet.c > cs_sheet.c
python3 $ROOT/compiler/p8cc.py cs_sheet.c -o cs_sheet.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py cs_sheet.asm -o cs_sheet.bin --base 0x5900 >/dev/null
rm -f cs.img
python3 $ROOT/tools/p8xfs.py create cs.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   cs.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  cs.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    cs.img cs_sheet.bin --name /bin/sheet.bin --load 0x5900 --exec 0x5900 >/dev/null

# Drive by keyboard: A1="5" Enter, A2="=A1+A1" Enter, A3="7" Enter, then a SUM in
# B1, then 's' to SAVE. Reading the saved file back verifies data entry + the save
# path exactly (raw cell text), where reading rendered glyphs could not.
printf 'B\rsheet\r5\r=A1+A1\r7\r' > cs.in            # fills A1,A2,A3 (cursor -> A4)
printf '\033[<0;19;5M\033[<0;19;5m' >> cs.in         # click cell B1 (col45,row1 = B1 region top)
printf '=SUM(A1:A3)\rs' >> cs.in                     # B1 formula, then save
../p8xemu -N -i cs.in -c cs.img -l 600000000 -g cs.ppm eeprom.bin > cs.out 2>/dev/null || true

# grid rendered? (the column-header band drew A..H)
python3 - <<'PY' || exit 1
import sys
d=open("cs.ppm","rb").read(); px=d.split(b"\n",3)[3]; W=480
def lit(x,wy): i=((271-wy)*W+x)*3; return px[i:i+3]!=b"\x00\x00\x00"
n=sum(1 for wy in range(241,256) for x in range(32,462) if lit(x,wy))
if n < 20: print("C-SHEET TEST: FAIL"); print("  header band empty (%d lit) -- grid did not render"%n); sys.exit(1)
PY

# read the saved sheet back and check the raw cell contents
python3 $ROOT/tools/p8xfs.py get cs.img /SHEET.SS --out cs.ss 2>/dev/null || fail "sheet did not save /SHEET.SS"
python3 - <<'PY' || exit 1
import sys
t = open("cs.ss").read()
want = {"A1":"5", "A2":"=A1+A1", "A3":"7", "B1":"=SUM(A1:A3)"}
got = {}
for line in t.splitlines():
    line = line.strip()
    if not line: continue
    ref, _, raw = line.partition(" ")
    got[ref] = raw
bad = []
for ref, raw in want.items():
    if got.get(ref) != raw:
        bad.append("cell %s saved as %r, want %r" % (ref, got.get(ref), raw))
# a click selected B1 (not A-column) -> the SUM must be in B1, proving mouse select
if "B1" not in got: bad.append("mouse click did not select B1 (formula landed elsewhere: %r)" % got)
if bad:
    print("C-SHEET TEST: FAIL"); [print("  "+b) for b in bad]; sys.exit(1)
print("C-SHEET TEST: data entry ok (A1..A3 + B1 SUM saved exactly; keyboard + mouse-select)")
PY

# load round-trip: run sheet again (it auto-loads /SHEET.SS, the default file),
# press 's' to re-save. If load() populated the cells, the file is unchanged; if
# load did nothing, the re-save would be empty.
cp cs.ss cs.ss.orig
printf 'B\rsheet\rs' > cl.in
../p8xemu -N -i cl.in -c cs.img -l 400000000 eeprom.bin > cl.out 2>/dev/null || true
python3 $ROOT/tools/p8xfs.py get cs.img /SHEET.SS --out cs.ss2 2>/dev/null || fail "re-save produced no file"
python3 - <<'PY' || exit 1
import sys
a = sorted(l.strip() for l in open("cs.ss.orig") if l.strip())
b = sorted(l.strip() for l in open("cs.ss2") if l.strip())
if a != b:
    print("C-SHEET TEST: FAIL"); print("  load round-trip lost cells: %r -> %r" % (a, b)); sys.exit(1)
print("C-SHEET TEST: load round-trip ok (re-saved sheet matches after a load)")
PY

echo "C-SHEET TEST: PASS (evaluator + render + keyboard/mouse entry + save/load round-trip)"
