# Generators

Python scripts that produce the P8X's boards, reference PDFs and shared tables from
code.

> **Generators are canon.** Board files (`.kicad_pcb`, and the frozen Eagle
> `.sch`/`.brd`), the schematic and reference PDFs and the ROM images are *build
> artifacts* — never hand-edit them. Change the generator and regenerate. See the
> project [CLAUDE.md](../CLAUDE.md) for the full rule set.

The PDF scripts need `reportlab` (`pip3 install reportlab`). The KiCad scripts run
under KiCad 10's bundled Python (they import `pcbnew`) and route with a Freerouting
jar (`FRJAR`, default `~/freerouting/freerouting.jar`).

## Boards (KiCad)

Every board is a 4-layer KiCad PCB in `hardware/<board>/kicad/` (signals on the
outer layers, GND and +5 V planes inside; plug-in cards 280 × 140 mm). The flow
replaced Eagle on 2026-09-18; see [`../hardware/KICAD-BOARDS.md`](../hardware/KICAD-BOARDS.md)
for the status of each board.

| Script | What it does |
|--------|--------------|
| `gen_eagle.py` | **The netlists.** Device library (pin maps, packages), the 96-pin DIN 41612 bus map (`busnet()`), and every card's netlist (`CARDS`), imported by everything below. Its own Eagle output is frozen at rev E (see below). |
| `gen_kicad.py <card>` | Generic board builder: turns a `CARDS` netlist into a placed KiCad board — footprints, a bypass cap above each IC, the labelled LED bank, planes, outline |
| `hardware/<card>/kicad/gen_*.py` | Bespoke placement for the memory (`gen_mem.py`, which also applies the rev F 6 KB ROM decode), I/O (`gen_io.py`), CF (`gen_cf.py`) and PS/2 (`gen_ps2.py`) cards |
| `gen_backplane.py` | The backplane board (8 DIN 41612 sockets, power entry, bulk + per-slot caps, wired-OR pull-ups) |
| `kicad_tools.py` | DSN export, routing import, the heal steps after Freerouting, Gerbers and renders |
| `build_kicad_card.sh <card>` | The generic pipeline: generate → export DSN → Freerouting → import + stitch → Gerbers/renders → readiness check |
| `build.sh <card>` (or `all`) | One command per board: dispatches to the bespoke `kicad/build.sh` or to `build_kicad_card.sh` |
| `check_card.sh <card>` (or `all`) | The manufacture-readiness check: ERC, gate-level simulation (where a testbench exists), DRC, mounting-hole keepout, fab minimums → PASS/FAIL |
| `gen_erc.py` | The netlist electrical-rules check `check_card.sh` runs |
| `gen_bom.py` | The bill of materials → `hardware/p8x-bom.csv` |

```sh
sh generators/build.sh memory-card        # one board, build + verify
sh generators/build.sh all                # every board
sh generators/check_card.sh all           # the readiness check alone
```

### `gen_eagle.py` and the frozen Eagle boards

`gen_eagle.py` is the single source of truth for the hardware netlists. It also
still contains the Eagle emitter that drew the first board generation (Autodesk
Eagle/Fusion schematic + board pairs, forward-annotated but unplaced). Those files
were moved to each board's `eagle-deprecated/` directory on 2026-09-18 and are
frozen at rev E — the Eagle memory card keeps the old 8 KB ROM decode; the KiCad
rev F board has the 6 KB one. Running `gen_eagle.py` directly still writes the
Eagle pairs into per-board subdirectories of the current directory, so do not run
it from `hardware/` unless the Eagle files are what you want; the KiCad scripts
import it and do not need that step.

`render_traditional_auto.py` (schematic PDFs drawn from `CARDS`) and
`render_board_pdf.py` (placement views of the Eagle `.brd`) belong to the Eagle
flow; their PDFs are in the `eagle-deprecated/` directories with the boards. The
KiCad flow makes its own placement PDF per board.

## Reference documents and tables

| Script | Produces | Output |
|--------|----------|--------|
| `gen_memmap.py` | **The memory map** — every data address: `memmap.inc` (assembler), `memmap.h` (C), `memmap.py`, and the command libraries `lib_mem.c`/`.inc` | `generators/`, `os/` |
| `gen_memmap_pdf.py` | The printable memory map | `docs/p8x-memory-map.pdf` |
| `gen_isa_card.py` | The instruction-set quick reference (Markdown + PDF), from `genucode.py` | `docs/p8x-isa-card.{md,pdf}` |
| `gen_bus_pdf.py` | Bus-definition PDF (pinout, DOE/DLD tables, microcode word layout) | `hardware/backplane/` |
| `gen_bus_card.py` | The bus reference card | `hardware/backplane/p8x-bus-card.pdf` |
| `render_bp_traditional.py` | Backplane schematic PDF (Eagle-era; the current copy is in `hardware/backplane/eagle-deprecated/`) | `hardware/backplane/` |
| `gen_p8xopc.py` | Opcode-table `.asm` for the native assembler (`OPCTAB`), from `genucode.OPC` | stdout / arg path |
| `gen_p8xdis.py` | The disassembler's opcode table, from `genucode.OPC` | `os/commands/lib_distab.c` (+ `.inc`) |
| `gen_glkw.py`, `gen_font.py`, `gen_chargen.py`, `gen_trig.py` | Graphics tables: the GL keyword table (`glkwtab.*`, `glvtab.inc`), the stroke font (`os/font.gl`), the text-overlay character generator (`chargen.h`/`.hex`), the trig tables (`trigtab.h`) | `generators/`, `basic/`, `os/` |
| `gen_logisim.py` | Logisim circuit export (proof of concept, memory card) | `hardware/memory-card/` |

`gen_p8xopc.py out.asm` emits the `(mnemonic, shape) → opcode` table that
[`apps/p8xasm.asm`](../apps/p8xasm.asm) (the on-target assembler) is built with;
the build concatenates it after the assembler logic. Sourcing it from
`genucode.OPC` keeps the native assembler's encodings locked to the microcode.

The programmer's guide (Markdown + PDF) is generated separately by
[`microcode/gen_progguide.py`](../microcode/gen_progguide.py).
