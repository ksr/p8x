# ALU Card

> **Theory of operation:** [p8x-alu-card-theory.md](p8x-alu-card-theory.md) — deep walkthrough of inputs/outputs, signal flow, and logic.

Holds the two ALU operand registers (**A**, **B**), the two hidden microcode
temporaries (**T**, **T2**), the **74181-based ALU** with a post-ALU shifter, and
the **FLAGS** register. All arithmetic and logic happens here.

> This README describes the circuit as actually built in
> [`generators/gen_eagle.py`](../../generators/gen_eagle.py). See
> [p8x-system-design.md §5](../../docs/p8x-system-design.md) for the overview and
> [p8x-bus-definition.md](../backplane/p8x-bus-definition.md) for bus pins.

## Chip inventory

| Ref | Device | Role |
|-----|--------|------|
| U1, U2 | 74377 + 74244 | A register (load latch + bus-drive buffer) |
| U3, U4 | 74377 + 74244 | B register |
| U5, U6 | 74377 + 74244 | T register (hidden temp) |
| U7, U8 | 74377 + 74244 | T2 register (hidden temp) |
| U9, U10 | 74181 | ALU, low and high nibble |
| U11 | 74182 | Carry-lookahead generator across the two 74181s |
| U12–U15 | 74157 | Two-stage shifter (pass / <<1 / >>1) |
| U16 | 74244 | ALU-result bus driver |
| U17 | 74175 | Z and N flag flip-flops (D3, D4 spare) |
| U18 | 74260 | Zero-detect NOR over the result |
| U19 | 74HCT08 | AND glue (zero combine, ALU LED) |
| U20 | 74138 | DOE decoder (codes 1–6) |
| U21 | 74138 | DLD decoder (codes 1–4, the four registers; 5, the flag restore `-LDFL`) |
| U22 | 74157 | Z/N source mux: ALU result, or the bus byte on a load (`LDZN`) |
| U23 | 74244 | FLAGS → data bus driver |
| U24 | 74HCT32 | OR: flag clock enables (`LDF | LDZN`, and with the restore `LDF | LDZN | LDFL`), any-shift detect |
| U25 | 74HCT00 | NAND: inverts the 74181 `Cn+4` (net `CFLGI`), `SETC`/`CLRC`/LDF-LED inverters |
| U26 | 7474 | C flag flip-flop (async preset/clear for `SETC`/`CLRC`); V flag in the second half |
| U27 | 74260 | Bus zero-detect over `D0–7` (Z on a load) |
| U28 | 74157 | Shift-out select (bit 0 or bit 7) |
| U29 | 74157 | C source mux: shift-out when shifting, else inverted `Cn+4` |
| U30 | 74157 | Shift-in mux (`SHCIN`): `CIN` or the current C |
| U31 | 74HCT08 | AND: flag clocks, C clear |
| U32, U33 | 74157 | B-operand mux (`BSEL`): B register or T (rev C) |
| U34 | 74HCT86 | XOR: V (signed overflow) derivation (rev C) |
| U35 | 74HCT08 | AND: V derivation (rev C) |
| U36 | 74157 | Flag restore mux (`-LDFL`): `D0–D3` or the normal C/Z/N/V sources to the flag flip-flops |
| U37 | 74HCT00 | NAND: C clock enable `LDF | LDFL` = NAND(`-LDF`, `-LDFL`) |

## How it works

### The four registers
A, B, T, T2 are each a **74377** (8-bit latch with a load enable) paired with a
**74244** output buffer. The 74377 loads from the data bus when its DLD code is
decoded by U21 (`-LDA`/`-LDB`/`-LDT`/`-LDT2`). The 74244 drives the register's value
back onto the data bus when its DOE code is decoded by U20. A feeds the 74181 A
inputs directly and continuously; the 74181 B inputs come through the U32/U33
B-mux, which passes the B register (`BSEL`=0) or T (`BSEL`=1).

### The ALU (74181 + 74182)
Two 74181s (U9 low nibble, U10 high nibble) form the 8-bit ALU. Function is set by
the backplane lines **ALUS0–3** (operation select), **ALUM** (logic vs arithmetic),
and **CIN** (carry in). Instead of rippling carry between the two 74181s, the
**74182** carry-lookahead generator (U11) takes their propagate/generate outputs
(`!P`/`!G`) and produces the fast intermediate carry `CNX` into the high nibble —
keeping the carry chain short and fast.

> **Carry flag polarity:** the 74181 `Cn+4` pin is active-low; since rev B a U25
> NAND inverts it (net `CFLGI`) before the C-source mux, so the C flag is
> conventional **active-high** (C=1 = carry out, or A≥B after SUB/CMP). Microcode,
> emulator, monitor and FPGA RTL all use this sense. (Rev A latched the raw pin.)

### The shifter
Two stages of 74157 muxes (U12/U13 then U14/U15) sit after the ALU, selected by
**SH0/SH1**, giving pass-through, shift-left, or shift-right. The shift-in bit
comes from the U30 mux: `CIN`, or the current C flag when **SHCIN** is set (how
`ROL`/`ROR` rotate through carry). The shifted result is driven onto the data bus
by U16 (74244) when DOE selects the ALU result (code 5).

### Flags
- **Z** (zero): U18 (74260) NORs the result bits, combined in U19 — asserted when
  the whole 8-bit result is zero. On a load (`LDZN`) U22 takes Z from the bus
  zero-detect U27 instead.
- **N** (negative): bit 7 of the result, or `D7` on a load (`LDZN`).
- **C** (carry): in its own 7474 (U26), clocked by `LDF` from the U29 C-source mux
  (shift-out when shifting, else the inverted `Cn+4`); `SETC`/`CLRC` force it.
- **V** (overflow): signed overflow since rev C, by the sign-bit method
  `V = (A7^F7) & (A7^B7^~ALUS2)` in U34/U35, ungated by M (meaningful after
  ADD/SUB/CMP). It sits in U26's second half and is clocked with C, so a load
  (`LDZN`) leaves it alone. Until 2026-11-27 it was in U17 and every load cleared
  it, which broke the signed result of `CMPW`/`SUBW`/`ADDW a,#` (`test_isa` E2).
- **Restore** (DLD code 5, `-LDFL` from U21): RTI loads all four flags from the
  bus byte it popped, in the DOE=6 order (`D0`=C, `D1`=Z, `D2`=N, `D3`=V). The U36
  mux puts `D0–D3` on the four flip-flop D inputs while `-LDFL` is low, and both
  flag clocks are enabled. Added 2026-11-27: before then no card decoded DLD=5,
  so on the TTL build RTI left the flags as they were, unlike the emulator and
  the FPGA.

U17 (Z, N) is clocked by `CLK & (LDF | LDZN | LDFL)` and U26 (C, V) by
`CLK & (LDF | LDFL)` (U24/U31/U37), so other cycles don't disturb the flags;
`-RES` clears them. U23 (74244) drives FLAGS onto the bus for
PHP-style pushes (DOE code 6). See
[p8x-alu-card-theory.md](p8x-alu-card-theory.md) §3.5 for the detail.

## Bus codes this card owns
- **DOE:** 1=A, 2=B, 3=T, 4=T2, 5=ALU result, 6=FLAGS
- **DLD:** 1=A, 2=B, 3=T, 4=T2, 5=FLAGS (restore)

## LEDs
PWR (green), ALU (green — result on bus), LDF (yellow — flags latching).
