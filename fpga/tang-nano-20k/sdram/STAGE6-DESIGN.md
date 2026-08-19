# Stage 6 — 16 bpp direct colour: RGB565 end to end

> **SHIPPED, 2026-08-18 — designed in the morning, on hardware by evening.**
> Every step below is done: the streaming controller (proven at 8 bpp first,
> as prescribed), the emulator, the re-pinned tests, BASIC's RGB()/16-bit
> COLOR/POINT, the RTL (co-sim green pixel-for-pixel on the first run), and
> the board — full-screen $F800 BOXFILL confirmed on the panel, POINT read
> back through the two-byte GDATA stream, bitstream in flash. 16 bpp cost
> +111 LUT4 over 8 bpp (7,450 total, 35%). The conversion surfaced two latent
> bugs recorded in the commits: the palette lookup had been dead on the board
> since the SDRAM scanout arrived, and the RTL's IDENT cursor never advanced.
> The design text below is kept as written, decisions and rejected
> alternatives included.

## Why, and why not

What 8 bpp palettized cannot do: photographic images. 256 simultaneous colours
chosen from 4096 is a lot of colour for *drawn* graphics, and the palette buys
a real capability — recolouring a pen recolours everything drawn in it, with no
redraw. Direct colour trades that away for true-colour pixels.

So the honest recommendation is: **stay at 8 bpp until something wants photos**
— which on this machine means an image loader exists before this stage does.
The design is recorded now because the analysis was done, and because it
determines what the controller (which IS wanted now) must be able to stream.

## The format: RGB565, stride 1024

**Not 4-4-4.** 12 bits packs into bytes miserably — every other pixel straddles
a boundary, which reintroduces per-pixel read-modify-write, the 2 bpp artefact
stage 5 celebrated deleting. Rounding up to 16 bits, the layout is decided by
the panel: its wires are literally `r[4:0] g[5:0] b[4:0]`. Store exactly that
and scanout needs no palette and no expansion — bits from the line buffer go
straight to the pins. 65,536 colours, which is more than the 4,096 the palette
could reach.

**Stride is 1024 bytes, not 960.** The SDRAM is 2K rows x 256 columns x 4 banks
x 32 bits (see sdram.v), so a row is exactly 1KB. A 960-byte line at a 960
stride drifts across row boundaries — most lines would pay two activations. At
1024:

- every line starts row-aligned, so a line fetch is ONE activation;
- the framebuffer address is `{y, x[9:1], 1'b0}` — **pure wiring, no
  multiplier**. The `y*STRIDE` multiply goes away, and with it the whole class
  of width bugs this project has already paid for twice (`y*60` folding the
  screen onto itself in 13 bits; the explicit-width note in sdram_video.v).

Cost: 64 dead bytes a line, 272KB of framebuffer instead of 261KB, out of 8MB.
Irrelevant.

## The gate: a streaming controller

Everything else in this stage is bookkeeping. The scanout numbers at 27 MHz
(1,680 fabric cycles per 560-pixel line):

| | words/line | vendored (~5-7 cyc/access) | row-open burst |
|---|---|---|---|
| 8 bpp today | 120 | 600-840 | ~140 |
| 16 bpp | 240 | **1,200-1,680 — dead on arrival** | **~270** |

The vendored controller precharges after every access (`BURST_LEN=1`), paying a
full activation per word. A controller that activates once and streams fetches
a 16 bpp line in a few hundred cycles — the depth costs nothing it cannot
afford. (As built, the stream issues every OTHER cycle — ~510-560 cycles a
line — because fully gapless CAS proved electrically marginal on the real
board: see HANDOFF.md's resolved border-edge bug. Still 3x the needed speed.)

**Refresh shapes the design.** 4096 auto-refreshes per 64ms is one every ~420
cycles at 27 MHz, so a ~270-cycle burst cannot be atomic and the drawing engine
must not starve behind it. The fetch runs as **sub-bursts** (16 words, say)
with arbiter slots between them for refresh and the engine. The video port's
interface changes from word-at-a-time rd/ack to *"stream N words from addr"*
with `data_ready` per word; the engine port stays word-at-a-time and simply
gets faster on row hits.

Build and prove this **at 8 bpp first**: `underruns == 0` on hardware, and
measure the engine speedup (its fills pay the same 5-7 cycles per word today).
That result stands on its own even if stage 6 stops there.

## Scanout

Minor surgery on sdram_video.v: the line buffer grows 1,024 -> 1,920 bytes,
which is still one BSRAM (512x32 = 16Kbit, exactly the data capacity of a
block); the read address becomes `{bank, ax[8:1]}` with `ax[0]` selecting the
halfword; the 4:1 byte mux and the palette lookup are deleted. The palette's
block RAM is freed: BSRAM goes 42 -> 41 of 46 net.

## The ABI

The register page `$FF20-$FF2F` is completely allocated — stage 2 called that
a happy surprise, and here it cuts the other way. The escape hatch: `GID0` and
`GID1` (`$FF2D`/`$FF2E`) are READ-only, so their write sides are unused.

- **`GCOLH` = the write side of `$FF2D`.** Same rule as the coordinate pairs:
  writing `GCOL` (the low byte) CLEARS the high byte, so 8-bit-minded software
  cannot be broken by a stale one. The write side of `$FF2E` stays free — the
  last spare corner of the map; spend it reluctantly.
- **`POINT` returns 16 bits through the existing `GDATA` streaming idiom** (it
  already streams the IDENT record): after a POINT, `GDATA` reads low byte then
  high. No new register.
- **IDENT bumps to protocol 2** and gains a depth byte, so software can ask
  the card rather than assume.
- **Pen numbers change meaning, and there is no shim.** `COLOR 224` stops
  being red — 224 in RGB565 is a dim blue-green. A compatibility mapping for
  small values would be modes wearing a false moustache; stage 5 removed
  modes. The precedent is this branch's own: when 4 pens became the 3-3-2
  ramp, the tests and docs were re-pinned and nothing shimmed. Same again.
- **BASIC gains `RGB(r,g,b)`** — r,b 0-31, g 0-63, native 565 — so nobody
  hand-packs bit fields. (Rejected: uniform 0-15 arguments scaled up, for
  continuity with PALETTE; it hides half the gamut to preserve the argument
  ranges of a statement this stage deletes anyway.)
- **A wart, documented rather than fixed:** BASIC integers are signed 16-bit,
  so `PRINT POINT(x,y)` on bright red (`$F800` = 63488) prints -2048.
  Comparisons still work bit for bit.

## What dies, what survives

Dies: the palette RAM, `SETPAL` (`GCMD $06`), BASIC's `PALETTE` (token `$AD`
retired but left unassigned — saved .BAS files are tokenised, the same
reasoning that parked `$B0`), and the recolour-without-redraw trick, which is
the one real capability lost.

