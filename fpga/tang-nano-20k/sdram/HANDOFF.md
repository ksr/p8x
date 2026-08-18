# SDRAM framebuffer — where this stands (2026-08-18)

## Achieved and on hardware

480x272, 8 bpp, 256 pens from a 4096 palette, framebuffer in the in-package
SDRAM. Verified on the board: fills, circles, GTEXT, POINT read-back, 256 pens.

| | old (BSRAM, 240x136, 4 pens) | now |
|---|---|---|
| LUT4 | 13,288 (64%) | 12,853 (61%) at the last good build |
| BSRAM | 44/46 | 41/46 |

Four times the pixels and 64x the colours for FEWER resources. 240x136 and
`SCREEN` were retired -- nothing needed them, and dropping them removed the
read-modify-write path entirely (a 2 bpp artefact, never an SDRAM one).

## THE ONE BLOCKER

The scanout fix (commit `75e166a`) is correct and proven in simulation --
`tb_sdram_scanout.v` passes column AND row mapping, co-sim green -- but the
design then fails to place at 15,397/20,736 LUT4 (74%). Two seeds tried, both
fail, so it is not placement luck.

**It should not cost that.** The fix added a 10-bit counter and one XOR, and
took the design from 12,853 to 15,397. That is +2,544 LUT4 for nothing, and it
is the THIRD inference accident on this branch:

1. a 256-way parallel palette write became ~3072 flops plus a 256:1 mux
2. `rd` left unreset let yosys fold away the whole fetch path (and the small
   LUT count that resulted looked like good news)
3. this one, not yet diagnosed

**Prime suspect:** `wire rd_bank = bank ^ (px == H_TOT-1);` used as part of the
`lbuf` read address in sdram_video.v. A computed read address can defeat Gowin
block-RAM inference and push the line buffer into LUTs. Check the yosys log
either side of `75e166a` for how `p8x_top.VID.lbuf` maps -- it should say
`mapping memory ... via $__GOWIN_SDP_`. If it no longer does, register the bank
select instead of computing it in the address.

## Then, in order

1. Rebuild, load, confirm `BOX 0,0,479,271` has all four edges.
2. Pixel-assertion tests: `gfx_test.sh` and the five parts of
   `basic_gfx_test.sh` still assume 240x136, four named pens and a 2x-doubled
   PPM. Two mechanical changes throughout: PPM indexing loses the doubling
   (`((y*2*W)+x*2)*3` -> `(y*480+x)*3`), and the pen->colour map becomes the
   3-3-2 ramp (pen 1 = `(0,0,85)`, 2 = `(0,0,170)`, 3 = `(0,0,255)`).
   THIS IS THE BULK OF THE REMAINING WORK.
3. Remove `SCREEN` from BASIC (token `$B0`, KWTAB, dispatch, `DOSCRN`) -- it is
   vestigial now and reports an error, since `SETMODE` no longer exists.
4. Docs: `gen_memmap.py` GCMD list, man page, language guide, READMEs, GLOSSARY.
   `STAGE2-DESIGN.md` describes the two-mode ABI and is superseded.

## Traps this branch has already paid for

- **Placement cliff.** This design fails to place from changes with no logical
  effect. Always check `p8x_lcd.fs`'s mtime before believing a result.
- **A LUT count that improves unexpectedly means broken logic**, twice now.
- **Two staleness surfaces**: bitstream and SD card. `?SYNTAX ERROR` on a
  graphics statement means the CARD is behind; `?No display` means the BITSTREAM
  is.
- **The co-sim cannot see scanout bugs.** It compares framebuffer contents.
  Anything about mapping to the panel needs `tb_sdram_scanout.v`.
- **A test that samples one pixel to measure a row property** will report the
  wrong bug when that pixel is broken. That cost several wasted iterations.

## State

Branch `sdram-framebuffer`, `main` untouched throughout. Board holds the 23:48
bitstream: left edge fixed, one-row shift still present, no bottom line at 271.
Flash holds the original 240x136 build, so a power cycle reverts. The SD card is
current (`basic.bin` 10,458).
