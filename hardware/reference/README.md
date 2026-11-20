# Reference material

External datasheets and manuals the P8X design draws on. Not build inputs.
They are third-party, so since 2026-11-20 they are kept out of this public
repository, in the private `../private-resources/p8x/hardware/reference/` beside
it (same file names); this README stays to say what they are.

## Matrox PG-640A

The P8X graphics language (the stage-10 command port at `$FF50` — see
[STAGE10-DESIGN.md](../../fpga/tang-nano-20k/sdram/STAGE10-DESIGN.md)) is
modelled on the Matrox PG-640A: opcode + int16 parameters into a FIFO, card-side
modeling/viewing matrices, projection, hither/yon clipping, pages, and command
lists. The `house` demo scene ([os/house.gl](../../os/house.gl)) is the PG-640A
manual's worked example (chapter 3).

- **`pg640a.pdf`** — the PG-640A programmer's manual. The docs, `emulator/p8xemu.c`
  and the `gl` and `house` man pages name it as `docs/reference/pg640a.pdf`, an
  identical copy kept at that path in `../private-resources/p8x/` as well.
- **`Matrox PG Series/`** — the wider PG-series archive (datasheets / firmware).
