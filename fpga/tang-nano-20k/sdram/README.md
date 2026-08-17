# SDRAM — Stage 0: does the in-package SDRAM work under the open flow?

The GW2AR-18's `R` is 64 Mbit of SDRAM in the same package, unused since the
microcode-compaction trick made it unnecessary for the 64K memory map. The
graphics framebuffer is the first thing that genuinely cannot fit in block RAM:
6 spare BSRAM blocks are 12288 bytes and the panel's own 480x272 needs 16320 at
even 1 bpp, so the current 240x136 2 bpp framebuffer is pixel-doubled to fill the
screen. Full resolution is an SDRAM project. This directory is the experiment.

## Finding 1: the SDRAM pads need NO `.cst` entries (verified 2026-08-17)

They are bonded inside the package, and **apicula/nextpnr special-cases the
magic port names**, exactly as Gowin EDA does. Verified by controlled experiment
rather than by reading about it:

| top-level port | result |
|---|---|
| `O_sdram_addr[10:0]` | placed, no constraint given |
| `O_notmagic_addr[10:0]` (same net, renamed) | `ERROR: Unconstrained IO` |

That control matters: nextpnr treats unconstrained IO as a hard error (it threw
exactly that for a mis-typed `led[4]`), so "placed without a constraint" can only
mean the name is recognised. A trivial design with all 55 SDRAM signals placed
clean at 30 IOBs for the control/address lines plus 32 `IOBUF`s for the data bus.

The magic names, which must appear verbatim on the top-level module:

```verilog
output        O_sdram_clk, O_sdram_cke, O_sdram_cs_n,
output        O_sdram_cas_n, O_sdram_ras_n, O_sdram_wen_n,
inout  [31:0] IO_sdram_dq,      // 32 bits wide, not 16
output [10:0] O_sdram_addr,
output [1:0]  O_sdram_ba,
output [3:0]  O_sdram_dqm
```

## What this does and does not prove

It proves the toolchain will *wire up* the SDRAM. It says nothing yet about
whether we can meet its timing, which is the actual risk: SDRAM has refresh, row
activation and CAS latency, so unlike block RAM it cannot promise a byte on
demand — and a video scanout cannot stall. That is what the rest of Stage 0 and
Stage 1 are for.

## Reference

`nand2mario/sdram-tang-nano-20k` (Apache 2.0) is a known-good 32-bit controller
for this exact board: 64.8 MHz, 4-cycle read latency, byte-addressable interface.
It targets Gowin EDA and instantiates the `Gowin_rPLL` IP wrapper, so an open-flow
port would instantiate the `rPLL` primitive directly.
