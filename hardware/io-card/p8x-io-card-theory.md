# I/O Card — Theory of Operation

The I/O card is how the P8X talks to the outside world. It carries the **6850 ACIA
serial console** (the terminal you type at), an 8-bit **switch input port**
(`$FF00`), an 8-bit **LED output port** (`$FF02`), passive **bus-monitor LED
arrays** that display the address and data buses in real time, and DNP footprints
for a **DS1302 real-time clock**. Everything lives in the `$FF00–$FF0F` I/O page.

> Source of truth: the `# I/O CARD` section of
> [`../../generators/gen_eagle.py`](../../generators/gen_eagle.py).

---

## 1. Inputs and outputs

### Inputs (from the backplane)

| Signal | Purpose |
|--------|---------|
| `A0–A15` | address — page-decoded ($FFxx) and port-decoded (A1–A3) |
| `D0–D7` | data bus — write data to the LED port / ACIA; read data from switches / ACIA |
| `DOE0–3` | decoded to the read strobe `-RD` |
| `DLD0–3` | decoded to the write strobe `-MEMW` |
| `CLKB` | clocks the LED output latch; gates the ACIA enable |

### Outputs

| Signal | Destination |
|--------|-------------|
| `D0–D7` | data bus, on a switch read or ACIA read |
| `SOUT`/`SIN` (J2) | RS-232 serial to/from the host terminal (via MAX232) |
| LEDs | the LED output port + always-on bus-monitor display |

---

## 2. Block diagram

```
  A8..A15 ─►┌────────┐ IOPG     ┌────────┐ -P0 ($FF00 switches)
            │U1 7430 ├─────────►│U2 74138├─► -P1 ($FF02 LEDs)
            │I/O page│   A1-3 ─►│PORT DEC│─► -P2 ($FF04/5 ACIA)
            └────────┘          └────────┘   (-P3 $FF08 RTC, reserved)
  DOE ─►U3 74138 ─► -RD ─┐
  DLD ─►U4 74138 ─► -MEMW┼─ gates (U5/U6/U15) ─► -SWOE, LCK, EEN
                          │
   switches SW1 ──pullups RNP── ┌──────────┐ -SWOE
   (closed=0)                   │U9 74244  ├──────────► D0-7  (read $FF00)
                                └──────────┘
   D0-7 ──► ┌──────────┐ LCK   LP0-7   ┌─────┐    ┌──────────┐
            │U10 74374 ├──────────────►│RL1  ├───►│LA1 8-LED │  (write $FF02)
            │ LED PORT │  (latch)      │330R │    │  array   │
            └──────────┘               └─────┘    └──────────┘
   D0-7 ◄─► ┌──────────┐  RS=A0, !CS2=-P2, E=EEN, RW=-MEMW
            │U14 6850  │  TXD/RXD ─► U8 MAX232 ─► J2 (RS-232)
            │  ACIA    │  TXCLK/RXCLK ◄─ U7 74161 ÷ (X2 2.4576MHz) = BCLK
            └──────────┘
   A0-15 ─► U11/U12 74244 ─► MA0-15 ─► RM1/RM2 330R ─► LM1/LM2  (address monitor LEDs)
   D0-7  ─► U13 74244     ─► MD0-7  ─► RM3 330R     ─► LM3      (data monitor LEDs)
   [DNP] U16 DS1302 RTC + X3 32.768kHz + BT1 coin cell + J3 3-wire header
```

---

## 3. How it works

### 3.1 Two-level address decode: page then port
First `U1` (7430 8-input NAND) asserts `IOPG` when A8–A15 are all high — i.e. any
`$FFxx` address. `IOPG` enables the **port decoder** `U2` (74138), which decodes
address bits A1–A3 into one-hot port selects:

| Port select | Address | Device |
|-------------|---------|--------|
| `-P0` | `$FF00–01` | switch input |
| `-P1` | `$FF02–03` | LED output |
| `-P2` | `$FF04–05` | 6850 ACIA |
| `-P3` | `$FF08` | DS1302 RTC (reserved, DNP) |

