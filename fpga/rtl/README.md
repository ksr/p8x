# fpga/rtl/ — the board-independent core

The files are **not** peers:

| File | What it is |
|------|-----------|
| `p8x_cpu.v` | **the machine.** Shared verbatim by the simulation and the board. |
| `gfx.v` | the **graphics display** — registers and the drawing engine. Since the SDRAM stages the framebuffer is NOT in here: pixels leave through the arbiter port (`e_*`) into the in-package SDRAM, and there is no palette (RGB565 direct colour, stage 6). Shared verbatim. |
| `mdu_core.v` | THE muldiv datapath — the one silicon definition of the signed `(a*b)/c` contract (stage 8a), instantiated by both wrappers below. |
| `p8x_mdu.v` | the CPU-facing **MDU** register wrapper at `$FF30` around `mdu_core`. |
| `p8x_geom.v` | the **geometry engine** (`$FF40`, stage 8b): parameter file, SDRAM edge-list walker, transform + clip + project via its own `mdu_core`, drawing by mastering `gfx.v`'s registers; owns the page-flip state. |
| `video_rgb.v` | the pre-SDRAM 480x272 scanout. **Superseded** on the board by `../tang-nano-20k/sdram/sdram_video.v`; kept for the simulation wrappers. |
| `p8x_soc.v` | a **simulation-only** wrapper. The board does not use this. |

(The old `sc_en` single-port-framebuffer contract died with the BSRAM
framebuffer; the SDRAM stack's sharing story — arbiter, stream port,
priorities — lives in [`../tang-nano-20k/sdram/`](../tang-nano-20k/sdram/)
and its `STAGE*.md` design docs.)

`gfx.v` is a transliteration of the `gpu_*` functions in `emulator/p8xemu.c`, and
the same rule applies to it as to the CPU: the emulator is the golden model, so a
cleverer Bresenham that lights a different pixel is a **bug**. The GL RTL
battery (`emulator/test/c_gl_rtl_test.sh`) byte-compares the frames the two
produce, streaming identical GL bytes through the walker into this engine.

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

(Graphics: `emulator/test/c_gl_rtl_test.sh`, the GL battery.)

Touching `gfx.v` or `video_rgb.v` additionally needs the two board benches, which
cover what the co-sim structurally cannot:

```sh
cd ../tang-nano-20k/sim
iverilog -g2012 -o tb.vvp ../../rtl/video_rgb.v tb_video.v   && vvp tb.vvp
iverilog -g2012 -o tb.vvp ../../rtl/video_rgb.v tb_scanout.v && vvp tb.vvp
```

`tb_scanout.v` checks **which framebuffer pixel reaches which panel pixel**.
`gfx.sh` only checks framebuffer *contents* and `tb_video.v` only frame *shape*,
so the mapping between them went untested — and a shift-width bug that blanked
half of every byte reached hardware through exactly that gap.

**The co-sim's hold pattern is irregular on purpose.** The engine's pixel loop is
six cycles, so the board's regular one-in-three hold has a *fixed* phase
relationship with it: a given collision either always happens or never does, and
a bug depending on one can be invisible in simulation while failing half the time
on hardware. Caveat, recorded honestly: reintroducing a known pending-write bug
did **not** make the frame diff fail, with either pattern, so this coverage is
unproven.

Then rebuild the board — the co-sim cannot catch anything that is purely about
the substrate, such as timing closure, block-RAM inference, or the phase
sequencer:

```sh
../tang-nano-20k/build.sh cpu      # p8x_cpu.v changes
../tang-nano-20k/build.sh lcd      # ... or gfx.v / video_rgb.v: the `cpu`
                                   #     target does NOT compile those two
```

That distinction matters. `gfx.v` and `video_rgb.v` live here, but only the `lcd`
target passes them to yosys, so `build.sh cpu` after editing the graphics
rebuilds a bitstream that does not contain your change — and loads it without
complaint. Substrate bugs that only the board shows have been found this way more
than once: block RAM inferring as true dual port (8 blocks, would not place) and
a register driven from two `always` blocks, neither visible in simulation.

Keep board-specific things **out** of this directory: pins, PLLs, BRAM style, and
peripherals belong in `../tang-nano-20k/`. The point of the split is that the CPU
the co-sim proves is the identical file the board runs.
