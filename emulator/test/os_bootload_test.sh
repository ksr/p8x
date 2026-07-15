#!/bin/sh
# bootload built-in: install an OS image into the boot sectors (LBA 1.. + OSCNT)
# so the next `exit`->`B` boots it. Boot v1.0, `bootload` a variant OS whose
# banner differs, exit to the monitor, B again, and confirm the NEW banner.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode
fail() { echo "OS-BOOTLOAD TEST: FAIL — $1"; [ -f "$2" ] && { echo "--- transcript ---"; cat "$2"; }; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osbl.bin --base 0x2000 >/dev/null
# a variant OS with a distinct banner. Assemble it from $ROOT/os so its
# `.include "../generators/memmap.inc"` still resolves.
sed 's/"P8X\/OS v1.0"/"P8X\/OS vBL2"/' $ROOT/os/p8xos.asm > $ROOT/os/_bltmp.asm
python3 $ROOT/assembler/p8xasm.py $ROOT/os/_bltmp.asm -o os2.bin --base 0x2000 >/dev/null
rm -f $ROOT/os/_bltmp.asm

rm -f bl.img
python3 $ROOT/tools/p8xfs.py create bl.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   bl.img osbl.bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    bl.img os2.bin --name /OS2.BIN >/dev/null

out=$(printf 'B\rbootload /OS2.BIN\rexit\rB\r' | \
      ../p8xemu -l 400000000 -c bl.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')
printf '%s' "$out" > bl_out.txt

echo "$out" | grep -q 'installed as boot OS' || fail "bootload did not confirm installation" bl_out.txt
echo "$out" | grep -q 'vBL2'                 || fail "reboot did not run the newly installed OS" bl_out.txt
# host-side: OSCNT in the boot block matches the image's sector count
osz=$(wc -c < os2.bin); need=$(( (osz + 511) / 512 ))
oscnt=$(python3 - "$need" <<'PY'
import sys
b=open("bl.img","rb").read()
print("OK" if b[3]==int(sys.argv[1]) else "BAD %d!=%d"%(b[3],int(sys.argv[1])))
PY
)
[ "$oscnt" = "OK" ] || fail "boot-block OSCNT wrong ($oscnt)" bl_out.txt

echo "OS-BOOTLOAD TEST: PASS"
