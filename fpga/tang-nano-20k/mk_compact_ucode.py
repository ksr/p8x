#!/usr/bin/env python3
"""Compact the microcode ROM so the FULL 64K memory map fits on the GW2AR-18.

The CPU addresses microcode as {cond(1), stp(4), IR(8)} = 8192 words x 32 bits =
256 Kbit = 15 BSRAM blocks. With a 64K main memory (32 blocks) that is 47 blocks
and the device has 46 -- which is why the first board build had to alias memory
down to 32K.

The opcode axis is sparse and the step axis is short: most opcodes finish in a
few steps, all the undefined encodings hold *the same* microcode, and every
step past an opcode's last one is the same "rail to fetch" word. So the ROM is
halved to 4096 words by giving each opcode a 16-word SLOT (8 steps x 2 condition
planes) and addressing it as {slot(8), stp[2:0], cond}:

    steps 0..7  of a defined opcode  live in slot IR (its own encoding);
    steps 8..15 of a LONG opcode     live in a second slot taken from the pool of
                                     UNDEFINED encodings (there are more spare
                                     encodings than long opcodes);
    an undefined opcode              maps to one shared UNDEF slot (steps 0..7),
    steps 8..15 of everything else   map to one shared RAIL slot (all urst).

The IR-side logic is a 256-entry 1-bit "is defined" table plus a small table
of second slots for the long opcodes -- less LUT logic than the earlier 7-bit
index map, and room for ~250 opcodes instead of 127. (2026-09-12: the Tier A
ISA reached 143 opcodes and the 7-bit scheme aborted here.)

The CPU is untouched. It still emits {cond, stp, IR}; the board top unpacks that,
maps IR to a slot, and repacks -- so the co-sim keeps verifying the same core.
Nothing is assumed: the script checks that the undefined encodings really share
one pattern, that every step past an opcode's end really is the rail word, and
that the compact image reproduces the original for ALL 8192 addresses.

Emits:
  irmap.vh      combinational: ir_def (IR is defined), ir_hi (slot of steps 8..15),
                ir_undef (the shared UNDEF slot number)
  ucode_c.hex   4096 x 32 compact microcode image
"""
import sys, os, importlib.util, io, contextlib


def load_opc(microdir):
    cwd = os.getcwd()
    try:
        os.chdir(microdir)
        spec = importlib.util.spec_from_file_location("gu", "genucode.py")
        gu = importlib.util.module_from_spec(spec)
        with contextlib.redirect_stdout(io.StringIO()):
            try: spec.loader.exec_module(gu)
            except SystemExit: pass
        return set(gu.OPC.values()), {code: len(steps) for code, steps in gu.U.items()}
    finally:
        os.chdir(cwd)


