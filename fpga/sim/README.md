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
| `isa_test.asm` | directed all-88-opcode exerciser (assembled by `run.sh`) |
| `run.sh` | build + run + diff RTL vs `p8xemu -T`; `run.sh [CYCLES] [ROM]` |
| `../rtl/p8x_cpu.v` | the CPU core (transliteration of the emulator microcycle) |
| `../rtl/p8x_soc.v` | CPU + microcode ROM + 64K memory + minimal sim I/O |

Generated files (`work/`, `*.hex`, `*.trace`, `*.vvp`) are git-ignored.

## Status

- Microcode-BRAM generator: **verified** (0 mismatches vs the emulator word
  formula).
- Emulator `-T` machine trace + harness: **verified** (golden trace generated).
- RTL (`p8x_cpu.v`, `p8x_soc.v`, `tb_p8x.v`): **PASSES** — the co-sim matches the
  emulator cycle-for-cycle out to 200 000 microcycles of monitor boot, and across
  **all 88 opcodes** via `isa_test.asm`, on Icarus 13.0. The transliteration was
  correct on its first real execution; no RTL fix has been needed.

### Two payloads: the monitor boot, and the all-opcode exerciser

The monitor boot alone is a **narrow** test. 200 000 cycles of it cover no more of
the machine than 20 000 do — 12 of the 88 defined opcodes — because after printing
its prompt the monitor sits in the console-poll loop, and with `-N` no key ever
arrives. Raising the cycle count buys nothing.

`isa_test.asm` closes that gap with stimulus instead of cycles. It executes **all
88 opcodes** in `genucode.py`'s `OPC` table, choosing operands that move the flags
rather than merely executing: carry out (`$FF + 1`), borrow (`$00 - 1`), signed
overflow at both sign boundaries (`$7F + 1`, `$80 - 1`), zero, and carry-in for
`ROL`/`ROR`. Every branch is taken **and** not taken. The interrupt path is real —
it writes `$FF06` to raise an IRQ, vectors through `$0808`, and returns via `RTI`.

```bash
./run.sh 20000                  # monitor boot   -> PASS, 20000 cycles
./run.sh 60000 isa_test.asm     # all 88 opcodes -> PASS, 509 cycles
```

It ends in `HLT`, so both sides stop at the same cycle rather than one being
clipped to the other's length — check the two trace lengths match if you change it.

It is a **payload, not a self-checking test**: it asserts nothing itself. A wrong
ALU result or mis-set flag is caught because it makes the traces differ, naming
the exact microcycle. That also makes it the regression test for any future RTL
change — clock-up, BRAM swap, the Milestone-5 IRQ work — which must still diff
clean against the emulator.

Still not covered: sustained console I/O (needs deterministic scripted input on
both sides — the Milestone-2 ACIA work) and the SD/disk path.

## Boot is deterministic (why the diff is valid)

With no console input, `$FF04` reads `0x02` (TDRE set, RDRF clear) on both sides,
so the monitor's early boot — before it ever waits on a key — is fully
deterministic. That's the window this co-sim checks. Interactive I/O and the
disk come in later milestones with their own harnessing.