The `DOE`/`DLD` fields are decoded locally (`U3`/`U4`) into `-RD`/`-MEMW`, and the
glue gates (`U5`,`U6`,`U15`) combine a port-select with the right strobe to produce
the per-device enables.

### 3.2 Switch input port ($FF00)
The 8 DIP switches `SW1` are pulled up by `RNP` (common to VCC) and short to GND
when closed — so a closed switch reads **0**, an open switch reads **1**. `U9`
(74244) drives those levels onto `D0–7` only when `-SWOE` is asserted
(`-SWOE = AND(-P0, -RD)`), i.e. on a read of `$FF00`. (In the emulator this byte is
set with `-s`.)

### 3.3 LED output port ($FF02)
`U10` (74374 octal latch) captures `D0–7` on `LCK` — a clock derived from a `$FF02`
write (`-P1` + `-MEMW`, phased by `CLKB`). Its outputs `LP0–7` drive the `LA1` LED
array through `RL1` (8×330 Ω). So `POKE $FF02,n` lights the bit pattern `n`. (In
the emulator, the `-L` flag traces these writes.)

### 3.4 The serial console (U14 6850, U7, U8, X2)
The 6850 ACIA is the UART. It is selected by `-P2` on `!CS2` with register-select
`RS = A0` (so `$FF04` = status/control, `$FF05` = data), read/written via `EEN`
(enable) and `RW = -MEMW`. Its transmit/receive clocks come from `U7` (74161)
dividing the dedicated 2.4576 MHz oscillator `X2` down to `BCLK` (the standard
trick to hit common baud rates). The ACIA's logic-level TXD/RXD are converted to
RS-232 voltages by `U8` (MAX232, with its charge-pump caps C2–C5) and brought out
on the 3-pin header `J2`. This is the path every character of the monitor/OS/BASIC
console travels.

### 3.5 Bus-monitor display (U11–U13, LM1–LM3) — passive
Independently of any address decode, three 74244 buffers continuously sample the
buses — `U11/U12` the 16-bit address bus, `U13` the 8-bit data bus — and drive
three 8-LED arrays through 330 Ω networks. This is a pure *spectator*: it never
drives the bus, only watches it, giving you a live binary readout of what the CPU
is doing. Great for bring-up and demos.

### 3.6 Real-time clock (U16 DS1302 — DNP)
Fully isolated 3-wire peripheral: crystal `X3` (32.768 kHz), main supply from +5,
backup supply from coin cell `BT1`, and CE/SCLK/IO broken out to header `J3`. It
**cannot** contend with the bus (it's not connected to it) — connecting the 3-wire
to a port is left for bring-up. Reserved address `$FF08`.

---

## 4. Worked example — printing a character

1. The monitor writes the byte to the ACIA data register at `$FF05`: it drives
   `A0–15 = $FF05` and `D0–7 = char`, with `DLD = 7` (write).
2. `U1` asserts `IOPG` (`$FFxx`); `U2` decodes A1–3 = 2 → `-P2` (ACIA); `RS = A0 =
   1` (data register); `-MEMW` → `RW` write; `EEN` enables the ACIA.
3. The ACIA shifts the byte out at the baud rate set by `BCLK`; `U8` levels it to
   RS-232 on `J2`; your terminal displays the character.

A read of `$FF00` is the input mirror: `-P0` + `-RD` → `-SWOE` → `U9` drives the
switch byte onto `D0–7`, which the CPU loads.

---

## 5. Known issues / verify (from the design review)

- **IC power pins:** built by the generator `card()` helper, which currently does
  not net IC VCC/GND supply pins to the pours — **fix before fab** (see BACKLOG).
- **SEL LED drive:** the I/O-select LED is source-driven from a gate output (a
  deviation from the sink-drive standard, noted on the schematic) — confirm
  brightness is acceptable at bring-up.
- **RTC (U16):** DNP; the 3-wire-to-port connection is deferred to bring-up.

See [README.md](README.md) and [../../BACKLOG.md](../../BACKLOG.md).
