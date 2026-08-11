# P8X-FPGA architecture (design notes)

Same microarchitecture as the TTL P8X; the physical backplane becomes internal
wiring. This is the plan we build to in Milestones 1+ — not final RTL yet.

## Module hierarchy (TTL card → RTL module)

```
p8x_top
├── clk_reset          PLL + power-on reset            (board glue)
├── cpu_core
│   ├── sequencer      ← control/microcode card: steps microwords, next-uaddr
│   ├── ucode_rom      ← 4× 28C64 → ONE BRAM, 8192 × 32-bit, init from genucode
│   ├── alu            ← ALU card: T-operand ops, V + N^V, carry-coupled shifter
│   ├── regfile        ← register-bank card
│   ├── pointers       ← PSEL: which pointer drives the 16-bit address
│   └── busmux         ← DOE/DLD as MUX selects (no tri-state on FPGA)
├── memory             ← memory card: 64 KB in BRAM (ROM region init from monitor)
├── uart_6850          ← I/O card ACIA, wrapped to the 6850 register map
├── sd_disk            ← CF card → SD-over-SPI behind the BIOS block interface
└── irq_ctrl           ← IRQ enable/pending latches (backlog #26 — trivial in RTL)
```

The key structural change from TTL: the shared tri-state data bus with `DOE`
driver-enables becomes a **mux** — `data_bus = mux(doe_sel, {alu_out, mem_out,
reg_out, …})`. `DLD` → latch enables, `PSEL` → address-source mux. The horizontal
microcode word is unchanged and drives the datapath control lines directly (no
instruction decode — that is what the microcode is for).

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
| `$FF17` | CFCMD/CFSTAT | command (wr) / status (rd) |

- **`uart_6850`** presents ACIAS/ACIAD so the existing serial driver is unchanged;
  baud is generated in the core (DIV=234 @ 27 MHz for 115200), not by the ACIA
  register model.
- **`sd_disk`** presents the CF task-file registers `$FF10–$FF17` and internally
  translates a sector read/write into SD-over-SPI, so BIOS `CFRDSEC`/`CFWRSEC`
  work unchanged. The dual-drive DEV bit (`CFHEAD` bit 0) maps to two SD images
  or is stubbed to drive 0 initially.

## Microcode BRAM

`microcode/genucode.py` already emits the four 8 K×8 EEPROM images
(`rom/p8x-ucode0..3.bin`) = one **8192 × 32-bit** control store = 256 Kbit. On the
Tang Nano's ~800 Kbit BRAM this initializes directly from a `.mem`/`.hex` (a small
addition to genucode: emit a combined-word init file). Together with the 8 KB ROM
(64 Kbit) and 64 KB memory (512 Kbit) the total ≈ 768 Kbit fits comfortably.

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

- SD image format: reuse a P8XFS image written by `tools/p8xfs.py` directly onto
  the SD card.
