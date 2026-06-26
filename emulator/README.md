# emulator/

`p8xemu.c` — a cycle-accurate P8X emulator. It does not hard-code instruction
behavior; it loads the microcode images `u0–u3.bin` and steps the same control
word the real hardware does, so it is a faithful model of the machine, not an
approximation.

## Build & run

```sh
make            # builds p8xemu and regenerates the microcode (u0-u3.bin)
./p8xemu [-t] [-l N] [-c disk.img] [-s NN] [-L] rom.bin
```

- `rom.bin` — the EEPROM image (origin `$0000`), e.g. the monitor or combined
  the monitor. The emulator expects `u0–u3.bin` in the current directory.
- `-c disk.img` — attach a CompactFlash image; models the 8-bit True IDE task
  file at `$FF10–$FF17`.
- `-s NN` — value the I/O card switches present at `$FF00` (hex or decimal, e.g.
  `-s 0xA5`); defaults to 0. So `PEEK(65280)` / monitor reads see it.
- `-L` — trace LED writes: each change to `$FF02` prints to stderr as
  `[LED $FF02] $NN  *.*..*.*` (`*` = lit). The final LED byte is always shown in
  the halt status line.
- `-t` — instruction trace. `-l N` — halt after N cycles.
- The 6850 ACIA is wired to stdin/stdout, so the monitor/OS/BASIC are interactive.

