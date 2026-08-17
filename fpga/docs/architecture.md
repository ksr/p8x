# P8X-FPGA architecture (design notes)

Same microarchitecture as the TTL P8X; the physical backplane becomes internal
wiring. This described the *plan* until Milestone 4; it now describes what was
actually built and runs.

## Module hierarchy (as built)

There are two top levels over one shared core. The CPU is deliberately **flat** —
the TTL cards map to regions of `p8x_cpu.v`, not to separate modules — because the
co-sim diffs its architectural state against the emulator cycle for cycle, and
splitting it would buy structure at the cost of that one-to-one correspondence.

```
SIMULATION                              BOARD
fpga/sim/tb_p8x.v                       fpga/tang-nano-20k/rtl/p8x_top.v
└── fpga/rtl/p8x_soc.v                  ├── fpga/rtl/p8x_cpu.v      ← SHARED
    ├── fpga/rtl/p8x_cpu.v   ← SHARED   ├── uart_tx / uart_rx  (rtl/uart.v)
    └── fpga/rtl/gfx.v       ← SHARED   ├── fpga/rtl/gfx.v         ← SHARED
                                        ├── fpga/rtl/video_rgb.v   480x272 scanout
                                        └── rtl/cf_sd.v   $FF10-$FF17 task file
                                            └── rtl/sd_spi.v   microSD over SPI
```

`p8x_cpu.v` is the machine and is the **only** file both paths share; it is what
the co-sim verifies. `p8x_soc.v` is **simulation-only** — async-read arrays and
modelled I/O, so a microcycle is one clock. The board cannot do that (block RAM is
synchronous and a microcycle needs two *dependent* reads), so `p8x_top.v` runs
three fabric phases per microcycle and gates the core with its `cen` input.

Inside `p8x_cpu.v`, the TTL cards appear as these regions:

| TTL card | Where it lives in `p8x_cpu.v` |
|----------|-------------------------------|
| control / microcode | `uc_addr = {cond, stp, IR}`, the step/`stp` sequencer, the condition mux off the previous word's `FCOND` |
| ALU card | the 74181 model (`alu181`-equivalent logic), the two-stage shifter, sign-bit V |
| register bank | `A`, `B`, `T`, `T2` and `P[0:5]` |
| pointers / address | `PSEL` picks which `P[]` drives `mem_addr` — there is no MAR |
| bus (tri-state) | the `DOE` **mux** into `bus`, and `DLD` as latch enables |

The microcode ROM and the 64K memory are **not** in the CPU: each SoC supplies
them, because their implementation is exactly what differs between the two
(plain arrays in simulation, BRAM with a phase sequencer on the board).

The key structural change from TTL: the shared tri-state data bus with `DOE`
driver-enables becomes a **mux** — FPGAs have no internal tri-state. `DLD` becomes
latch enables, `PSEL` an address-source mux. The horizontal microcode word is
unchanged and drives the datapath control lines directly (no instruction decode —
that is what the microcode is for).

## Memory map (identical to the TTL build — see `generators/gen_memmap.py`)

| Range | Size | Contents | FPGA realization |
|-------|------|----------|------------------|
| `$0000–$1FFF` | 8 KB | firmware ROM (monitor) | BRAM, **initialized** from the ROM image |
| `$2000–$FEFF` | ~56 KB | RAM: OS + scratch + TPA (`$6A00`) | BRAM, uninitialized |
| `$FF00–$FFFF` | 256 B | memory-mapped I/O | address-decoded to peripherals |

Address decode: `$FF00–$FFFF` → I/O; else BRAM (the ROM/RAM split is just which
BRAM region and whether writes are allowed below `$2000`).

### Peripheral decode (`$FF00` page)

| Addr | Reg | Peripheral |
|------|-----|-----------|
| `$FF04` | ACIAS | 6850 status (rd) / control (wr) |
| `$FF05` | ACIAD | 6850 data |
| `$FF10` | CFDATA | CF/IDE task file (data) |
| `$FF11` | CFFEAT | feature |
| `$FF12` | CFSCNT | sector count |
| `$FF13–$FF15` | CFLBA0–2 | LBA bytes |
| `$FF16` | CFHEAD | `$E0` = LBA mode, drive 0 (bit0 = device select) |
| `$FF20–$FF23` | GX0 GY0 GX1 GY1 | graphics coordinates (low bytes) |
| `$FF24` | GCOL | pen 0–3 |
| `$FF25` | GCMD | write executes a drawing command |
| `$FF26` | GSTAT | bit7 BUSY, bit0 ERR |
| `$FF27` | GDATA | IDENT stream / POINT result |
| `$FF28` | GPARM | scalar argument (CIRCLE radius) |
| `$FF29–$FF2C` | GX0H… | coordinate high bytes |
| `$FF2D/$FF2E` | GID0/GID1 | `'P'`/`'G'` presence signature |
| `$FF17` | CFCMD/CFSTAT | command (wr) / status (rd) |

- **ACIAS/ACIAD** are presented by a shim inside `p8x_top.v` over `uart_tx`/
  `uart_rx`, so the existing serial driver is unchanged; baud is generated in the
  core (DIV=234 @ 27 MHz for 115200), not by an ACIA register model.
