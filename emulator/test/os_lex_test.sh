#!/bin/sh
# Self-host pass 2: the native LEX (tokenizer, os/commands/lex.c) run ON the P8X
# must produce the exact same token stream as the host reference
# `p8cc.py --tokens`. Build lex.bin, put a couple of (preprocessed) C sources on a
# disk, run `lex SRC >OUT.tok` on-target, and assert the on-target token stream is
# byte-identical to the host p8cc.py --tokens output for the same source.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o oslex.bin --base 0x4000 >/dev/null

# lex itself is built on the host (it //#use apath); it becomes /bin/lex.bin.
python3 $ROOT/tools/clib.py $ROOT/os/commands/lex.c -o lex.pp.c
python3 $ROOT/compiler/p8cc.py lex.pp.c -o lex.cc.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py lex.cc.asm -o lex.cc.bin --base 0x7A00 >/dev/null

# a small source that exercises every token class: keywords, identifiers, decimal
# and hex numbers, char literals with escapes, string literals with escapes,
# single- and multi-char operators, and both comment styles (line-counting quirk).
cat > lex_src.c <<'EOF'
/* header
   comment */
int g;
int main() {
    int x;          // trailing comment
    char *s;
    x = 0x1F + 3;
    s = "hi\n\t\"end\"";
    if (x >= 16 && x != 99) { x = x << 2; }
    return x - '0';
}
EOF

rm -f lex.img
python3 $ROOT/tools/p8xfs.py create lex.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   lex.img oslex.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  lex.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    lex.img lex.cc.bin --name /bin/lex.bin --load 0x7A00 --exec 0x7A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    lex.img lex_src.c --name /lex_src.c >/dev/null

fail() { echo "OS-LEX TEST: FAIL — $1"; exit 1; }

# run the native lexer, capturing its token stream to /OUT.tok on the card
printf 'B\rlex lex_src.c >OUT.tok\r' | ../p8xemu -l 400000000 -c lex.img eeprom.bin 2>/dev/null >/dev/null
python3 $ROOT/tools/p8xfs.py get lex.img OUT.tok --out lex_out.tok >/dev/null 2>&1
[ -s lex_out.tok ] || fail "lex produced no /OUT.tok"

# host reference token stream for the same source
python3 $ROOT/compiler/p8cc.py --tokens lex_src.c > lex_ref.tok 2>/dev/null

cmp -s lex_out.tok lex_ref.tok || {
    echo "--- diff (on-target < vs host reference >) ---"
    diff lex_out.tok lex_ref.tok | head -40
    fail "on-target token stream differs from p8cc.py --tokens"
}
echo "OS-LEX TEST: PASS"
