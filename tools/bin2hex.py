#!/usr/bin/env python3
"""Binary -> Intel HEX, for loading P8X ROM images into an EEPROM programmer.

Importable: `write(data, path, base=0)` / `to_ihex(data, base=0)`.
CLI:        python3 bin2hex.py in.bin out.hex [base_addr]

16 data bytes per record, record type 00 (data), terminated by an end record.
Addresses are 16-bit (records cap at $FFFF) — fine for the 28C64 microcode EPROMs
(8 KB) and the 28C256 program ROM (32 KB). Anything past 64 KB would need
extended-linear-address (type 04) records, which P8X images never reach."""
import sys

def to_ihex(data, base=0, width=16):
    if base + len(data) > 0x10000:
        raise ValueError("image exceeds 64 KB; needs type-04 extended records")
    lines = []
    for off in range(0, len(data), width):
        chunk = data[off:off + width]
        addr = base + off
        rec = [len(chunk), (addr >> 8) & 0xFF, addr & 0xFF, 0x00] + list(chunk)
        chk = (-sum(rec)) & 0xFF
        lines.append(":" + "".join("%02X" % b for b in rec) + "%02X" % chk)
    lines.append(":00000001FF")              # end-of-file record
    return "\n".join(lines) + "\n"

def write(data, path, base=0):
    with open(path, "w") as f:
        f.write(to_ihex(bytes(data), base))

if __name__ == "__main__":
    if not 3 <= len(sys.argv) <= 4:
        sys.exit("usage: bin2hex.py in.bin out.hex [base_addr]")
    base = int(sys.argv[3], 0) if len(sys.argv) == 4 else 0
    with open(sys.argv[1], "rb") as f:
        write(f.read(), sys.argv[2], base)
    print("wrote", sys.argv[2])
