# Stage 2 — SCREEN modes and 8 bpp: the ABI

Stages 0 and 1 answered the hardware questions. This is the design the software
has to live with, written down before any of it is built, because it is the part
that cannot be changed later without breaking programs.

## The happy surprise: the ABI barely moves

The graphics register page `$FF20–$FF2F` is **completely allocated** — all 16
bytes. That sounds like a problem and is not, because two decisions taken much
earlier absorb almost all of this change:

- **Coordinates are already 16-bit** low/high pairs (`GX0`/`GX0H`…). They were
  built that way *specifically* because "this panel at native 480x272 needs 9
  bits of X (the SDRAM path)". That foresight is now cashed in: not one
  coordinate register changes.
- **`GCMD` is a write-to-execute command port**, so new capability costs a
  command code, not a register. `$01`–`$0B` and `$F0`–`$F2` are taken; `$0C` is
  free.

## The change

### `GCMD $0C` — SETMODE, mode number in `GPARM`

| mode | geometry | depth | pens | notes |
|---|---|---|---|---|
| **0** | 240×136 | 2 bpp | 4 | today's behaviour, pixel-doubled to the panel |
| **1** | 480×272 | 8 bpp | 256 | native panel resolution, framebuffer in SDRAM |

**Mode 0 is the reset default**, and that is the whole compatibility story: an
existing program that never issues SETMODE behaves exactly as it does now. A
program that draws `BOX 0,0,239,135` still fills the screen. Nothing that exists
today has to know this feature happened.

### `GCOL` widens

Already a byte register, documented as "pen 0-3 (the device masks to 2 bits)".
In mode 1 it carries 0–255. No layout change, and mode 0 keeps masking to 2 bits
so old software cannot accidentally address a pen that mode 0 does not have.

### Palette, not direct colour

Mode 1 uses a **256-entry palette of 12-bit RGB**, not a fixed 3-3-2 mapping.
Stage 1 used 3-3-2 because it needed no palette memory and the point was to
prove the data path; that is the wrong choice for the real thing:

- 256 colours chosen from 4096 beats 256 fixed ones, for 384 bytes.
- `SETPAL` and BASIC's `PALETTE` already exist and simply widen their pen
  argument from 0–3 to 0–255. A direct-colour mode would make `PALETTE`
  meaningless in mode 1, which is a worse outcome than the memory it saves.

### BASIC: `SCREEN n`

A new statement, token `$B0`. `SCREEN 0` and `SCREEN 1` map onto SETMODE.
`COLOR` and `PALETTE` widen their pen range in mode 1; everything else —
`LINE`, `BOX`, `CIRCLE`, `PLOT`, `POINT`, `GTEXT` — is unchanged, because they
all speak coordinates and a pen, and both already generalise.

`GTEXT` gets more useful for free: at 480 wide its 6-pixel cell gives **80
columns** instead of 40.

## What this does NOT settle

The **drawing engine** is the real work and is deliberately not specified here.
Today a pixel is a five-cycle read-modify-write against single-cycle block RAM.
Against SDRAM that shape is wrong: a per-pixel RMW pays a row activation each
time, and fill rate would get *worse* than today despite the extra bandwidth. It
wants a write buffer and word-at-a-time fills, and it is the strongest argument
for replacing the vendored controller with one that holds a row open across a
span. That is its own stage.

## Build order

The project's discipline decides this: **the emulator is the golden model**, so
it changes first and the RTL is made to match it, not the other way round.

1. **Emulator** — `gpu_*` gains a mode, the 8 bpp path and a 256-entry palette;
   `-g`/`-G` render both modes.
2. **Tests** — `gfx_test.sh` and `basic_gfx_test.sh` gain mode-1 cases, and a
   mode-0 case that proves old behaviour is bit-identical.
3. **BASIC** — `SCREEN`, and the widened `COLOR`/`PALETTE`.
4. **RTL** — the engine against SDRAM, plus `sdram_video` for scanout.
5. **Co-sim** — `gfx.sh` proves RTL and emulator agree pixel-for-pixel in *both*
   modes. That is the acceptance test for the whole branch.
