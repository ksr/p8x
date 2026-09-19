# PS/2 Card — Theory of Operation

> **Status: BUILT (rev A, 2026-09-19).** Standalone keyboard+mouse card, split
> back out of the (now parked) combined peripheral card. **The built design is the
> ATmega328 latch-bridge**, not the pure-TTL receiver that §3–§4 and §6 below
> describe — those sections are the ORIGINAL 2026-09-17 proposal, kept for the
> rationale and the register semantics (which are identical); see
> **§0 (built design)** for what `generators/gen_eagle.py` actually emits and
> `hardware/ps2-card/kicad/` for the board. The bus-visible behaviour — the exact
> `$FF58-$FF5F` window the emulator models and `lib_ps2` decodes — is the same
> either way. The parallel FPGA-fabric path (PS/2 hung off the Tang Nano 20K,
> level-shifted with a TXS0102 per port) is a DIFFERENT design, documented in
> [`fpga/tang-nano-20k/PS2-INTERFACE.md`](../../fpga/tang-nano-20k/PS2-INTERFACE.md).

The P8X design split for human input is deliberate and runs through the whole
project: **the hardware receives, the software understands.** Turning Set-2 scan
codes into ASCII (make/break, shift, caps) and 3-byte packets into (dx, dy,
buttons) is entirely `lib_ps2`'s job (see `man ps2`); the card only guarantees
"here is the next whole byte, and whether you missed one," which the emulator's
golden model matches byte-for-byte.

Two identical channels: **port A = keyboard**, **port B = mouse**.

## 0. Built design — ATmega328 latch-bridge

The built card (`CARDS["ps2-card"]` in `generators/gen_eagle.py`) hands the PS/2
protocol to an **ATmega328 (U13)** running in firmware — 5 V-native, open-drain in
software, so there is **no level translation anywhere** (the TXS0102 is only the
3.3 V FPGA path). The '328 does framing / parity / ready / overrun for both ports
and keeps four **74HC374** read latches (U7–U10 = `PSADAT`/`PSAST`/`PSBDAT`/`PSBST`)
loaded over its `MB0–7` bus; each latch tri-states onto D0–7 under its read strobe.
`PSLINE` (U11 74244) reads the four live PS/2 lines, and `PSID` (U12 74244) drives
the constant `$4B` (`'K'`) presence byte. Decode is local to the card (the parked
peripheral shared it): **U1 7430** detects the `$FFxx` page, **U2/U3 74138** turn
DOE=7→`-RD` and DLD=7→`-MEMW`, **U4 74688** window-compares A3–7 = 01011 →
`-PSSEL`, and **U5/U6 74138** decode A0–2 into the per-register read/write strobes.
An AVR **ICSP** header (`JICSP`) programs the '328; **RRST** is its reset pull-up.

