# Memory Card — Theory of Operation

The memory card is the P8X's address space. **Rev E** map (as of the 2026-09-14
ROM shrink): a **6 KB ROM window** (`$0000–$17FF`, holding the monitor + BIOS) and
**58 KB of SRAM** (`$1800–$FEFF`) across two 62256 chips. The `$1800–$1FFF` island
that the shrink freed is **RAM** — it holds written OS/BIOS scratch (IBUF/PATHBUF/
APBUF, the sector buffer `SBUF $1D00`, and BIOS scratch at `$1F00`), so it must be
writable. The card decodes the address bus to decide which chip — if any —
responds, steers a bidirectional data buffer the right way for reads vs writes,
and includes a jumper to write-protect the ROM.

| Region | Range | Size | Chip | `!CE` decode |
|--------|-------|------|------|--------------|
| ROM | `$0000–$17FF` | 6 KB | U1 28C64 (or low 6 K of a 28C256) | `A13 OR A14 OR A15 OR (A11·A12)` |
| RAM | `$1800–$7FFF` | 26 KB | U10 62256 | `A15 OR NOT(A13 OR A14 OR (A11·A12))` |
| RAM | `$8000–$FEFF` | 32 KB | U2 62256 | `NAND(A15, -IOPG)` |
| I/O | `$FF00–$FFFF` | — | (other cards) | — |

