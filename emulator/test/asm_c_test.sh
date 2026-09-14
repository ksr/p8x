#!/bin/sh
# The C-written assembler (apps/asm.c, the size/speed twin of apps/p8xasm.asm):
# build it with the host toolchain, install it as /bin/asmc.bin, and assemble
# on-target the same sources the asm-assembler tests use -- the all-opcode
# coverage source, the feature program, the asm assembler's OWN source (self-
# host), a ';#use' command and a relative '.include' -- each byte-identical to
# the host assembler. The C image must stay below its symbol table at $A800.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode
fail() { echo "ASM-C TEST: FAIL — $1"; [ -f "$2" ] && { echo "--- transcript ---"; cat "$2"; }; exit 1; }
cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osac.bin --base 0x2000 >/dev/null
# the C build: the generated opcode table + the source, //#use spliced, p8cc.py
python3 $ROOT/generators/gen_p8xopc.py acopc.asm >/dev/null
cat $ROOT/apps/opctab.c $ROOT/apps/asm.c > asmc_src.c
cp $ROOT/os/commands/lib_abi.c .
python3 $ROOT/tools/clib.py asmc_src.c -o asmc_pp.c >/dev/null
python3 $ROOT/compiler/p8cc.py asmc_pp.c -o asmc.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py asmc.asm -o asmc.bin --base 0x5900 >/dev/null
[ "$(wc -c < asmc.bin)" -le 20224 ] || fail "asmc.bin is $(wc -c < asmc.bin) bytes, overlaps the symbol table at \$A800"
# host goldens: the coverage + feature sources of os_asm_test, the asm
# assembler's own source, and a ;#use command
sh os_asm_test.sh >/dev/null 2>&1 || true          # (re)creates cover.asm, prog.asm, covgold.bin, golden.bin
[ -f cover.asm ] && [ -f covgold.bin ] || fail "os_asm_test.sh did not leave cover.asm / covgold.bin"
cat $ROOT/apps/p8xasm.asm acopc.asm > acself.asm
python3 $ROOT/assembler/p8xasm.py acself.asm -o acselfgold.bin --base 0x5900 >/dev/null
sh $ROOT/os/commands-asm/mkasm.sh cat > accat.asm
python3 $ROOT/assembler/p8xasm.py accat.asm -o accatgold.bin --base 0x5900 >/dev/null
rm -f ac.img
python3 $ROOT/tools/p8xfs.py create ac.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   ac.img osac.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  ac.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  ac.img /lib >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  ac.img /work >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  ac.img /work/asm >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  ac.img /work/inc >/dev/null
python3 $ROOT/tools/p8xfs.py put ac.img asmc.bin --name /bin/asmc.bin --load 0x5900 --exec 0x5900 >/dev/null
python3 $ROOT/tools/p8xfs.py put ac.img cover.asm --name /cover.asm >/dev/null
python3 $ROOT/tools/p8xfs.py put ac.img prog.asm  --name /prog.asm >/dev/null
python3 $ROOT/tools/p8xfs.py put ac.img acself.asm --name /self.asm >/dev/null
python3 $ROOT/tools/p8xfs.py put ac.img $ROOT/os/commands-asm/lib_stdin.inc --name /lib/stdin.inc >/dev/null
python3 $ROOT/tools/p8xfs.py put ac.img $ROOT/os/commands-asm/lib_abi.inc   --name /lib/abi.inc >/dev/null
python3 $ROOT/tools/p8xfs.py put ac.img $ROOT/os/commands-asm/cat.asm --name /cat.asm >/dev/null
printf 'FOO = $41\n' > aceq.inc
printf '        .include "../inc/eq.inc"\n        .org $5900\n        LDA #FOO\n        JSR $0103\n        LDA #$0D\n        JSR $0103\n        LDA #$0A\n        JSR $0103\n        RTS\n' > act.asm
python3 $ROOT/assembler/p8xasm.py act.asm -o actgold.bin --base 0x5900 -D FOO=0x41 >/dev/null 2>&1 || \
    { printf 'FOO = $41\n' | cat - act.asm | grep -v '.include' > actflat.asm; python3 $ROOT/assembler/p8xasm.py actflat.asm -o actgold.bin --base 0x5900 >/dev/null; }
python3 $ROOT/tools/p8xfs.py put ac.img aceq.inc --name /work/inc/eq.inc >/dev/null
python3 $ROOT/tools/p8xfs.py put ac.img act.asm  --name /work/asm/t.asm >/dev/null
printf 'B\rasmc /cover.asm /COVER.BIN\rasmc /prog.asm /PROG.BIN\rasmc /cat.asm /CAT.BIN\rcd /work/asm\rasmc t.asm /T.BIN\rcd /\rasmc /self.asm /SELF.BIN\r' | \
    ../p8xemu -l 3000000000 -c ac.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r' > ac_out.txt
n=$(grep -c '^OK$' ac_out.txt); [ "$n" = "5" ] || fail "expected 5 OK, got $n" ac_out.txt
for f in COVER PROG CAT T SELF; do
    python3 $ROOT/tools/p8xfs.py get ac.img $f.BIN --out ac_$f.bin >/dev/null 2>&1 || fail "$f.BIN not produced" ac_out.txt
done
cmp -s covgold.bin   ac_COVER.bin || fail "all-opcode coverage differs from the host assembler" ac_out.txt
cmp -s golden.bin    ac_PROG.bin  || fail "the feature program differs from the host" ac_out.txt
cmp -s accatgold.bin ac_CAT.bin   || fail ";#use output differs from host mkasm+asm" ac_out.txt
cmp -s actgold.bin   ac_T.bin     || fail "relative .include output differs from the host" ac_out.txt
cmp -s acselfgold.bin ac_SELF.bin || fail "self-host (the asm assembler's source) differs from the host" ac_out.txt
echo "ASM-C TEST: PASS ($(wc -c < asmc.bin | tr -d ' ') B; coverage, program, ;#use, .include, self-host byte-identical)"
