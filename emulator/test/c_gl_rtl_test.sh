#!/bin/sh
# Stage-10a cross-implementation pixel proof: the SAME GL hex command stream
# is rendered by the EMULATOR (c_gl_test.sh's gl_b program, run on the
# emulated machine) and by the RTL (tb_gl_pix.v: real p8x_geom + gfx +
# arbiter + p8x_sdram + sdram chip model at the pins), and the two 480x272
# framebuffers must be BYTE-IDENTICAL. This is the strongest 10a statement:
# not just the same ops (tb_gl) or the same emulator pixels (c_gl_test),
# but the flashed logic and the golden model agreeing on every pixel of a
# frame that exercises FLOOD, colour, plain/window-clipped/near-clipped
# lines and two filled TRIs. Needs iverilog on PATH.
set -e
set -o pipefail
cd "$(dirname "$0")"
SD=../../fpga/tang-nano-20k/sdram

fail() { echo "C-GL-RTL TEST: FAIL — $1"; exit 1; }

command -v iverilog >/dev/null 2>&1 || fail "iverilog not on PATH"

# 1: the emulator's frame (c_gl_test builds and runs the gl_b scene)
sh c_gl_test.sh > /dev/null || fail "emulator GL suite failed"
[ -f gl_b.ppm ] || fail "emulator run left no gl_b.ppm"

# 2: the RTL's frame, through the real pixel stack
( cd $SD && iverilog -g2012 -o tbglp tb_gl_pix.v ../../rtl/p8x_geom.v \
      ../../rtl/mdu_core.v ../../rtl/gfx.v gfx_mem.v gfx_span.v \
      sdram_arb.v p8x_sdram.v sdram_video.v sdram_chip.v \
  && ./tbglp | grep -q "TB-GL-PIX: DONE" ) || fail "tb_gl_pix did not finish"

# 3: every pixel, both implementations
cmp gl_b.ppm $SD/tb_gl_pix.ppm || fail "RTL frame differs from emulator frame"

echo "C-GL-RTL TEST: PASS (RTL and emulator framebuffers byte-identical for the GL scene)"
