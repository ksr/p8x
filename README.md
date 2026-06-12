# P8X — An 8-Bit TTL Computer

A hand-built 8-bit CPU in ~75 chips of 74HCT logic on a 10-slot DIN 41612
backplane, with a microcoded control unit, a 4x16-bit pointer register bank
(74169s) that unifies PC/SP/MAR, CompactFlash storage, and a small ROM
monitor + disk operating system (P8X/OS) with a hierarchical filesystem.

## Repository layout

| Path | Contents |
|---|---|
| `docs/` | Design documents. `p8x-bus-definition.pdf` is the bus spec for review; `p8x-card-standards.md` is binding on all plug-in cards |
| `hardware/eagle/` | **Current CAD** (rev C, dash active-low convention): backplane (fully routed 4-layer, compact <250 mm) and memory card (placed, signals unrouted). Eagle XML — imports directly into Fusion 360 Electronics |
| `hardware/kicad-legacy/` | Earlier KiCad versions, pre-dash-convention. Reference only |
| `generators/` | **Canonical sources.** `gen_eagle_full.py` emits all Eagle sch/brd files; `gen_bus_pdf.py` emits the bus PDF. Both share the `busnet()` pin map — edit there, regenerate everywhere. Never hand-edit CAD against a stale netlist |
| `firmware/` | `p8xmon.asm` — ROM monitor (examine/modify, dump, CF init/format, boot, go) |
| `BACKLOG.md` | Living backlog: NEXT / IDEAS / VERIFY / DONE |

## Architecture in one paragraph

8-bit data bus, 16-bit address bus driven exclusively by a bank of four
16-bit up/down pointer registers (P0=PC, P1/P2=general, P3=SP). Microcoded
control: IR + step counter + condition flag address four EPROMs whose 32-bit
control word is pipeline-latched. Bus discipline is one-hot by construction:
4-bit DOE/DLD fields are broadcast encoded and decoded per-card. Memory is
32K EEPROM + 32K SRAM with memory-mapped I/O at $FF00-$FFFF (ACIA serial,
switches/LEDs, CF in 8-bit True-IDE mode at $FF10).

## Regenerating artifacts

    python3 generators/gen_eagle_full.py   # all four Eagle files
    python3 generators/gen_bus_pdf.py      # bus definition PDF (needs reportlab)

Both validate their own output (netlist coverage, parse, geometry checks).

## Status (2026-06-12)

Backplane: routed, pending Fusion DRC + mounting holes + connector footprint
verification against physical DIN 41612 parts. Memory card: placed, signal
routing pending. Remaining cards (control, register bank, ALU, I/O, CF-IDE):
designed in docs, CAD generation pending. See BACKLOG.md.
