#!/bin/sh
# The C-written C compiler (apps/cc.c, the size/speed twin of apps/p8xcc.asm):
# build it with the host toolchain, install it as /binc/cc.bin next to the asm
# compiler, and compile the SAME sources with both on the machine -- the
# os_cc_test / os_cc_bigcmd_test programs, an `a && b == c` condition, a program
# with more than 256 labels and a 300-byte local array (the three asm-compiler
# bugs the twin found on 2026-09-13), and the spliced grep command -- each
# text-identical. Two of the programs compiled by the C compiler are then
# assembled by the native assembler and RUN.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode
fail() { echo "CC-C TEST: FAIL — $1"; [ -f "$2" ] && { echo "--- transcript ---"; tail -20 "$2"; }; exit 1; }
cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osccc.bin --base 0x2000 >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/apps/p8xcc.asm -o ccca.bin --base 0x6100 >/dev/null
python3 $ROOT/generators/gen_p8xopc.py > opctab.asm
cat $ROOT/apps/p8xasm.asm opctab.asm > asmfull.asm
python3 $ROOT/assembler/p8xasm.py asmfull.asm -o cccasm.bin --base 0x6100 >/dev/null
# the C build: //#use abi spliced by clib.py, p8cc.py, the host assembler
cp $ROOT/apps/cc.c $ROOT/os/commands/lib_abi.c .
python3 $ROOT/tools/clib.py cc.c -o ccc_pp.c >/dev/null
python3 $ROOT/compiler/p8cc.py ccc_pp.c -o ccc.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py ccc.asm -o ccc.bin --base 0x6100 >/dev/null
[ "$(wc -c < ccc.bin)" -le 22272 ] || fail "ccc.bin is $(wc -c < ccc.bin) bytes, overlaps its tables at \$B800"
# the sources
printf 'int odd(int n); int even(int n) { if (n == 0) return 1; return odd(n - 1); } int odd(int n) { if (n == 0) return 0; return even(n - 1); } int main() { puts("P8"); if (even(10)) putchar(65); else putchar(66); }\n' > cct.c
{
  i=1
  while [ $i -le 20 ]; do printf 'int f%d() { return %d; }\n' "$i" "$i"; i=$((i+1)); done
  printf 'int main() { putchar(f17() + 48); putchar(f20() + 70); }\n'
} > ccbigf.c
printf 'char big[600];\nint after;\nint main() { big[0] = 66; after = 65; putchar(after); putchar(big[0]); }\n' > ccslots.c
# `a && rel` with a false a fell INTO the body (the relational took the
# condition-mode branch alone); the || forms were always right
cat > ccand.c <<'EOF'
int main() { int a; int b; a = 0; b = 1;
  if (a && b == 1) puts("BAD1"); else puts("OK1");
  a = 1; if (a && b == 1) puts("OK2"); else puts("BAD2");
  if (a && b == 2) puts("BAD3"); else puts("OK3");
  a = 0; if (a || b == 1) puts("OK4"); else puts("BAD4");
  if (a || b == 2) puts("BAD5"); else puts("OK5");
  return 0; }
EOF
# 280 labels (a byte label counter wrapped at 256) + a char[300] local (byte
# arithmetic sized it at 21 slots instead of 150). f returns 140: 'A' 'B' 'A'.
{
  printf 'int f() { char b[300]; int i; b[0] = 65; b[299] = 66; i = 0;\n'
  i=0
  while [ $i -lt 140 ]; do printf 'i = i + (i == %d);\n' "$i"; i=$((i+1)); done
  printf 'putchar(b[0]); putchar(b[299]); return i; }\nint main() { int r; r = f(); putchar(r - 75); putchar(10); return 0; }\n'
} > cclbl.c
python3 $ROOT/tools/clib.py $ROOT/os/commands/grep.c -o ccgrep.c >/dev/null
rm -f ccc.img
python3 $ROOT/tools/p8xfs.py create ccc.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   ccc.img osccc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  ccc.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  ccc.img /binc >/dev/null
python3 $ROOT/tools/p8xfs.py put ccc.img ccca.bin   --name /bin/cc.bin   --load 0x6100 --exec 0x6100 >/dev/null
python3 $ROOT/tools/p8xfs.py put ccc.img cccasm.bin --name /bin/asm.bin  --load 0x6100 --exec 0x6100 >/dev/null
python3 $ROOT/tools/p8xfs.py put ccc.img ccc.bin    --name /binc/cc.bin --load 0x6100 --exec 0x6100 >/dev/null
for s in t bigf slots and lbl grep; do python3 $ROOT/tools/p8xfs.py put ccc.img cc$s.c --name /$s.c >/dev/null; done
cmds='B\r'
for s in t bigf slots and lbl grep; do cmds="${cmds}cc /$s.c >A$s.ASM\rrun /binc/cc.bin /$s.c >C$s.ASM\r"; done
cmds="${cmds}asm Cand.ASM AND.BIN\rrun AND.BIN\rasm Clbl.ASM LBL.BIN\rrun LBL.BIN\r"
printf "$cmds" | ../p8xemu -l 1500000000 -c ccc.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r' > ccc_out.txt
for s in t bigf slots and lbl grep; do
    python3 $ROOT/tools/p8xfs.py get ccc.img A$s.ASM --out ccc_a_$s.asm >/dev/null 2>&1 || fail "the asm compiler produced no output for $s.c" ccc_out.txt
    python3 $ROOT/tools/p8xfs.py get ccc.img C$s.ASM --out ccc_c_$s.asm >/dev/null 2>&1 || fail "the C compiler produced no output for $s.c" ccc_out.txt
    cmp -s ccc_a_$s.asm ccc_c_$s.asm || { diff ccc_a_$s.asm ccc_c_$s.asm | head -10; fail "$s.c: the two compilers' text differs" ccc_out.txt; }
done
[ "$(grep -c '^OK[1-5]$' ccc_out.txt)" = "5" ] || fail "the && / || program (C compiler, native asm) did not print OK1..OK5" ccc_out.txt
grep -q '^ABA$' ccc_out.txt || fail "the 280-label / char[300] program did not print ABA" ccc_out.txt
echo "CC-C TEST: PASS ($(wc -c < ccc.bin | tr -d ' ') B; t/bigf/slots/and/lbl/grep text-identical to the asm compiler; and+lbl assembled natively and run)"
