# Stage 4 — the drawing engine against SDRAM

## A correction to the premise

The earlier plan said a per-pixel read-modify-write against SDRAM would pay a
row activation each time and make fill rate *worse* than today. That is wrong
for mode 1, and the mistake matters because it was the main reason this stage
looked hard.

**At 8 bpp a pixel is a whole byte, so there is no read.** A plot is one SDRAM
write. The read-modify-write is an artefact of mode 0's 2 bpp, where four pixels
share a byte and you cannot touch one without preserving the other three.

## The free win in the controller

The controller already drives `dq_out <= {din,din,din,din}` — the byte
replicated across all four lanes — and then uses `SDRAM_DQM` to let exactly one
through. **Clearing DQM instead writes all four**, so a run of four
same-coloured pixels costs one write rather than four. That is a same-colour
span, which is precisely what `CLS`, `BOXFILL` and the span-filled circle and
ellipse are made of.

## The numbers

| | pixels | cycles | at 27 MHz |
|---|---|---|---|
| mode 0 full fill, today, BSRAM | 32,640 | 244,800 | **9.1 ms** |
| mode 1 full fill, byte writes | 130,560 | 783,360 | 29.0 ms |
| mode 1 full fill, **word writes** | 130,560 | 195,840 | **7.3 ms** |

Mode 1 fills come out *faster in absolute time than mode 0 is today*, at four
times the pixels. Fill rate is not the problem this stage has to solve.

## The decision: where does mode 0 live?

Two coherent designs.

**A — mode 0 stays in block RAM, mode 1 in SDRAM.** No change to a proven path.
Costs 4 blocks for the mode-0 framebuffer plus 1 for the scanout line buffer =
**5 blocks against today's 4**, and adds the controller's ~600 LUTs, on a design
that is already at 44/46 and has failed to place from a change with no logical
effect at all. Also means two memory paths in the engine, two scanout sources,
and a mode switch between them.

**B — everything in SDRAM, block RAM keeps only the line buffer.** One memory
path, one scanout source. **1 block instead of 4, so three handed back** —
44/46 becomes 41/46, which buys back the placement headroom this design has been
short of all along.

The cost of B is that mode 0's per-pixel work becomes a real read-modify-write
over SDRAM, ~12 cycles a pixel against 7.5 today. In the worst realistic case
that is a screen-width line going from 0.07 ms to 0.11 ms. Fills are unaffected
because a mode-0 span is also a run of identical bytes (`(pen)*0x55`) and uses
the same word-write path.

**Recommended: B.** The slowdown is imperceptible and confined to outline
drawing; the three freed blocks are the scarcest resource in the design; and one
memory path is markedly less RTL than two. Critically, **B changes no pixels** —
the co-sim compares framebuffer *contents*, not timing, so mode 0 stays
bit-identical and every existing test still applies unchanged.

## What stays hard

Not fill rate, but **arbitration**. Three masters want the SDRAM: the scanout
(which cannot stall), refresh (which cannot be deferred indefinitely), and the
engine (which can wait). Priority is therefore scanout > refresh > engine, and
the engine must be interruptible at a pixel boundary rather than mid-operation —
the same shape as the bug the stage 0 testbench caught, where refresh preempted
a read that had been issued and not yet answered.

The scanout has ~50% of the line budget spare, so the engine gets roughly half
the bus. That is the number to verify with the underrun counter once both are
running, and it is the reason that counter exists.

## Order

1. Extend the controller with a word-write mode (DQM all-low). Small, and it is
   what makes fills fast.
2. Arbiter: scanout > refresh > engine, engine interruptible between pixels.
3. Engine: replace the BSRAM port with the arbiter port, keep the algorithms
   untouched — they must stay step-for-step with the emulator's `gpu_*`.
4. Span detection for `CLS`, `BOXFILL` and the filled circle/ellipse spans, so
   they take the word-write path.
5. Co-sim in both modes. That is the acceptance test.
