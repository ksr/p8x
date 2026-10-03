# Where P8X stands (October 2026)

P8X exists in two forms that run the same microcode: an **FPGA build** on a Sipeed
Tang Nano 20K, which runs the whole software stack today, and the **TTL card set**,
which is designed and routed in KiCad but not yet built. The C emulator,
`emulator/p8xemu`, interprets the same microcode images and is the golden model for
both. This page is a summary; the working list, with every open item, is
[BACKLOG.md](../BACKLOG.md).

## What runs today

**On the FPGA build** ([P8X on FPGA](../fpga/README.md)): the Verilog CPU runs the
unmodified monitor from its ROM, boots P8X/OS from a microSD card and runs the `/bin`
toolchain, at 9 MHz effective (three fabric phases per microcycle). The same chip
carries the **graphics engine** for a 4.3" 480×272 panel in RGB565 colour: a
graphics language modelled on the Matrox PG-640A, with hardware 3D transforms,
clipping and command lists, a multiply-divide unit and a geometry engine
([graphics theory of operation](p8x-graphics-theory.md)). The RTL is checked by
running the same program on the Verilog and on the emulator and comparing their
state cycle by cycle ([co-simulation](../fpga/sim/README.md)).

**The software**, on the FPGA build and in the emulator:

- **The monitor** in a 6 KB ROM (about 4.9 KB used): memory examine and change,
  disk format and boot, and the BIOS jump table at `$0100` that programs call
  ([ROM monitor](p8x-monitor.md)).
- **P8X/OS**, loaded from CompactFlash (or microSD on the FPGA): a hierarchical
  filesystem, a shell with redirection, two-stage pipes, command history and Tab
  completion, `make`, a second drive mounted at `/d1`, and dozens of `/bin` commands
  with manual pages ([P8X/OS](../os/README.md), [manual pages](../os/man/README.md)).
  With a display fitted, the console also appears on the screen and a desktop with a
  Finder runs full-screen applications ([two-mode operation](p8x-two-mode-design.md)).
- **BASIC**, with statements for the graphics engine
  ([BASIC programmer's guide](../basic/p8x-basic-guide.md)).
- **A toolchain on the machine**: a line editor and `vi`, an assembler whose output is
  byte-identical to the host assembler's, a C compiler written in assembler, and
  `cc.c`, a C compiler written in C that compiles its own source on P8X and
  reproduces itself byte for byte (Milestone B, 2026-09-14; checked in the emulator
  by `cc_selfhost_test`) ([on-target tools](../apps/README.md)).
- **On the host**: the C cross-compiler `p8cc.py`, which builds every `/bin`
  command, and `p8cc.c`, the same compiler in its own C subset, which compiles
  itself (Milestone A) ([C compiler](../compiler/README.md)).

The instruction set has **143 opcodes**, all microcoded. The 55 added after the
first 88 (39 of them in September 2026, for the C compilers) are microcode only; on
the TTL machine they need nothing beyond the register bank change below
([instruction set](p8x-isa-card.md)).

## The TTL card set

Nine boards are **designed and routed in KiCad**, 4-layer, with orderable Gerbers and
0 unconnected pads each: the control, register bank, ALU, memory, I/O and CF-IDE
cards, a PS/2 card, a bus test card for bring-up, and the 8-slot backplane. The
plug-in cards are 280 × 140 mm. **None has been fabricated yet.**
([KiCad boards](../hardware/KICAD-BOARDS.md), [hardware overview](../hardware/README.md))

The latest revisions follow the current software: the memory card (rev F) decodes the
6 KB ROM, the I/O card (rev B) has a second serial port, and the CF card (rev B) has
two drives. Before ordering ([build readiness](../hardware/RECONCILIATION.md)):

- **Register bank rev D.** The 16-bit instructions count the hidden scratch pointer
  PT, and `MOVW` needs a second one, PT2; the routed board still has PT as load-only
  latches. About ten more chips, on the register bank card only.
- **CF drive 1.** The CF card decodes drive 1 at its own `$FF18–$FF1F`; the firmware
  and the emulator still select it with the device bit on `$FF10–$FF17`.
- **Bench checks.** The DIN 41612 footprints against the physical connectors, and
  the bus test card's firmware, which has not been compiled yet.

The backplane is to be ordered first, as the cheap validation article.

## What is next

- **TTL:** the register bank rev D, then an **interrupt controller card** (the last
  core-machine card still to design), then ordering and bring-up, backplane first.
- **FPGA:** the RTL still write-protects `$0000–$1FFF`, while since the 6 KB ROM map
  (2026-09-14) `$1800–$1FFF` is RAM; the board build and the co-simulation follow that
  boundary next. Then Milestone 5: a faster clock than today's 9 MHz, and
  interrupts.
- **Software:** pipes of more than two stages (`a | b | c`), and opening a file by
  name as a single system call (`SYS_OPEN`).
- **This website** ([p8x.cottageworker.com](https://p8x.cottageworker.com)) is
  built and published from the repository's own documents on every push to `main`.

Everything above is drawn from [BACKLOG.md](../BACKLOG.md), the
[README](../README.md), [hardware/KICAD-BOARDS.md](../hardware/KICAD-BOARDS.md) and
[hardware/RECONCILIATION.md](../hardware/RECONCILIATION.md); BACKLOG.md carries the
detail and the dates.
