#!/bin/sh
# p8cc (C cross-compiler) end to end: compile a C program to P8X asm, assemble
# it, RUN it under P8X/OS, and check its console output. Exercises while/if,
# arithmetic (+ * <=), assignment, a user function returning via AX, and the
# putchar/puts builtins over the BIOS.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x4000 >/dev/null

cat > ctest.c <<'EOF'
int sq() { return 7 * 7; }
int main() {
    int i;
    i = 1;
    while (i <= 5) {
        putchar(i + 48);
        i = i + 1;
    }
    putchar(10);
    if (sq() == 49) puts("SQ-OK");
    return 0;
}
EOF
python3 $ROOT/compiler/p8cc.py ctest.c -o ctest.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py ctest.asm -o ctest.bin --base 0xB000 >/dev/null

rm -f c.img
python3 $ROOT/tools/p8xfs.py create c.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   c.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    c.img ctest.bin --name CT.BIN --load 0xB000 --exec 0xB000 >/dev/null

out=$(printf 'B\rRUN CT.BIN\r' | ../p8xemu -l 120000000 -c c.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')
fail() { echo "C-COMPILE TEST: FAIL — $1"; echo "$out" | sed -n '/RUN CT/,$p'; exit 1; }

echo "$out" | grep -qx '12345' || fail "loop/arith output not '12345'"
echo "$out" | grep -qx 'SQ-OK' || fail "user function / multiply path failed"
echo "C-COMPILE TEST: PASS"
