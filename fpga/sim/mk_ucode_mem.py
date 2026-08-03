#!/usr/bin/env python3
"""Combine the four P8X microcode ROM images into a single 32-bit-wide
$readmemh init file for the FPGA microcode BRAM.

The emulator forms each control word as
    cw = u0[ad] | u1[ad]<<8 | u2[ad]<<16 | u3[ad]<<24
(p8xemu.c). We emit exactly that 32-bit word per address, 8192 lines of 8 hex
digits, so the RTL `ucode_rom` reads the same word the emulator interprets and
the two cannot drift.

Usage: mk_ucode_mem.py <dir-with-u0..u3.bin> <out.hex>
       (dir defaults to ../../emulator, out to ucode.hex)
"""
import sys, os

def main():
    here = os.path.dirname(os.path.abspath(__file__))
    src  = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "..", "emulator")
    out  = sys.argv[2] if len(sys.argv) > 2 else os.path.join(here, "ucode.hex")
    roms = []
    for k in range(4):
        p = os.path.join(src, "u%d.bin" % k)
        with open(p, "rb") as f:
            b = f.read()
        if len(b) != 8192:
            sys.exit("error: %s is %d bytes, expected 8192" % (p, len(b)))
        roms.append(b)
    with open(out, "w") as f:
        for ad in range(8192):
            word = roms[0][ad] | roms[1][ad] << 8 | roms[2][ad] << 16 | roms[3][ad] << 24
            f.write("%08x\n" % word)
    print("wrote %s (8192 x 32-bit words)" % out)

if __name__ == "__main__":
    main()
