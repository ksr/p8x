# P8X — Hand-Built 8-Bit TTL CPU

A from-scratch 8-bit CPU built from ~75 74HCT logic chips on a 10-slot DIN41612 backplane. Fully microcoded; the microcode ROM images burned to the EPROMs are the same images the emulator interprets.

## Architecture

- **8-bit data bus, 16-bit address bus**
- **4 × 16-bit pointer registers** (74169 up/down counters): P0 = PC, P1/P2 = general-purpose, P3 = stack pointer (empty-descending). The address bus is *always* driven by one of these — no separate MAR.
- **Registers:** A, B (ALU operands), T/T2 (hidden microcode temporaries), FLAGS (C, Z, N, V)
- **ALU:** 2 × 74181 + 74182 carry-lookahead, with a post-ALU shifter
- **Microcoded control:** 4 × 28C64 EEPROMs; ROM address = IR | step<<8 | cond<<12
- **Memory map:** `$0000–$7FFF` EEPROM, `$8000–$FEFF` RAM, `$FF00–$FFFF` I/O

## Cards (6)

| Card | Function |
|------|----------|
| Control / Microcode | Clock, reset, sequencer, microcode EPROMs, IR, condition mux, front-panel |
| Register Bank | P0–P3 16-bit pointer registers, address bus drivers |
| ALU | A, B, T, T2 registers; 74181 ALU; shifter; FLAGS |
| Memory | 28C256 EEPROM + 62256 SRAM, address decode |
| I/O | Switches, LEDs, 6850 ACIA (RS-232) |
| CF-IDE | CompactFlash in 8-bit True IDE mode, memory-mapped at $FF10–$FF17 |

All six cards plug into a passive 10-slot backplane over a 96-pin DIN 41612 bus (rev C2).

## Toolchain

| Tool | Location | Purpose |
|------|----------|---------|
| `microcode/genucode.py` | `microcode/` | Microcode generator → `u0–u3.bin` EPROM images |
| `firmware/p8xasm.py` | `firmware/` | Two-pass assembler, shares opcode table with genucode.py |
| `emulator/p8xemu.c` | `emulator/` | Cycle-accurate emulator, interprets the same u0–u3.bin images |
| `generators/gen_eagle.py` | `generators/` | Generates Eagle schematics + boards for all 7 boards (backplane + 6 cards) |

**Generators are canon.** Never hand-edit Eagle `.sch`/`.brd` files or ROM binaries — they are build artifacts. Edit the generator and regenerate.

## Quick Start

```sh
# Build the emulator and regenerate microcode images
cd emulator && make

# Run the smoke tests (message print, JSR/RTS round-trip, branch countdown)
make test

# Regenerate the Eagle boards + schematic PDFs. The schematic renderers import
# gen_eagle.py, which writes the .sch/.brd files into the current directory, so
# run them from hardware/eagle/.
cd ../hardware/eagle
python3 ../../generators/gen_eagle.py                # all 14 .sch/.brd files
python3 ../../generators/render_traditional.py       # memory card schematic PDF
python3 ../../generators/render_traditional_auto.py  # 5 plug-in card schematic PDFs

# These are standalone (write straight to docs/) and run from anywhere:
python3 ../../generators/gen_bus_pdf.py              # bus definition
python3 ../../generators/render_bp_traditional.py    # backplane schematic
python3 ../../microcode/gen_progguide.py             # programmer's guide
```

## Documentation

| Document | Description |
|----------|-------------|
| [docs/backplane/p8x-bus-definition.md](docs/backplane/p8x-bus-definition.md) | Authoritative 96-pin bus pinout, signal descriptions, DOE/DLD encoding, microcode word layout |
| [docs/backplane/p8x-backplane-design.md](docs/backplane/p8x-backplane-design.md) | PCB stackup, termination analysis, BOM |
| [docs/p8x-card-standards.md](docs/p8x-card-standards.md) | Design rules that apply to every plug-in card |
| [docs/p8x-system-design.md](docs/p8x-system-design.md) | System and card-by-card architecture reference |
| [docs/cf-card/p8x-cf-os-design.md](docs/cf-card/p8x-cf-os-design.md) | CF-IDE hardware + P8X/OS design |
| [docs/cf-card/p8xfs-v2-hierarchical.md](docs/cf-card/p8xfs-v2-hierarchical.md) | P8XFS v2 hierarchical filesystem spec |
| [docs/p8x-programmers-guide.pdf](docs/p8x-programmers-guide.pdf) | Generated instruction set reference |
| [BACKLOG.md](BACKLOG.md) | NEXT / IDEAS / VERIFY / DONE |

### Per-card guides

Each card has a README explaining how its circuit works, chip by chip:

| Card | Guide |
|------|-------|
| Control / Microcode | [docs/control-card/README.md](docs/control-card/README.md) |
| Register Bank | [docs/reg-bank/README.md](docs/reg-bank/README.md) |
| ALU | [docs/alu-card/README.md](docs/alu-card/README.md) |
| Memory | [docs/memory-card/README.md](docs/memory-card/README.md) |
| I/O | [docs/io-card/README.md](docs/io-card/README.md) |
| CF-IDE | [docs/cf-card/README.md](docs/cf-card/README.md) |

## Status

- Emulator working: 35 opcodes, ACIA on stdin/stdout, verified against microcode images
- Assembler working: two-pass, full expression support, shares opcode table with microcode generator
- Eagle schematics + boards generated for all 6 cards and backplane
- **Next:** boot the ROM monitor in the emulator; CF-IDE emulation