def main():
    here  = os.path.dirname(os.path.abspath(__file__))
    micro = sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "..", "microcode")
    outvh = os.path.join(here, "irmap.vh")
    outhex= os.path.join(here, "ucode_c.hex")

    roms = []
    for k in range(4):
        with open(os.path.join(micro, "u%d.bin" % k), "rb") as f:
            b = f.read()
        if len(b) != 8192:
            sys.exit("u%d.bin is %d bytes, expected 8192" % (k, len(b)))
        roms.append(b)
    word = lambda cond, stp, ir: (roms[0][(cond << 12) | (stp << 8) | ir]
                                  | roms[1][(cond << 12) | (stp << 8) | ir] << 8
                                  | roms[2][(cond << 12) | (stp << 8) | ir] << 16
                                  | roms[3][(cond << 12) | (stp << 8) | ir] << 24)
    column = lambda ir: tuple(word(c, s, ir) for c in range(2) for s in range(16))
    half = lambda ir, h: tuple(word(c, s, ir) for s in range(8 * h, 8 * h + 8) for c in range(2))

    used_set, nsteps = load_opc(micro)
    used = sorted(used_set)
    unused = [ir for ir in range(256) if ir not in used_set]

    # 1. every undefined encoding holds the same microcode (check, don't assume)
    sigs = {column(ir) for ir in unused}
    if len(sigs) != 1:
        sys.exit("ABORT: the %d undefined opcodes no longer share one microcode "
                 "pattern (%d distinct). Compaction would change behaviour."
                 % (len(unused), len(sigs)))
    undef_ir = unused[0]
    # 2. the rail word: steps past an opcode's last one are all identical
    rail = word(0, 15, undef_ir)
    for ir in used:
        for stp in range(nsteps[ir] + 1, 16):
            for cond in range(2):
                if word(cond, stp, ir) != rail:
                    sys.exit("ABORT: IR %02x step %d cond %d is not the rail word" % (ir, stp, cond))
    if half(undef_ir, 1) != tuple([rail] * 16):
        sys.exit("ABORT: the undefined column's steps 8..15 are not the rail word")

    # 3. slot allocation: steps 0..7 in slot IR; long opcodes take a spare encoding
    longs = [ir for ir in used if nsteps[ir] >= 8]           # steps 8.. exist (len >= 8)
    pool = list(unused)                                       # spare slot numbers
    if len(pool) < len(longs) + 2:
        sys.exit("ABORT: %d long opcodes + 2 shared slots need more spare encodings than the %d undefined ones"
                 % (len(longs), len(pool)))
    undef_slot = pool.pop(0)                                  # steps 0..7 of an undefined opcode
    rail_slot  = pool.pop(0)                                  # steps 8..15 of every short/undefined opcode
    hi = {ir: pool.pop(0) for ir in longs}

    with open(outvh, "w") as f:
        f.write("// GENERATED by mk_compact_ucode.py -- do not edit.\n")
        f.write("// Microcode slot map (combinational on purpose): ir_def = IR is a defined\n")
        f.write("// opcode (its steps 0..7 live in slot IR); ir_hi = the slot holding its steps\n")
        f.write("// 8..15 (long opcodes only, else the shared rail slot); ir_undef = the slot\n")
        f.write("// every undefined opcode maps to. %d defined, %d long, %d undefined.\n"
                % (len(used), len(longs), len(unused)))
        f.write("ir_undef = 8'h%02x;\n" % undef_slot)
        f.write("case (ir)\n")
        for ir in used:
            f.write("  8'h%02x: ir_def = 1'b1;\n" % ir)
        f.write("  default: ir_def = 1'b0;\n")
        f.write("endcase\n")
        f.write("case (ir)\n")
        for ir in longs:
            f.write("  8'h%02x: ir_hi = 8'h%02x;   // %d steps\n" % (ir, hi[ir], nsteps[ir]))
        f.write("  default: ir_hi = 8'h%02x;   // steps 8..15 of a short opcode: the rail\n" % rail_slot)
        f.write("endcase\n")

    def slot_of(ir, stp):
        if stp >= 8: return hi.get(ir, rail_slot)
        return ir if ir in used_set else undef_slot
    comp = [rail] * 4096
    for ir in range(256):
        for stp in range(16):
            for cond in range(2):
                comp[(slot_of(ir, stp) << 4) | ((stp & 7) << 1) | cond] = word(cond, stp, ir)
    with open(outhex, "w") as f:
        for w in comp: f.write("%08x\n" % w)

    # 4. prove the compact image reproduces the original for every address
    for ir in range(256):
        for stp in range(16):
            for cond in range(2):
                got = comp[(slot_of(ir, stp) << 4) | ((stp & 7) << 1) | cond]
                if got != word(cond, stp, ir):
                    sys.exit("ABORT: mismatch at cond=%d stp=%d IR=%02x" % (cond, stp, ir))

    print("irmap.vh: %d defined opcodes (slot = IR), %d long ones with a second slot, "
          "undef slot %02x, rail slot %02x, %d spare slots left"
          % (len(used), len(longs), undef_slot, rail_slot, len(pool)))
    print("ucode_c.hex: 4096 words (was 8192) -- verified identical for all 8192 "
          "original addresses")


if __name__ == "__main__":
    main()
