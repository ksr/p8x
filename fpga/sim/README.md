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

### Why the emulator runs with `-N`

`p8x_soc.v` models `$FF04` (ACIA status) as a constant `0x02` — TDRE set, RDRF
clear, "ready to send, no key ever". The emulator's `$FF04` instead reports real
console state, and *that depends on what stdin is*: an interactive TTY with no
keystrokes reports not-ready (`0x02`, matching), but a redirected or closed stdin
is at EOF, which `select()` calls readable, so RDRF comes back set (`0x03`). The
same command then passes from a terminal and fails from a script or CI, diverging
at the first ACIA status poll with a one-bit difference in `A`.

`-N` forces console RX permanently empty, which is exactly the RTL's model. The
diff is now identical regardless of how stdin is wired.

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
- RTL (`p8x_cpu.v`, `p8x_soc.v`, `tb_p8x.v`): **PASSES** — the co-sim matches the
  emulator cycle-for-cycle out to 200 000 microcycles, on Icarus 13.0. The
  transliteration was correct on its first real execution; no RTL fix was needed.

### Coverage caveat — the PASS is narrower than the cycle count suggests

200 000 cycles cover **no more of the machine than 20 000 do**: 19 distinct
opcodes, 13 microcycle steps, 114 distinct PC values, max PC `$0f98`. The monitor
boots, prints its prompt, then sits in the console-poll loop — and with `-N` no key
ever arrives, so every additional cycle re-runs the same few microcycles. Raising
the cycle count buys nothing after boot.

So what is proven is the **boot path plus the idle loop**, over 19 opcodes. The
untested majority of the ISA — most ALU ops, the shifter, the signed branches, the
pointer modes, RTI/interrupts — has never been co-simulated. Closing that needs
stimulus, not more cycles:

- a directed ROM that exercises every opcode and flag case, run through the same
  trace-diff, or
- deterministic scripted console input (a fixed byte string fed identically to
  both sides) so the monitor can be driven past the prompt — which is the
  Milestone-2 ACIA modelling work anyway.

## Boot is deterministic (why the diff is valid)

With no console input, `$FF04` reads `0x02` (TDRE set, RDRF clear) on both sides,
so the monitor's early boot — before it ever waits on a key — is fully
deterministic. That's the window this co-sim checks. Interactive I/O and the
disk come in later milestones with their own harnessing.
