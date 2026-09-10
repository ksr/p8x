#!/bin/sh
# P5 Kermit command: Kermit-style file transfer over the 2nd serial port
# ($FF08/$FF09, from P3). `kermit send /F` frames a file into packets out port 2;
# `kermit recv /F` reads packets from port 2 into a file. Framing: SEQ LEN
# data[LEN] CHK per packet, a LEN=0 packet ends the file.
#
# Round-trip: send /A.DAT with the emulator capturing port-2 TX to a file (-2o),
# then recv /B.DAT feeding that capture back as port-2 RX (-2i). /B.DAT must equal
# /A.DAT byte-for-byte -- proving the framing + checksum are self-consistent end
# to end, with the P8X as both the sender and the receiver.
set -e
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "C-KERMIT TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o kos.bin --base 0x2000 >/dev/null
python3 $ROOT/tools/clib.py $ROOT/os/commands/kermit.c -o km.pp.c >/dev/null
python3 $ROOT/compiler/p8cc.py km.pp.c -o km.asm >/dev/null
python3 $ROOT/assembler/p8xasm.py km.asm -o km.bin --base 0x6A00 >/dev/null

# a payload that spans several 64-byte packets (171 bytes)
python3 -c "open('adat.bin','wb').write((b'The quick brown fox jumps over the lazy dog. 0123456789. ')*3)"

rm -f k.img
python3 $ROOT/tools/p8xfs.py create k.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   k.img kos.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  k.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    k.img km.bin   --name /bin/kermit.bin --load 0x6A00 --exec 0x6A00 >/dev/null
python3 $ROOT/tools/p8xfs.py put    k.img adat.bin --name /A.DAT >/dev/null

# send: /A.DAT -> port 2 TX (captured to cap.dat)
printf 'B\rrun /bin/kermit.bin send /A.DAT\r' > ks.in
../p8xemu -N -i ks.in -2o cap.dat -c k.img -l 200000000 eeprom.bin > ks.out 2>/dev/null || true
tr -d '\0' < ks.out | grep -q 'kermit: sent' || fail "send did not complete"
[ -s cap.dat ] || fail "nothing was sent out port 2 (-2o empty)"

# recv: port 2 RX (cap.dat) -> /B.DAT
printf 'B\rrun /bin/kermit.bin recv /B.DAT\r' > kr.in
../p8xemu -N -i kr.in -2i cap.dat -c k.img -l 200000000 eeprom.bin > kr.out 2>/dev/null || true
tr -d '\0' < kr.out | grep -q 'kermit: received' || { tr -d '\0'<kr.out|grep -q checksum && fail "recv reported a checksum error"; fail "recv did not complete"; }

# the round-trip is byte-exact
python3 $ROOT/tools/p8xfs.py get k.img /B.DAT --out bdat.bin >/dev/null 2>&1 || fail "recv wrote no /B.DAT"
cmp -s adat.bin bdat.bin || fail "round-trip mismatch (/B.DAT != /A.DAT)"

echo "C-KERMIT TEST: PASS (send frames a file out port 2; recv reads it back; round-trip byte-exact)"
