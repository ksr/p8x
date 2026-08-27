# docs/

System-wide documentation. (Per-card guides live with their board under
[`../hardware/<card>/`](../hardware/); language and tool guides live next to
their source in `../basic/`, `../os/`, etc.)

| Document | Description |
|----------|-------------|
| [p8x-system-design.md](p8x-system-design.md) | System and card-by-card architecture reference; §3.2 has the as-built control-word layout. |
| [p8x-card-standards.md](p8x-card-standards.md) | Design rules every plug-in card must follow (form factor, connector, decoupling, etc.). |
| [p8x-monitor.md](p8x-monitor.md) | ROM monitor command reference and memory map. |
| [p8x-graphics-theory.md](p8x-graphics-theory.md) | Graphics engine theory of operation — the machines inside the card, from bus window to panel. |
| [p8x-graphics-guide.md](p8x-graphics-guide.md) | Graphics programmer's guide — drawing from the shell, BASIC, C and assembly. |
| [p8x-programmers-guide.md](p8x-programmers-guide.md) | CPU programmer's guide (GENERATED — regenerate via `microcode/gen_progguide.py`, never edit; PDF twin beside it). |
| [p8x-isa-card.md](p8x-isa-card.md) | Instruction-set quick reference (GENERATED — `generators/gen_isa_card.py`; PDF twin beside it). |
| [mount-drives-design.md](mount-drives-design.md) | Design record for the Unix-style `/D1` mount of the second CF — shipped; kept for the reasoning. |
| [p8x-programmers-guide.pdf](p8x-programmers-guide.pdf) | Generated instruction-set reference (built by `../microcode/gen_progguide.py`). |

The **FPGA** track has its own documentation tree rather than living here:
[`../fpga/README.md`](../fpga/README.md) (milestones + layout),
[`../fpga/docs/architecture.md`](../fpga/docs/architecture.md) (module hierarchy,
memory/peripheral map, co-sim spec), [`../fpga/sim/README.md`](../fpga/sim/README.md)
(how the cycle-for-cycle diff against the emulator works) and
[`../fpga/tang-nano-20k/README.md`](../fpga/tang-nano-20k/README.md) (board build,
pinout, flashing).

The PDF is a generated artifact — regenerate it rather than editing:

```sh
python3 ../microcode/gen_progguide.py      # writes the guide PDF here
```

New to the abbreviations and signal names used throughout these docs? See the
root [GLOSSARY.md](../GLOSSARY.md).
