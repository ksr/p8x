#!/bin/sh
# p8cc global initializers: scalar int, char* to a string literal, an int array
# initializer list, an array-of-char* (string table), and char[] from a string
# (inferred length). Compiles, assembles, RUNs and checks output "7HI/6CY/YO".
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x4000 >/dev/null

cat > cglob.c <<'EOF'
int n = 7;
char *msg = "HI";
int squares[4] = {1, 4, 9, 16};
char *names[3] = {"AL", "BO", "CY"};
char greet[] = "YO";
int main() {
    putchar(48 + n);                 /* 7 */
    puts(msg);                       /* HI */
    putchar(48 + squares[3] - 10);   /* 16-10 = 6 */
    puts(names[2]);                  /* CY */
    puts(greet);                     /* YO */
    return 0;
}
EOF
python3 $ROOT/compiler/p8cc.py cglob.c -o cglob.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py cglob.asm -o cglob.bin --base 0xA700 >/dev/null

rm -f cg.img
python3 $ROOT/tools/p8xfs.py create cg.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   cg.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    cg.img cglob.bin --name CG.BIN --load 0xA700 --exec 0xA700 >/dev/null

out=$(printf 'B\rRUN CG.BIN\r' | ../p8xemu -l 120000000 -c cg.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')
fail() { echo "C-GLOBAL TEST: FAIL — $1"; echo "$out" | sed -n '/RUN CG/,$p'; exit 1; }

echo "$out" | grep -qx '7HI'  || fail "scalar int / char* string init failed"
echo "$out" | grep -qx '6CY'  || fail "int array list / char* table init failed"
echo "$out" | grep -qx 'YO'   || fail "char[] from string (inferred length) failed"
echo "C-GLOBAL TEST: PASS"
