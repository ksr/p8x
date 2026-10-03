# PS/2 Card

> **Theory of operation:** [p8x-ps2-card-theory.md](p8x-ps2-card-theory.md) —
> the receiver architecture, register semantics, and the 5 V / no-level-shift
> reasoning.

> **Status: designed and routed in KiCad (rev A, 2026-09-19); not fabricated yet.**
> The board is in [`kicad/`](kicad/README.md) (280 × 140 mm, 4-layer, Gerbers +
> renders; bespoke placement by `kicad/gen_ps2.py`). This is the standalone TTL card
> that realises the PS/2 window the emulator already models and `lib_ps2` already
> decodes. The first proposal (2026-09-17) was a pure-TTL receiver; the routed
> board uses an **ATmega1284P** instead (see below). The alternative FPGA-fabric path
> (PS/2 ports off the Tang Nano 20K graphics card, TXS0102 level-shifted) is a
> separate design — see
> [`fpga/tang-nano-20k/PS2-INTERFACE.md`](../../fpga/tang-nano-20k/PS2-INTERFACE.md).

A human-input card: **two dumb PS/2 receivers**, port A for a keyboard and port B
for a mouse. Each channel takes in the device's 11-bit frames and latches every
byte with a ready flag — nothing more. All meaning (Set-2 scan codes → ASCII,
3-byte mouse packets → dx/dy/buttons, the host→device transmit dance) lives in
software (`lib_ps2`, `man ps2`), which is why the card is small and the emulator's
golden model matches it byte-for-byte.

| Address | Register | Access | Port |
|---------|----------|--------|------|
| `$FF58` | `PSADAT` | read   | A (keyboard) data byte; ready clears on read |
| `$FF59` | `PSAST`  | r/w    | A status (r: ready/overrun/parity; w: CLK/DATA low) |
| `$FF5A` | `PSBDAT` | read   | B (mouse) data byte |
| `$FF5B` | `PSBST`  | r/w    | B status |
| `$FF5C` | `PSLINE` | read   | live CLK/DATA line states (for bit-banged TX) |
| `$FF5E` | `PSID`   | read   | `'K'` presence probe (absent floats `$FF`) |

`$FF5D` / `$FF5F` are unallocated.

## Why a standalone card
The P8X backplane is one card per function (six core cards + the planned IRQ card). PS/2
input is its own card so it drops into a free slot without touching the I/O card,
which already fills its `$FF00-$FF0F` decode. PS/2 is native **5 V TTL**
open-drain, and the backplane data bus is 5 V, so this card needs **no level
translation anywhere** — the one real difference from the FPGA-fabric option,
whose 3.3 V GPIO forces a TXS0102 per port.

## Chip family
An **ATmega1284P** (U13, PDIP-40, 5 V) runs both PS/2 ports in firmware: framing,
parity, ready and overrun. An MCU cannot meet the bus's read timing directly, so a
**latch bridge** sits between it and the backplane: four **74HCT374** read latches
(`PSADAT`/`PSAST`/`PSBDAT`/`PSBST`) that the MCU keeps loaded, a **74HCT244** for
`PSLINE` and another driving the constant `'K'` for `PSID`. The decode is local:
a **7430** page detector, **74138**s for DOE/DLD and the per-register strobes, and a
**74688** window compare. Four status LEDs (power, keyboard read, mouse read,
keystroke available) and an AVR **ICSP** header; the MCU's reset follows the bus
`-RES` through a 470 Ω isolation resistor. Through-hole, with the house per-IC
100 nF decoupling caps. The full description is §0 of the
[theory of operation](p8x-ps2-card-theory.md); the original pure-TTL proposal
(74HC164 / 74HC161 / 74HC574 / 7407 per channel) is kept there as the fallback.

## Presence
`PSID` reads `'K'` ($4B) when the card is fitted — the same probe convention as
the GL port (`'G'`) and MDU (`'M'`). `ps2_present()` checks it.

> The netlist is `CARDS["ps2-card"]` in
> [`generators/gen_eagle.py`](../../generators/gen_eagle.py). The addresses are single-sourced in
> [`generators/gen_memmap.py`](../../generators/gen_memmap.py); the bus pins are in
> [p8x-bus-definition.md](../backplane/p8x-bus-definition.md). See
> [p8x-system-design.md](../../docs/p8x-system-design.md) for the machine overview
> and `BACKLOG.md` (the "PS/2 keyboard + mouse card" item) for status.
