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
| `gen_eagle.py` | All 23 Eagle files (8 boards: `.sch`+`.brd`, plus a placed `-full.brd` per card) | `hardware/<board>/` | `hardware/` |
| `render_traditional_auto.py` | All 7 card schematic PDFs | `hardware/<board>/` | `hardware/` |
| `render_board_pdf.py` | Placement-view PDF for every `.brd` (incl. `-full`) | `hardware/<board>/` | anywhere |
| `gen_bus_pdf.py` | Bus-definition PDF | `hardware/backplane/` | anywhere |
| `render_bp_traditional.py` | Backplane schematic PDF | `hardware/backplane/` | anywhere |

(The programmer's guide PDF is generated separately by
[`microcode/gen_progguide.py`](../microcode/gen_progguide.py).)

### `gen_eagle.py` — the canonical board generator
The single source of truth for the hardware. It defines the device library (pin
maps, packages), the 96-pin DIN 41612 bus map (`busnet()`), and the netlist for
every board, then emits Autodesk Eagle schematic + board files for all eight:
backplane, memory, control, register-bank, ALU, I/O, CF-IDE, and the LED output
card. Every card also gets a placed `-full.brd` companion alongside its
forward-annotated (unplaced) `.brd`. Each board is validated after generation
(pin/pad names checked, no pin wired to two nets).

It writes each board's `.sch`/`.brd` pair into its **own subdirectory** of the
current directory (e.g. `control-card/p8x-control-card.sch`), creating the
subdirectories as needed, so run it from `hardware/`:

```sh
cd hardware && python3 ../generators/gen_eagle.py
```

It also exposes its netlists for other scripts to import (`DEV`, `busnet`,
`ALLPINS`, `CARDS`, `mcn`) — so the renderers below draw from the same data the
boards are built from, and can't drift out of sync.

### `render_traditional_auto.py` — card schematics
Imports `gen_eagle` and algorithmically lays out a traditional-style schematic
(bus spines, junction dots, power-rail glyphs, NC marks) for every card in
`gen_eagle.CARDS` — all seven (control, register-bank, ALU, I/O, CF, memory, and
the LED card). Automatic placement: functional rather than hand-polished, but
covers every card from one run. Each card's PDF lands in its own
`hardware/<board>/` directory. Because it imports `gen_eagle`, running it
regenerates the board files too, so run it from `hardware/`.

### `render_board_pdf.py` — placement views
Imports `gen_eagle` and draws a placement-view PDF for every `.brd` (and
`-full.brd`): board outline, component footprints from the canonical `PKG` pad
geometry, ref designators/values, pin-1 markers, board mounting holes, and cap
polarity marks. It is a pre-route sanity check (placement/spacing/overlap) — not
routed copper; Gerbers come from Fusion after routing.

### `gen_bus_pdf.py` / `render_bp_traditional.py` — backplane docs
Standalone scripts (no `gen_eagle` import) that write straight to
`hardware/backplane/` via absolute paths, so they run from anywhere:
- `gen_bus_pdf.py` — the bus-definition reference PDF (pinout, DOE/DLD tables,
  microcode word layout).
- `render_bp_traditional.py` — the backplane schematic PDF.

## Regenerate everything

```sh
cd hardware
python3 ../generators/gen_eagle.py                # 23 .sch/.brd files (8 boards + 7 -full.brd)
python3 ../generators/render_traditional_auto.py  # all 7 card schematic PDFs
python3 ../generators/render_board_pdf.py         # placement-view PDFs
python3 ../generators/gen_bus_pdf.py              # bus-definition PDF
python3 ../generators/render_bp_traditional.py    # backplane schematic PDF
python3 ../microcode/gen_progguide.py             # programmer's guide PDF
```

Other helper generators (run as needed, not part of the board set):
`gen_bom.py` (bill of materials), `gen_bus_card.py` / `gen_isa_card.py`
(reference cards), and `gen_logisim.py` (Logisim circuit export).
