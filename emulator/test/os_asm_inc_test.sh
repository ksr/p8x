#!/bin/sh
# .include directive in the native assembler: `.include "path"` at line start
# appends the file (resolved relative to the SOURCE file's directory) after the
# body, so equates in it resolve (two-pass, order-independent) — the on-target
# counterpart of the host assembler's .include, letting /src/os-bios build the
# OS/monitor on the machine (they .include "../generators/memmap.inc").
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode
fail() { echo "OS-ASM-INC TEST: FAIL — $1"; [ -f "$2" ] && { echo "--- transcript ---"; cat "$2"; }; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osinc.bin --base 0x2000 >/dev/null
python3 $ROOT/generators/gen_p8xopc.py opc.asm
cat $ROOT/apps/p8xasm.asm opc.asm > asmfull.asm
python3 $ROOT/assembler/p8xasm.py asmfull.asm -o asm.bin --base 0x6A00 >/dev/null

rm -f inc.img
python3 $ROOT/tools/p8xfs.py create inc.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   inc.img osinc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  inc.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    inc.img asm.bin --name /bin/asm.bin --load 0x6A00 --exec 0x6A00 >/dev/null
# a source under work/asm that includes ../inc/eq.inc (relative to the source dir)
python3 $ROOT/tools/p8xfs.py mkdir inc.img /work >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir inc.img /work/asm >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir inc.img /work/inc >/dev/null
printf 'FOO = $41\n' > eq.inc
python3 $ROOT/tools/p8xfs.py put inc.img eq.inc --name /work/inc/eq.inc >/dev/null
printf '        .include "../inc/eq.inc"\n        .org $6A00\n        LDA #FOO\n        JSR $0103\n        LDA #$0D\n        JSR $0103\n        LDA #$0A\n        JSR $0103\n        RTS\n' > t.asm
python3 $ROOT/tools/p8xfs.py put inc.img t.asm --name /work/asm/t.asm >/dev/null
# a full-memmap include in an os-bios-shaped layout, built from the parent CWD
python3 $ROOT/tools/p8xfs.py mkdir inc.img /so >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir inc.img /so/asm >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir inc.img /so/generators >/dev/null
python3 $ROOT/tools/p8xfs.py put inc.img $ROOT/generators/memmap.inc --name /so/generators/memmap.inc >/dev/null
printf '        .include "../generators/memmap.inc"\n        .org $6A00\n        LDP1 #TPABASE\n        RTS\n' > mm.asm
python3 $ROOT/tools/p8xfs.py put inc.img mm.asm --name /so/asm/mm.asm >/dev/null

out=$(printf 'B\rcd /work/asm\rasm t.asm out.bin\rrun out.bin\rcd /so\rasm asm/mm.asm o2.bin\r' | \
      ../p8xemu -l 800000000 -c inc.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')
printf '%s' "$out" > inc_out.txt

# FOO ($41='A') came from the relative include -> the program printed 'A'
echo "$out" | grep -qE '^A$' || fail "relative .include did not resolve FOO (printed 'A')" inc_out.txt
# the os-bios-shaped full-memmap include assembled OK
echo "$out" | sed -n '/asm asm.mm/,$p' | grep -q 'OK' || fail "os-bios-shaped memmap .include did not assemble" inc_out.txt

echo "OS-ASM-INC TEST: PASS"