Survives untouched: every coordinate register (16-bit already — still paying),
all geometry commands, `GTEXT`, the monitor, the OS, the CF path. Single-pixel
writes stay RMW-free: the bus is 32 bits with byte masks, so one pixel is one
masked write at any depth.

## What this does NOT settle

- **The engine's burst use.** Span fills could stream writes the way scanout
  streams reads (gfx_span feeding sub-bursts) — that is where the controller
  turns into fill rate. Its own design note, once the controller exists.
- **The image loader's implementation** — but its FILE FORMAT is settled, and
  settled the way IDENT settled geometry: the file describes itself, so the
  statement is `IMAGE X,Y,name$` and cannot be lied to. A statement that took
  XSIZE,YSIZE would let a wrong guess SHEAR the image into plausible garbage —
  the worst failure mode, wrong without erroring.

  **P8I format:**

  | bytes | field |
  |---|---|
  | 3 | magic `"P8I"` |
  | 1 | version, `$01` |
  | 2 | width, little-endian |
  | 2 | height, little-endian |
  | 1 | depth, `$10` = RGB565 — ask, don't assume |
  | 1 | reserved (flags someday; a transparency key would live here) |
  | … | width × height RGB565 words, row-major, little-endian, no padding |

  Little-endian words match the GCOL/GCOLH write order exactly, so the
  loader's inner loop is read-byte → GCOL, read-byte → GCOLH, PLOT, advance.
  Off-screen pixels clip for free under the device's discard rule. The host
  side is a small converter (PNG → P8I) next to p8xfs.py. Scaling, if ever
  wanted, is a new OPTIONAL argument — never a mandatory geometry.

## Build order

The discipline, plus the lesson stage 5 paid for (tests re-pinned IMMEDIATELY
after the golden model, not at the end — steps that ran against silently-vacuous
tests looked greener than they were):

1. **Controller** — new RTL + benches, proven at 8 bpp on hardware:
   `underruns == 0`, engine speedup measured. Independently shippable; stop
   here freely.
2. **Emulator** — `gfb` to 16-bit, palette out, PPM expands 565 -> 888 by bit
   replication.
3. **Tests** — re-pinned the same day. Payload colours become 565 primaries.
4. **BASIC** — 16-bit pen via GCOL/GCOLH, `RGB()`, `PALETTE` removed.
5. **RTL** — scanout + engine to 16 bpp; co-sim green.
6. **Hardware, flash, then docs** — and the stage doc for the engine's burst
   fills, if appetite remains.

## Rejected alternatives, for the record

- **4-4-4 packed (12 bpp):** byte-straddling pixels, RMW returns. No.
- **24 bpp (8-8-8):** the panel's data bus is physically 16 wires, so the
  bottom 3-2-3 bits of every pixel would be paid for and then discarded at the
  pins every frame -- and a 24-bit colour does not fit the machine's 16-bit
  integer model, so `POINT` could not return one and BASIC could not hold one.
  Packing is the worst of any depth (every fourth pixel straddles a word);
  padding to 32 bpp doubles bandwidth again and breaks one-activation-per-line
  (480 words > a 256-word row). Dithering, the one honest use of deeper
  source data on a 565 panel, belongs in the image-conversion tool on the
  host, offline, not in the framebuffer. RGB565 is the natural ceiling: the
  panel's native depth, the machine's word size, exactly two pixels per bus
  word, and a line in one row. Everything below it is a choice; everything
  above it fights the panel, the CPU and the memory at once. No.
- **4 bpp / 16 pens:** halves bandwidth the design no longer needs (34% LUT4,
  scanout comfortably in budget) and packs two pixels per byte — RMW again,
  backwards. No.
- **Compatibility shim for 0-255 colour values:** modes by another name. No.
- **16 bpp on the vendored controller:** arithmetic says no before RTL is
  written. The controller is the gate, and it is the part worth having anyway.
