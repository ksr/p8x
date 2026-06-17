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
| `assembler/p8xasm.py` | `assembler/` | Two-pass assembler, shares opcode table with genucode.py |
| `emulator/p8xemu.c` | `emulator/` | Cycle-accurate emulator, interprets the same u0–u3.bin images |
| `firmware/p8xmon.asm` | `firmware/` | ROM monitor (E/D/I/F/B/G/X commands) + BIOS jump table at `$0100` |
| `os/p8xos.asm` | `os/` | P8X/OS, RAM-resident disk OS booted from CF ([guide](os/README.md)) |
| `tools/p8xfs.py` | `tools/` | Host-side P8XFS disk-image tool (create/boot/put/get/ls) |
| `basic/p8xbasic.asm` | `basic/` | BASIC interpreter — standalone, disk, or ROM-in-monitor builds ([guide](basic/README.md)) |
| `tools/build_basic_rom.py` | `tools/` | Build the combined monitor + ROM-BASIC EEPROM image |
| `generators/gen_eagle.py` | `generators/` | Generates Eagle schematics + boards for all 7 boards (backplane + 6 cards) |

**Generators are canon.** Never hand-edit Eagle `.sch`/`.brd` files or ROM binaries — they are build artifacts. Edit the generator and regenerate. See [generators/README.md](generators/README.md) for what each script does and how to run it.

## Quick Start

```sh
# Build the emulator and regenerate microcode images
cd emulator && make

# Run the smoke tests (message print, JSR/RTS round-trip, branch countdown)
make test

# Regenerate the Eagle boards + schematic PDFs. The schematic renderers import
# gen_eagle.py, which writes the .sch/.brd files into per-board subdirectories of
# the current directory, so run them from hardware/.
cd ../hardware
python3 ../generators/gen_eagle.py                # all 14 .sch/.brd files (hardware/<board>/)
python3 ../generators/render_traditional_auto.py  # all 6 card schematic PDFs (hardware/<board>/)

# These write straight to hardware/backplane/ (and docs/) and run from anywhere:
python3 ../generators/gen_bus_pdf.py              # bus definition PDF
python3 ../generators/render_bp_traditional.py    # backplane schematic PDF
python3 ../microcode/gen_progguide.py             # programmer's guide (-> docs/)
```

## Documentation

| Document | Description |
|----------|-------------|
| [hardware/backplane/p8x-bus-definition.md](hardware/backplane/p8x-bus-definition.md) | Authoritative 96-pin bus pinout, signal descriptions, DOE/DLD encoding, microcode word layout |
| [hardware/backplane/p8x-backplane-design.md](hardware/backplane/p8x-backplane-design.md) | PCB stackup, termination analysis, BOM |
| [docs/p8x-card-standards.md](docs/p8x-card-standards.md) | Design rules that apply to every plug-in card |
| [docs/p8x-system-design.md](docs/p8x-system-design.md) | System and card-by-card architecture reference |
| [hardware/cf-card/p8x-cf-os-design.md](hardware/cf-card/p8x-cf-os-design.md) | CF-IDE hardware + P8X/OS design |
| [hardware/cf-card/p8xfs-v2-hierarchical.md](hardware/cf-card/p8xfs-v2-hierarchical.md) | P8XFS v2 hierarchical filesystem spec |
| [docs/p8x-programmers-guide.pdf](docs/p8x-programmers-guide.pdf) | Generated instruction set reference |
| [basic/p8x-basic-guide.md](basic/p8x-basic-guide.md) | P8X BASIC language reference (statements, expressions, examples) |
| [BACKLOG.md](BACKLOG.md) | NEXT / IDEAS / VERIFY / DONE |

### Per-card guides

Each board has its own directory under `hardware/` holding everything about it —
the Eagle `.sch`/`.brd`, the schematic PDF, a README explaining how the circuit
works chip by chip, and any board-specific design docs:

| Card | Directory |
|------|-----------|
| Control / Microcode | [hardware/control-card/](hardware/control-card/README.md) |
| Register Bank | [hardware/regbank-card/](hardware/regbank-card/README.md) |
| ALU | [hardware/alu-card/](hardware/alu-card/README.md) |
| Memory | [hardware/memory-card/](hardware/memory-card/README.md) |
| I/O | [hardware/io-card/](hardware/io-card/README.md) |
| CF-IDE | [hardware/cf-card/](hardware/cf-card/README.md) |
| Backplane | [hardware/backplane/](hardware/backplane/p8x-backplane-design.md) |

## Status

- Emulator working: 67 opcodes, ACIA on stdin/stdout, CF-IDE disk model (`-c <img>`), verified against microcode images
- Assembler working: two-pass, full expression support, shares opcode table with microcode generator
- Eagle schematics + boards generated for all 6 cards and backplane
- ROM monitor boots in the emulator; its filesystem hooks (`I`/`F`/`B`) run end to end against a CF image (`make test-cf`)
- P8X/OS v0.4 boots from CF: shell with `DIR`/`LOAD`/`RUN`/`SAVE`/`DEL`/`DUMP`/`DEP`/`HELP`; `DEP`+`SAVE`+`RUN` author and run programs on-target; host-side `p8xfs.py` builds disk images (`make test-os`)
- BASIC builds three ways from one source: standalone, disk-bootable (`B`), and ROM-in-monitor (launched by `X`) (`make test-basic`)
- **Next:** OS `PACK` (compaction); P8XFS v2 hierarchy (`CD`/`MKDIR`/`TREE`)
