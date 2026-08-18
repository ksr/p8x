# SDRAM framebuffer — where this stands (2026-08-18)

## Achieved and on hardware

480x272, 8 bpp, 256 pens from a 4096 palette, framebuffer in the in-package
SDRAM. Verified on the board: fills, circles, GTEXT, POINT read-back, 256 pens.

240x136 and `SCREEN` were retired -- nothing needed them, and dropping them
removed the read-modify-write path entirely (a 2 bpp artefact, never an SDRAM
one).

## The placement blocker: found, and it was not the scanout fix

The branch spent a long time believing the scanout fix (`75e166a`) cost +2,544
LUT4 and pushed the design off the placement cliff. Three controlled builds say
otherwise:

| tree | LUT4 | places? |
|---|---|---|
| `741430a` (pre-counter) | 12,853 (61%) | yes |
| `+ bfcdf27` fetch counter | 14,643 (70%) | no |
| `+ 75e166a` scanout XOR | 15,397 (74%) | no |

So the growth was split across TWO commits, and the design already failed to
place without the scanout fix -- reverting it never would have produced a
bitstream. `lbuf` was never the problem either: it maps via `$__GOWIN_SDP_` in
all three builds and BSRAM stays at 41/46 throughout.

**The real cause was `CF.buf_`, the 512-byte SD sector buffer in `rtl/cf_sd.v`,
which has nothing to do with graphics.** Bucketing the flattened netlist by
instance path put the entire growth in `CF`, and yosys said `using FF mapping
for memory p8x_top.CF.buf_` in every build:

```
                      pre        HEAD
CF.buf_ DFF          4,096       4,096
CF.buf_ LUT          5,671       7,365
CF.buf_ MUX          1,924       4,052
```

4,096 flip-flops plus a 512-entry read mux -- over half the logic in the whole
design -- and the mux half re-optimised to a different size on every unrelated
edit. That is what made "changes with no logical effect" move the LUT count by
thousands.

It was FF-mapped because IDENTIFY wrote the whole buffer in one cycle (a `for`
loop over all 512 entries plus 40 more for the model string). 552 write ports
means no RAM primitive can be used at all. **The same accident as the palette,
in a different file.**

The fix (`rtl/cf_sd.v`): the IDENTIFY fill walks the buffer a byte per clock
with BSY held, every writer muxes onto one write port, and both readers share
one asynchronous read. `idx` is a register, so yosys merges the address flop
into the RAM (`merged address FF to cell`) and the buffer maps via
`$__GOWIN_DP_` with the read timing unchanged.

| | before | after |
|---|---|---|
| LUT4 | 15,397 / 20,736 (74%, failed to place) | **7,226 (34%)** |
| DFF | 5,657 | 1,581 |
| BSRAM | 41 / 46 | 42 / 46 |
| Fmax | — | 51.6 MHz (PASS at 12) |

−4,076 flops and +1 block is the buffer, exactly.

## Then, in order

1. **Load and confirm on hardware.** Nothing since the 23:48 bitstream has been
   on the board. `BOX 0,0,479,271` should have all four edges, and the `I`
   command should still print the model string (the IDENTIFY path was rewritten).
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

## Open question, not area-related

The scanout fix makes yosys emit `emulate_read_first` on `lbuf`: with
`rd_bank = bank ^ (px == H_TOT-1)` the read can hit the bank the fetch is
writing, at the same address, in the same cycle. Simulation is defined there;
a Gowin SDPB on a same-address collision is not. Worth confirming on the panel
before trusting column 0.

## Traps this branch has already paid for

- **A LUT count that improves unexpectedly means broken logic** -- twice on this
  branch. It is not an absolute rule: the drop above is real, and the way to
  tell is that it comes with an arithmetic story (−4,076 DFF and +1 BSRAM is
  one 512-byte buffer) rather than a fold-away.
- **Attribute area before theorising about it.** Bucketing cells by flattened
  instance path found this in minutes; the previous sessions guessed at the
  module that had just changed and were wrong for hours. There is a throwaway
  script for it in the session scratchpad; the logic is ten lines.
- **A parallel write to a whole array costs a RAM.** Palette, then this. Any
  `for` loop that assigns every element of an array in one cycle is the tell.
- **Placement cliff.** Always check `p8x_lcd.fs`'s mtime before believing a
  result. (Much less pressing at 34%.)
- **Two staleness surfaces**: bitstream and SD card. `?SYNTAX ERROR` on a
  graphics statement means the CARD is behind; `?No display` means the BITSTREAM
  is.
- **The co-sim cannot see scanout bugs.** It compares framebuffer contents.
  Anything about mapping to the panel needs `tb_sdram_scanout.v`.
- **A test that samples one pixel to measure a row property** will report the
  wrong bug when that pixel is broken. That cost several wasted iterations.

## State

Branch `sdram-framebuffer`, `main` untouched throughout. `p8x_lcd.fs` is current
and has never been loaded -- the board still holds the 23:48 bitstream (left
edge fixed, one-row shift, no bottom line at 271). Flash holds the original
240x136 build, so a power cycle reverts. The SD card is current (`basic.bin`
10,458).
