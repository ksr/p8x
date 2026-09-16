# PS/2 keyboard + mouse interface for the Tang Nano 20K graphics card

Status: **design, 2026-09-16.** A breadboard interface that gives the P8X native
human input by hanging two PS/2 ports off the graphics FPGA card. The card already
has the bridge wire back to the CPU (emulator or on-chip) and spare fabric, so this
is the fastest route to a working mouse + keyboard (option 3 in the BACKLOG "PS/2
keyboard + mouse card" item). Hardware is not wired yet — the emulator `$FF58`
model and `lib_ps2` are in place, so software development continues meanwhile.

The visual wiring diagram is **[PS2-INTERFACE.pdf](PS2-INTERFACE.pdf)** (rendered
from the same design).

## The electrical problem

PS/2 CLK and DATA are a **5 V open-collector** bus: idle high through a pull-up,
either end only ever *pulls low*, and both directions share the one line (the mouse
must be written to — `$F4` enable — so it is genuinely bidirectional). The Tang
Nano 20K's GW2AR-18 GPIO are **3.3 V and NOT 5 V-tolerant**. So every line crossing
to the FPGA needs **bidirectional, open-drain 5 V ↔ 3.3 V level translation**.

## Chosen part: TXS0102 (one per port)

The **TXS0102** is a 2-channel auto-direction translator built for exactly this
kind of open-drain bus (its intended job is I²C/SDIO). One chip carries one PS/2
port's two lines:

- **Auto-direction** — no direction pin, which is essential because PS/2 gives no
  direction signal; either end may pull a line low at any moment.
- **Open-drain native**, with an edge-rate one-shot and **~10 kΩ internal pull-ups**
  to both VCCA and VCCB — that *is* the PS/2 bus pull-up, so **no external signal
  pull-ups** are wired (adding your own fights the one-shot).
- `VCCA ≤ VCCB` sets the two domains: **VCCA = 3.3 V**, **VCCB = 5 V**.
- `OE` (active-high) gates all channels — tie to VCCA so it enables *after* both
  supplies are up.

### Alternatives considered

| Part | Verdict |
|------|---------|
| **TXS0102 / TXS0108 / PCA9306** | ✅ auto-direction, open-drain — correct. TXS0102 = one chip per port; TXS0108 (8-ch) = one chip for both ports. |
| **BSS138 4-ch module** | ✅ also correct (discrete MOSFET + pull-ups); the fallback if a device is flaky on the TXS0102's weak 10 kΩ (add a 2.2 kΩ pull-up). |
| **74LVC07** (open-drain, 5 V-tolerant inputs) | ✅ works as a logic-gate alternative. |
| **74AHCT125** | ❌ a 3.3→5 *up*-shifter only; cannot down-shift 5→3.3 for receive (not 5 V-tolerant at 3.3 V VCC), and push-pull. |
| **TXB0102 / TXB0104** | ❌ push-pull auto-direction — fights the open-drain pull-ups. The TX**B**/TX**S** trap. |
| **2-resistor divider** | ❌ receive-only; the mouse never initialises (no transmit). |
| **Direct wire at 5 V** | ❌ destroys the FPGA I/O. |

## PS/2 mini-DIN 6 (female socket) pinout

| Pin | Signal |
|-----|--------|
| 1 | DATA |
| 2 | (reserved / NC) |
| 3 | GND |
| 4 | VCC (+5 V) |
| 5 | CLK |
| 6 | (reserved / NC) |

> If you cut a PS/2 extension cable instead of using a socket, **meter the pins** —
> wire colours are not standardised.

## Wiring — the authoritative reference

| PS/2 | Pin | Net | TXS0102 | B side | A side | Nano |
|------|-----|-----|---------|--------|--------|------|
| Mouse | 5 | CLK | #1 (mouse) | B1 | A1 | pin76 |
| Mouse | 1 | DATA | #1 (mouse) | B2 | A2 | pin75 |
| Keyboard | 5 | CLK | #2 (kbd) | B1 | A1 | pin74 |
| Keyboard | 1 | DATA | #2 (kbd) | B2 | A2 | pin73 |
| Both | 4 | +5 V | both | VCCB | — | 5V |
| — | — | +3.3 V | both | — | VCCA **+ OE** | 3V3 |
| Both | 3 | GND | both | GND | — | GND |

- **Power** the PS/2 devices from the Nano's **5 V** (USB-derived) pin; the logic
  side from **3V3**. Two devices draw ~150 mA total — fine on USB.
- **Decoupling:** 0.1 µF on each chip's VCCA and VCCB; optionally 0.1 µF across
  each socket's +5 V ↔ GND.

### Nano pins are examples — confirm and constrain

`76 / 75 / 74 / 73` are free on the current card build (used pins: 4, 15–20, 27–42,
48, 69, 70, 77, 81–84). Confirm they are broken out on your board; any four free
GPIO work. Add to `tangnano20k.cst`:

```
IO_LOC  "ms_clk"  76;   IO_PORT "ms_clk"  IO_TYPE=LVCMOS33 PULL_MODE=NONE;
IO_LOC  "ms_dat"  75;   IO_PORT "ms_dat"  IO_TYPE=LVCMOS33 PULL_MODE=NONE;
IO_LOC  "kb_clk"  74;   IO_PORT "kb_clk"  IO_TYPE=LVCMOS33 PULL_MODE=NONE;
IO_LOC  "kb_dat"  73;   IO_PORT "kb_dat"  IO_TYPE=LVCMOS33 PULL_MODE=NONE;
```

## The RTL rule: drive open-drain, never push-pull

Each PS/2 line in fabric drives `0` to pull low, else goes high-Z and reads the pin:

```verilog
assign clk = clk_oe ? 1'b0 : 1'bz;   // never `assign clk = value;`
```

A hard push-pull HIGH from the FPGA confuses the TXS0102's auto-direction sensing
and fights the device. Leave the on-chip pull as `NONE` — the TXS0102's internal
pull-up already holds the A side high.

## Bill of materials

| Qty | Part | Notes |
|-----|------|-------|
| 2 | TXS0102 breakout | one per PS/2 port (breakout easier than bare VSSOP on a breadboard) |
| 2 | PS/2 (mini-DIN 6) female socket | or a metered PS/2 extension cable |
| 4 | 0.1 µF ceramic | VCCA + VCCB decoupling, per chip |
| 2 | 0.1 µF ceramic (optional) | across each socket's +5 V ↔ GND |
| — | breadboard + ~12 jumpers | — |
| 1 | Tang Nano 20K | the P8X graphics card |

No BSS138s and no discrete pull-up resistors — the two TXS0102s replace the
4-channel module and its pull-ups.

## Build order

1. **Rails first.** Nano 5V → red rail, 3V3 → second rail, GND → blue rail. Meter
   5.0 V and 3.3 V *before* anything else.
2. **Each TXS0102:** VCCB→5 V, VCCA→3.3 V, GND→GND, **OE→3.3 V**, 0.1 µF on each
   VCC. (OE low = all channels Hi-Z — do not forget it.)
3. **Sockets:** pin 4→5 V, pin 3→GND, optional 0.1 µF across them.
4. **Signals:** mouse CLK(5)→#1 B1, DATA(1)→#1 B2; keyboard CLK(5)→#2 B1,
   DATA(1)→#2 B2. Then #1 A1→pin76, A2→pin75; #2 A1→pin74, A2→pin73.
5. **Constrain + build:** add the pins to `tangnano20k.cst`, wire them to the PS/2
   receiver in the RTL (below), rebuild the bitstream.

## Where this sits in the stack (status)

- **DONE — golden model:** the `$FF58–$FF5F` PS/2 window in `emulator/p8xemu.c`
  (`-ps2/-ps2a/-ps2b`); `PSADAT/PSAST/PSBDAT/PSBST/PSLINE/PSID`.
- **DONE — decode:** `os/commands/lib_ps2.c` (Set-2 make/break → ASCII; 3-byte
  mouse packet → dx/dy/buttons), tested by `emulator/test/c_ps2_test.sh`.
- **NEXT — RTL receiver:** a shift register clocked by the device CLK (the fabric
  mirror of the 74HC164/161/574 receive path) on these four pins, plus the bridge
  reverse-channel that ships received bytes back to the emulator's `$FF58` FIFOs.
  Fit is the caveat: the card sits near the ~19,150 LUT4 placement cliff.
- **NEXT — transmit:** the bit-banged `$F4` mouse-enable / `$FF` reset handshake
  (stubbed in both the emulator and `lib_ps2` today).

See the BACKLOG "PS/2 keyboard + mouse card" item for the full plan (packaging
options, the bridge reverse-channel, and the emulator feed paths).
