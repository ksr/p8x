# Memory Card

Provides the system's ROM and RAM and gates them onto the data bus. It decodes the
address bus to pick ROM vs RAM, keeps both off the data bus during I/O accesses,
and generates a clean write strobe.

| Region | Device | Size |
|--------|--------|------|
| `$0000–$7FFF` | 28C256 EEPROM (U1) | 32 KB — ROM monitor / user code |
| `$8000–$FEFF` | 62256 SRAM (U2) | 32 KB (minus the I/O page) |
| `$FF00–$FFFF` | — (I/O page) | RAM inhibited; handled by I/O & CF cards |

> This README describes the circuit as actually built in
> [`generators/gen_eagle.py`](../../generators/gen_eagle.py). See
> [p8x-system-design.md §6](../p8x-system-design.md) for the overview and
> [p8x-bus-definition.md](../backplane/p8x-bus-definition.md) for bus pins.

## Chip inventory

| Ref | Device | Role |
|-----|--------|------|
| U1 | 28C256 | EEPROM, 32 KB |
| U2 | 62256 | SRAM, 32 KB |
| U3 | 74245 | Bidirectional data-bus transceiver |
| U4 | 7430 | 8-input NAND — I/O page ($FFxx) detector |
| U5 | 74138 | DOE decoder (read enable) |
| U6 | 74138 | DLD decoder (write strobe) |
| U7 | 74HCT00 | NAND — RAM chip-select logic |
| U8 | 74HCT32 | OR — write-strobe gating |
| U9 | 74HCT08 | AND — transceiver enable |

## How it works

### Address decode (ROM vs RAM vs I/O)
- **ROM** (28C256, U1) is selected whenever **A15 = 0** — its `!CE` is tied directly
  to A15, so the lower 32 KB is EEPROM.
- The **I/O page detector** (U4, a 7430 8-input NAND on A8–A15) asserts `-IOPG` low
  whenever the address is `$FFxx`.
- **RAM** (62256, U2) is selected only when **A15 = 1 *and* not the I/O page**. U7
  NANDs A15 with `-IOPG` to produce `-RAMCE`: RAM enables for `$8000–$FEFF` but
  stays off for `$FFxx`, leaving that page to the I/O and CF cards.

### Data-bus transceiver
The 74245 (U3) connects on-card memory to the backplane data bus. Its **direction**
is set by read vs write: on a read (DOE = 7 → `-RD`) it drives the bus from memory;
on a write (DLD = 7 → `-MEMW`) it drives memory from the bus. It is **enabled only
for on-card addresses** (`-BOE`, gated in U9), so the card never fights another
driver during I/O cycles.

### Read path
DOE code 7 (`-RD`, decoded by U5) drives the memory output-enables (`!OE`) and sets
the 74245 direction toward the bus. The selected chip (ROM or RAM, per the decode
above) puts its byte on the bus.

### Write path & strobe timing
DLD code 7 (`-MEMW`, decoded by U6) is the write request. The actual `!WE` strobe is
`-MEMW` **gated with CLK̄** in U8: this gives address and data a full half-cycle to
set up before the write pulse falls in the second half-cycle — clean, glitch-free
writes. Only RAM responds to writes; the EEPROM `!WE` is held inactive (in-system
EEPROM programming is out of scope for normal operation).

## Bus codes this card owns
- **DOE:** 7 = memory read (drives D0–D7)
- **DLD:** 7 = memory write (`MEMW` strobe) — shared decode convention with the I/O card

## LEDs
PWR (green), ROM (yellow), RAM (yellow), RD (green), WR (red) — show which region
and direction is active each cycle.
