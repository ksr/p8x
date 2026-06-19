# Register Bank Card — Theory of Operation

The register bank holds the machine's four **16-bit pointer registers** —
P0 (the program counter), P1/P2 (general purpose), P3 (the stack pointer) — plus
a hidden scratch pointer **PT** (PSEL = 4). It is also the **address-bus driver**:
the 16-bit address bus is *always* driven by exactly one of these pointers, so the
P8X has no separate memory-address register. The card increments/decrements the
active pointer, loads pointer bytes from the data bus, and can read a pointer byte
back onto the data bus.

> Source of truth: the `# REGISTER BANK CARD` section of
> [`../../generators/gen_eagle.py`](../../generators/gen_eagle.py).

---

## 1. Inputs and outputs

### Inputs (from the backplane)

| Signal | Purpose |
|--------|---------|
| `D0–D7` | byte to load into a pointer's low or high half; also the readback path's tristate source |
| `PSEL0–2` | selects the active pointer (0–3 = P0–P3, 4 = PT) |
| `PINC` / `PDEC` | increment / decrement the active pointer this clock |
| `DLD0–3` | data-load field — decoded here to "load pointer low/high" |
| `DOE0–3` | data-output field — decoded here to "drive pointer low/high onto D0–7" |
| `CLK` | counter / latch clock |
| `-RES` | reset — forces P0 (PC) to `$0000` |

### Outputs (to the backplane)

| Signal | Destination | Meaning |
|--------|-------------|---------|
| `A0–A15` | address bus | the active pointer's value (memory + I/O + CF decode it) |
| `D0–D7` | data bus | a selected pointer byte, when the DOE field asks for it (e.g. pushing the PC) |

---

## 2. Block diagram

```
  PSEL0-2 ─► ┌────────────┐ -SEL0..4 (one-hot)
             │U33 74138   ├───────────────┬─────────────┬───────────────┐
             │ SEL decode │                │             │               │
             └────────────┘                ▼             ▼               ▼
                                    ┌──────────┐  ┌──────────┐    ┌──────────────┐
  D0-7 ─load─► ┌──────────────┐     │P0: U1-4  │  │P1: U5-8  │ …  │PT: U41/42    │
              │load/cnt decode│     │4× 74169  │  │4× 74169  │    │2× 74377      │
  DLD0-3 ─►   │U30 U32 U40    │────►│16-bit    │  │16-bit    │    │16-bit scratch│
  PINC/PDEC ─►│U34 U35 U39    │cnt  │ up/down  │  │ up/down  │    └──────┬───────┘
              └──────────────┘ /load└────┬─────┘  └────┬─────┘           │
                                         │PQ           │PQ               │PTQ
                                  ┌──────▼─────────────▼─────────────────▼──────┐
                                  │ pointer-select buffers (74244, gated -SELp) │  selected
                                  │ U17-U24 (P0-P3) + U43/U44 (PT)              │  pointer →
                                  └──────────────────────┬───────────────────────┘  PB0-15
                                                         │PB0-15 (internal pointer bus)
                          ┌──────────────────────────────┼───────────────────────┐
                          ▼ (always enabled)              ▼ (readback)             │
                  ┌───────────────┐              ┌─────────────────────┐          │
                  │U25/U26 74244  │              │U27/U28 74257 mux    │ POEHP    │
                  │ ADDR DRIVERS  │              │ pick lo or hi byte  │◄────      │
                  └──────┬────────┘              └─────────┬───────────┘          │
                         ▼ A0-A15 (to bus)                 ▼ RB0-7                 │
                                                  ┌─────────────────┐  -POE        │
  DOE0-3 ─►┌────────┐ -POEL/-POEH                 │U29 74244 RDBK   ├──► D0-7      │
           │U31 DOE │────────────────────────────►│ OUT (to D bus)  │  (to bus)   │
           └────────┘                             └─────────────────┘             │
  -RES ─► U36 (74244) forces 0x0000 into P0 on reset ◄──────────────────────────┘
```

---

## 3. How it works

### 3.1 Each pointer is four 74169s in a carry chain
A 16-bit pointer is built from four 74169 synchronous up/down counters (4 bits
each): `L0,L1` for the low byte, `H0,H1` for the high byte. They count as one
16-bit unit because the carry chain is cascaded: slice 0's count-enable is the
pointer's `-CNTp`, and each later slice takes its `!ENT` from the previous slice's
`!RCO` (ripple-carry-out). Only when a slice is at terminal count does it enable
the next — that is the textbook fully-synchronous cascade, so all 16 bits change on
the same clock edge with no ripple delay in the *outputs*.

