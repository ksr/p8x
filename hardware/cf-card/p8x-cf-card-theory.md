# CF-IDE Card — Theory of Operation

The CF-IDE card is the P8X's mass storage: a CompactFlash card run in **8-bit True
IDE mode**, memory-mapped into the I/O page at `$FF10–$FF17`. CF cards speak the
IDE/ATA protocol directly in True IDE mode, so this card is mostly **address
decode + strobe generation + a data buffer** — it translates the CPU's
read/write cycles into IDE register accesses.

> Source of truth: the `# CF-IDE CARD` section of
> [`../../generators/gen_eagle.py`](../../generators/gen_eagle.py). Protocol/OS
> detail: [p8x-cf-os-design.md](p8x-cf-os-design.md).

---

## 1. Inputs and outputs

### Inputs (from the backplane)

| Signal | Purpose |
|--------|---------|
| `A0–A4`, `A8–A15` | address — page-decoded ($FFxx), then `$FF10–17` select + register select (A0–A2) |
| `D0–D7` | data bus — IDE register data in/out |
| `DOE0–3` | decoded to the read strobe `-RD` |
| `DLD0–3` | decoded to the write strobe `-MEMW` |
| `CLKB` | gates the IDE `-IOR`/`-IOW` strobe timing |
| `-RES` | drives the CF reset pin |

### Outputs

| Signal | Destination |
|--------|-------------|
| `D0–D7` | data bus, on an IDE read |
| `J2` (40-pin IDE) | the CompactFlash card (in a CF-to-IDE socket) |

---

## 2. Block diagram

```
  A8..A15 ─►┌────────┐ IOPG   ┌────────┐ IOPGP
            │U2 7430 ├───────►│U5 HC14 ├──┐
            │I/O page│        │ schmitt│  │   ┌──────────┐ -CS0 (J2.37)
            └────────┘        └────────┘  ├──►│U6 7410   ├─► -CS1 (J2.38)
  A3,A4 ───────────────────────────────────► │ NAND     │   (select $FF10-17)
                                              └────┬─────┘
                                          -CS0/-CS1│ ┌────────┐ -CFSEL
                                                   └►│U8 HC08 ├──────┐
  DOE ─►U3 ─► -RD ──► ┌────────┐ RDP                └────────┘      │ SELP
  DLD ─►U4 ─► -MEMW ─►│U5 HC14 │ WRP    ┌──────────┐                │
                      └────────┘────────│U7 7410   │◄── CLKB ───────┘
                                        │ strobe   ├─► -IOR (J2.25)
                                        │ gates    ├─► -IOW (J2.23)
                                        └──────────┘
  A0,A1,A2 ─────────────────────────────────────────► J2.35/33/36 (IDE reg select)
  -RES ─────────────────────────────────────────────► J2.1 (CF reset)
                       ┌──────────────┐ DIR=-IOR, !OE=-CFOE
  D0-7 ◄──────────────►│U1 74245 DATA ├◄────────► CFD0-7 (J2 odd data pins)
                       │  BUFFER      │
                       └──────────────┘
  [DNP] U9 74374 captures CF high byte D8-15 (J2 even pins) — 8-bit fallback only
  RN1 10k pull-ups: IORDY, -PDIAG, -DASP ;  LEDs: ACT, DASP
```

---

## 3. How it works

### 3.1 Address decode → chip selects
Like the I/O card, `U2` (7430) asserts `IOPG` for any `$FFxx` address, cleaned by a
schmitt stage `U5` to `IOPGP`. Then `U6` (7410 3-input NANDs) combines `IOPGP` with
address bits A3/A4 to assert the IDE chip-selects `-CS0`/`-CS1` for the `$FF10–17`
window. `-CS0` covers the command-block registers, `-CS1` the control block — the
standard IDE split. The low address bits A0–A2 pass straight to the CF connector as
the IDE register-select (so `$FF10` = data register, `$FF17` = status/command,
etc.).

### 3.2 Read/write strobes (the IDE handshake)
IDE devices are strobed with active-low `-IOR` (I/O read) and `-IOW` (I/O write),
*qualified* by chip select. The card derives `RDP`/`WRP` from the CPU's
`-RD`/`-MEMW` (through schmitt stages in `U5`), combines them with the CF select
(`-CFSEL` from `U8`, and `SELP`), and gates them with `CLKB` in `U7` (7410) to
produce properly-timed `-IOR` (J2.25) and `-IOW` (J2.23). Gating with the clock
phase gives the strobes a clean, bounded width instead of following the CPU
combinational edges directly.

### 3.3 Data buffer (U1, 74245)
The bus `D0–7` and the CF low data byte `CFD0–7` (the odd-numbered IDE data pins)
are joined through a 74245 transceiver:
- **Direction** = `-IOR`: read → bus ← CF; write → CF ← bus.
- **Output enable** = `-CFOE` (`= AND(-IOR,-IOW)`, `U8`): active only during an
  actual CF access, high-Z otherwise so it never fights other bus drivers.

In True IDE 8-bit mode the CF transfers a byte per data-register access, so only
the low byte path is needed for normal operation.

### 3.4 8-bit fallback latch (U9, 74374 — DNP)
Some CF cards may not honor the SET FEATURES command that enables 8-bit mode. As a
safety net, `U9` is wired to capture the CF **high** data byte (`D8–15`, the
even-numbered IDE pins) so a 16-bit transfer could be read back as two bytes. As
shipped it is inert — outputs forced high-Z, clock grounded — and is only populated
(and its bus-drive/decode completed, with DRC) if 8-bit-mode testing shows a card
needs it.

### 3.5 Supporting signals
`RN1` provides 10 kΩ pull-ups for the open-drain-ish IDE status lines `IORDY`,
`-PDIAG`, and `-DASP`. `-RES` resets the CF. Activity (`ACT`) and drive-active
(`DASP`) LEDs show disk access.

---

## 4. Worked example — reading a status byte

1. The OS reads `$FF17` (CF status). The register bank drives `A0–15 = $FF17`;
   microcode sets `DOE = 7` (read).
2. `U2`→`IOPG`; `U6` decodes A3/A4 → `-CS0` active; A0–A2 = 7 selects the status
   register on the CF.
3. `-RD` → `RDP` → gated by `CLKB` in `U7` → `-IOR` (J2.25) pulses; `U1` `DIR` =
   read, `-CFOE` enables it.
4. The CF drives the status byte onto `CFD0–7`; `U1` passes it to `D0–7`; the CPU
   loads it. The OS's driver spins on the BSY/DRQ bits in that byte (exactly as the
   emulator's CF model does for `make test-cf`).

---

## 5. Known issues / verify (from the design review)

- **IC power pins:** built by the generator `card()` helper, which currently does
  not net IC VCC/GND supply pins to the pours — **fix before fab** (see BACKLOG).
- **8-bit mode (the big unknown):** confirm a real CF card honors SET FEATURES
  `$EF/$01` for 8-bit transfers early at bring-up; only if it refuses do you
  populate/complete the `U9` fallback (design its bus-drive path with DRC — it
  drives the data bus).
- **IDE strobe timing:** verify `-IOR`/`-IOW` width and setup/hold against the CF's
  timing at the chosen clock; the `CLKB` gating is meant to bound them.

See [README.md](README.md) and [../../BACKLOG.md](../../BACKLOG.md).
