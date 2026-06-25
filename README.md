# P8X — Hand-Built 8-Bit TTL CPU

A from-scratch 8-bit CPU built from ~130 74HCT logic chips on a 10-slot DIN41612 backplane. Fully microcoded; the microcode ROM images burned to the EPROMs are the same images the emulator interprets.

New to the abbreviations and signal names? See [GLOSSARY.md](GLOSSARY.md).

## Architecture

- **8-bit data bus, 16-bit address bus**
- **4 × 16-bit pointer registers** (74169 up/down counters): P0 = PC, P1/P2 = general-purpose, P3 = stack pointer (empty-descending). The address bus is *always* driven by one of these — no separate MAR.
- **Registers:** A, B (ALU operands), T/T2 (hidden microcode temporaries), FLAGS (C, Z, N, V)
- **ALU:** 2 × 74181 + 74182 carry-lookahead, with a post-ALU shifter
- **Microcoded control:** 4 × 28C64 EEPROMs; ROM address = IR | step<<8 | cond<<12
- **Memory map (rev D):** `$0000–$3FFF` ROM (16 KB), `$4000–$FEFF` RAM (48 KB, 2× 62256), `$FF00–$FFFF` I/O

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
| `apps/p8xedit.asm`, `apps/p8xasm.asm` | `apps/` | On-target toolchain: line editor + native two-pass assembler, as `/BIN` programs ([guide](apps/README.md)) |
| `compiler/p8cc.py` | `compiler/` | C cross-compiler (subset) → P8X asm → RUNnable `.BIN` ([guide](compiler/README.md)) |
| `generators/gen_p8xopc.py` | `generators/` | Opcode table for the native assembler, generated from `genucode.OPC` |
| `generators/gen_eagle.py` | `generators/` | Generates Eagle schematics + boards for all 8 boards (backplane + 6 cards + LED test card) |

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
python3 ../generators/gen_eagle.py                # all 23 .sch/.brd files (hardware/<board>/)
python3 ../generators/render_traditional_auto.py  # all 7 card schematic PDFs (hardware/<board>/)
python3 ../generators/render_board_pdf.py         # placement-view PDFs (hardware/<board>/)

# These write straight to hardware/backplane/ (and docs/) and run from anywhere:
python3 ../generators/gen_bus_pdf.py              # bus definition PDF
python3 ../generators/render_bp_traditional.py    # backplane schematic PDF
python3 ../microcode/gen_progguide.py             # programmer's guide (-> docs/)
```

### EEPROM / programmer images

Both build paths emit **Intel HEX** alongside the raw `.bin`, for loading into an
EEPROM programmer:

- **Microcode** — `microcode/genucode.py` writes `u0–u3.bin` (what the emulator
  and tests load); the matching Intel HEX for the four 28C64 control-store EPROMs
  is produced into `rom/` by `make rom` (see below).
- **Program ROM** — `tools/build_basic_rom.py out.bin` writes `out.bin` *and*
  `out.hex` (monitor + ROM BASIC for the 28C256 at `$0000`).
- **Any other binary** — `python3 tools/bin2hex.py in.bin out.hex [base]`
  (e.g. a plain monitor built with `p8xasm.py`).

For a ready-to-burn set at fixed paths, run `cd emulator && make rom` (or
`sh tools/build_rom.sh`). It refreshes the four control-store EPROMs in
`microcode/` and writes the program ROM to `rom/p8x-prog-rom.{bin,hex}`. Both
are committed; see [rom/README.md](rom/README.md) for the chip map.

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

- Emulator working: 86 opcodes, ACIA on stdin/stdout, CF-IDE disk model (`-c <img>`), interactive I/O card (switches `-s`, LED trace `-L`), verified against microcode images
- Assembler working: two-pass, full expression support, shares opcode table with microcode generator
- Eagle schematics + boards generated for all 6 CPU cards, the front-panel LED card, and the backplane (8 boards)
- ROM monitor boots in the emulator; its filesystem hooks (`I`/`F`/`B`) run end to end against a CF image (`make test-cf`)
- P8X/OS v1.0 — full shell over flat **and hierarchical (P8XFS v2)** volumes. Built-in commands: `DIR [path]`/`CD`/`PWD`/`MKDIR`/`RMDIR`/`TREE`/`LOAD`/`RUN`/`SAVE`/`DEL`/`DUMP`/`DEP`/`PACK`/`FSCK`/`EXIT`. **Userland commands in `/BIN`** (written in C, run by bare name via implicit RUN + a `/BIN` search PATH, or explicit `RUN`): **`CAT`/`WC`/`GREP`/`CP`/`MV`** plus `DIR`/`PWD` (`-R`, etc.) — see [os/commands/](os/commands/README.md). Path resolution + CWD-path prompt; I/O redirection (`<`/`>`) and two-stage pipes (`a | b`); line editing (backspace/DEL, Ctrl-D EOF); **`PACK`** compacts the directory tree and **`FSCK`** checks integrity on-target; host-side `p8xfs.py` builds (`--v2`), navigates, and `fsck`s images (`make test-os`)
- BASIC builds four ways from one source: standalone, disk-bootable (`B`), ROM-in-monitor (launched by `X`), and a run-from-OS TPA program (`make test-basic`)
- On-target toolchain: **EDIT** (line editor) + **ASM** (native two-pass assembler) as `/BIN` programs — edit → assemble → run a program entirely on the machine; ASM output is byte-identical to the host assembler across the whole opcode table (`make test-os`, see [apps/](apps/README.md))
- **C compiler** — `compiler/p8cc.py` (Python host tool) plus `compiler/p8cc.c`, the same compiler rewritten in its own subset that **self-compiles** ("small C in small C", Milestone A). Full subset: `int`/`char`, pointers, arrays, `struct`/`union`, functions with params/locals/recursion, `if`/`else`/`while`/`for`, the complete operator set (`+ - * / % << >>`, comparisons, `& ^ | && ||`, unary `- ! ~`), global initializers, and `getchar`/`putchar`/`puts`; compiles to P8X asm and runs as a `/BIN` program (`make test-c`, host-vs-self differential `c_selfhost_test`, see [compiler/](compiler/README.md))
- BIOS **file API**: byte streams (`FOPEN`/`FGETB`, `FWOPEN`/`FPUTB`/`FCLOSE`), path resolution into subdirectories (`FRESOLVE`), name formatting (`FNORM`), and directory iteration (`FOPENDIR`/`FNEXT`) — the assembler rides on the streams and self-hosts (`make test-cf`)
- **Next:** C compiler **Milestone B** (run `p8cc.c` *on the P8X* — a streaming/RAM problem, not a language gap); multi-stage pipes (`a | b | c`); a `PATH` command; the IRQ-controller hardware card; hardware bring-up checklist (Fusion DRC, footprint confirmation, order backplane first)