> **⚠ EAGLE CAD NOT YET REGENERATED (2026-09-17) — but a buildable KiCad rev F
> exists.** The 2026-09-14 ROM shrink (8 KB → 6 KB) is reflected in the emulator,
> `generators/gen_memmap.py` and the OS, but the **Eagle** CAD/`.sch` for this
> card still carries the OLDER 8 KB decode (`ROM !CE = A13 OR A14 OR A15`,
> ROM = `$0000–$1FFF`). That decode maps `$1800–$1FFF` to the ROM chip —
> **unwritable** — which would break the OS/BIOS the moment it touches its
> scratch there.
>
> **The corrected 6 KB decode IS implemented** in the KiCad board at
> [`kicad/`](kicad/README.md) (rev F, 4-layer, fully routed, orderable gerbers) —
> `kicad/gen_mem.py` applies the decode change below to the imported netlist,
> adding **no new chips** (it rewires spare gates U9.4 = `A11·A12`, U11.2 =
> ROM `!CE`, U11.3, and moves U7.3's input). Build from `kicad/` until the Eagle
> generator is brought to rev F. The decode change:
> - **ROM `!CE`** gains an `(A11·A12)` deselect term (one AND gate), so the ROM
>   answers only `$0000–$17FF`; within the `$0000–$1FFF` page, `A11·A12` picks the
>   top 2 KB (`$1800–$1FFF`), which is now RAM.
> - **Low-RAM `!CE` (U10)** is widened to cover `$1800–$7FFF` (26 KB, was 24 KB):
>   it is selected whenever `A15=0` and the address is NOT in the `$0000–$17FF`
>   ROM window.
>
> Rev E also moved the RAM floor and freed `$2000–$3FFF` (formerly the upper ROM
> window) for the OS, which loads at `$2000`. U10 covers the low 32 K address
> space; ROM overlays only its bottom 6 KB now, so `$1800–$7FFF` (26 K) of U10 is
> reachable. High RAM (U2, `$8000–$FEFF`) is unchanged.

> Source of truth: the `# MEMORY CARD rev E` section of
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
  A13,A14 ─► U8.4 OR (Q) ─► U11.1 OR (Q,A15) ─► U1 ROM !CE  (ROM=$0000-1FFF: A13=A14=A15=0)
  A15,Q ──► U7.3 NAND (= A15 OR NOR(A13,A14)) ─────────► U10 62256 !CE (RAM=$2000-7FFF)
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
                        │U3 74245 DATA │◄────────► U1 28C64  IO0-7
                        │  BUFFER      │◄────────► U2 62256  IO0-7
                        └──────────────┘
```

---

## 3. How it works

### 3.1 Address decode — who responds (rev E)
> The block diagram and this section describe the CAD **as currently generated**
> (the pre-2026-09-14 8 KB decode). The 6 KB shrink needs the decode change in the
> ⚠ note at the top of this doc before a board is built; the target logic is given
> there and in the region table. What follows is the as-built 8 KB decode plus, in
> brackets, the 6 KB target.

The top three address bits, **A15/A14/A13**, pick the region:

- **ROM** (`U1`): as built, `!CE = A13 OR A14 OR A15`, active-low only when all
  three are 0 → `$0000–$1FFF` (8 KB). **6 KB target:** add an `(A11·A12)` term,
  `!CE = A13 OR A14 OR A15 OR (A11·A12)`, so the ROM answers only `$0000–$17FF`
  and the top 2 KB of the page (`$1800–$1FFF`, where `A11·A12`) belongs to RAM.
  A 28C64 fits (low 6 KB used); a 28C256 works too.
- **Low SRAM** (`U10` 62256): as built, `!CE = A15 OR NOR(A13, A14)` → `$2000–
  $7FFF`. **6 KB target:** widen it to `$1800–$7FFF` by selecting U10 whenever
  `A15=0` and the address is not in the `$0000–$17FF` ROM window
  (`!CE = A15 OR NOT(A13 OR A14 OR (A11·A12))`), so the `$1800–$1FFF` scratch
  island is writable RAM.
- **Main SRAM** (`U2` 62256): `!CE = -RAMCE = NAND(A15, -IOPG)`, unchanged. `U4`
  (a 7430 8-input NAND) asserts `-IOPG` low for an `$FFxx` address (A8–A15 all
  high); the RAM responds when A15 = 1 **and** it is not the I/O page. That
  carve-out keeps the RAM from fighting the I/O and CF cards at `$FF00–$FFFF`.

So the decode yields (6 KB target in brackets):
- `$0000–$1FFF` → ROM (8 KB)  [`$0000–$17FF` → ROM, 6 KB]
- `$2000–$7FFF` → SRAM U10 (24 KB)  [`$1800–$7FFF` → SRAM U10, 26 KB]
- `$8000–$FEFF` → SRAM U2 (32 KB)
- `$FF00–$FFFF` → neither responds here (the I/O and CF cards do)

The rev-E decode adds the A13 term to the ROM/RAM-low select. rev D's spare gates
were exhausted, so rev E adds exactly one 2-input gate — **U11.1** (a 74HCT32 OR) —
reusing the rev-D gates in place: `U8.4 = OR(A13,A14) = Q`, `U11.1 = OR(Q,A15)` =
the ROM `!CE` (`A13|A14|A15`), and `U7.3 = NAND(!A15,Q)` = the RAM-low `!CE`
(= `A15 OR NOR(A13,A14)`). The other added parts are U10 (the second 62256) and the
two decoupling caps C10/C11.

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
The ROM (a 28C64, or a 28C256 used as 8K) is electrically writable (an EEPROM), which is convenient for
in-system programming but risky if runaway code scribbles on it. `JWP` is a 3-pin
select on the ROM's `!WE` only: position **1-2** routes the live `-WE` net (ROM
writable, the default for flashing), position **2-3** ties `!WE` to VCC (ROM
write-protected). The RAM's `!WE` is unconditionally on `-WE`, so protecting the
ROM never disables RAM writes. (A jumper must be fitted — an open header floats the
ROM `!WE`.)

### 3.5 Status LEDs
`U8` and `U9` spare gates also drive activity LEDs: ROM-select, RAM-select, RD, and
WR, which is invaluable during bring-up to *see* the bus cycles. **Rev E** keeps the
**RAM2** LED for the new `$2000–$7FFF` bank: `U7`'s last spare gate (a NAND wired
as an inverter) flips `-RAM2CE` to active-high and sources the LED through `RS5`.
Unlike the others it isn't `-BOE`-gated (no spare gate left for that), so it's a
bank-*select* indicator — it lights whenever an address in `$2000–$7FFF` is driven.

---

## 4. Worked example — fetching an opcode at `$0100`

1. The register bank drives `A0–15 = $0100` (the PC). A13=A14=A15 = 0 → `U1` (ROM)
   `!CE` active; U10's `NOR(A13,A14)` term also holds it deselected in this page.
2. Microcode sets `DOE = 7`; `U5.Y7` = `-RD` goes low → ROM `!OE` active, `U3`
   `DIR` = read, `-BOE` enables the buffer.
3. The ROM puts the byte at `$0100` on `MD0–7`; `U3` drives it onto `D0–7`; the
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
- **Spare lines stay off GND (rev E).** When it was hand-built this card wired
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
