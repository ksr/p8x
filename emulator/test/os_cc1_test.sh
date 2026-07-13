#!/bin/sh
# Self-host pass 3: the native parser (cc1, os/commands/cc1.c) run ON the P8X must
# turn a LEX token stream into the exact serialized AST the host reference
# `p8cc.py --ast` produces. This exercises the real pass-2 -> pass-3 chain: run
# `lex SRC >SRC.tok` then `cc1 SRC.tok >SRC.ast` on-target, and assert SRC.ast is
# byte-identical to `p8cc.py --ast SRC` on the host.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o oscc1.bin --base 0x2000 >/dev/null

# lex.bin + cc1.bin are host-built (both //#use apath); they become /bin/*.bin.
python3 $ROOT/tools/clib.py $ROOT/os/commands/lex.c -o lex.pp.c
python3 $ROOT/compiler/p8cc.py lex.pp.c -o lex.cc.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py lex.cc.asm -o lex.cc.bin --base 0x7A00 >/dev/null
python3 $ROOT/tools/clib.py $ROOT/os/commands/cc1.c -o cc1.pp.c
python3 $ROOT/compiler/p8cc.py cc1.pp.c -o cc1.cc.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py cc1.cc.asm -o cc1.cc.bin --base 0x7A00 >/dev/null

# a source exercising every construct: struct, globals+initializers, functions
# with params/locals, all statement forms, and the full expression grammar.
cat > cc1_src.c <<'EOF'
struct P { int x; char *name; int v[4]; };
char buf[8] = "hi";
int tab[3] = {1, 2, 3};
int helper(int a, char *s);
int helper(int a, char *s) {
    int i;
    i = 0;
    while (i < a) {
        if (s[i] == 0 || i > 10) { return i; }
        i = i + 1;
    }
    return a - '0';
}
int main() {
    struct P p;
    int j;
    p.x = 0x1F + helper(3, buf) * 2;
    for (j = 0; j < 3; j = j + 1) { tab[j] = tab[j] << 1; }
    return p.x & 7;
}
EOF

rm -f cc1.img
python3 $ROOT/tools/p8xfs.py create cc1.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   cc1.img oscc1.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  cc1.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    cc1.img lex.cc.bin --name /bin/lex.bin --load 0x7A00 --exec 0x7A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    cc1.img cc1.cc.bin --name /bin/cc1.bin --load 0x7A00 --exec 0x7A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    cc1.img cc1_src.c --name /cc1_src.c >/dev/null

fail() { echo "OS-CC1 TEST: FAIL — $1"; exit 1; }

# run the chain on-target: lex then cc1
printf 'B\rlex cc1_src.c >S.tok\rcc1 S.tok >S.ast\r' | ../p8xemu -l 900000000 -c cc1.img eeprom.bin 2>/dev/null >/dev/null
python3 $ROOT/tools/p8xfs.py get cc1.img S.ast --out cc1_out.ast >/dev/null 2>&1
[ -s cc1_out.ast ] || fail "cc1 produced no /S.ast"

# host reference AST for the same source
python3 $ROOT/compiler/p8cc.py --ast cc1_src.c > cc1_ref.ast 2>/dev/null

cmp -s cc1_out.ast cc1_ref.ast || {
    echo "--- diff (on-target < vs host reference >) ---"
    diff cc1_out.ast cc1_ref.ast | head -20
    fail "on-target AST differs from p8cc.py --ast"
}
echo "OS-CC1 TEST: PASS"
