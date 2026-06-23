# Memory Card — Theory of Operation

The memory card is the P8X's address space. **Rev D** map: a 16 KB EEPROM window
(`$0000–$3FFF`, holding the monitor + ROM BASIC) and **48 KB of SRAM**
(`$4000–$FEFF`) across two 62256 chips. It decodes the address bus to decide which
chip — if any — responds, steers a bidirectional data buffer the right way for
reads vs writes, and includes a jumper to write-protect the ROM.

| Region | Range | Size | Chip | `!CE` decode |
|--------|-------|------|------|--------------|
| ROM | `$0000–$3FFF` | 16 KB | U1 28C256 (low half) | `A15 OR A14` |
| RAM | `$4000–$7FFF` | 16 KB | U10 62256 (rev D, new) | `NAND(!A15, A14)` |
| RAM | `$8000–$FEFF` | 32 KB | U2 62256 | `NAND(A15, -IOPG)` |
| I/O | `$FF00–$FFFF` | — | (other cards) | — |

> Rev D shrank the ROM window to 16 KB and added the second SRAM (U10) to grow RAM
> to 48 KB — the EEPROM still holds the same image (only its low 16 KB is now
> addressable), and the new decode reuses spare gates in U7/U8 (no added logic IC).

> Source of truth: the `# MEMORY CARD rev D` section of
> [`../../generators/gen_eagle.py`](../../generators/gen_eagle.py). Like every
> other logic card it is now built through the shared `card()` helper; its
> functional netlist is assembled with a local `mnet` helper and handed to
> `card()`, which adds the connector, decoupling caps, IC power pins, and the
> J1 bus/power wiring.

---

## 1. Inputs and outputs

### Inputs (from the backplane)

| Signal | Purpose |
|--------|---------|
| `A0–A15` | address to decode and present to the memory chips |
| `D0–D7` | data bus (bidirectional through the buffer) — write data in, read data out |
| `DOE0–3` | decoded here: code 7 = memory **read** (`-RD`) |
| `DLD0–3` | decoded here: code 7 = memory **write** (`-MEMW`) |
| `CLK` | gates the write strobe so writes land on the clock edge |

### Outputs

| Signal | Destination | Meaning |
|--------|-------------|---------|
| `D0–D7` | data bus | the addressed byte, on a read |
| — | (on-card) | EEPROM/RAM chip-enables, output-enables, write-enable |

---

## 2. Block diagram

```
  A15,A14 ─► U8 OR  ──────────────────────────► U1 28C256 !CE  (ROM=$0000-3FFF: A15=A14=0)
  A15,A14 ─► U7 NAND(!A15,A14) ───────────────► U10 62256 !CE (RAM=$4000-7FFF)
                     │
  A8..A15 ─► ┌───────▼────┐ -IOPG    ┌─────────┐ -RAMCE
             │U4 7430 NAND├─────────►│U7 74HC00├─────────► U2 62256 !CE (RAM=$8000-FEFF)
             │ I/O page   │   A15 ──►│  NAND   │           (disabled in $FFxx I/O page)
             └────────────┘          └─────────┘
  DOE0-3 ─►┌─────────┐ -RD (Y7)
           │U5 74138 ├──────┬──────────────► U1/U2/U10 !OE  (output enable on read)
           │DOE decode│      ├──────────────► U3 74245 DIR (read → drive bus)
           └─────────┘       └──► U9 ─┐
  DLD0-3 ─►┌─────────┐ -MEMW(Y7)        ├─AND─► -BOE ─► U3 74245 !OE (buffer active on R or W)
           │U6 74138 ├──┬──► U8 ─┐      │
           │DLD decode│  │  AND  ├─ -WE─┴─► U2/U10 !WE (RAM write)┌─────┐
           └─────────┘  │CLK ───┘            └─► JWP 1 ──────────│ JWP │ 2─► U1 !WE (ROM)
                        │                        VCC ─── JWP 3 ──│ WP  │     (jumper: writable
                        ▼                                        └─────┘      or VCC=protected)
              D0-7 ◄──► ┌──────────────┐ MD0-7
                        │U3 74245 DATA │◄────────► U1 28C256 IO0-7
                        │  BUFFER      │◄────────► U2 62256  IO0-7
                        └──────────────┘
```

---

## 3. How it works

### 3.1 Address decode — who responds (rev D)
The top two address bits, **A15** and **A14**, pick the region:

- **ROM** (`U1` 28C256): `!CE = A15 OR A14` (`U8` spare OR gate). Active-low only
  when both are 0, so the EEPROM responds for `$0000–$3FFF`. Its A14 pin is then
  always 0 when selected, so only the low 16 KB of the 32 KB part is used.
- **New SRAM** (`U10` 62256): `!CE = NAND(!A15, A14)` (`U7` spare NAND gates — one
  inverts A15, one ANDs it with A14). Responds for `$4000–$7FFF`.
