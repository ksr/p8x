# Generators

Python scripts that produce the P8X's CAD artifacts and schematic PDFs from code.

> **Generators are canon.** The Eagle `.sch`/`.brd` files and the schematic PDFs
> are *build artifacts* — never hand-edit them. Change the generator and
> regenerate. See the project [CLAUDE.md](../CLAUDE.md) for the full rule set.

All scripts need `reportlab` for PDF output:

```sh
pip3 install reportlab
```

## Scripts

| Script | Produces | Output dir | Run from |
|--------|----------|------------|----------|
| `gen_eagle.py` | All 14 Eagle files (7 boards × `.sch`+`.brd`) | `hardware/eagle/` | `hardware/eagle/` |
| `render_traditional_auto.py` | All 6 card schematic PDFs | `docs/<card>/` | `hardware/eagle/` |
| `gen_bus_pdf.py` | Bus-definition PDF | `docs/backplane/` | anywhere |
| `render_bp_traditional.py` | Backplane schematic PDF | `docs/backplane/` | anywhere |

(The programmer's guide PDF is generated separately by
[`microcode/gen_progguide.py`](../microcode/gen_progguide.py).)

### `gen_eagle.py` — the canonical board generator
The single source of truth for the hardware. It defines the device library (pin
maps, packages), the 96-pin DIN 41612 bus map (`busnet()`), and the netlist for
every board, then emits Autodesk Eagle schematic + board files for all seven:
backplane, memory, control, register-bank, ALU, I/O, and CF-IDE. Each board is
validated after generation (pin/pad names checked, no pin wired to two nets).

It writes the `.sch`/`.brd` files into the **current directory**, so run it from
`hardware/eagle/`:

```sh
cd hardware/eagle && python3 ../../generators/gen_eagle.py
```

It also exposes its netlists for other scripts to import (`DEV`, `busnet`,
`ALLPINS`, `CARDS`, `mcn`) — so the renderers below draw from the same data the
boards are built from, and can't drift out of sync.

### `render_traditional_auto.py` — card schematics
Imports `gen_eagle` and algorithmically lays out a traditional-style schematic
(bus spines, junction dots, power-rail glyphs, NC marks) for every card in
`gen_eagle.CARDS` — all six (control, register-bank, ALU, I/O, CF, and memory).
Automatic placement: functional rather than hand-polished, but covers every card
from one run. Because it imports `gen_eagle`, running it regenerates the board
files too, so run it from `hardware/eagle/`.

### `gen_bus_pdf.py` / `render_bp_traditional.py` — backplane docs
Standalone scripts (no `gen_eagle` import) that write straight to `docs/backplane/`
via absolute paths, so they run from anywhere:
- `gen_bus_pdf.py` — the bus-definition reference PDF (pinout, DOE/DLD tables,
  microcode word layout).
- `render_bp_traditional.py` — the backplane schematic PDF.

## Regenerate everything

```sh
cd hardware/eagle
python3 ../../generators/gen_eagle.py                # 14 .sch/.brd files
python3 ../../generators/render_traditional_auto.py  # all 6 card schematic PDFs
python3 ../../generators/gen_bus_pdf.py              # bus-definition PDF
python3 ../../generators/render_bp_traditional.py    # backplane schematic PDF
python3 ../../microcode/gen_progguide.py             # programmer's guide PDF
```
