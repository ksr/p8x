#!/bin/sh
# lib_ps2 golden-model test: feed scripted PS/2 keyboard + mouse byte streams into
# the emulator's $FF58 window (p8xemu -ps2a/-ps2b) and check that lib_ps2 decodes
# them -- Set-2 make/break -> ASCII (shift + caps + a shifted symbol), and the
# standard 3-byte mouse packet -> (dx,dy,buttons) including a negative delta.
#
# The driver (ps2drv.c) and a copy of the library are scratch in this allow-list
# dir; only this .sh is committed. Runs headless (-ng): serial-only console, so
# the driver's output comes back on stdout. PS/2 is independent of the GL card.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode
fail() { echo "C-PS2 TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o gtos.bin --base 0x2000 >/dev/null

# the library, beside the driver, so clib.py's //#use ps2 resolves in this dir
cp $ROOT/os/commands/lib_ps2.c .

cat > ps2drv.c <<'EOF'
//#use ps2
/* hex byte printer (sign-safe: no signed compare, which is unsigned in p8cc) */
int hexc(int n) { n = n & 15; if (n < 10) { return n + 48; } return n + 55; }
int puthex(int v) { v = v & 255; putchar(hexc(v / 16)); putchar(hexc(v & 15)); return 0; }
int main() {
    int c; int n;
    ps2_init();
    if (ps2_present()) { puts("PRESENT"); } else { puts("ABSENT"); }
    puts("KBD:");
    n = 0;
    while (n < 300) { c = kb_getc(); if (c) { putchar(c); } n = n + 1; }
    putchar(10);
    puts("MOUSE:");
    n = 0;
    while (n < 300) {
        if (ms_poll()) { puthex(ms_dx & 255); puthex(ms_dy & 255); puthex(ms_btn); putchar(10); }
        n = n + 1;
    }
    puts("DONE");
    return 0;
}
EOF

python3 $ROOT/tools/clib.py    ps2drv.c -o ps2drv.pp.c >/dev/null
python3 $ROOT/compiler/p8cc.py ps2drv.pp.c -o ps2drv.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py ps2drv.asm -o ps2drv.bin --base 0x5900 >/dev/null

rm -f ps2.img
python3 $ROOT/tools/p8xfs.py create ps2.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   ps2.img gtos.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  ps2.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    ps2.img ps2drv.bin --name /bin/ps2drv.bin --load 0x5900 --exec 0x5900 >/dev/null

# port A (keyboard): Set-2 codes that type "Hi!" --
#   12 shift-dn, 33 'h' (+shift='H'), F0 33 release, F0 12 shift-up,
#   43 'i', F0 43 release, 12 shift-dn, 16 '1' (+shift='!'), F0 16, F0 12
printf '\x12\x33\xf0\x33\xf0\x12\x43\xf0\x43\x12\x16\xf0\x16\xf0\x12' > kbd.bin
# port B (mouse): three 3-byte packets --
#   09 00 00  left click, no move          -> dx 0  dy 0  btn 1
#   08 05 03  move right+up, no button      -> dx +5 dy +3 btn 0
#   18 FB 00  X-sign set, dx=0xFB           -> dx -5 dy 0  btn 0
printf '\x09\x00\x00\x08\x05\x03\x18\xfb\x00' > mouse.bin

printf 'B\rps2drv\r' > ps2.in
../p8xemu -ng -i ps2.in -c ps2.img -ps2a kbd.bin -ps2b mouse.bin -l 60000000 eeprom.bin \
    > ps2.out 2>/dev/null || true
out=$(tr -d '\0' < ps2.out | tr -d '\r')

echo "$out" | grep -q 'PRESENT'  || fail "PSID did not read 'K' (ps2_present)"
echo "$out" | grep -q '^Hi!$'    || fail "keyboard decode wrong (expected Hi!); got: $(echo "$out" | sed -n '/KBD:/{n;p;}')"
echo "$out" | grep -q '^000001$' || fail "mouse packet 1 wrong (expected 000001 = left click, no move)"
echo "$out" | grep -q '^050300$' || fail "mouse packet 2 wrong (expected 050300 = +5,+3, no button)"
echo "$out" | grep -q '^FB0000$' || fail "mouse packet 3 wrong (expected FB0000 = -5,0, no button)"
echo "$out" | grep -q 'DONE'     || fail "driver did not finish"

echo "C-PS2 TEST: PASS (PSID 'K'; Set-2 -> Hi!; mouse packets incl. a negative delta)"
