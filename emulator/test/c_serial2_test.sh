#!/bin/sh
# P3 of the two-mode design (docs/p8x-two-mode-design.md): the SECOND serial port
# -- a 2nd ACIA at $FF08 (status) / $FF09 (data), register-identical to the first
# ($FF04/$FF05), for the later serial-terminal / Kermit file-transfer command.
# The emulator backs it with a file pair: -2i feeds RX bytes, -2o captures TX.
#
# The probe polls the 2nd ACIA's RDRF (status bit 0), reads each byte from $FF09,
# and echoes it BOTH to the 2nd port's TX ($FF09 write -> the -2o file) AND to the
# console ($FF05 -> serial stdout). So a known payload on -2i must come back on
# both stdout (RX works) and the -2o file (TX works), proving the port end to end.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-SERIAL2 TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o s2os.bin --base 0x2000 >/dev/null

# probe: drain the 2nd ACIA to the 2nd-port TX and the console (raw ACIA writes,
# so it needs no lib). test/*.c is gitignored, so generate it here.
cat > s2_probe.c <<'PROBEEOF'
//#define A1D 0xFF05  /* console (1st ACIA) data */
//#define A2S 0xFF08  /* 2nd ACIA status: bit0 RDRF, bit1 TDRE */
//#define A2D 0xFF09  /* 2nd ACIA data */
int main() {
    while (peek(A2S) & 1) {        /* RDRF: a byte waiting on the 2nd port */
        int c;
        c = peek(A2D);             /* read it */
        while ((peek(A2S) & 2) == 0) { }   /* TDRE: 2nd-port TX ready */
        poke(A2D, c);              /* echo it out the 2nd port (-> -2o file) */
        poke(A1D, c);              /* and to the console (serial stdout) */
    }
    return 0;
}
PROBEEOF

python3 $ROOT/compiler/p8cc.py s2_probe.c -o s2_probe.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py s2_probe.asm -o s2_probe.bin --base 0x6A00 >/dev/null

rm -f s2.img
python3 $ROOT/tools/p8xfs.py create s2.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   s2.img s2os.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  s2.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    s2.img s2_probe.bin --name /bin/s2.bin --load 0x6A00 --exec 0x6A00 >/dev/null

printf 'HELLO-P3' > s2_in.dat            # the payload arriving on the 2nd port
printf 'B\rrun /bin/s2.bin\r' > s2.in
../p8xemu -N -i s2.in -2i s2_in.dat -2o s2_out.dat -c s2.img -l 200000000 eeprom.bin > s2.out 2>/dev/null || true

# RX proven: the payload came back on the console (1st-port stdout)
tr -d '\0' < s2.out | grep -q 'HELLO-P3' || { echo "--- serial ---"; tr -d '\0' < s2.out | tail; fail "2nd-port RX did not reach the console"; }
# TX proven: the same bytes were written out the 2nd port into the -2o file
[ -f s2_out.dat ] || fail "2nd-port TX file (-2o) was not created"
got=$(cat s2_out.dat)
[ "$got" = "HELLO-P3" ] || fail "2nd-port TX file is '$got', want 'HELLO-P3'"

echo "C-SERIAL2 TEST: PASS (2nd ACIA \$FF08/\$FF09: RX from -2i echoed to console AND out -2o)"
