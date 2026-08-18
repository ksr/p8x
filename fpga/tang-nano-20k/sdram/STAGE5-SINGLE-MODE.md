# Dropping 240x136: the device becomes single-mode

Decision (user, 2026-08-17): **no software needs the 240x136 4-pen mode**, so it
goes, and `SCREEN` goes with it — with one mode there is nothing to select.

The device becomes: **480x272, 8 bpp, 256 pens from a 4096 palette.**

## Why this is the right simplification, not just a smaller one

- **The read-modify-write disappears entirely.** It was never an SDRAM problem;
  it was a 2 bpp problem, where four pixels share a byte and the other three have
  to be preserved. At 8 bpp a plot is one write. `gfx_mem` loses a whole state
  path.
- **The mode muxing goes** — address arithmetic, bounds, span width, palette
  reload, `IDENT` geometry were all conditional on it.
- **It closes a real correctness gap.** `sdram_video` is hardcoded to 480x272
  8 bpp and has no mode support, so mode 0 would not have displayed correctly on
  the panel. That gap now cannot exist rather than needing to be fixed — and
  fixing it would have added LUTs to a design that has just failed to place.

## The cost, which is mostly NOT the RTL

The graphics tests are all written against a 240x136 screen with 4 pens and a
PPM that is pixel-doubled to the panel. They need reworking: geometry, the
`fb(x,y)` indexing, and the pen-to-colour expectations (the classic four pens
become the 3-3-2 ramp). That is `gfx_test.sh` and all five parts of
`basic_gfx_test.sh`. This is the bulk of the work and it is easy to
underestimate next to the RTL edit.

## Order (emulator first — it is the golden model)

1. **Emulator**: `gpu_*` drops the mode, `gw/gh/gstride/gbpp` become constants
   at 480/272/480/8, `gpu_setmode` goes, `SETMODE $0C` goes, `gpu_reset` loads
   the 3-3-2 palette, the PPM stops doubling.
2. **Tests**: rework the two graphics test scripts for the new geometry and
   palette. Do this immediately after 1, so the golden model is re-pinned before
   anything else moves.
3. **BASIC**: remove `SCREEN`, token `$B0`, its KWTAB entry, dispatch and
   `DOSCRN`; `COLOR`/`PALETTE` keep their widened 0-255 range.
4. **RTL**: `gfx_mem` loses `mode` and the RMW path; `gfx.v` loses `gmode`,
   `SETMODE` and the mode-conditional geometry; `tb_gfx.v` stops asking the
   device which mode it is in.
5. **Generators/docs**: `gen_memmap.py` drops `$0C` from the GCMD list; the man
   page, language guide, READMEs, GLOSSARY and the stage 2 design doc all
   describe one mode.
6. Rebuild and place. The LUT saving from 1-4 is the point: the design failed to
   place at 15,587/20,736 and this removes work rather than adding it.

## Note

`STAGE2-DESIGN.md` describes the two-mode ABI and is now superseded. Leave it as
the record of why modes were considered — the compatibility argument that
motivated them was sound, and it was the *absence of software needing it* that
made them unnecessary, which is a fact about this project rather than about the
design.