On halt it prints `PC/A/B/...` register state (`A=00` is the convention for "test
passed" in the self-checking suites).

## Tests

```sh
make test        # everything below
make test-isa    # per-instruction self-check (halts A=00 on success)
make test-cf     # monitor format/boot against the CF model
make test-os     # P8X/OS boot + shell on flat and v2 volumes
make test-basic  # monitor smoke test, disk BASIC (B), SAVE/LOAD
make test-io     # switch input (-s) -> $FF00 and LED writes ($FF02, -L)
```

Test scripts and fixtures live in [`test/`](test/); their build artifacts
(`*.bin`, `*.img`, `*.hex`, …) are gitignored.

## Other targets

`make rom` builds the persistent burnable image set into [`../rom/`](../rom/).

---

# Theory of operation

This section explains, in detail, *how `p8xemu.c` works* — and therefore how the
real P8X works, because the emulator is a direct model of the hardware rather
than a behavioral re-implementation. If you understand this file you understand
the machine.

## 1. The central idea: a microcode interpreter

The P8X is a **microcoded** CPU. It has no hard-wired instruction logic; instead
every machine instruction is carried out by a short sequence of **micro-steps**,
and each micro-step is one 32-bit **control word** read from a control store
(four 28C64 EEPROMs on the real control card). The control word's bits are wired
directly to the datapath's enables, selects, and load lines.

The emulator does exactly the same thing. It loads the *same* four ROM images
(`u0.bin`…`u3.bin`, produced by [`../microcode/genucode.py`](../microcode/genucode.py))
that get burned to the hardware, and its main loop reads one control word per
iteration and applies its bits to a modeled datapath. There is no `switch` on
opcode that "implements ADD"; ADD happens because the microcode for opcode
`$09` drives the ALU select lines to the add function across a couple of steps.
**Emulator and silicon cannot drift, because they execute the identical control
store.** The only things the C file hard-codes are the *physical building blocks*
the control word commands: the 74181 ALU, the shifter, the register file, the
bus multiplexer, memory, and the I/O devices.

## 2. The micro-cycle

One pass of the `while(!halted && cycles<lim)` loop = one micro-step = one
hardware clock. Each pass does four things in order, mirroring a real clocked
datapath (combinational settle, then a clock edge that latches results):

1. **Form the micro-address** from current state and read the control word.
2. **Compute combinational results** — the ALU, the shifter, the next flags, and
   the value currently on the **bus** — from the *current* register contents.
3. **Commit on the (modeled) clock edge** — load whatever register/memory the
   control word selects from the bus, bump pointers, latch flags.
4. **Advance the micro-sequencer** — pick the next micro-step (or reset to step 0
   to fetch the next instruction).

## 3. The control store and the micro-address

The control store is addressed by a 13-bit micro-address built from three
fields (`int ad = IR | stp<<8 | cond<<12;`):

| Bits | Field | Meaning |
|------|-------|---------|
| 0–7  | `IR`   | the current opcode (instruction register) — 256 instructions |
| 8–11 | `stp`  | the micro-step counter, 0–15 within the instruction |
| 12   | `cond` | the **condition plane** (A12): selects taken vs not-taken microcode |

Each ROM is 8 KB = 2¹³, so the four ROMs together supply a 32-bit word at every
address. The word is reassembled little-endian across the four images:

```c
uint32_t cw = rom[0][ad] | rom[1][ad]<<8 | rom[2][ad]<<16 | rom[3][ad]<<24;
```

## 4. The 32-bit control word

Every micro-step is fully described by these fields (exactly the bit positions
the C decodes, which match `genucode.py`'s packing — the single source of truth):

| Bits | Field | Function |
|------|-------|----------|
| 0–3   | `DOE`   | **bus source** / output-enable — who drives the internal bus this cycle |
| 4–7   | `DLD`   | **load destination** — who latches the bus on the clock edge |
| 8–10  | `PSEL`  | pointer select: `P0`=PC, `P1`, `P2`, `P3`=SP, `P4`=PT (hidden scratch) |
| 11    | `PINC`  | post-increment the selected pointer |
| 12    | `PDEC`  | post-decrement the selected pointer |
| 13–16 | `ALUS`  | 74181 function select S3–S0 |
| 17    | `M`     | 74181 mode: 0 = arithmetic, 1 = logic |
| 18    | `CINP`  | 74181 carry-in **pin** (active-low at the silicon) |
| 19    | `SH0`   | shifter stage 1 enable (shift **left**) |
| 20    | `SH1`   | shifter stage 2 enable (shift **right**) |
| 21    | `LDF`   | latch C/Z/N/V from the ALU+shifter result this cycle |
| 22–24 | `FCOND` | condition code that selects the **next** cycle's condition plane |
| 25    | `URST`  | micro-reset: next step = 0 (i.e. the instruction retires → fetch) |
| 26    | `HALT`  | stop the machine |
| 27    | `LDZN`  | set Z and N from the bus byte (used by load/move ops) |
| 28    | `SHCIN` | shift-in bit = current C (rotate-through-carry); else 0 |
| 29    | `SETC`  | force C = 1 (`SEC`) |
| 30    | `CLRC`  | force C = 0 (`CLC`) |
| 31    | `BSEL`  | ALU B-input mux: 0 = `B` register, 1 = `T` register |

## 5. The datapath and the internal bus

Registers modeled: accumulator `A`, operand `B`, temporaries `T`/`T2`, the
instruction register `IR`, and the five 16-bit pointers `P[0..4]`
(`P0`=program counter, `P1`/`P2` general, `P3`=stack pointer, `P4`=`PT` hidden
scratch used by call/return microcode).

Exactly one source drives the bus per cycle (`DOE`); exactly one destination
latches it (`DLD`). `addr = P[PSEL]` is the address presented to memory.

| `DOE` | bus source | | `DLD` | latches bus into |
|-------|-----------|---|-------|------------------|
| 1 | `A` | | 1 | `A` |
| 2 | `B` | | 2 | `B` |
| 3 | `T` | | 3 | `T` |
| 4 | `T2` | | 4 | `T2` |
| 5 | ALU+shifter result `r` | | 5 | flags (C/Z/N/V from bus bits 0–3) |
| 6 | flags packed as C,Z,N,V in bits 0–3 | | 6 | `IR` (instruction fetch) |
| 7 | `memrd(addr)` | | 7 | `memwr(addr, bus)` |
| 8 | `addr` low byte | | 8 | `P[PSEL]` low byte |
| 9 | `addr` high byte | | 9 | `P[PSEL]` high byte |
| 0 | idle (`0xFF`) | | 0 | nothing |

A memory→register move is thus two coordinated fields in one word: `DOE=7`
(read `[addr]`) and `DLD=1` (latch into `A`), with `PSEL` choosing which pointer
addresses memory and `PINC` optionally walking it — that is the `LDA (P1)+`
primitive.

## 6. The ALU (74181), flags, and shifter

`alu181()` models a 74181 with **active-high** data. It computes the arithmetic
result for the chosen function `ALUS`, adds the logical carry-in
(`c = !CINP`, because the pin is active-low), and reports the **conventional**
carry-out in `*cn4`: `C=1` means carry (after ADD) or "no borrow / A≥B" (after
SUB/CMP) — this rev-B convention is what the firmware's `JC`/`CMP` rely on. The
carry chain is computed **regardless of `M`**, so a logic op still latches the
carry the silicon would (a deliberate fidelity detail). When `M=1` the function
table switches to the bitwise-logic column.

The **shifter** is two stages fed by the ALU result `f`: stage 1 (`SH0`) shifts
left, stage 2 (`SH1`) shifts right. The bit shifted out is captured; with
`SHCIN` the bit shifted *in* is the current carry (rotate through carry),
otherwise 0. The final datapath result `r` is what `DOE=5` puts on the bus.

Flag updates at the clock edge:
- `LDF` → latch all four flags from this cycle's results: `C` = shifted-out bit
  for shift ops else the ALU carry-out; `Z` = (`r`==0); `N` = bit 7 of `r`;
  `V` = signed overflow.
- else `LDZN` → set only `Z`/`N` from the **bus byte** (so a plain load reflects
  the value moved).
- `SETC`/`CLRC` force `C` independently (the `SEC`/`CLC` instructions).

**V (signed overflow)** is derived by the sign-bit method, matching the ALU
card's XOR+AND nets exactly: `V = (A7 ^ F7) & (A7 ^ B7 ^ isADD)`, where `F7` is
the raw (pre-shifter) result sign and `isADD = ~ALUS2`. It is computed every op
but only *meaningful* after ADD/SUB/CMP — which is exactly where the signed
branches are documented.

## 7. The micro-sequencer and conditional branching

After the commit, the sequencer chooses the next micro-step:

```c
stp = URST ? 0 : (stp+1)&15;
```

`URST` ends an instruction (next address has `stp=0`, so the next fetch reads a
fresh opcode into `IR` via `DLD=6`). Otherwise the step counter simply advances.

**Conditional execution is pipelined.** The `FCOND` field of the word *currently*
in the pipeline selects the condition plane (ROM A12) used for the *next*
look-up — so the emulator remembers it in `prev_fcond` and evaluates it at the
top of the next loop:

| `FCOND` | condition | used by |
|---------|-----------|---------|
| 0 | false | (fall through) |
| 1 | true (unconditional) | `JMP`/`JSR` |
| 2 | `C` | `JC` / `BCP` |
| 3 | `Z` | `JZ` / `BZ` |
| 4 | `N` | (negative) |
| 5 | `V` | (overflow) |
| 6 | `N ^ V` | `BLT` / `BGE` (signed <) |
| 7 | `(N ^ V) \| Z` | `BLE` / `BGT` (signed ≤) |

The branch microcode places its two possible continuations on the `cond=0` and
`cond=1` planes; the condition simply routes the sequencer to one or the other,
so the hardware never "stalls" to decide.

## 8. Reset

```c
P[0]=0; P[1]=P[2]=0; P[3]=0xFEFF; P[4]=0; stp=0; IR=0;
```

PC is forced to `$0000` (the reset vector — a `JMP` to the monitor cold start),
the stack pointer starts at `$FEFF` (top of RAM, growing down), and step 0 with
`IR=0` begins the first fetch.

## 9. Memory map and I/O

```
0000–3FFF  ROM   (16K, decoded from the EEPROM image)
4000–FEFF  RAM   (48K: 2×62256, $4000–7FFF and $8000–FEFF)
FF00–FFFF  I/O
```

`memrd`/`memwr` implement the decode. Writes below `$4000` are refused with a
warning (you can't write ROM). The I/O page:

| Addr | R/W | Device |
|------|-----|--------|
| `$FF00` | R | I/O-card switches — value set with `-s` |
| `$FF02` | W | LEDs — traced with `-L` |
| `$FF04` | R | 6850 ACIA status: bit1 `TDRE` (always ready), bit0 `RDRF` (key waiting) |
| `$FF05` | R/W | ACIA data: read = next console byte, write = transmit |
| `$FF06` | W | raise a maskable IRQ (models an external device, rev C) |
| `$FF10–$FF17` | R/W | CF-IDE task file (only when `-c` attaches an image) |

## 10. The CompactFlash model

When `-c disk.img` is given, `$FF10–$FF17` model a CompactFlash in **8-bit True
IDE** mode, matching the driver in `firmware/p8xmon.asm`. The firmware writes the
24-bit LBA (`$FF13–$FF15`), sector count/head, then a command to `$FF17`, polls
the status register for `BSY`/`DRQ`, and streams 512 bytes through the data port
`$FF10`. The model implements that handshake: **`BSY` is never asserted** (the
host-side transfer is instantaneous), and `DRQ` is raised while a 512-byte buffer
is draining/filling and dropped when it empties. Commands handled: `SET FEATURES`
(`$EF`), `IDENTIFY` (`$EC`, returns a byte-swapped model string in words 27–46
for the monitor's `I` command), `READ SECTORS` (`$20`), `WRITE SECTORS` (`$30`).
The image is a flat file of 512-byte sectors at `LBA×512`; a missing file is
created and zero-filled to 256 sectors.

## 11. Interrupts (rev C)

Three pieces model the maskable-interrupt path:

- **`IE`** — interrupt-enable latch. It is *not* a microcode bit; it is set/cleared
  by an **opcode decode** as the instruction retires (`URST`): `EI`/`RTI`
  (`IR=$02`/`$04`) set it, `DI` (`IR=$03`) clears it. This mirrors the control
  card's discrete decode.
- **`irq_pending`** — raised when a device writes `$FF06`.
- **The forcing buffer** — at fetch (`stp==0`, `DOE==7`) with `IE` set and an IRQ
  pending, the buffer overrides the memory read and injects opcode **`$08`** onto
  the bus, then acknowledges the interrupt (`irq_pending=0; IE=0`, masking nesting).
  While the `$08` micro-routine then runs with an idle `DOE`, the buffer keeps
  driving `$08`, so the two pointer-load micro-steps build `P0 = $0808` — the
  ROM interrupt vector. `RTI` later re-enables `IE` and returns.

## 12. Console / ACIA host integration

The 6850 ACIA is bridged to the host's stdin/stdout so the monitor, OS, and
BASIC are interactive:

- **Interactive (a TTY):** the terminal is put in raw mode — `ICANON`/`ECHO` off
  (the firmware echoes), and `ICRNL` off so **Enter arrives as CR**, matching the
  hardware serial line. A one-character lookahead (`peeked`) lets the `RDRF`
  status read and the data read stay consistent.
- **Non-blocking RX with idle-block:** `$FF04` RX-ready must never block, because
  the same status register carries `TDRE`, which `PUTC` polls before every
  transmitted byte — a blocking status read would freeze all output until a key
  is pressed. So RX-ready is non-blocking; but to keep an idle prompt from
  spinning the host at 100% CPU, after `RX_SPIN` (4000) consecutive "no key, no
  output" polls it blocks for a single key. Any console output (`$FF05` write)
  resets that counter, so transmit and bulk output never block.
- **Batch (piped stdin):** RX-ready uses `select()`, reads consume the stream,
  and EOF exits cleanly — which is how the test scripts drive the machine.

The cycle cap (`-l`, default 200M) bounds batch runs; an interactive session
sets it to unlimited.

## 13. Fidelity summary

**Exact:** instruction semantics (same control store as hardware); the 74181
function set and conventional-carry convention; V by the card's sign-bit nets;
the two-stage shifter and rotate-through-carry; pipelined conditional branching;
the reset vector and stack origin; the CF True-IDE register handshake; switch and
LED I/O.

**Idealized (timing only, not behavior):** one host loop iteration ≈ one clock,
so the cycle count is a micro-step count, not wall-clock nanoseconds; CF
transfers complete instantly (`BSY` never set); propagation delays, refresh, and
bus capacitance are not modeled. None of these affect the values a program
computes — they are exactly why the emulator is trusted as the reference oracle
for the firmware and the differential compiler tests.