`UDB` (derived from `PDEC`) sets the count **direction** for all slices: PINC →
count up, PDEC → count down. Loading a pointer half drives `D0–7` into the slice
`A/B/C/D` inputs and pulses `!LOAD`.

PT (PSEL = 4) is different hardware — two 74377 octal latches (`U41/U42`) instead
of counters, because the scratch pointer only ever needs to be *loaded*, never
counted.

### 3.2 Pointer selection → the internal pointer bus (PB0–15)
`PSEL0–2` drive `U33` (74138), producing the one-hot select `-SEL0..-SEL4`. The
selected pointer's counter outputs (`PQ`) are gated onto the internal **pointer
bus PB0–15** by that pointer's pair of 74244 buffers (`U17–U24` for P0–P3, or
`U43/U44` for PT). Exactly one pointer drives PB at a time.

### 3.3 Address drivers (U25/U26) — always on
Two 74244s (`U25/U26`) copy PB0–15 straight to the backplane address bus `A0–A15`,
and they are **permanently enabled** (`!G1=!G2=GND`). That is deliberate: the
address bus must always carry *some* pointer (there is no MAR), so whichever
pointer is selected onto PB is what the rest of the machine sees as the address.

### 3.4 Loading a pointer (from the data bus)
The `DLD` field is decoded by `U30` (74138) into `-LDL`/`-LDH` (load low/high
byte). These are then routed to the correct pointer:
- For P0–P3, `U32` (74139) decodes `PSEL0/1` into per-pointer load strobes
  `-LDL0..3 / -LDH0..3`, gated by `PSEL2` via `U40` so they only fire for the
  P0–P3 group.
- For PT, `U40` ANDs the load with `-SEL4` to make `-LDL4 / -LDH4`, which strobe
  the PT 74377 latches.

So "load P2 high byte" = DLD decodes to load-high, PSEL=2 routes it to P2's `H0/H1`
`!LOAD` lines, and those slices capture `D0–7`.

### 3.5 Increment / decrement
`PINC`/`PDEC` go to `U34` (NOR) to produce the global count-enable `CNTN`, and
`U35` derives the direction `UDB`. `U39` (74139, enabled by `CNTN`) decodes
`PSEL0/1` to `-CNT0..3` so only the selected P0–P3 pointer's slices count. (PT does
not count.) This is how the PC self-increments during fetch and how the SP
adjusts on push/pop.

### 3.6 Reading a pointer back onto the data bus
To push the PC (or otherwise spill a pointer to memory) the card can put a pointer
byte on `D0–7`: the `DOE` field is decoded by `U31` into `-POEL`/`-POEH` (output
low/high). `U27/U28` (74257 muxes) select the low or high byte of PB (select line
`POEHP`), and `U29` (74244, enabled by `-POE`) drives it onto the data bus.

### 3.7 Reset → PC = $0000
On `-RES`, `U36` (74244) is enabled to force `0x0000` onto the P0 load inputs while
`U37` asserts P0's load strobes (`-LDL0E/-LDH0E`), so the program counter
deterministically comes up at `$0000` (the monitor's reset vector). Other pointers
are not forced — software initializes them.

---

## 4. Worked example — a JSR (push PC, jump)

1. **Push PC low.** Microcode selects P3 (SP) onto the address bus (`PSEL=3`),
   asks the register bank to output P0's low byte (`DOE`=pointer-low... in practice
   the PC is spilled via the chosen path), memory write captures it; `PDEC` adjusts
   SP.
2. **Push PC high** similarly.
3. **Load PC** from the target: `DLD`=load-low/high with `PSEL=0` strobes P0's
   slices from `D0–7`, so the PC now holds the subroutine address and the next
   fetch comes from there.

(The exact microstep sequence lives in `genucode.py`; the point here is that every
one of those actions is just a combination of `PSEL`, `PINC/PDEC`, `DLD`, and
`DOE` decoded on this card.)

---

## 5. Known issues / verify (from the design review)

- **IC power pins:** *fixed* — `card()` now nets every IC's VCC/GND supply pin to
  the power pours (the review found it previously omitted them). This card has 44
  ICs and was the most affected; verified all 44 now have both rails.
- **Address bus floats for PSEL = 5, 6, 7:** `U33` is always enabled and only
  decodes 0–4; for codes 5–7 no pointer drives PB, yet the always-on address
  drivers (`U25/U26`) still push an undefined PB value onto `A0–15`. Safe **only
  if** the microcode never emits PSEL > 4 (PT = 4 is the max). Worth a constraint
  note / bring-up check.
- Confirmed OK: the 16-bit carry chain, the load data path (low/high nibble
  mapping), direction control, and that exactly one pointer drives PB for valid
  PSEL.

See [README.md](README.md) and [../../BACKLOG.md](../../BACKLOG.md).