TX (host→device) is a firmware stub, so the status-register *writes* are only
decoded (the '328 senses `-WR1`/`-WR3`); there is no write-data capture latch — the
mouse runs in its power-on stream mode, matching the emulator and `lib_ps2` stub.

The '328 reset (`-RESET`) is tied to the backplane **`-RES`** through a **470 Ω
series isolation resistor (`RRB`)**, with the 10 kΩ `RRST` pull-up on the local
node. A system reset (`-RES` is push-pull driven by the control card) pulls
`-RESET` below the AVR reset threshold via the `RRB`/`RRST` divider, so the '328
re-initialises with the rest of the machine. `RRB` also keeps in-system ICSP safe:
the programmer pulls only the *local* `-RESET` node low, and the resistor keeps
that off the bus, so it neither fights the `-RES` driver nor resets the other
cards. (Program the '328 off-bus and it still resets normally — `RRST` holds it
out of reset when `-RES` floats.)

Everything below (§3 block diagram, §4 how-it-works, §6 chip inventory) is the
earlier **pure-TTL** realisation (74HC164 shift register + 74HC161 counter +
74HC574 + 7407 per channel). It is NOT what is built; it is retained as the
fallback design and because its register map (§2) and bus codes (§7) are shared.

## 1. Inputs and outputs

### Inputs (from the backplane)
- **A0–A7 / A8–A15** — address bus. This card claims the eight-byte window
  `$FF58-$FF5F` inside the `$FFxx` I/O page.
- **D0–D7** — data bus. Read-only from the card's point of view except for the
  two status registers, whose *writes* drive the bit-banged transmit lines.
- **DOE (4-bit) / DLD (4-bit)** — the read-enable / write-strobe fields, decoded
  the same way every card decodes them (DOE 7 = read, DLD 7 = write).
- **CLK, -RES** — system clock and reset.

### Inputs (from the outside world)
- **PS/2 port A** — CLK-A, DATA-A (6-pin mini-DIN, +5 V, GND).
- **PS/2 port B** — CLK-B, DATA-B.
  Both CLK and DATA are **open-drain, 5 V**, idle-high through pull-ups; either
  the device or the host may pull a line low.

### Outputs
- **D0–D7** — the selected register's byte on a read.
- **IRQ (optional)** — a "byte ready on either port" line to the (planned) IRQ
  controller card. Polling at PS/2 rates is fine, so this is a build option, not
  a requirement (see `BACKLOG.md`, the `$FF06` polling note).

## 2. Register map (`$FF58-$FF5F`)

Single-sourced in `generators/gen_memmap.py` (regenerate to move it):

| Addr | Name | Access | Meaning |
|------|------|--------|---------|
| `$FF58` | `PSADAT` | read | port A (keyboard) byte; the ready flag clears on read |
| `$FF59` | `PSAST`  | r/w  | **read:** bit0 ready, bit1 overrun, bit2 parity error. **write:** bit0 pull CLK-A low, bit1 pull DATA-A low (the host→device transmit dance) |
| `$FF5A` | `PSBDAT` | read | port B (mouse) byte; ready clears on read |
| `$FF5B` | `PSBST`  | r/w  | as `PSAST`, port B |
| `$FF5C` | `PSLINE` | read | live line states: bit0 Aclk, bit1 Adat, bit2 Bclk, bit3 Bdat — the CPU reads these to clock out a transmit frame |
| `$FF5E` | `PSID`   | read | `$4B` = `'K'`, the presence probe (an absent card floats the bus to `$FF`) |

`$FF5D` and `$FF5F` are unallocated and float `$FF`.

## 3. Block diagram

```
              +-------------------- $FFxx page (7430) ---------------------+
  A8..A15 --->| 7430 8-in NAND: all high => in the I/O page                |
              +-----------------------------+-----------------------------+
                                            | -IOPG
  A3..A7  --->[ window compare = $FF58..5F ]-+--> -PSSEL (this card active)
  A0..A2  --->[ 74138 : one of 8 register selects -R0.. -R7 ]
  DOE=7   --->[ read decode ]--+   DLD=7 -->[ write decode ]--+
                               |                              |
        +----------------------+----------+       +-----------+----------+
        |            READ side            |       |      WRITE side      |
        |  -R0 PSADAT  -> chan A data     |       | -R1 PSAST  -> chan A |
        |  -R1 PSAST   -> chan A status   |       |   TX line drivers    |
        |  -R2 PSBDAT  -> chan B data     |       | -R3 PSBST  -> chan B |
        |  -R3 PSBST   -> chan B status   |       +----------------------+
        |  -R4 PSLINE  -> live CLK/DATA   |
        |  -R6 PSID    -> 'K' buffer      |
        +---------------[ 74HC245 bus driver -> D0..D7 ]-------------------+

  Per channel (A shown; B identical):
     CLK-A (open-drain, pull-up) --falling edge--> [ 74HC161 bit counter ]
                                                  \-> [ 74HC164 shift reg ]
     DATA-A (open-drain, pull-up) --serial in-----/         |
        at count 11 (start+8+parity+stop): [ 74HC574 latches d0..d7 ] + set READY
     7407 open-collector drivers pull CLK-A / DATA-A low on PSAST writes (TX)
```

## 4. How it works

### 4.1 Address decode: page, window, register
Two-level, like the I/O card. A **7430** detects the `$FFxx` page (all of
A8–A15 high). A small comparator on A3–A7 narrows that to the eight-byte window
`$FF58-$FF5F` (`-PSSEL`). Within the window a **74138** decodes A0–A2 into eight
register selects; read vs write comes from the DOE decoder (DOE 7 → `-RD`) and
DLD decoder (DLD 7 → `-MEMW`), exactly the convention the other cards use. Only
six of the eight selects are wired; `$FF5D`/`$FF5F` are left unconnected and read
back as the floating bus (`$FF`).

### 4.2 Receiving a frame (the dumb receiver)
A PS/2 device sends an **11-bit frame** on its own clock (10–16.7 kHz), LSB
first: a start bit (0), eight data bits, an odd-parity bit, and a stop bit (1);
DATA is valid on the **falling edge** of CLK. Per channel:

- The device's **CLK** drives a **74HC161** bit counter and clocks a **74HC164**
  shift register, both on the falling edge; **DATA** feeds the 164's serial
  input.
- After the counter reaches **11**, the frame is complete: the eight data bits
  now sit at known taps of the shift chain, and the terminal count strobes a
  **74HC574** to latch them and set the channel's **READY** flip-flop. Parity is
  checked across the latched byte (odd) and recorded as the status bit2; a frame
  whose stop bit is not high is dropped.
- If a new frame completes while READY is still set (the CPU has not read the
  last byte), the **overrun** bit latches. READY (and overrun) clear when the CPU
  reads `PSxDAT`.

Because everything downstream — Set-2 make/break, the E0/F0 prefixes, the mouse's
3-byte packet framing — is software, the card needs no knowledge of *what* a byte
means. It only guarantees "here is the next whole byte, and whether you missed
one." This is exactly what the emulator models at `$FF58-$FF5F` and what
`lib_ps2` consumes.

### 4.3 Transmitting (host → device) — bit-banged, software-owned
PS/2 is bidirectional: to enable the mouse (`$F4`) or reset a device (`$FF`) the
host must pull CLK low (inhibit) for ~100 µs, pull DATA low (the start bit),
release CLK, and then clock out the frame while the *device* drives CLK. The card
provides only the muscle and the eyes for this: **7407** open-collector buffers
pull CLK/DATA low when the CPU sets bit0/bit1 of `PSxST`, and `PSLINE` reads the
live line states back so the software can time each bit against the device clock.
The sequencing itself lives in `lib_ps2` (currently a stub — `ms_enable()` — so
the mouse runs in its power-on stream mode; the emulator models the same stub).

### 4.4 Presence probe
A read of `$FF5E` enables a buffer that drives the constant `$4B` (`'K'`) onto
D0–D7. Software reads `PSID`, and `'K'` means "a PS/2 card is fitted"; with no
card the bus floats and reads `$FF`, which is not `'K'`. This is the same
presence convention the GL port (`'G'`) and the MDU (`'M'`) use.

## 5. Levels: 5 V TTL, no bus shifting
The whole card is 5 V TTL, and **PS/2 is native 5 V open-drain**, so the device
lines connect straight to the 7407 drivers and the 74HC inputs through 5 V
pull-ups — there is **no level translation anywhere on this card**. This is the
key difference from the FPGA-fabric path, where the Tang Nano 20K's 3.3 V,
non-5 V-tolerant GPIO forces a **TXS0102** auto-direction translator per port
(see the FPGA PS/2 interface doc). On the TTL backplane the data bus is 5 V too,
so nothing between this card and the CPU needs shifting either.

## 6. Chip inventory (proposed)

| Ref | Device | Role |
|-----|--------|------|
| U1 | 7430 | 8-input NAND — `$FFxx` I/O-page detector |
| U2 | 74HC688 (or 74138+gates) | window compare → `-PSSEL` for `$FF58-$FF5F` |
| U3 | 74138 | register decode (A0–A2 → `-R0..-R7`) |
| U4 | 74138 | DOE decoder (read enable) |
| U5 | 74138 | DLD decoder (write strobe) |
| U6 | 74HCT32 | OR glue (per-register read/write strobes) |
| U7 | 74HC164 | port A receive shift register |
| U8 | 74HC161 | port A bit counter (terminal count = frame done) |
| U9 | 74HC574 | port A data latch + READY flip-flop |
| U10 | 7407 | port A open-collector CLK/DATA drivers (TX) |
| U11 | 74HC164 | port B receive shift register |
| U12 | 74HC161 | port B bit counter |
| U13 | 74HC574 | port B data latch + READY |
| U14 | 7407 | port B open-collector CLK/DATA drivers (TX) |
| U15 | 74HC74 | overrun / status flip-flops |
| U16 | 74HC245 | read-data bus driver (D0–D7) |
| U17 | 74HC244 | `PSLINE` live-line + `PSID` `'K'` buffer |
| U18 | 74HCT08 | AND glue (strobe gating) |

Plus two 6-pin mini-DIN PS/2 connectors, the CLK/DATA pull-ups, and the
house-standard **per-IC 100 nF decoupling caps** (through-hole — see the
decoupling-cap rule).

## 7. Bus codes this card owns
- **DOE:** 7 = read (the selected register drives D0–D7) — shared decode
  convention with the memory and I/O cards.
- **DLD:** 7 = write (`MEMW`) — the two status registers latch the transmit line
  drive bits.
- **Address:** `$FF58-$FF5F` (recorded in
  [`p8x-bus-definition.md`](../backplane/p8x-bus-definition.md) §6 and the
  memory-map generator before use).

## 8. Known issues / verify
- **Shift-tap alignment.** With a single 8-bit 74HC164 the eight data bits must
  be taken from the correct taps after 11 clocks; confirm on the bench (or chain
  two 164s for a full 16-bit capture and latch bits 1–8) before committing the
  layout.
- **Metastability of READY vs. the CPU read.** The READY flip-flop is set by the
  device clock and cleared by the bus read — synchronise the clear to the system
  clock (U15) so a read that races a completing frame cannot drop a byte silently
  (that is what the overrun bit is for; verify it latches).
- **TX timing is unproven.** The bit-banged host→device path (`PSxST` drive bits
  + `PSLINE` readback) has never run on real silicon — `ms_enable()` is a stub in
  both `lib_ps2` and the emulator. The mouse works in its power-on stream mode
  without it; enabling higher report rates needs this path finished and tested.
- **IRQ vs. poll.** Left as a build option; PS/2 byte rates are low enough that
  the OS can poll `PSxST`, matching the `$FF06`/poll convention. Wire the IRQ
  line only once the IRQ-controller card exists.
