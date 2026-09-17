# PS/2 Card

> **Theory of operation:** [p8x-ps2-card-theory.md](p8x-ps2-card-theory.md) —
> the receiver architecture, register semantics, and the 5 V / no-level-shift
> reasoning.

> **Status: DESIGN / PROPOSAL (2026-09-17).** Not built yet, no generated CAD.
> This is the standalone TTL card that realises the PS/2 window the emulator
> already models and `lib_ps2` already decodes. The alternative FPGA-fabric path
> (PS/2 ports off the Tang Nano 20K graphics card, TXS0102 level-shifted) is a
> separate design — see
> [`fpga/tang-nano-20k/PS2-INTERFACE.md`](../../fpga/tang-nano-20k/PS2-INTERFACE.md).

A human-input card: **two dumb PS/2 receivers**, port A for a keyboard and port B
for a mouse. Each channel shifts in the device's 11-bit frames and latches every
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
The P8X backplane is one card per function (6 built + the planned IRQ card). PS/2
input is its own card so it drops into a free slot without touching the I/O card,
which already fills its `$FF00-$FF0F` decode. PS/2 is native **5 V TTL**
open-drain, and the backplane data bus is 5 V, so this card needs **no level
translation anywhere** — the one real difference from the FPGA-fabric option,
whose 3.3 V GPIO forces a TXS0102 per port.

## Chip family
Per channel: **74HC164** (receive shift register), **74HC161** (bit counter →
frame-done), **74HC574** (data latch + ready), **7407** (open-collector CLK/DATA
line drivers for transmit). Plus the usual page/register decode (7430 + 74138s),
a 74HC245 bus driver, and the `'K'` presence buffer. Through-hole, 5 V, with the
house per-IC 100 nF decoupling caps. Full inventory in the theory doc.

## Presence
`PSID` reads `'K'` ($4B) when the card is fitted — the same probe convention as
the GL port (`'G'`) and MDU (`'M'`). `ps2_present()` checks it.

> This README describes the PROPOSED circuit. The addresses are single-sourced in
> [`generators/gen_memmap.py`](../../generators/gen_memmap.py); the bus pins are in
> [p8x-bus-definition.md](../backplane/p8x-bus-definition.md). See
> [p8x-system-design.md](../../docs/p8x-system-design.md) for the machine overview
> and `BACKLOG.md` (the "PS/2 keyboard + mouse card" item) for status.
