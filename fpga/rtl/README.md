# fpga/rtl/ — the board-independent core

Four files, and they are **not** peers:

| File | What it is |
|------|-----------|
| `p8x_cpu.v` | **the machine.** Shared verbatim by the simulation and the board. |
| `gfx.v` | the **graphics display** — registers, drawing engine, framebuffer, palette. Also shared verbatim. |
| `video_rgb.v` | 480x272 panel timing + scanout. Board-only in practice, but board-independent. |
| `p8x_soc.v` | a **simulation-only** wrapper. The board does not use this. |

`gfx.v` is a transliteration of the `gpu_*` functions in `emulator/p8xemu.c`, and
the same rule applies to it as to the CPU: the emulator is the golden model, so a
cleverer Bresenham that lights a different pixel is a **bug**. `../sim/gfx.sh`
byte-compares the frames the two produce.

Unlike the CPU, the graphics device **cannot be cycle-diffed**. The emulator draws
instantaneously and never raises BUSY; the RTL takes thousands of clocks and does.
A program that polls `GSTAT` therefore reads different values on the two by
design, so their CPU traces legitimately diverge. The framebuffer is what must
agree, and nothing else about the engine's timing is visible to software.

`p8x_cpu.v` is a direct transliteration of the emulator's microcycle loop — the
74181 model, the two-stage shifter, sign-bit V, the condition mux off the previous
word's `FCOND`, `DOE`/`DLD`/`PSEL` as muxes rather than tri-state. It is
deliberately **flat**: the TTL cards are regions of one module, not sub-modules,
so its state maps one-to-one onto the emulator's for the cycle-by-cycle diff. See
[`../docs/architecture.md`](../docs/architecture.md) for that mapping.

`p8x_soc.v` gives the CPU async-read arrays and modelled I/O, so one microcycle is
one clock. **The board cannot do that** — block RAM is synchronous and a microcycle
needs two *dependent* reads (the microcode word first, because its `PSEL` field
picks the pointer that drives `mem_addr`, and only then the memory byte). The board
top is [`../tang-nano-20k/rtl/p8x_top.v`](../tang-nano-20k/rtl/p8x_top.v), which
runs three fabric phases per microcycle and gates the core with `cen`.

So: **`cen` must be tied high** by any wrapper that presents single-cycle memory.
`p8x_soc.v` does exactly that.

## Changing anything here

`p8x_cpu.v` is what the co-sim verifies, and it is shared, so an edit reaches both
the simulator and the board. Re-run all three co-sims — they are the regression
test, and a divergence names the exact microcycle:

```sh
../sim/run.sh 20000                        # monitor boot
../sim/run.sh 60000 isa_test.asm           # all 88 opcodes
../sim/run.sh 200000 "" console_in.txt     # driven monitor + console diff
```

Then rebuild the board (`../tang-nano-20k/build.sh cpu`) — the co-sim cannot catch
anything that is purely about the substrate, such as timing closure, block-RAM
inference, or the phase sequencer.

Keep board-specific things **out** of this directory: pins, PLLs, BRAM style, and
peripherals belong in `../tang-nano-20k/`. The point of the split is that the CPU
the co-sim proves is the identical file the board runs.