- **`cf_sd.v`** presents the CF task-file registers `$FF10–$FF17` and translates a
  sector read/write into SD-over-SPI via `sd_spi.v`, so BIOS `CFRDSEC`/`CFWRSEC`
  work unchanged. Only device 0 is fitted (one slot); the DEV bit selecting
  device 1 reads back `$FF`, which the firmware's bounded waits time out.
  One deliberate difference from the emulator: **BSY is asserted** for the
  duration of a transfer, because a real card takes milliseconds where the
  emulator is instantaneous.

## Microcode BRAM

`microcode/genucode.py` emits the four 8 K×8 EEPROM images
(`rom/p8x-ucode0..3.bin`) = one **8192 × 32-bit** control store = 256 Kbit.
`fpga/sim/mk_ucode_mem.py` combines them into a `$readmemh` file for simulation.

It did **not** fit on the board: 256 Kbit of microcode plus 512 Kbit of memory
needs 47 BSRAM blocks and the GW2AR-18 has 46. All 32 control-word bits are used,
so nothing could be shaved off the width — but only 88 of the 256 opcode
encodings exist and all 168 undefined ones hold the same word. So the board build
squeezes IR through a combinational 256-entry map into a 7-bit index (88 opcodes
plus one shared undefined slot), halving the store to **4096 × 32**:
`fpga/tang-nano-20k/mk_compact_ucode.py`, which re-verifies both properties and
refuses to emit anything if either stops holding. Result: 40/46 blocks with the
full 64K map, and no SDRAM controller needed.

## Graphics (`gfx.v` + `video_rgb.v`)

`gfx.v` is the device: register file, drawing engine, framebuffer, palette. It is
**shared verbatim** by the simulation and the board, like `p8x_cpu.v`, and it is a
transliteration of the `gpu_*` functions in `emulator/p8xemu.c` — the emulator is
the golden model, so a cleverer Bresenham that lights a different pixel is a bug.

**240×136 at 2 bits per pixel**, every logical pixel drawn 2×2 on the 480×272
panel. That geometry is forced by block RAM, not chosen: the Tang Nano has 6 spare
BSRAM blocks (12288 bytes) and the panel's own resolution needs 16320 at even one
bit per pixel.

The framebuffer uses **one port, time-shared**. True dual port halves a Gowin
block's usable depth, so 8160 bytes would cost 8 blocks rather than 4 and the
design would not place. The scanout needs a byte only once per eight panel pixels,
so it takes the port for a cycle and the engine holds.

`video_rgb.v` generates the panel timing (560×297 at 9 MHz = 54.11 Hz, DE-only —
this panel has no HSYNC/VSYNC) and scans the framebuffer out with 2× doubling.
9 MHz is 27/3, the same divider the CPU runs on, so **no PLL is needed**.

### Why the graphics is not cycle-diffed

Unlike the CPU, it cannot be. The emulator draws instantaneously and never raises
BUSY; the RTL takes thousands of clocks and does. Software that polls `GSTAT`
therefore reads different values on the two models **by design**, so their traces
diverge legitimately. What must agree is the **framebuffer**, and `fpga/sim/gfx.sh`
byte-compares it.

That leaves the mapping from framebuffer to panel untested by either — which is
how a shift-width bug that blanked half of every byte reached hardware.
`tang-nano-20k/sim/tb_scanout.v` covers it now.

## Co-sim harness (the workhorse test)

`emulator/p8xemu.c` is the golden model. The harness:

1. Loads the same program image into both the Icarus-built RTL sim and the C
   emulator.
2. Steps both one microcycle at a time.
3. Diffs architectural state after each step: PC, A, pointers/registers, flags
   (C/Z/N/V/IE), and any memory write (address + value).
4. Stops at the first divergence and reports the step, the signal, and both
   values.

Console I/O in sim is piped through the modeled UART so the monitor/OS can be
driven and its output checked. This is what lets Milestones 1–2 reach "OS boots"
entirely in simulation, before the board exists.

## Settled decisions

- **Sim tool: Icarus** (`iverilog -g2012`), decided at Milestone 1. Verilator was
  the earlier lean for speed, but the testbench is behavioral Verilog that Icarus
  runs directly, where Verilator would need a C++ harness wrapped around it. The
  traces are small and the runs are short, so simulation speed never became the
  constraint. Icarus also ships in the same oss-cad-suite bundle as the board
  flow, so it adds no extra dependency.
- **Co-sim granularity: microcycle-accurate.** Instruction-accurate was the
  planned starting point, but both sides already emit per-cycle state cheaply
  (`p8xemu -T` and `-DP8X_TRACE` in the testbench), and a per-cycle diff names the
  exact failing microcycle instead of just the instruction containing it.

## Open decisions (to settle as we build)

- **Milestone 5, clock-up.** 9 MHz today (27 MHz fabric / three phases). Fmax is
  ~50 MHz, so the headroom is real: overlap the two dependent reads by pipelining
  the microcode fetch a cycle ahead, drop to two phases, or raise the fabric clock
  with a PLL. Whatever changes, it must still diff clean against the emulator.
- **Milestone 5, IRQ.** `irq_set` is tied low in `p8x_top.v`. The core already
  implements the rev-C forcing-buffer entry ($08 injection, vector $0808,
  EI/DI/RTI) and `isa_test.asm` exercises it; it needs a real source wired up.

*(Settled: the SD image format is a P8XFS image written straight to the card —
`tools/p8xfs.py` builds one, and `fpga/tang-nano-20k/tools/imgload.asm` installs
it over the serial console when the host has no root.)*
