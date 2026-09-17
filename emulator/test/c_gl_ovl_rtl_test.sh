#!/bin/sh
# Scanout-compositor cross-implementation pixel proof: the SAME TX* + background
# GL byte stream (ending in GXEN 0) is composited by the EMULATOR (gpu_tx_sample
# into its -g PPM) and by the RTL (tb_gl_ovx.v: real p8x_geom + gfx + arbiter +
# p8x_sdram + sdram_video WITH its gtxt, captured at the SCANOUT PINS -- both
# layers composite there, so the SDRAM dump the other tb_gl_* benches use would
# not see them). The two 480x272 frames must be BYTE-IDENTICAL: TXEN, window,
# colour, glyphs, cursor advance, TXSCR AND the GXEN bitmap-visibility mux (blue
# CLEARS ground hidden to black, white text on top) agreeing on every pixel.
# Needs iverilog on PATH.
set -e
set -o pipefail
cd "$(dirname "$0")"
ROOT=../..
UC=../../microcode
SD=../../fpga/tang-nano-20k/sdram

fail() { echo "C-GL-OVL-RTL TEST: FAIL — $1"; exit 1; }
command -v iverilog >/dev/null 2>&1 || fail "iverilog not on PATH"

cp $UC/u?.bin .

# ---- emulator golden: a bare program poking the exact TX byte stream --------
python3 - <<'PY'
seq  = [0x0F,0,0,31,  0x52,31,63,31,  0x51,0,0,80,34,  0x50,1,  0x55,  0x53,2,2]
for c in "P8X RTL": seq += [0x54, ord(c)]
seq += [0x53,2,4,  0x54,ord('Y'),  0x54,ord('Z'),  0x56]        # 2nd row + TXSCR
seq += [0x57, 0]    # GXEN 0: hide the blue bitmap -> text on black (both layers)
lines = ["GLDATA = $FF50", "        .org 0"]
for bb in seq: lines += ["        LDA #$%02X" % bb, "        STA GLDATA"]
lines.append("        HLT")
open("ovl_probe.asm","w").write("\n".join(lines)+"\n")
PY
python3 $ROOT/assembler/p8xasm.py ovl_probe.asm -o ovl_probe.bin >/dev/null
../p8xemu -l 5000000 -g ovl_emu.ppm ovl_probe.bin >/dev/null 2>&1 || true
[ -f ovl_emu.ppm ] || fail "emulator produced no PPM"

# ---- RTL frame through the real pixel stack, captured at the scanout pins ---
( cd $SD && iverilog -g2012 -I../../rtl -o tbovx tb_gl_ovx.v ../../rtl/p8x_geom.v \
      ../../rtl/mdu_core.v ../../rtl/trigtab.v ../../rtl/gfx.v ../../rtl/gtxt.v \
      gfx_mem.v gfx_span.v sdram_arb.v p8x_sdram.v sdram_video.v sdram_chip.v \
  && vvp tbovx | grep -q "TB-GL-OVX: DONE" ) || fail "tb_gl_ovx did not finish"

cmp ovl_emu.ppm $SD/tb_gl_ovx.ppm || fail "RTL overlay frame differs from emulator frame"
echo "C-GL-OVL-RTL TEST: PASS (TX* overlay + GXEN mux: RTL scanout == emulator, byte-identical)"
