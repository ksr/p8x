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

**First, once:** the microcode images `u0-u3.bin` are build products and are not
in the repo, so a fresh clone has to make them before anything here works.

```bash
cd emulator && make        # from the repo root
```

Then, from this directory:

```bash
./run.sh [CYCLES]      # default 20000
```

Needs a C compiler (builds the emulator) and **iverilog** (from oss-cad-suite —
the same suite you install for the board). Without iverilog, `run.sh` still
builds the emulator golden trace and tells you what's missing; without the
microcode images it tells you to run the `make` above.

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
| `console_in.txt` | scripted keystrokes for the driven-monitor run (LF → CR) |
| `cf_id.txt`, `boot_in.txt` | CF scripts: IDENTIFY, and boot the OS from disk |
| `run.sh` | build + run + diff; `run.sh [CYCLES] [ROM] [RXSCRIPT] [CFIMAGE]` |
| `console.sh` | **interactive** console; `console.sh [ROM] [CFIMAGE]` |
| `gfx.sh` | RTL drawing engine vs the emulator, **frame by frame** |
| `tb_gfx.v` | runs a payload and dumps the framebuffer as a PPM |
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

It ends in `HLT`, so both sides stop at the same cycle rather than one being
clipped to the other's length — check the two trace lengths match if you change it.

It is a **payload, not a self-checking test**: it asserts nothing itself. A wrong
ALU result or mis-set flag is caught because it makes the traces differ, naming
the exact microcycle. That also makes it the regression test for any future RTL
change — clock-up, BRAM swap, the Milestone-5 IRQ work — which must still diff
clean against the emulator.

```bash
./run.sh 20000                            # monitor boot   -> PASS, 20000 cycles
./run.sh 60000 isa_test.asm               # all 88 opcodes -> PASS, 509 cycles
./run.sh 200000 "" console_in.txt         # driven monitor -> PASS + console diff
```

### Milestone 2: the ACIA and a driven console

`$FF04`/`$FF05` are now modelled properly on both sides, and the third command
above drives the monitor with scripted keystrokes and additionally diffs its
**console output**.

The model is deliberately timing-free, because that is what makes it
co-simulable: **RDRF is simply "the script still has a byte"**, and exactly one
byte is consumed per `$FF05` read. There is no baud rate and no arrival race, so
both implementations step identically by construction.

The subtlety is *when* a read consumes. The emulator consumes inside `memrd()`,
so the RTL keys off `mem_rd` — a new CPU output asserted on the microcycles that
source the bus from memory (`doe == 7`). Keying off `mem_addr == $FF05` instead
would double-consume, because the address can linger across microcycles.