- **Main SRAM** (`U2` 62256): `!CE = -RAMCE = NAND(A15, -IOPG)`, unchanged. `U4`
  (a 7430 8-input NAND) asserts `-IOPG` low for an `$FFxx` address (A8–A15 all
  high); the RAM responds when A15 = 1 **and** it is not the I/O page. That
  carve-out keeps the RAM from fighting the I/O and CF cards at `$FF00–$FFFF`.

So the decode yields four regions:
- `$0000–$3FFF` → EEPROM (16 KB)
- `$4000–$7FFF` → SRAM U10 (16 KB, rev D)
- `$8000–$FEFF` → SRAM U2 (32 KB)
- `$FF00–$FFFF` → neither responds here (the I/O and CF cards do)

The new decode added **no logic chips** — it reuses spare gates already on the
card (U7 had three unused NANDs, U8 a spare OR). The only added part is U10 (the
second 62256) and its 100 nF decoupling cap.

### 3.2 Read vs write strobes
The control word's `DOE` and `DLD` fields are decoded locally:
- `U5` (74138) decodes `DOE`; output Y7 = `-RD` (a memory read). `-RD` enables the
  selected chip's `!OE`, sets the data buffer to drive *toward* the bus, and
  enables the buffer.
- `U6` (74138) decodes `DLD`; output Y7 = `-MEMW` (a memory write). `-MEMW` is
  ANDed with `CLK` in `U8` to produce `-WE`, so the write pulse is clock-aligned.

### 3.3 The bidirectional data buffer (U3, 74245)
The card's `D0–7` (backplane) and `MD0–7` (the EEPROM/SRAM data pins) are joined
through a 74245 transceiver:
- **Direction** (`DIR`) = `-RD`: on a read the buffer drives bus ← memory; on a
  write it drives memory ← bus.
- **Output enable** (`!OE`) = `-BOE` = `AND(-RD, -MEMW)` (`U9`): the buffer is
  active whenever a read *or* a write is happening, and high-Z otherwise so it
  never contends with other cards' bus drivers.

### 3.4 ROM write-protect jumper (JWP)
The 28C256 is electrically writable (it's an EEPROM), which is convenient for
in-system programming but risky if runaway code scribbles on it. `JWP` is a 3-pin
select on the ROM's `!WE` only: position **1-2** routes the live `-WE` net (ROM
writable, the default for flashing), position **2-3** ties `!WE` to VCC (ROM
write-protected). The RAM's `!WE` is unconditionally on `-WE`, so protecting the
ROM never disables RAM writes. (A jumper must be fitted — an open header floats the
ROM `!WE`.)

### 3.5 Status LEDs
`U8` and `U9` spare gates also drive activity LEDs: ROM-select, RAM-select, RD, and
WR, which is invaluable during bring-up to *see* the bus cycles. **Rev D** adds a
**RAM2** LED for the new `$4000–$7FFF` bank: `U7`'s last spare gate (a NAND wired
as an inverter) flips `-RAM2CE` to active-high and sources the LED through `RS5`.
Unlike the others it isn't `-BOE`-gated (no spare gate left for that), so it's a
bank-*select* indicator — it lights whenever an address in `$4000–$7FFF` is driven.

---

## 4. Worked example — fetching an opcode at `$2000`

1. The register bank drives `A0–15 = $2000` (the PC). A15 = 0 → `U1` (ROM) `!CE`
   active; `-IOPG` is high (not `$FFxx`) so RAM stays disabled.
2. Microcode sets `DOE = 7`; `U5.Y7` = `-RD` goes low → ROM `!OE` active, `U3`
   `DIR` = read, `-BOE` enables the buffer.
3. The ROM puts the byte at `$2000` on `MD0–7`; `U3` drives it onto `D0–7`; the
   control card latches it into the instruction register.

A write to RAM at, say, `$9000` is the mirror: A15 = 1 and not `$FFxx` → `-RAMCE`
active; `DLD = 7` → `-MEMW`; `AND(CLK)` → `-WE` pulses; `U3` drives bus → memory.

---

## 5. Known issues / verify (from the design review)

- **Power pins.** This card was hand-built originally and explicitly netted every
  IC's VCC/GND — which is why the design review's power-pin gap (the five
  `card()`-built boards missed those) didn't affect it; that hand wiring was the
  reference for the `card()` fix. The card is now `card()`-built too, so all
  boards get their IC power pins the same way.
- **Spare lines stay off GND (rev D).** When it was hand-built this card wired
  *every* row-B pin straight to GND — which would have shorted the new even-pin
  spares (SPARE12–23). Routing J1 through `card()`/`busnet()` fixed that: only the
  odd-pin guards are grounded.
- **I/O-page carve-out:** the `-RAMCE = NAND(A15, -IOPG)` logic is what prevents
  the RAM from driving the bus during `$FFxx` accesses; confirm on the bench that
  RAM is truly silent in the I/O page so it can't contend with the I/O / CF cards.
- **EEPROM access time vs read timing:** the 28C256-15 (150 ns) must deliver data
  within the read window at the chosen clock; slow the clock during bring-up if
  marginal.

See [README.md](README.md) and [../../BACKLOG.md](../../BACKLOG.md).
