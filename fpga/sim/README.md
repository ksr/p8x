# P8X-FPGA simulation — Milestone 1 co-sim

Proves the RTL CPU core matches the C emulator (the golden model) **cycle for
cycle**, entirely in simulation — no board needed.

## How it works

Both the RTL and the emulator emit one **canonical state line per cycle**:

```
<cyc> <IR> <stp> <A> <B> <T> <T2> <P0> <P1> <P2> <P3> <P4> <P5> <fC fZ fN fV>
```

- Emulator: `p8xemu -T` → this line on **stderr** (`emulator/p8xemu.c`).
- RTL: `tb_p8x.v` built with `-DP8X_TRACE` → the same line on **stdout**
  (`p8x_cpu.v` `$display`).

`run.sh` runs both on the same monitor-ROM boot and `diff`s the traces. Identical
traces ⇒ the RTL datapath, ALU, shifter, flags, sequencer, and condition mux all
match the emulator. A divergence prints the exact cycle and the differing state.

## Run it

```bash
./run.sh [CYCLES]      # default 20000
```

Needs a C compiler (builds the emulator) and **iverilog** (from oss-cad-suite —
the same suite you install for the board). Without iverilog, `run.sh` still
builds the emulator golden trace and tells you what's missing.

Output: `PASS: RTL matches emulator for N cycles`, or a `DIVERGENCE` dump.

## Files

| File | What |
|------|------|
| `mk_ucode_mem.py` | 4 ROM images → `ucode.hex` (8192 × 32-bit `$readmemh`) |
| `tb_p8x.v` | testbench: run N cycles, emit the canonical trace |
| `run.sh` | build + run + diff RTL vs `p8xemu -T` |
| `../rtl/p8x_cpu.v` | the CPU core (transliteration of the emulator microcycle) |
| `../rtl/p8x_soc.v` | CPU + microcode ROM + 64K memory + minimal sim I/O |

Generated files (`work/`, `*.hex`, `*.trace`, `*.vvp`) are git-ignored.

## Status

- Microcode-BRAM generator: **verified** (0 mismatches vs the emulator word
  formula).
- Emulator `-T` machine trace + harness: **verified** (golden trace generated).
- RTL (`p8x_cpu.v`, `p8x_soc.v`, `tb_p8x.v`): **written, hand-reviewed, not yet
  simulated** — no local Verilog toolchain. First `run.sh` under oss-cad-suite
  will either PASS or point at the first divergence to fix. Expect to iterate a
  few rounds here; that iteration *is* Milestone 1.

## Boot is deterministic (why the diff is valid)

With no console input, `$FF04` reads `0x02` (TDRE set, RDRF clear) on both sides,
so the monitor's early boot — before it ever waits on a key — is fully
deterministic. That's the window this co-sim checks. Interactive I/O and the
disk come in later milestones with their own harnessing.
