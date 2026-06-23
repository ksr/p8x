#!/bin/sh
# Milestone A (self-hosting p8cc): compiler/p8cc.c is BOTH standard C and
# p8cc-subset C.  This checks the two build paths and that the subset accepts
# its own source:
#   1. a host C compiler (cc) builds p8cc.c -> a native bootstrap compiler;
#   2. that bootstrap lexes a sample identically to the expected output;
#   3. p8cc.py compiles p8cc.c and the result assembles (subset accepts itself).
# Running the p8cc.py-built binary ON the P8X is Milestone B (RAM/streaming) and
# is NOT exercised here.  p8cc.c is built incrementally; this stage is the lexer.
set -e
cd "$(dirname "$0")"
ROOT=../..

fail() { echo "C-SELFHOST TEST: FAIL — $1"; exit 1; }

# 1. host build
if ! command -v cc >/dev/null 2>&1; then
    echo "C-SELFHOST TEST: SKIP (no host cc)"; exit 0
fi
cc -w $ROOT/compiler/p8cc.c -o p8cc_host 2>/dev/null || fail "cc could not build p8cc.c"

# 2. host lexer classification of a fixed sample
got=$(printf "int main() { return 0x10 + 'a'; }\n" | ./p8cc_host)
[ "$got" = "kipppknpnpp" ] || fail "host lexer output '$got' != 'kipppknpnpp'"

# 3. p8cc.py compiles p8cc.c and the assembler accepts it (subset self-compiles)
python3 $ROOT/compiler/p8cc.py $ROOT/compiler/p8cc.c -o pcc.asm >/dev/null \
    || fail "p8cc.py could not compile p8cc.c"
python3 $ROOT/assembler/p8xasm.py pcc.asm -o pcc.bin --base 0xB000 >/dev/null \
    || fail "p8cc.py output of p8cc.c did not assemble"

echo "C-SELFHOST TEST: PASS"
