#!/usr/bin/env python3
"""Build the combined monitor + ROM-BASIC EEPROM image.

The ROM-resident BASIC is assembled to run at $2000 (BASORG) with its data at
$A000 (BASRAM), and overlaid into the 32K monitor ROM image at offset $2000.
The monitor's X command JMPs to $2000 to launch it. The monitor body lives
below $2000, so the two never overlap (this script asserts it).

Usage:  tools/build_basic_rom.py [out.bin]      (default: p8x-rom-basic.bin)
"""
import sys, os, subprocess, tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASM  = os.path.join(ROOT, "assembler", "p8xasm.py")
MON  = os.path.join(ROOT, "firmware", "p8xmon.asm")
BAS  = os.path.join(ROOT, "basic", "p8xbasic.asm")
BASE = 0x2000

def asm(src, out, *extra):
    subprocess.run([sys.executable, ASM, src, "-o", out, *extra],
                   check=True, stdout=subprocess.DEVNULL)

def main():
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "p8x-rom-basic.bin")
    with tempfile.TemporaryDirectory() as d:
        mon_bin = os.path.join(d, "mon.bin")
        bas_bin = os.path.join(d, "basic.bin")
        asm(MON, mon_bin)
        asm(BAS, bas_bin, "--base", hex(BASE),
            "-D", "BASORG=0x%X" % BASE, "-D", "BASRAM=0xA000")
        rom = bytearray(open(mon_bin, "rb").read())          # 32K
        bas = open(bas_bin, "rb").read()
        end = BASE + len(bas)
        if any(rom[BASE:end]):
            sys.exit("build_basic_rom: monitor occupies $%04X..$%04X — "
                     "BASIC would overwrite it" % (BASE, end - 1))
        rom[BASE:end] = bas
        open(out, "wb").write(rom)
        print("wrote %s: monitor + BASIC (%d bytes @ $%04X)" % (out, len(bas), BASE))

if __name__ == "__main__":
    main()
