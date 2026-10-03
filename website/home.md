---
hide:
  - navigation
  - toc
---

<!-- Author: Claude (Anthropic) for Ken Rother, 2026. The visitor home page of the P8X website (stage.py copies it
     to index.md). Every fact here comes from the p8x repository. -->

# P8X — a hand-built 8-bit TTL CPU

**P8X is an 8-bit computer designed from scratch in 74HCT logic** — about 130 chips on six cards plugged into a
passive backplane, with no microprocessor. Every instruction is **microcoded**: four EPROMs hold a control word for
each step of each instruction, and the same microcode images the EPROMs are burned from are what the emulator runs.
P8X also exists a second time, as an **FPGA build** of the same microarchitecture that boots the same, unmodified
software, and that build carries a **graphics engine** with hardware 3D. Around both sits a complete software stack:
a ROM monitor, a disk operating system with dozens of commands, BASIC, an assembler and C compilers.

I'm Ken Rother. I designed P8X, and it runs on an FPGA. Claude, Anthropic's AI, has been directly involved in its design, coding
and documentation.

[:material-github: Source on GitHub](https://github.com/ksr/p8x){ .md-button .md-button--primary }
[:material-home: My other projects](https://cottageworker.com){ .md-button }

## At a glance

| | |
|---|---|
| **Data path** | 8-bit data bus, 16-bit address bus; an ALU of two 74181s and a 74182 carry-lookahead, with a shifter |
| **Registers** | A and B; four 16-bit pointer registers, P0–P3 (P0 is the program counter, P3 the stack pointer), one of which always drives the address bus; flags C, Z, N, V |
| **Address space** | 64K: 6 KB of ROM at `$0000`, RAM from `$1800` to `$FEFF`, and an I/O page at `$FF00` |
| **Instructions** | 143 opcodes, all microcoded; the microcode address is the opcode, the step and the condition |
| **Construction** | about 130 74HCT chips on six cards, in a passive 8-slot backplane with a 96-pin DIN 41612 bus |
| **Clock** | a 4 MHz oscillator, divided by 1, 2, 4 or 8 (a jumper) |
| **Console** | RS-232 serial through a 6850 ACIA |
| **Disk** | CompactFlash in 8-bit True IDE mode, two drives |
| **FPGA build** | a Sipeed Tang Nano 20K: 9 MHz, a microSD card as the disk, a 4.3" 480×272 colour panel |

## What it runs

- **The monitor ROM** — examine and change memory, dump it, initialise, format and boot the disk, run programs; and a
  BIOS jump table at `$0100` that programs call. ([ROM monitor](docs/p8x-monitor.md))
- **P8X/OS** — a disk operating system loaded from CompactFlash, with a hierarchical filesystem, a shell with
  redirection, pipes, command history and Tab completion, `make`, and a second card mounted at `/d1`. The commands
  have manual pages, on the disk and [here](commands/index.md). ([P8X/OS](os/README.md))
- **BASIC** — an interpreter written in P8X assembler, with statements for the graphics display.
  ([BASIC programmer's guide](basic/p8x-basic-guide.md))
- **A toolchain on the machine itself** — a line editor and `vi`, an assembler whose output is byte-identical to the
  host assembler's, and C compilers: one written in assembler, and one written in C that compiles its own source on
  P8X and reproduces itself byte for byte. ([On-target tools](apps/README.md))
- **Tools on the Mac** — the C cross-compiler that builds every `/bin` command, the assembler, and a cycle-accurate
  emulator that runs the microcode images rather than a model of the instructions. ([C compiler](compiler/README.md),
  [assembler](assembler/README.md), [emulator](emulator/README.md))

## The cards

<div class="grid cards" markdown>

-   ![Control / microcode card, KiCad 3D render](hardware/control-card/kicad/p8x-control-card-render-3d.png)

    **[Control / microcode](hardware/control-card/README.md)** — the clock, reset and front-panel run controls, the
    instruction register, and the microcode engine that drives every other card over the backplane.

-   ![Register bank card, KiCad 3D render](hardware/regbank-card/kicad/p8x-regbank-card-render-3d.png)

    **[Register bank](hardware/regbank-card/README.md)** — the four 16-bit pointer registers, built from 74169
    up/down counters; there is no separate memory address register.

-   ![ALU card, KiCad 3D render](hardware/alu-card/kicad/p8x-alu-card-render-3d.png)

    **[ALU](hardware/alu-card/README.md)** — the A and B registers, two hidden temporaries for the microcode, the
    74181 ALU, the shifter and the flags.

-   ![Memory card, KiCad 3D render](hardware/memory-card/kicad/p8x-memory-card-render-3d.png)

    **[Memory](hardware/memory-card/README.md)** — the ROM and RAM and their address decode.

-   ![I/O card, KiCad 3D render](hardware/io-card/kicad/p8x-io-card-render-3d.png)

    **[I/O](hardware/io-card/README.md)** — switches, LEDs, the serial ports, and a bus monitor of LEDs that shows
    the machine at work.

-   ![CF-IDE card, KiCad 3D render](hardware/cf-card/kicad/p8x-cf-card-render-3d.png)

    **[CF-IDE](hardware/cf-card/README.md)** — two CompactFlash drives in 8-bit True IDE mode, in the I/O page.

-   ![PS/2 card, KiCad 3D render](hardware/ps2-card/kicad/p8x-ps2-card-render-3d.png)

    **[PS/2](hardware/ps2-card/README.md)** — a keyboard port and a mouse port at `$FF58`–`$FF5F`.

-   ![Backplane, KiCad 3D render](hardware/backplane/kicad/p8x-backplane-render-3d.png)

    **[Backplane](hardware/backplane/p8x-backplane-design.md)** — eight slots on a passive 96-pin bus that carries the
    microcode control word itself ([bus definition](hardware/backplane/p8x-bus-definition.md)).

-   ![Bus test card, KiCad 3D render](hardware/bustest-card/kicad/p8x-bustest-card-render-3d.png)

    **[Bus test card](hardware/bustest-card/p8x-bustest-card-design.md)** — a USB-attached card that sits where the
    control card would and drives the bus one microcycle at a time, to bring up each card on its own.

</div>

These are renders of the KiCad boards. All of them are routed; the plug-in cards are all 280 × 140 mm with four
layers. See [KiCad boards](hardware/KICAD-BOARDS.md) and [build readiness](hardware/RECONCILIATION.md).

## The FPGA build and the graphics engine

The [FPGA build](fpga/README.md) puts the whole machine — CPU, memory, serial console, disk and display — into one
Gowin chip on a Tang Nano 20K; one USB cable programs it and carries the serial console. It is a parallel track to the TTL cards,
not a replacement: the same microcode, sequencer and pointer registers, so the monitor, OS, BASIC, assembler and C
compiler run on it unmodified. It is checked by running the same program on the Verilog and on the emulator and
comparing their state cycle by cycle ([co-simulation](fpga/sim/README.md)).

It also carries a **graphics engine** for a 480×272 panel in 16-bit colour: a graphics language modelled on the
Matrox PG-640A, with hardware 3D transforms, clipping and command lists, a multiply-divide unit and a geometry engine.
Programs draw through it from the shell, BASIC, C or assembler, and the emulator models the same device so the two
can be compared frame by frame. When a display is present, the same OS shows its console on the screen and offers a
desktop with a Finder and full-screen applications; without one, it runs over the serial console.
([Graphics theory of operation](docs/p8x-graphics-theory.md), [graphics programmer's guide](docs/p8x-graphics-guide.md),
[two-mode operation](docs/p8x-two-mode-design.md))

## Where to start

| If you want to... | Read |
|---|---|
| understand how it works | [System design](docs/p8x-system-design.md), then the [bus definition](hardware/backplane/p8x-bus-definition.md) |
| look up an instruction | the [instruction set quick reference](docs/p8x-isa-card.md) or the [programmer's guide](docs/p8x-programmers-guide.md) |
| program it | the [memory map](docs/memory-map.md), the [ROM monitor](docs/p8x-monitor.md) and the [BASIC guide](basic/p8x-basic-guide.md) |
| use the OS | [P8X/OS](os/README.md) and the [commands](commands/index.md) |
| look at the hardware | the [hardware overview](hardware/README.md) and each card's theory of operation |
| draw on the screen | the [graphics programmer's guide](docs/p8x-graphics-guide.md) |
| decode an abbreviation | the [glossary](GLOSSARY.md) |
| see what is being worked on | [Status and backlog](BACKLOG.md) |
| build it from source | [Working on the code](repository.md) |

## Status (October 2026)

- **Running on the FPGA build:** the monitor, P8X/OS booting from a microSD card, the whole `/bin` toolchain, and the
  graphics engine. Next there: a faster clock than today's 9 MHz, and interrupts.
- **TTL cards:** all boards are designed and routed. Before ordering, the memory card's ROM decode has to follow the
  6 KB ROM map, and the microcode EPROMs are reburned from the current microcode; the backplane is ordered first.
  An interrupt controller card is still to be designed.
- **Software:** the C compiler compiles itself on P8X. Next on the list: pipes of more than two stages
  (`a | b | c`), and opening a file by name as a single system call.
