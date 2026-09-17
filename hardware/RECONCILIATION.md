# Board ↔ emulator ↔ FPGA reconciliation (2026-09-17)

A build-readiness pass over the `hardware/` boards against the current emulator
(the golden model) and the FPGA CPU, ahead of ordering and building the real
machine. **Docs + bus-definitions only** — no CAD was regenerated (the `.sch` is
the source of truth and `.brd` placement is the user's Fusion work).

## TL;DR

The six built CPU cards (control, register bank, ALU, memory, I/O, CF-IDE) plus
the LED display and backplane are **current** — the ISA has grown a lot since
they were laid out, but that growth is **entirely in the microcode ROM**, which
is data burned into the control card's existing EPROMs, not a change to any
card's logic. What is missing is **I/O expansion cards** for subsystems that so
far live only in the emulator and/or on the FPGA graphics card.

## What is current (no board change needed)

- **Control / microcode card.** The Tier A ISA growth (143 opcodes now, up from
  88) is microcode: `microcode/genucode.py` → `u0-u3.bin` burned to the card's
  microcode EPROMs. The microcode-ROM address map (`IR | step<<8 | cond<<12`) and
  the card's sequencer are unchanged; a wider instruction set is just a fuller
  ROM. Reburn the EPROMs from the current `genucode.py`; no rewire.
- **Register bank, ALU, memory cards.** No architectural change. The rev-E memory
  map (6K ROM `$0000-$17FF`, RAM from `$1800`) is a decode/strapping detail the
  memory card already reflects; the bus-definition memory map is now current
  (`p8x-bus-definition.md` §5).
- **I/O card.** `$FF00` switches / `$FF02` LEDs / `$FF04-05` ACIA unchanged. These
  ports are now named in the single-source memory map (`SWITCHES`, `LEDS`).
- **CF-IDE card.** `$FF10-$FF17`, unchanged.
- **Backplane, LED display.** Unchanged.

## Gaps — subsystems with no TTL board yet

| Subsystem | Window | Lives now in | Action to build |
|-----------|--------|--------------|-----------------|
| **PS/2 keyboard + mouse** | `$FF58-$FF5F` | emulator model + `lib_ps2`; FPGA-fabric option | **Designed** — [ps2-card/](ps2-card/README.md) (74HC164/161/574 + 7407 per port, 5 V, no level shift). Next: gen the CAD, DRC, order. |
| **MDU (multiply/divide)** | `$FF30-$FF3F` | emulator model + FPGA `mdu_core.v` | No TTL card yet. Only needed for the TTL build if 3D/`lib_g3d` math must run there at speed; otherwise the software muldiv still works. |
| **GL graphics-language port** | `$FF50-$FF54` | emulator model + the Tang Nano 20K graphics card | The **FPGA card *is*** the graphics engine (~19 k LUT4). A discrete-TTL GL walker is out of scope — the graphics card is the intended realisation. |
| **IRQ controller** | (`$FF06` device-IRQ model) | emulator model | No card yet. The emulator raises a maskable IRQ on a `$FF06` write to exercise the interrupt path; on hardware the IRQ must come from a controller card. This is the standing near-term TTL item (see `CLAUDE.md` roadmap, `BACKLOG.md`). |

## Second serial port

The 2nd ACIA (`$FF08-$FF09`, the Kermit / serial-terminal port) is modelled and
now named in the map. On hardware it is a second 6850 — either a small daughter
addition to the I/O card or a second I/O card strapped to `$FF08`. Low priority.

## Known deltas that are NOT bugs

- **C flag is active-low** (raw 74181 Cn+4); the emulator must not "fix" it. A
  rev-B *verify* item, not a board error (`CLAUDE.md` hard rule 5).
- **V flag hardwired 0** in rev A (matches the ALU card) — hard rule 6.
- **FPGA runs at 9 MHz** (three fabric phases per microcycle) vs a ~50 MHz Fmax
  ceiling; a clock-up milestone, not a board issue.

## Suggested build order

1. **Backplane first** (everything plugs into it; a fab error there blocks all).
2. The six core cards as already laid out; **reburn the microcode EPROMs** from
   the current `genucode.py` before bring-up.
3. **PS/2 card** once its CAD is generated and DRC-clean — it is the one new card
   with a finished design and a working emulator/`lib_ps2` counterpart to test
   against.
4. **IRQ controller card** — design it next (the last core-machine gap); until
   then interrupt-driven I/O stays polled (`$FF06`/poll convention).

Every I/O address above is single-sourced in `generators/gen_memmap.py`; the
backplane bus signals and the full I/O allocation are in
[backplane/p8x-bus-definition.md](backplane/p8x-bus-definition.md).