`console_in.txt` is plain text and **newlines are translated to CR** (what the
monitor's line reader expects), so scripts stay readable:

```
?
D 0100
E 3000
.
```

That drives the banner, the help text, a 256-byte hex dump of the BIOS jump
table, and an examine/modify session — 2380 bytes of console output, byte-identical
between the two models, and 44 of 88 opcodes along the way.

### CF disk: the OS boots in simulation

`$FF10..$FF17` (8-bit True IDE task file) is modelled too, mirroring `p8xemu.c`
command for command: `$EF` SET FEATURES, `$EC` IDENTIFY, `$20` READ SECTORS,
`$30` WRITE SECTORS, BSY never asserted, absent drive reads `$FF`. Feature and
LBA writes latch into **both** devices (shared task file); the `$FF16` DEV bit
picks who executes. The model lives in the testbench, which owns the image file
and reads sectors on demand with `$fseek` — a 6 MB image will not fit in a
Verilog array.

```bash
./run.sh 300000  "" cf_id.txt   os/run-disk.img   # I -> CF OK: P8X-CF EMULATOR
./run.sh 2000000 "" boot_in.txt os/run-disk.img   # B -> boots P8X/OS
```

The disk is **copied into `work/`**, so neither mode can touch your real image.
Whether writes take effect then depends on which mode you are in, and the split
is deliberate:

| | disk opened | WRITE SECTORS |
|---|---|---|
| `run.sh` (co-sim) | read-only | accepted, **discarded** |
| `console.sh` (interactive) | read-write (`+cfrw`) | **flushed to `work/disk.img`** |

The co-sim must not mutate the image it is diffing — a run that changed the disk
would not be reproducible, which is the whole point of the harness. But the
interactive console has no such constraint, and discarding writes there was
actively misleading: `SAVE` in BASIC printed `Saved` (truthfully — the CF model
reported success) and the file was gone the moment you left. Your changes live in
`work/disk.img` and are replaced next time `console.sh` starts; copy it out to
keep them.

The boot run gets you this, byte-identical on both sides:

```
* B

P8X/OS v1.0
/>
```

and `console.sh "" os/run-disk.img` lets you go further by hand — `pwd`, `dir`,
loading the 16 KB `/bin/dir.bin` off the simulated disk and listing the real
filesystem. Note the shell wants **lowercase** command names on this image.

Still not covered: SD-over-SPI (Milestone 4 replaces CF-IDE with different
silicon behind the same BIOS block API), and any peripheral behaviour that
depends on real timing rather than these polled, timing-free models.

### Graphics: a frame diff, not a cycle diff

```bash
./gfx.sh            # runs the graphics payloads on both models, cmp's the frames
```

> **RED TODAY.** The RTL misses two of the nine commands the payload issues
> (`SETPAL` and `BOXFILL`); the CPU never writes `$FF25` for them at all. Left
> failing deliberately — it was green for days over payloads that drew nothing.
> Details in the banner at the top of [`../../BACKLOG.md`](../../BACKLOG.md).

The drawing engine is verified by byte-comparing the **framebuffer** the RTL
produces against the one `p8xemu -g` writes, not by diffing CPU traces. That is
deliberate: the emulator draws instantaneously and never raises BUSY, while the
RTL takes one clock per byte for `CLS` and about seven and a half per pixel
otherwise. A program
that polls `GSTAT` therefore reads different values on the two models **by
design**, so a cycle diff would report a divergence that is not a fault.

What must agree is the picture, and it does — to the byte, for both payloads.

This is also why the payloads call `GWAIT` before every command. The device draws
in real time and **a command issued while another is running aborts it**; the wait
costs nothing on the emulator (never busy) and is essential on the RTL, so one
payload is correct on both. Without it the RTL renders a handful of scattered
pixels while the emulator looks perfect — the first thing this test caught.

### A hazard worth knowing about

`p8xemu` used to drop its cycle cap whenever `isatty(0)` — correct for
interactive typing, catastrophic with `-T`, which writes a trace line per cycle.
A `run.sh` launched from a terminal therefore ignored `-l` and streamed until the
disk filled: 80 GB in one sitting here, and because an orphaned emulator still
held the file open, `rm` did not even give the space back until the process was
killed. `-N`/`-i` now suppress interactive mode entirely and an explicit `-l` is
always honoured; `run.sh` additionally aborts if the trace is longer than the
cycle count. If a run ever dies oddly, check `pgrep p8xemu` before anything else.

## Driving it by hand

```bash
./console.sh                 # monitor, live, on the RTL
./console.sh isa_test.asm    # any other ROM
```

You get a real terminal into the CPU running inside Icarus: type `?`, `D 0100`,
`E 3000`, whatever the monitor takes. **Ctrl-D or Ctrl-C quits.**

The terminal is put in `-icanon -echo -icrnl` — deliberately *not* `stty raw`,
which also clears `ISIG` and would swallow Ctrl-C, leaving no way out but killing
the process from another terminal. Ctrl-D is handled in the testbench, because a
non-canonical tty delivers it as a plain `0x04` byte rather than EOF. And the
script does not `exec` vvp, so its EXIT trap still runs and restores your
terminal. If a session is ever orphaned anyway: `pkill -9 -f 'vvp console.vvp'`
(vvp ignores SIGTERM), then `stty sane`. The script puts the terminal
in raw mode so keystrokes arrive immediately and are echoed once (by the monitor,
not the shell), and restores it on exit.

This is **not** the co-sim — a live console is not reproducible, so nothing is
diffed. `run.sh` verifies; `console.sh` lets you poke.

How it gets a keystroke is worth knowing, because it is the one place the two
consoles differ. Verilog has no non-blocking stdin read, so the testbench copies
the emulator's rule: only after the machine has polled `$FF04` `SPIN` times with
no output in between — i.e. it is genuinely sitting at a prompt — does it block on
`$fgetc`. Any output resets the counter, so bulk printing never stalls waiting for
a key you have not typed.

## Boot is deterministic (why the diff is valid)

With no console input, `$FF04` reads `0x02` (TDRE set, RDRF clear) on both sides,
so the monitor's early boot — before it ever waits on a key — is fully
deterministic. That's the window this co-sim checks. Interactive I/O and the
disk come in later milestones with their own harnessing.
