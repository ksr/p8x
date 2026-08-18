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

1. [x] **Load and confirm on hardware.** Done, from FLASH, after a power cycle:
   `I` prints the model string through the rewritten IDENTIFY against a real
   card; `BOX 0,0,479,271` reads back pen 224 at all four extreme edges, with
   the pixel one inside each edge background (outline exactly one pixel);
   `BOX ...,FILL` interior reads back and stops at its edge.
2. [x] Pixel-assertion tests -- reworked, and it was more than mechanical: two
   payload cases had quietly stopped testing anything (a "full-screen" box at
   (239,135), a clipping line to x=255 that is now on-screen), and the pens
   moved to the 3-3-2 primaries $E0/$1C/$03 so all eight pen bits are
   exercised. All suites and the co-sim pass.
3. [x] `SCREEN` removed from BASIC; `$B0` left deliberately unassigned (saved
   .BAS files are tokenised and old programs on disk still contain it).
4. [x] Docs: man page, language guide, READMEs, GLOSSARY, `gen_memmap.py`, and
   `STAGE2-DESIGN.md` now opens with a HISTORICAL header recording what of that
   design survived (16-bit coordinates, 0-255 pens, the 12-bit palette, 80-col
   GTEXT) and what did not (the modes themselves).

Nothing remains open in this handoff.

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

Branch `sdram-framebuffer`, `main` untouched throughout. **STAGE 6 SHIPPED
(2026-08-18, same day it was designed):** the board is RGB565 end to end. The
7,450-LUT4 bitstream is IN FLASH; the SD card carries the RGB() BASIC (cloned
over serial with imgsend.py, all 3,260 sectors acked). Verified on hardware
from BASIC itself: COLOR RGB(31,0,0) box edges read back -2048 through
POINT's two-byte GDATA stream, the green fill reads 2016, RGB() packs
correctly on-target. The panel showed the full-screen $F800 fill. The
streaming controller underneath was proven at 8 bpp first (0 underruns,
asserted in a bench that runs the real controller against a protocol-checking
chip model validated against the vendored RTL).

One formality open: the flash content is byte-identical to the verified SRAM
image, but a power-cycle boot from THIS flash has not itself been observed.

Two operational notes for whoever drives the board over serial next:

- **Opening the serial port resets the machine.** Any scripted interaction must
  do everything in ONE session; a second open finds the monitor again, and its
  `?` replies to BASIC lines look confusingly like an interpreter fault.
- BASIC spells the filled box `BOX x0,y0,x1,y1,FILL`; `BOXFILL` is the DEVICE
  command name and is a syntax error in BASIC.
