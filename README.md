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
| `firmware/p8xmon.asm` | `firmware/` | ROM monitor (E/D/I/F/B/G/? commands) + BIOS jump table at `$0100` |
| `os/p8xos.asm` | `os/` | P8X/OS, RAM-resident disk OS booted from CF ([guide](os/README.md)) |
| `tools/p8xfs.py` | `tools/` | Host-side P8XFS disk-image tool (create/boot/put/get/ls) |
| `basic/p8xbasic.asm` | `basic/` | BASIC interpreter — standalone, disk, or run-from-OS builds ([guide](basic/README.md)) |
| `apps/p8xedit.asm`, `apps/p8xasm.asm`, `apps/p8xcc.asm` | `apps/` | On-target toolchain: line editor + native two-pass assembler + native C compiler (`cc`), as `/bin` programs ([guide](apps/README.md)) |
| `compiler/p8cc.py` | `compiler/` | C cross-compiler (subset) → P8X asm → RUNnable `.bin` ([guide](compiler/README.md)) |
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
- **Program ROM** — the assembled monitor + BIOS for the 28C256 at `$0000`
  (~4.3 KB; BASIC is no longer ROM-resident). `make rom` builds it into `rom/`.
- **Any other binary** — `python3 tools/bin2hex.py in.bin out.hex [base]`
  (e.g. a monitor built directly with `p8xasm.py`).

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

- Emulator working: 88 opcodes, ACIA on stdin/stdout, CF-IDE disk model (`-c <img>`), interactive I/O card (switches `-s`, LED trace `-L`), verified against microcode images
- Assembler working: two-pass, full expression support, shares opcode table with microcode generator
- Eagle schematics + boards generated for all 6 CPU cards, the front-panel LED card, and the backplane (8 boards)
- ROM monitor boots in the emulator; its filesystem hooks (`I`/`F`/`B`) run end to end against a CF image (`make test-cf`)
- P8X/OS v1.0 — full shell over flat **and hierarchical (P8XFS v2)** volumes. Built-in commands: `cd`/`mkdir`/`rmdir`/`load`/`run`/`save`/`del`/`path`/`pack`/`fsck`/`format`/`mount`/`umount`/`help`/`exit`/`man`/`sh`/`make` (the minimal-kernel split moved the pure-viewer/memory commands to `/bin`, including `dump`/`dep` — only `pack`/`fsck` remain resident because they mutate/scan the filesystem). **Dual CompactFlash** — a second card is **mounted at `/d1`** in one unified namespace (drive 0 is the root), so ordinary paths reach it with drive-unaware commands: `cd /d1`, `cat /d1/NOTES`, `grep x /d1/SRC/*.C`, cross-mount `cp /d1/A /B`. A single mount redirect in `FRESOLVE`/`RV_START` does the routing; **`cp -r /d1/dir /dir`** recursively copies a subtree across the mount (card provisioning), creating directories via the `SYS_MKDIR` syscall. **Userland commands in `/bin`** (written in C, run by bare name via implicit RUN + a `/bin` search PATH, or explicit `run`): **`dir`/`pwd`/`tree`/`cat`/`wc`/`grep`/`cp`/`mv`/`head`/`tail`/`more`/`sort`/`uniq`/`sed`/`find`/`diff`/`vi`/`touch`/`man`/`dump`/`dep`/`disasm`** (`dir -R`, `cp -r`, a VT100 `vi` screen editor, `man <cmd>` reading `/man`, etc.) — see [os/commands/](os/commands/README.md). Path resolution + CWD-path prompt; I/O redirection (`<`/`>`) and two-stage pipes (`a | b`); line editing (backspace/DEL, Ctrl-D EOF); **`pack`** compacts the directory tree and **`fsck`** checks integrity on-target; host-side `p8xfs.py` builds (`--v2`), navigates, and `fsck`s images (`make test-os`)
- BASIC builds three ways from one source: standalone, disk-bootable (`B`), and a run-from-OS TPA program (`run BASIC.bin`) — `make test-basic` (ROM-resident BASIC was removed to reclaim ROM space)
- On-target toolchain: **EDIT** (line editor) + **ASM** (native two-pass assembler) + **CC** (a from-scratch C compiler written in asm) as `/bin` programs — edit → **compile (`cc x.c >x.asm`)** → assemble → run a program entirely on the machine; ASM output is byte-identical to the host assembler across the whole opcode table (`make test-os`, see [apps/](apps/README.md)). **Rebuild any command on-target** — every command's source rides along under `/src/commands/{c,asm}` (plus shared `lib_*` helpers), and the **`sh`** script runner + **`make <target>`** built-in drive `cc`→`asm` (or `asm` alone) to rebuild one command, a group (`make c`/`make asm`), or everything (`make`), landing binaries under `/src/commands/{c,asm}/bin`, then `make installc`/`make installa` publishes the chosen twin over `/bin` — see [os/commands/](os/commands/README.md). (`make NAME` runs `/src/mk/NAME.sh`; P8X shell scripts end in `.sh`.)
- **Native C compiler — Milestone B achieved.** `apps/p8xcc.asm` (`/bin/cc`) is a from-scratch, single-pass C compiler written directly in assembly, small enough to compile C **entirely on the machine** (front *and* back end) where the optimizing `p8cc.c` codegen — ~82 KB, larger than the whole 64 KB address space — never could. Through v0.28 it covers: functions, direct **and mutual** recursion, pointers + pass-by-reference, `int`/`char` arrays with `[]` and decay, **structs** (`.`/`->`), globals, the full operator set (`+ - * / % << >> & ^ | && || ?:`, `++`/`--`/`+=`/`-=`, comparisons, unary `- ! * &`), hex/char/string literals with escapes, `//`+`/* */` comments, a recursive **`//#use`** preprocessor (splices `/lib/lib_*.c`), and the `putchar`/`puts`/`getchar`/`peek`/`poke`/`argstr`/`bios` builtins. It compiles real OS command source: **`pwd.c` → `cc` → `asm` → runs** correctly on-target. Known gaps are listed under "cc — KNOWN LIMITATIONS" in `BACKLOG.md`.
- **Host C compiler** — `compiler/p8cc.py` (the primary build tool: every `/bin` command is compiled with it) plus `compiler/p8cc.c`, the same compiler rewritten in its own subset that **self-compiles** ("small C in small C", Milestone A). Full subset incl. `struct`/`union`, global initializers, and the operators above (`make test-c`, host-vs-self differential `c_selfhost_test`, see [compiler/](compiler/README.md)).
- **DEPRECATED — self-hosted front end (`cpp | lex | cc1`).** The earlier path-A route ran the front half on-target (`cpp | lex | cc1` → AST) with codegen on the host. It is **superseded by the native `cc`** (which does the whole compile on-target) and is no longer built or shipped; the sources/man pages remain in the repo for reference (see `compiler/README.md`).
- BIOS **file API**: byte streams (`FOPEN`/`FGETB`, `FWOPEN`/`FPUTB`/`FCLOSE`), path resolution into subdirectories (`FRESOLVE`), name formatting (`FNORM`), and directory iteration (`FOPENDIR`/`FNEXT`) — the assembler rides on the streams and self-hosts (`make test-cf`)
- **Next:** multi-stage pipes (`a | b | c`); a `path` command; the IRQ-controller hardware card; hardware bring-up checklist (Fusion DRC, footprint confirmation, order backplane first)
