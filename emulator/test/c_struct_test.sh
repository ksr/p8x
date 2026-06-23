#!/bin/sh
# p8cc structs/unions: definitions, member access (. and ->), pointer-to-struct,
# nested struct members, array members, and a union (members share offset 0).
# Compiles, assembles, RUNs under P8X/OS and checks the console output "796A".
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x4000 >/dev/null

cat > cstruct.c <<'EOF'
struct Point { int x; int y; };
struct Rect { struct Point tl; struct Point br; };
union U { int i; char c[2]; };

int wide(struct Rect *r) { return r->br.x - r->tl.x; }   /* -> and nested . */

int main() {
    struct Point p;
    p.x = 3; p.y = 4;
    putchar(48 + p.x + p.y);            /* 7 */
    struct Point *pp;
    pp = &p;
    pp->x = 9;
    putchar(48 + pp->x);                /* 9 */
    struct Rect r;
    r.tl.x = 2; r.br.x = 8;
    putchar(48 + wide(&r));             /* 6 */
    union U u;
    u.c[0] = 65; u.c[1] = 0;
    putchar(u.c[0]);                    /* A */
    putchar(10);
    return 0;
}
EOF
python3 $ROOT/compiler/p8cc.py cstruct.c -o cstruct.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py cstruct.asm -o cstruct.bin --base 0xB000 >/dev/null

rm -f cs.img
python3 $ROOT/tools/p8xfs.py create cs.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   cs.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    cs.img cstruct.bin --name CS.BIN --load 0xB000 --exec 0xB000 >/dev/null

out=$(printf 'B\rRUN CS.BIN\r' | ../p8xemu -l 120000000 -c cs.img eeprom.bin 2>/dev/null | LC_ALL=C tr -d '\0\r')
fail() { echo "C-STRUCT TEST: FAIL — $1"; echo "$out" | sed -n '/RUN CS/,$p'; exit 1; }

echo "$out" | grep -qx '796A' || fail "struct/union member access output not '796A'"
echo "C-STRUCT TEST: PASS"
