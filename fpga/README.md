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

## Milestones

| # | Milestone | Board? | Proves |
|---|-----------|--------|--------|
| **0** | First light: UART echo + heartbeat LED ✅ | yes | toolchain, bitstream, console path |
| **1** | CPU core in simulation ✅ | no | the microarchitecture is correct (all 88 opcodes) |
| **2** | Peripherals in simulation (ACIA-UART) ✅ | no | monitor boots to a sim console; console output diffed |
| **3** | Core on real hardware ✅ | yes | P8X talks over USB for real, full 64K map |
| **4** | SD disk (SD-over-SPI behind the BIOS block API) ✅ | yes | OS boots from SD, full FS |
| **5** | Polish: clock-up, IRQ (backlog #26), stretch goals | yes | performance + extras |

Milestones 0–2 are most of the effort and only 0 needs the board — the CPU is
built and proven in simulation before the hardware ever runs it.

**Status 2026-08-12: 0–4 done.** P8X/OS boots from a microSD on the Tang Nano
20K. The CPU runs at 27/3 = 9 MHz (three fabric phases per microcycle, see
`tang-nano-20k/rtl/p8x_top.v`) with the full 64K map — affordable because the
microcode ROM is compacted from 8192 to 4096 words, so no SDRAM controller was
needed. Build and flash with `tang-nano-20k/build.sh cpu load`.

Two things to know before driving the board: the bitstream is loaded to
**volatile SRAM**, so any power cycle reverts to the factory LiteX demo (whose
console answers on the same serial port and will silently swallow anything you
send it), and a disk can be installed without host root using the serial
loaders in `tang-nano-20k/tools/`.

## Layout

```
fpga/
├── README.md                 this file
├── docs/
│   └── architecture.md       module hierarchy, memory/peripheral map, co-sim spec
├── rtl/                       board-independent core (shared by sim and board)
│   ├── p8x_cpu.v             CPU: one microcycle/clock (matches the emulator)
│   └── p8x_soc.v             CPU + microcode ROM + 64K memory + sim I/O
├── sim/                       Milestone-1 co-simulation vs the C emulator
│   ├── README.md             how the trace-diff co-sim works
│   ├── mk_ucode_mem.py       4 ROM images → 32-bit ucode.hex
│   ├── tb_p8x.v              testbench (emits canonical per-cycle trace)
│   └── run.sh                build + run + diff RTL vs `p8xemu -T`
└── tang-nano-20k/
    ├── README.md             Milestone-0 build / flash / terminal steps
    ├── tangnano20k.cst        pin constraints (verified)
    └── rtl/
        ├── uart.v            8N1 UART (TX+RX)
        └── top.v             Milestone-0 top: echo + heartbeat
```

## How we work

- RTL + testbenches + co-sim harness written here; board bitstreams flashed and
  reported from hardware.
- **Sim green before hardware** — never debug unproven RTL and an unproven board
  at once.
- Small commits into `fpga/`, docs alongside, emulator stays the spec.
