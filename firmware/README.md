# firmware/

`p8xmon.asm` — the P8X ROM monitor, the firmware that runs from the memory-card
EEPROM at reset (origin `$0000`).

## What it provides

- **Interactive monitor commands** over the ACIA: `E` (examine/edit memory),
  `D` (dump, with paging — CR = next block, `.` = exit), `I`/`F`/`B` (CF init /
  format / boot), `G` (go), `X` (launch ROM BASIC at `$2000`).
- **BIOS jump table at `$0100`** — a stable call interface (ABI) for P8X/OS and
  other programs: `CONIN`, `CONOUT`, `CONST`, `CFINIT`, `CFREAD`, `CFWRITE`,
  `PUTS`, `PHEX8`. Programs call fixed addresses here so they keep working even
  if the monitor internals move.

## Build

Assembled by [`../assembler/p8xasm.py`](../assembler/) into a 32 KB ROM image.
The combined monitor + ROM BASIC image (and its Intel HEX) is built into
[`../rom/`](../rom/) by:

```sh
cd ../emulator && make rom        # -> rom/p8x-prog-rom.{bin,hex}
```

## Reference

- Command reference: [docs/p8x-monitor.md](../docs/p8x-monitor.md)
- Memory map, BIOS ABI, signal names: [GLOSSARY.md](../GLOSSARY.md)
