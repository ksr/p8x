# Reference material

External datasheets and manuals the P8X design draws on. Not build inputs —
kept here so the source material is versioned alongside the project.

## Matrox PG-640A

The P8X graphics language (the stage-10 command port at `$FF50` — see
[STAGE10-DESIGN.md](../../fpga/tang-nano-20k/sdram/STAGE10-DESIGN.md)) is
modelled on the Matrox PG-640A: opcode + int16 parameters into a FIFO, card-side
modeling/viewing matrices, projection, hither/yon clipping, pages, and command
lists. The `house` demo scene ([os/house.gl](../../os/house.gl)) is the PG-640A
manual's worked example (chapter 3).

- **`pg640a.pdf`** — the PG-640A programmer's manual.
- **`Matrox PG Series/`** — the wider PG-series archive (datasheets / firmware).
