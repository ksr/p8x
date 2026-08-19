# Stage 8 — arithmetic to the fabric: the MDU, then the geometry engine

Stage 7 measured the wall: a software muldiv is ~10k cycles even on its
fast path, an edge costs ~130k, and twelve edges run at 13.9 fps. The DSP
multipliers in the GW2AR-18 have been idle the whole time. Stage 8 moves
the arithmetic to them — in two rungs, because a small piece of the
geometry engine can ship alone and pay for the rest:

- **8a (this document, being built): the MDU** — a memory-mapped
  multiply-divide unit at `$FF30`. The CPU pokes a, b, c and reads back
  (a*b)/c. Independently shippable; every program on the machine can use
  it; and its datapath IS the geometry engine's heart, proven CPU-facing
  first — the same discipline that proved the streaming controller at
  8 bpp before 16 bpp asked anything of it.
- **8b (sketch at the end): the engine** — a walker FSM wrapped around
  that same datapath: edge list in SDRAM, matrix registers, one command
  renders the list without the CPU touching a vertex.

## 8a: the contract IS the software contract

The MDU computes exactly what lib_g3d's C muldiv computes — bit for bit,
so it is a drop-in replacement and stage 7's test vectors apply verbatim:

    if |a| == 0 or |b| == 0:   q = 0        (even when c == 0)
    else if |c| == 0:          q = +/-32767 (sign of a xor b)
    else:                      q = trunc(|a|*|b| / |c|), saturated at
                               32767, sign = a xor b xor c

Signs are stripped by 16-bit negate ($8000 negates to $8000 = 32768
unsigned — same wrap the software relies on), the multiply is one DSP
pass, the divide is a 16-round restoring long division: ~20 cycles busy,
which is LESS than the CPU takes to execute the two instructions between
its GO poke and its first result peek. The status register exists anyway:
polling is the house idiom, and depending on instruction timing instead
of a busy flag is how the ACIA/GDATA class of hazard is born.

## 8a: registers ($FF30-$FF3F — previously unclaimed I/O space)

The gfx conventions apply: operands are 16-bit pairs, a LOW write CLEARS
the high byte, the highs sit 9 above their lows.

| addr | write | read |
|---|---|---|
| $FF30 | MDA low | — |
| $FF31 | MDB low | — |
| $FF32 | MDC low | — |
| $FF33 | — | MDQ low (result) |
| $FF34 | MDGO: any value starts the op | — |
| $FF35 | — | MDSTAT: bit 7 = busy |
| $FF36 | — | MDID: 'M' ($4D) — presence probe |
| $FF39 | MDA high | — |
| $FF3A | MDB high | — |
| $FF3B | MDC high | — |
| $FF3C | — | MDQ high |

Everything else in the window reads $FF. MDQ while busy is undefined:
poll MDSTAT first. MDID is the probe — an absent unit floats the bus to
$FF, the same rule as the display's "PG".

The explicit MDGO (rather than triggering on a C-high write) costs one
poke and buys an unambiguous start: c with a zero high byte needs no
dummy write, and re-running the same operands is one poke, not six.

## 8a: who uses it

**lib_g3d.c** probes MDID once (cached in a global) and routes muldiv
through the unit when present, falling back to the stage-7 software path
when not — the same source runs on an old bitstream, the emulator, and
the new silicon, fastest available path chosen at runtime. The emulator
gets the MDU too (golden model first, as always), so its runs exercise
the hardware path; the test forces the software path as well by resetting
the probe cache, keeping both implementations pinned to the reference.

**Measured (emulator, 27 MHz).** The poke-overhead bound was real: a
muldiv through the MDU costs ~4k cycles — ten port operations of
p8cc-generated code — against ~10k software fast-path and ~118k slow.
The cube: 1.94M -> 1.38M cycles/frame, **72 -> 51 ms, 13.9 -> 19.6 fps**.
Per edge ~86k, of which the arithmetic is now a third; the rest is p8cc
call frames, pool indexing and the clip logic, which no peripheral can
absorb — that is 8b's argument in one number. The RTL divider is busy
17 cycles; tb_mdu.v pins it against a behavioral reference with the same
14 directed vectors the emulator test uses plus 2,000 randoms, and
c_g3d_test runs every vector through BOTH the software and MDU paths.

## 8a: build order

1. Emulator MDU (the golden model), c_g3d_test grows MDU vectors — both
   paths diffed against the host reference.
2. lib_g3d muldiv: probe + hardware path + fallback. Cube re-measured.
3. RTL p8x_mdu.v + tb_mdu.v (directed vectors from the test, plus random
   co-check against a behavioral model; busy-timing assertions).
4. p8x_top decode ($FF30-$FF3F), both build flavours (the MDU is
   display-independent). Bitstream, flash, disk rebuild, board.
5. Docs: man basic MEMORY table, READMEs, this file's numbers.

## 8b: the geometry engine (sketch — its own design before any RTL)

The walker around the datapath: edge list uploaded once into SDRAM via a
streaming write port; sin/cos or full 3x3 matrix + translation loaded per
frame into registers; one command — render list at address N, count M —
transforms, near-clips, window-clips and feeds the existing line engine.
SDRAM gains a fourth client (priority: scanout > refresh > geometry >
engine pixels), which is where the design attention must go — this
branch's hardest bugs have all lived in that arbitration. Page-flip
double buffering (deferred from stage 7) rides along: at engine speeds
the in-place erase becomes the dominant artifact. Perspective ~450 edges
at 60 Hz from the ~1k-cycles-per-edge estimate; verification ladder is
emulator engine first, then co-sim, as ever.
