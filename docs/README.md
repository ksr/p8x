# docs/

System-wide documentation. (Per-card guides live with their board under
[`../hardware/<card>/`](../hardware/); language and tool guides live next to
their source in `../basic/`, `../os/`, etc.)

| Document | Description |
|----------|-------------|
| [p8x-status.md](p8x-status.md) | Where P8X stands (November 2026): what runs today, the TTL card set's state, what is next. The detail is in [`../BACKLOG.md`](../BACKLOG.md). |
| [p8x-system-design.md](p8x-system-design.md) | System and card-by-card architecture reference; §3.2 has the as-built control-word layout. |
| [p8x-card-standards.md](p8x-card-standards.md) | Design rules every plug-in card must follow (form factor, connector, decoupling, etc.). |
| [p8x-monitor.md](p8x-monitor.md) | ROM monitor command reference and memory map. |
| [p8x-graphics-theory.md](p8x-graphics-theory.md) | Graphics engine theory of operation — the machines inside the card, from bus window to panel. |
| [p8x-graphics-guide.md](p8x-graphics-guide.md) | Graphics programmer's guide — drawing from the shell, BASIC, C and assembly. |
| [p8x-programmers-guide.md](p8x-programmers-guide.md) | CPU programmer's guide (GENERATED — regenerate via `microcode/gen_progguide.py`, never edit; PDF twin beside it). |
| [p8x-isa-card.md](p8x-isa-card.md) | Instruction-set quick reference (GENERATED — `generators/gen_isa_card.py`; PDF twin beside it). |
| [mount-drives-design.md](mount-drives-design.md) | Design record for the Unix-style `/D1` mount of the second CF — shipped; kept for the reasoning. |
| [p8x-two-mode-design.md](p8x-two-mode-design.md) | Two-mode operation: the same OS runs headless-serial OR as a GL graphics desktop (Finder + full-screen apps), selected by a graphics-present flag. Design + phase log (P1–P5 shipped in the emulator). |
| [p8x-isa-c-extensions.md](p8x-isa-c-extensions.md) | **Design note (not shipped on the disk); Tier A implemented on the emulator 2026-09-11:** ISA additions to shrink `p8cc` output — Tier A pure-microcode ops (`(Pn+d8)` displacement addressing, 16-bit memory-word `LDW`/`STW`/`ADDW`/`SUBW`/`CMPW`/`INCW`/`DECW`, `LDPn #imm16`, `ADDP3`/`SUBP3`), Tier B one hardware register (frame pointer P4), Tier C a 16-bit accumulator — with opcodes, microcode step sketches, projected savings, ripple and open questions. Compiler-only wins (−15.1%) landed first; see BACKLOG. |
| [p8x-wm-design.md](p8x-wm-design.md) | Design record for the resident window manager: windows that outlive the app, keyboard and mouse-drag input, per-window state across launches. |
| [p8x-programmers-guide.pdf](p8x-programmers-guide.pdf) | Generated instruction-set reference (built by `../microcode/gen_progguide.py`). |
| [p8x-isa-card.pdf](p8x-isa-card.pdf) | Printable instruction-set quick reference (GENERATED — `generators/gen_isa_card.py`). |
| [p8x-memory-map.pdf](p8x-memory-map.pdf) | Printable memory map (GENERATED — `generators/gen_memmap_pdf.py`). |
| [reference/README.md](reference/README.md) | Where the Matrox PG-640A manual (`reference/pg640a.pdf`, named by the graphics docs) is kept: out of this public repository since 2026-11-20. |

The **FPGA** track has its own documentation tree rather than living here:
[`../fpga/README.md`](../fpga/README.md) (milestones + layout),
[`../fpga/docs/architecture.md`](../fpga/docs/architecture.md) (module hierarchy,
memory/peripheral map, co-sim spec), [`../fpga/sim/README.md`](../fpga/sim/README.md)
(how the cycle-for-cycle diff against the emulator works) and
[`../fpga/tang-nano-20k/README.md`](../fpga/tang-nano-20k/README.md) (board build,
pinout, flashing).

The three PDFs are generated artifacts — regenerate them rather than editing
(from the repository root):

```sh
python3 microcode/gen_progguide.py         # the programmer's guide (.md + .pdf)
python3 generators/gen_isa_card.py         # the instruction-set card (.md + .pdf)
python3 generators/gen_memmap_pdf.py       # the memory map PDF
```

New to the abbreviations and signal names used throughout these docs? See the
root [GLOSSARY.md](../GLOSSARY.md).
