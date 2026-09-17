# Board ↔ emulator ↔ FPGA reconciliation (2026-09-17)

A build-readiness pass over the `hardware/` boards against the current emulator
(the golden model) and the FPGA CPU, ahead of ordering and building the real
machine. **Docs + bus-definitions only** — no CAD was regenerated (the `.sch` is
the source of truth and `.brd` placement is the user's Fusion work).

## TL;DR

Most of the built CPU cards (control, register bank, ALU, I/O, CF-IDE) plus the
LED display and backplane are **current** — the ISA has grown a lot since they
were laid out, but that growth is **entirely in the microcode ROM**, which is
data burned into the control card's existing EPROMs, not a change to any card's
logic. **Two things need attention before a build:** (1) the **memory card's ROM
decode is stale** — it still maps 8 KB ROM `$0000-$1FFF`, but the 2026-09-14
shrink made it 6 KB ROM with `$1800-$1FFF` a *writable* RAM scratch island, so the
decode must change or the OS breaks (see "Needs a decode change" below); and (2)
the missing **I/O expansion cards** for subsystems that so far live only in the
emulator and/or on the FPGA graphics card.

## What is current (no board change needed)

- **Control / microcode card.** The Tier A ISA growth (~149 opcodes now, up from
  88) is microcode: `microcode/genucode.py` → `u0-u3.bin` burned to the card's
  four microcode EPROMs. Those are **28C64 (8 KB) each** and `u0-u3.bin` are 8 KB,
  so the full 256-opcode IR space is already there — 149 opcodes fit with room.
  The address map (`IR | step | cond`) and sequencer are unchanged; a wider ISA is
  just fuller EPROM contents. Reburn from the current `genucode.py`; no rewire, no
  bigger part. (The CPU address space is still 16-bit/64 KB; word ops use it too.)
- **Register bank, ALU cards.** No architectural change.
- **I/O card.** `$FF00` switches / `$FF02` LEDs / `$FF04-05` ACIA unchanged. These
  ports are now named in the single-source memory map (`SWITCHES`, `LEDS`).
- **CF-IDE card.** `$FF10-$FF17`, unchanged.
- **Backplane, LED display.** Unchanged.

## Needs a decode change before building

- **Memory card — STALE, must be revised (found 2026-09-17).** The card's decode
  (`.sch` + `p8x-memory-card-theory.md`) still carries the pre-2026-09-14 **8 KB
  ROM window `$0000-$1FFF`** (`ROM !CE = A13 OR A14 OR A15`). The current map is
  **6 KB ROM `$0000-$17FF`** with **`$1800-$1FFF` a RAM scratch island** (IBUF/
  SBUF `$1D00`/BIOS scratch `$1F00`) — those are *written*, so `$1800-$1FFF` must
  be RAM. As drawn, that scratch lands in unwritable ROM and the OS/BIOS breaks on
  a real board. **Change:** ROM `!CE` gains an `(A11·A12)` deselect term (one AND
  gate) so ROM answers only `$0000-$17FF`; low-RAM U10 widens to `$1800-$7FFF`.
  Docs corrected 2026-09-17; the `.sch` regen is a CAD/Fusion step. (The overnight
  reconciliation missed this — it was an inventory + I/O-port pass, and the doc
  says "Rev E" while carrying an *earlier* Rev E decode.)

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
2. The core cards as laid out — but **revise the memory-card ROM decode first**
   (6 KB ROM + the `$1800-$1FFF` RAM island; see above) and regenerate its `.sch`,
   and **reburn the microcode EPROMs** from the current `genucode.py`, before
   bring-up.
3. **PS/2 card** once its CAD is generated and DRC-clean — it is the one new card
   with a finished design and a working emulator/`lib_ps2` counterpart to test
   against.
4. **IRQ controller card** — design it next (the last core-machine gap); until
   then interrupt-driven I/O stays polled (`$FF06`/poll convention).

Every I/O address above is single-sourced in `generators/gen_memmap.py`; the
backplane bus signals and the full I/O allocation are in
[backplane/p8x-bus-definition.md](backplane/p8x-bus-definition.md).
