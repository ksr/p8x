#!/bin/sh
# `make` built-in: reads a real Makefile from the CWD (target: deps + TAB recipe),
# resolves prerequisites depth-first (deps built before their dependents, shared
# deps built exactly once), flattens the plan's recipes to a temp file and runs it
# through the `sh` engine. Two phases:
#   A. make semantics (fast, cat/cp recipes only): deps-first order, dedup, clean,
#      unknown-target + prerequisite-cycle errors.
#   B. toolchain integration: `make pwd` drives cc+asm to build a command from its
#      C source (and asm from its asm source), `make install` publishes it to /bin,
#      then the published /bin/pwd.bin runs — the whole native build the way
#      run.sh's generated Makefiles are used (`cd /src/commands/c && make all`).
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode
fail() { echo "OS-MAKE TEST: FAIL — $1"; [ -f "$2" ] && { echo "--- transcript ---"; cat "$2"; }; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osmk.bin --base 0x2000 >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/apps/p8xcc.asm -o cc.bin --base 0x6A00 >/dev/null
python3 $ROOT/generators/gen_p8xopc.py > opctab.asm
cat $ROOT/apps/p8xasm.asm opctab.asm > asmfull.asm
python3 $ROOT/assembler/p8xasm.py asmfull.asm -o asm.bin --base 0x6A00 >/dev/null
# cat + cp: the phase-A recipe commands (and cp publishes in phase B).
build_c() { # build_c <src.c> <out.bin>
    python3 $ROOT/tools/clib.py "$1" -o tmp.pp.c 2>/dev/null
    python3 $ROOT/compiler/p8cc.py tmp.pp.c -o tmp.asm >/dev/null 2>&1
    python3 $ROOT/assembler/p8xasm.py tmp.asm -o "$2" --base 0x6A00 >/dev/null 2>&1
}
build_c $ROOT/os/commands/cat.c cat.bin
build_c $ROOT/os/commands/cp.c  cp.bin

rm -f mk.img
python3 $ROOT/tools/p8xfs.py create mk.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   mk.img osmk.bin >/dev/null
for d in /bin /lib /src /src/commands /src/commands/c /src/commands/c/bin \
         /src/commands/asm /src/commands/asm/bin /work; do
    python3 $ROOT/tools/p8xfs.py mkdir mk.img "$d" >/dev/null
done
python3 $ROOT/tools/p8xfs.py put mk.img cc.bin  --name /bin/cc.bin  --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put mk.img asm.bin --name /bin/asm.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put mk.img cat.bin --name /bin/cat.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put mk.img cp.bin  --name /bin/cp.bin  --load 0x6A00 --exec 0x6A00 >/dev/null
printf 'hi\n' > HELLO.TXT
python3 $ROOT/tools/p8xfs.py put mk.img HELLO.TXT --name /HELLO.TXT >/dev/null

# ---------- Phase A: make semantics (distinct recipe per target to trace order) --
# all -> a,b ; a -> shared ; b -> shared ; shared is a shared prereq (build once).
# x <-> y is a cycle. clean/nope exercise the error + delete paths.
{
  printf 'all: a b\n\tcp /HELLO.TXT /ALL.TXT\n'
  printf 'a: shared\n\tcp /HELLO.TXT /A.TXT\n'
  printf 'b: shared\n\tcp /HELLO.TXT /B.TXT\n'
  printf 'shared:\n\tcp /HELLO.TXT /S.TXT\n'
  printf 'clean:\n\tdel /A.TXT\n'
  printf 'x: y\n\tcp /HELLO.TXT /X.TXT\n'
  printf 'y: x\n\tcp /HELLO.TXT /Y.TXT\n'
} > Makefile.A
python3 $ROOT/tools/p8xfs.py put mk.img Makefile.A --name /work/Makefile >/dev/null

printf 'B\rcd /work\rmake all\rmake nope\rmake x\rmake clean\r' \
    | ../p8xemu -l 800000000 -c mk.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r' > mkA_out.txt

# deps-first order: shared's recipe before a's, a's before b's, b's before all's.
sline=$(grep -n 'cp /HELLO.TXT /S.TXT'   mkA_out.txt | head -1 | cut -d: -f1)
aline=$(grep -n 'cp /HELLO.TXT /A.TXT'   mkA_out.txt | head -1 | cut -d: -f1)
bline=$(grep -n 'cp /HELLO.TXT /B.TXT'   mkA_out.txt | head -1 | cut -d: -f1)
allln=$(grep -n 'cp /HELLO.TXT /ALL.TXT' mkA_out.txt | head -1 | cut -d: -f1)
[ -n "$sline" ] && [ -n "$aline" ] && [ -n "$bline" ] && [ -n "$allln" ] \
    || fail "make all did not run every prerequisite recipe" mkA_out.txt
[ "$sline" -lt "$aline" ] && [ "$aline" -lt "$bline" ] && [ "$bline" -lt "$allln" ] \
    || fail "prerequisites not built depth-first (order was S=$sline A=$aline B=$bline ALL=$allln)" mkA_out.txt
# dedup: the shared prereq's recipe ran exactly once though a AND b depend on it.
n=$(grep -c 'cp /HELLO.TXT /S.TXT' mkA_out.txt)
[ "$n" -eq 1 ] || fail "shared prerequisite built $n times, expected once (dedup)" mkA_out.txt
# errors
grep -q 'no rule to make target' mkA_out.txt || fail "unknown target 'nope' not reported" mkA_out.txt
grep -q 'cycle'                  mkA_out.txt || fail "prerequisite cycle x<->y not detected" mkA_out.txt
# clean deleted /A.TXT (cp created it during `make all`)
python3 $ROOT/tools/p8xfs.py ls mk.img / 2>/dev/null | grep -qE '^A\.TXT ' \
    && fail "make clean did not delete /A.TXT" mkA_out.txt

# ---------- Phase B: make drives the native toolchain (cc + asm) -----------------
python3 $ROOT/tools/p8xfs.py put mk.img $ROOT/os/commands/pwd.c       --name /src/commands/c/pwd.c     >/dev/null
python3 $ROOT/tools/p8xfs.py put mk.img $ROOT/os/commands-asm/pwd.asm --name /src/commands/asm/pwd.asm >/dev/null
# pwd names its BIOS/OS addresses: cc's //#use abi splices /lib/lib_abi.c, asm's
# ;#use abi splices /lib/abi.inc — both must be on the disk.
python3 $ROOT/tools/p8xfs.py put mk.img $ROOT/os/commands/lib_abi.c       --name /lib/lib_abi.c >/dev/null
python3 $ROOT/tools/p8xfs.py put mk.img $ROOT/os/commands-asm/lib_abi.inc --name /lib/abi.inc    >/dev/null
# Makefiles exactly as run.sh generates them (relative recipes, run in the CWD).
printf 'pwd:\n\tcc pwd.c >T.ASM\n\tasm T.ASM bin/pwd.bin\ninstall:\n\tcp /src/commands/c/bin/*.bin /bin\n' > Makefile.C
printf 'pwd:\n\tasm pwd.asm bin/pwd.bin\n' > Makefile.S
python3 $ROOT/tools/p8xfs.py put mk.img Makefile.C --name /src/commands/c/Makefile   >/dev/null
python3 $ROOT/tools/p8xfs.py put mk.img Makefile.S --name /src/commands/asm/Makefile >/dev/null

# Build the C twin, publish it to /bin, and run the published binary; build the asm twin.
printf 'B\rcd /src/commands/c\rmake pwd\rmake install\rcd /src/commands/asm\rmake pwd\rrun /bin/pwd.bin\r' \
    | ../p8xemu -l 9000000000 -c mk.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r' > mkB_out.txt

python3 $ROOT/tools/p8xfs.py ls mk.img /src/commands/c/bin 2>/dev/null | grep -qE '^pwd\.bin ' \
    || fail "make pwd (C) produced no /src/commands/c/bin/pwd.bin" mkB_out.txt
python3 $ROOT/tools/p8xfs.py ls mk.img /src/commands/asm/bin 2>/dev/null | grep -qE '^pwd\.bin ' \
    || fail "make pwd (asm) produced no /src/commands/asm/bin/pwd.bin" mkB_out.txt
python3 $ROOT/tools/p8xfs.py ls mk.img /bin 2>/dev/null | grep -qE '^pwd\.bin ' \
    || fail "make install did not publish /bin/pwd.bin" mkB_out.txt
grep -qE '^/src/commands/asm$' mkB_out.txt \
    || fail "published /bin/pwd.bin did not run / print the CWD" mkB_out.txt

echo "OS-MAKE TEST: PASS"
