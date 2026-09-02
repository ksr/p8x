# P8X on FPGA

A **standalone** FPGA implementation of P8X — the whole machine (CPU, memory,
UART console, SD disk) in one FPGA, no backplane. It keeps the **same
microarchitecture** as the TTL build: the horizontal microcode word, the
sequencer, the pointer/address model, `DOE`/`DLD`/`PSEL` selects. The microcode
binary (from `microcode/genucode.py`) and the C emulator stay the reference, so
the monitor / OS / BASIC / C-compiler / assembler run **unmodified**.

This is a **parallel track** to the TTL / bus-connected hardware build, which
continues (just delayed). Nothing here touches `generators/` or the card designs.

Target board: **Sipeed Tang Nano 20K** (Gowin GW2AR-18). See
[`tang-nano-20k/`](tang-nano-20k/) for the board-specific files and the
Milestone-0 build.

## The verification spine

Every milestone is "make the RTL match the emulator." We run the **same program**
on an Icarus sim of the RTL and on the C emulator (`emulator/`), and **diff
architectural state** (PC, registers, flags, memory writes) cycle by cycle. The
emulator is the golden model; a divergence is a bug with an exact cycle and
signal. Same adversarial-diff discipline used elsewhere in the project.

## Getting started

Two independent paths. **The simulator needs no hardware** and is the whole of
Milestones 1-2; the board adds 0, 3 and 4.

### Prerequisites

| For | You need |
|-----|----------|
| Everything | `python3`, a C compiler (Apple clang / gcc) |
| Simulation | **`iverilog`** — `brew install icarus-verilog` |
| The board | **oss-cad-suite** (yosys, nextpnr-himbaechel, apicula, openFPGALoader) |
| The board | a **Sipeed Tang Nano 20K** and a USB-C **data** cable |

