#!/bin/sh
# SYS_RUNSH ($2051): a PROGRAM hands the shell a script to run. A probe calls
# bios(SYS_RUNSH, "/SCR.TXT", 0); the shell then runs the script's lines. The
# script here is `mkdir PROOFDIR` -- an observable, file-system side effect we
# can check on the disk afterward. Proves the script-run primitive that wires
# the window sink's TERM to real commands (15c-ii).
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-RUNSH TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null
cp $ROOT/os/commands/lib_abi.c .

cat > runsh_probe.c <<'PEOF'
//#use abi
int main() {
    bios(SYS_RUNSH, "/SCR.TXT", 0);        /* run the script; does not return */
    puts("?RUNSH");                        /* only reached if the path was bad */
    return 1;
}
PEOF
python3 $ROOT/tools/clib.py runsh_probe.c -o rp.c
python3 $ROOT/compiler/p8cc.py rp.c -o rp.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py rp.asm -o rp.bin --base 0x6A00 >/dev/null

printf 'mkdir PROOFDIR\n' > scr.txt

rm -f rs.img
python3 $ROOT/tools/p8xfs.py create rs.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   rs.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  rs.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    rs.img rp.bin  --name /bin/probe.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    rs.img scr.txt --name /SCR.TXT >/dev/null

printf 'B\rrun /bin/probe.bin\r' > rs.in
../p8xemu -N -i rs.in -c rs.img -l 400000000 eeprom.bin > rs.out 2>/dev/null || true
grep -q "?RUNSH" rs.out && fail "SYS_RUNSH did not run the script (probe fell through to ?RUNSH)"

# the script's `mkdir PROOFDIR` must have created the directory on the disk
python3 $ROOT/tools/p8xfs.py ls rs.img / 2>/dev/null | grep -qi "PROOFDIR" \
    || fail "script side effect missing: /PROOFDIR was not created"

echo "C-RUNSH TEST: PASS (a program handed the shell a script via SYS_RUNSH; the script ran)"
