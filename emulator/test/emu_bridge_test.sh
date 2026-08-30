#!/bin/sh
# p8xemu -B: the emulator as the CPU of a real graphics card. No hardware
# here -- the "card" is test_glbridge's MockCard behind a pty -- but the
# whole path is real: BASIC statements -> the emulator's bus -> the
# card-edge protocol over a tty -> a register file on the far side.
# GCHECK's probes must read the mock's identity, LINE's register writes
# and GCMD must arrive on the wire, and PEEK must round-trip.
set -e
set -o pipefail
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode

fail() { echo "EMU-BRIDGE TEST: FAIL — $1"; exit 1; }

cp $UC/u?.bin .
python3 $ROOT/assembler/p8xasm.py $ROOT/firmware/p8xmon.asm -o eeprom.bin >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/os/p8xos.asm -o osc.bin --base 0x2000 >/dev/null
python3 $ROOT/assembler/p8xasm.py $ROOT/basic/p8xbasic.asm -o eb_basic.bin \
        --base 0x6A00 -D BASORG=0x6A00 -D BASRAM=0xC500 -D PBUF=0xE000 -D MONITOR=0x2000 >/dev/null

rm -f eb.img
python3 $ROOT/tools/p8xfs.py create eb.img >/dev/null
python3 $ROOT/tools/p8xfs.py boot   eb.img osc.bin >/dev/null
python3 $ROOT/tools/p8xfs.py mkdir  eb.img /bin >/dev/null
python3 $ROOT/tools/p8xfs.py put    eb.img eb_basic.bin --name /bin/basic.bin --load 0x6A00 --exec 0x6A00 >/dev/null

python3 - <<'EOF' || exit 1
import os, pty, sys, subprocess, threading, time
sys.path.insert(0, "../../fpga/tang-nano-20k/tools")
from test_glbridge import MockCard

mock = MockCard()
master, slave = pty.openpty()
sdev = os.ttyname(slave)

stop = False
def serve():
    # pump host bytes into the mock, mock replies back to the host
    while not stop:
        try:
            data = os.read(master, 256)
        except OSError:
            return
        if data:
            mock.send(data)          # feeds mock.rx, runs the decoder
        if mock.tx:
            os.write(master, mock.tx)
            mock.tx = b""
t = threading.Thread(target=serve, daemon=True)
t.start()

script = ("B\rbasic\r"
          "10 PRINT PEEK(65325)\r"          # $FF2D GID0 -> mock 'P' = 80
          "20 PRINT PEEK(65364)\r"          # $FF54 GLID -> mock 'G' = 71
          "30 COLOR 1234\r"                 # feeds BOTH pens: gfx + GL bytes
          "40 LINE 3,4,5,6\r"
          "50 PRINT PIXELR(3,4)\r"           # a read through GDATA
          "60 END\rRUN\rBYE\r")
open("eb.in", "w").write(script)

p = subprocess.run(["../p8xemu", "-N", "-B", sdev, "-i", "eb.in",
                    "-c", "eb.img", "-l", "400000000", "eeprom.bin"],
                   capture_output=True, timeout=300)
stop = True
out = p.stdout.decode("latin1").replace("\x00", "")

def seen(idx, val):
    return (idx, val) in mock.writes

ok = True
if "80" not in out:  print("FAIL: GID0 PEEK missing");  ok = False
if "71" not in out:  print("FAIL: GLID PEEK missing");  ok = False
# LINE 3,4,5,6: coord registers then GCMD=2, all on the wire
for idx, val in ((0x00, 3), (0x01, 4), (0x02, 5), (0x03, 6), (0x05, 2)):
    if not seen(idx, val):
        print("FAIL: write idx %02X val %d never crossed the wire" % (idx, val)); ok = False
# COLOR wrote the gfx pen low byte over the bridge (1234 & 255 = 210)
if not seen(0x04, 210):
    print("FAIL: COLOR low byte missing"); ok = False
# POINT: GCMD 9 then two GDATA reads happened (mock GDATA reads return 0)
if not seen(0x05, 9):
    print("FAIL: POINT command missing"); ok = False
sys.exit(0 if ok else 1)
EOF
echo "EMU-BRIDGE TEST: PASS (BASIC drove a mock card over the pty: identity PEEKs, LINE/COLOR/POINT register traffic all on the wire)"