oss-cad-suite is a tarball, not a package: download the `darwin-arm64` (or your
platform's) release from
[oss-cad-suite-build](https://github.com/YosysHQ/oss-cad-suite-build/releases),
extract to `~/oss-cad-suite`, then — on macOS, or every binary refuses to launch:

```sh
xattr -dr com.apple.quarantine ~/oss-cad-suite
```

No admin rights are needed for any of this; `build.sh` sources the environment
itself.

### Step 0 — build the emulator first (both paths need it)

The microcode images `u0-u3.bin` are build products and are **not** in the repo,
and the emulator is the co-sim's reference model. From the repo root:

```sh
cd emulator && make
```

### Path A — simulation only, no hardware

```sh
fpga/sim/run.sh 20000                        # monitor boot, RTL vs emulator
fpga/sim/run.sh 60000 isa_test.asm           # all 88 opcodes
fpga/sim/run.sh 200000 "" console_in.txt     # driven monitor + console diff
fpga/sim/run.sh 2000000 "" boot_in.txt os/run-disk.img   # boots P8X/OS
```

Each prints `PASS: RTL matches emulator for N cycles`, or a `DIVERGENCE` dump
naming the exact microcycle. To drive the machine by hand instead of diffing:

```sh
fpga/sim/console.sh "" os/run-disk.img       # real terminal into the RTL
```

(The graphics engine is byte-compared against the emulator by the GL RTL
battery, `emulator/test/c_gl_rtl_test.sh` — the old `sim/gfx.sh` device-door
co-sim retired with the single-interface migration.)

`B` boots the OS, then `pwd` / `dir` / `cat README.TXT`. Ctrl-D or Ctrl-C quits.
Writes persist for the session — they land in `fpga/sim/work/disk.img`, a copy, so
your real image is untouched and your changes are replaced next launch.
It is slow but usable — roughly 30-50k CPU cycles/second.

### Path B — the real board

```sh
fpga/tang-nano-20k/build.sh cpu load     # build + program (volatile SRAM)
fpga/tang-nano-20k/build.sh cpu flash    # ... or persist it across power cycles
```

Then talk to it. The onboard bridge enumerates **two** serial devices and the
**higher-numbered one is the console** (the other is JTAG and returns garbage);
use `/dev/cu.*`, not `/dev/tty.*`:

```sh
tang-nano-20k/tools/term.py               # auto-picks the port; Ctrl-] quits
```

`term.py` is a dependency-free terminal that picks the console port for you and
quits with Ctrl-]. A stock terminal is equally fine —
`screen /dev/cu.usbserial-<N>1 115200`, exit with Ctrl-A then k — because the
firmware expands newlines itself (see [`docs/p8x-monitor.md`](../docs/p8x-monitor.md)).

Press Enter for the monitor's `*` prompt. `?` for help, `I` to identify the
microSD, `B` to boot the OS from it.

### Updating the board — TWO surfaces, not one

A change may live in either place, and a feature can need both:

| Surface | Carries | Update with |
|---------|---------|-------------|
| **bitstream** | CPU, microcode, monitor ROM, graphics RTL | `build.sh lcd load` |
| **SD card** | P8X/OS, `/bin`, BASIC | `tools/imgsend.py os/run-disk.img` |

The graphics ellipse is the cautionary example: it is RTL **and** a BASIC
statement. Rebuilding only the bitstream left the hardware understanding a
command that nothing on the card could issue, which presents as `?SYNTAX ERROR`
from BASIC — nothing about it points at the card being stale.

**Check `p8x_cpu.fs`'s timestamp after a build.** This concealed two separate
build failures here. The script itself is no longer the hole — it runs under
`set -euo pipefail` and each of synthesise / place-and-route / pack exits `1` on
failure, so `load` cannot be reached after a failed build. What remains is that
**`cpu` and `lcd` write the same `p8x_cpu.fs`**: a failed `lcd` build leaves the
previous file sitting there looking perfectly valid, and it may well be a `cpu`
bitstream with no graphics in it at all. Note also that a `| tail`-style pipeline
hides the exit status, which is how the failure reads as success. If a fix appears
to do nothing on the board, check the mtime before debugging anything else — and if that is current, reload once: a freshly loaded
bitstream has come up not answering more than once, and the same file loaded
again fixed it.

A card needs a P8XFS image on it. Writing one from the host needs root, so if you
do not have it the board can install its own over the serial console — see
[`tang-nano-20k/tools/`](tang-nano-20k/tools/README.md).

**If the board goes silent**, load the Milestone-0 echo bitstream
(`build.sh echo load`) as a known-good baseline; if that is silent too, the USB
bridge has wedged and a replug fixes it. After any replug, drain the port before
testing — the factory boot text sits buffered and reads like a reply.

## Milestones

| # | Milestone | Board? | Proves |
|---|-----------|--------|--------|
| **0** | First light: UART echo + heartbeat LED ✅ | yes | toolchain, bitstream, console path |
| **1** | CPU core in simulation ✅ | no | the microarchitecture is correct (all 88 opcodes) |
| **2** | Peripherals in simulation (ACIA-UART) ✅ | no | monitor boots to a sim console; console output diffed |
| **3** | Core on real hardware ✅ | yes | P8X talks over USB for real, full 64K map |
| **4** | SD disk (SD-over-SPI behind the BIOS block API) ✅ | yes | OS boots from SD, full FS |
| **5** | Polish: clock-up, IRQ (backlog #26), stretch goals | yes | performance + extras |
| **6** | Graphics: 480x272 panel + drawing engine ✅ | yes | BASIC draws on a real panel; the engine matches the emulator pixel for pixel across all three payloads |

Milestones 0–2 are most of the effort and only 0 needs the board — the CPU is
built and proven in simulation before the hardware ever runs it.

**Status 2026-08-12: 0–4 done.** P8X/OS boots from a microSD on the Tang Nano
20K. The CPU runs at 27/3 = 9 MHz (three fabric phases per microcycle, see
`tang-nano-20k/rtl/p8x_top.v`) with the full 64K map — affordable because the
microcode ROM is compacted from 8192 to 4096 words, so no SDRAM controller was
needed. Build and flash with `tang-nano-20k/build.sh cpu load`.

P8X is written to the board's **onboard flash**, so it comes up standalone on
power with no host involvement. (`build.sh cpu load` puts a build in volatile
SRAM instead, which is what you want while iterating — but note that a power
cycle then reverts to whatever is in flash, and the factory LiteX demo answers on
the same serial port and will silently swallow anything a script sends it.)

## Layout

```
fpga/
├── README.md                 this file
├── docs/architecture.md      module hierarchy, memory/peripheral map, co-sim spec
├── rtl/                      board-independent core (shared by sim and board)
│   ├── README.md             what is shared vs sim-only, and the `cen` contract
│   ├── p8x_cpu.v             the CPU. `cen` clock enable; otherwise one
│   │                         microcycle per clock, matching the emulator
│   ├── gfx.v                 graphics: registers, drawing engine, framebuffer
│   ├── video_rgb.v           480x272 panel timing + 2x-doubled scanout
│   └── p8x_soc.v             sim-only SoC: async-read arrays + modelled I/O
├── sim/                      co-simulation against the C emulator
│   ├── README.md             how the trace-diff works, and why -N exists
│   ├── run.sh                build + run + diff  [CYCLES] [ROM] [RX] [CF]
│   ├── console.sh            interactive console on the RTL (not diffed)
│   ├── mk_ucode_mem.py       4 ROM images → 32-bit ucode.hex
│   ├── tb_p8x.v              testbench: canonical per-cycle trace, ACIA, CF
│   ├── isa_test.asm          directed all-88-opcode exerciser
│   └── console_in.txt, cf_id.txt, boot_in.txt   scripted keystrokes
└── tang-nano-20k/            the board build
    ├── README.md             toolchain, pinout, flashing, board-sim benches
    ├── build.sh              [echo|cpu|lcd] [build|load|flash]
    ├── mk_compact_ucode.py   8192→4096-word microcode remap (buys the 64K map)
    ├── tangnano20k.cst       pin constraints (verified)
    ├── rtl/
    │   ├── top.v             Milestone-0: UART echo + heartbeat
    │   ├── p8x_top.v         the real SoC: 3-phase microcycle, BRAM, ACIA, CF
    │   ├── uart.v            8N1 UART (TX+RX)
    │   ├── cf_sd.v           $FF10-$FF17 CF task file over the SD controller
    │   └── sd_spi.v          microSD in SPI mode: init, read block, write block
    ├── sim/                  board-level benches (see tang-nano-20k/README.md)
    │   ├── tb_top.v          Milestone-0 echo path
    │   ├── tb_p8x_top.v      whole board top: monitor + OS boot off a card
    │   ├── tb_video.v        panel frame geometry (480x272, 54.11 Hz)
    │   ├── tb_scanout.v      which fb pixel reaches which panel pixel
    │   ├── sd_model.v        behavioural SPI card, with +sdfail fault injection
    │   └── tb_sd_spi.v       sd_spi's error paths
    └── tools/                host-side helpers, none needing root
        ├── README.md
        ├── term.py           serial terminal; translates P8X's bare-LF output
        ├── osload.asm        N sectors → LBA 1.., patch OSCNT
        └── imgload.asm       clone a whole P8XFS image from LBA 0
```

## How we work

- RTL + testbenches + co-sim harness written here; board bitstreams flashed and
  reported from hardware.
- **Sim green before hardware** — never debug unproven RTL and an unproven board
  at once.
- Small commits into `fpga/`, docs alongside, emulator stays the spec.
