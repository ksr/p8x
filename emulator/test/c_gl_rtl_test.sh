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
( cd $SD && iverilog -g2012 -I../../rtl -o tbglp tb_gl_pix.v ../../rtl/p8x_geom.v \
      ../../rtl/mdu_core.v ../../rtl/trigtab.v ../../rtl/gfx.v gfx_mem.v \
      gfx_span.v sdram_arb.v p8x_sdram.v sdram_video.v sdram_chip.v \
  && ./tbglp | grep -q "TB-GL-PIX: DONE" ) || fail "tb_gl_pix did not finish"

# 3: every pixel, both implementations
cmp gl_b.ppm $SD/tb_gl_pix.ppm || fail "RTL frame differs from emulator frame"

# 4: the stage-10b matrix scene, the same way (needs gl_m.ppm)
sh c_gl_mat_test.sh > /dev/null || fail "emulator matrix suite failed"
( cd $SD && iverilog -g2012 -I../../rtl -o tbglm tb_gl_mpx.v ../../rtl/p8x_geom.v \
      ../../rtl/mdu_core.v ../../rtl/trigtab.v ../../rtl/gfx.v gfx_mem.v \
      gfx_span.v sdram_arb.v p8x_sdram.v sdram_video.v sdram_chip.v \
  && ./tbglm | grep -q "TB-GL-MPX: DONE" ) || fail "tb_gl_mpx did not finish"
cmp gl_m.ppm $SD/tb_gl_mpx.ppm || fail "RTL matrix frame differs from emulator frame"

# 5: the stage-10c fly-through -- record + CLOOP through the real stack
sh c_gl_list_test.sh > /dev/null || fail "emulator list suite failed"
( cd $SD && iverilog -g2012 -I../../rtl -o tbglx tb_gl_lpx.v ../../rtl/p8x_geom.v \
      ../../rtl/mdu_core.v ../../rtl/trigtab.v ../../rtl/gfx.v gfx_mem.v \
      gfx_span.v sdram_arb.v p8x_sdram.v sdram_video.v sdram_chip.v \
  && ./tbglx | grep -q "TB-GL-LPX: DONE" ) || fail "tb_gl_lpx did not finish"
cmp gl_lc_l.ppm $SD/tb_gl_lpx.ppm || fail "RTL fly-through frame differs from emulator frame"

# 6: the stage-10d ASCII scene -- translator in fabric, frame == hex frame
( cd $SD && iverilog -g2012 -I../../rtl -o tbgla tb_gl_apx.v ../../rtl/p8x_geom.v \
      ../../rtl/mdu_core.v ../../rtl/trigtab.v ../../rtl/gfx.v gfx_mem.v \
      gfx_span.v sdram_arb.v p8x_sdram.v sdram_video.v sdram_chip.v \
  && ./tbgla | grep -q "TB-GL-APX: DONE" ) || fail "tb_gl_apx did not finish"
cmp gl_b.ppm $SD/tb_gl_apx.ppm || fail "RTL ASCII frame differs from the hex frame"

# 7: the stage-10f LINFUN scene -- XOR/complement/OR through the real
#    read-modify-write pixel path (needs gl_lf.ppm)
sh c_gl_lf_test.sh > /dev/null || fail "emulator LINFUN suite failed"
( cd $SD && iverilog -g2012 -I../../rtl -o tbglf tb_gl_fpx.v ../../rtl/p8x_geom.v \
      ../../rtl/mdu_core.v ../../rtl/trigtab.v ../../rtl/gfx.v gfx_mem.v \
      gfx_span.v sdram_arb.v p8x_sdram.v sdram_video.v sdram_chip.v \
  && ./tbglf | grep -q "TB-GL-FPX: DONE" ) || fail "tb_gl_fpx did not finish"
cmp gl_lf.ppm $SD/tb_gl_fpx.ppm || fail "RTL LINFUN frame differs from emulator frame"

# 8: the stage-10g AREA scene -- the fill walker (gm POINT probes, gm LINE
#    paints, SDRAM seed stack) against gl_afill (needs gl_ar.ppm)
sh c_gl_area_test.sh > /dev/null || fail "emulator AREA suite failed"
( cd $SD && iverilog -g2012 -I../../rtl -o tbglar tb_gl_arx.v ../../rtl/p8x_geom.v \
      ../../rtl/mdu_core.v ../../rtl/trigtab.v ../../rtl/gfx.v gfx_mem.v \
      gfx_span.v sdram_arb.v p8x_sdram.v sdram_video.v sdram_chip.v \
  && ./tbglar | grep -q "TB-GL-ARX: DONE" ) || fail "tb_gl_arx did not finish"
cmp gl_ar.ppm $SD/tb_gl_arx.ppm || fail "RTL AREA frame differs from emulator frame"

echo "C-GL-RTL TEST: PASS (RTL and emulator framebuffers byte-identical: 10a scene, 10b matrix, 10c fly-through, 10d ASCII, 10f LINFUN, 10g AREA)"
