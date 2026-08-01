# Tang Nano 20K — Milestone 0: first light

Proves the toolchain and console path before any CPU exists. The bitstream
echoes bytes over the USB serial link and blinks LED0. When this works, the P8X
core drops in where the echo logic sits in `rtl/top.v`.

Board: **Sipeed Tang Nano 20K**, Gowin **GW2AR-LV18QN88C8/I7**, 27 MHz clock.

## Files

| File | What |
|------|------|
| `rtl/uart.v` | 8N1 UART, TX + RX, DIV=234 (115200 @ 27 MHz) |
| `rtl/top.v` | echo + heartbeat, internal power-on reset |
| `tangnano20k.cst` | pin constraints (clk 4, uart_tx 69, uart_rx 70, led 15–20) |

## Wiring

**None.** A single **USB-C cable** does both programming and the serial console,
through the board's onboard BL616 USB↔JTAG/UART bridge.

## Toolchain — open flow (recommended)

Install YosysHQ **oss-cad-suite** (bundles yosys, nextpnr-himbaechel, apicula's
`gowin_pack`, and `openFPGALoader`). On macOS: download the release tarball,
extract, then `source <path>/oss-cad-suite/environment`.

From this directory:

```bash
# 1. synthesize
yosys -p "read_verilog rtl/top.v rtl/uart.v; synth_gowin -top top -json p8x.json"

# 2. place & route
nextpnr-himbaechel --json p8x.json --write pnr.json \
  --device "GW2AR-LV18QN88C8/I7" \
  --vopt cst=tangnano20k.cst

# 3. pack to a bitstream
gowin_pack -d GW2A-18C -o p8x.fs pnr.json

# 4. load to SRAM (volatile) — or add -f to write onboard flash (persistent)
openFPGALoader -b tangnano20k p8x.fs
```

> If the open-flow device strings fight you on the first try, the free vendor
> **Gowin EDA** IDE is the fallback: new project → device
> `GW2AR-LV18QN88C8/I7` → add `rtl/top.v`, `rtl/uart.v`, `tangnano20k.cst` →
> Synthesize → Place & Route → Program. `openFPGALoader` still flashes it.

## Connect a terminal

```bash
ls /dev/tty.*                 # note devices, then plug in the board and re-run
screen /dev/tty.usbserial-XXXX 115200      # exit: Ctrl-A then k
# or: picocom -b 115200 /dev/tty.usbserial-XXXX
```

## Success looks like

- **LED0 blinks** ~once a second (heartbeat).
- Every character you **type echoes back** in the terminal (type at a human pace;
  this first-light echo drops a char if you paste a fast burst — that's fine, the
  real UART gets flow handling later).

That confirms clock, synthesis, bitstream, UART, and console — the whole
substrate the P8X core will sit on.

## Notes

- 115200 8N1. Baud is `clk / DIV` in the UART; change both `DIV` and the terminal
  to rescale.
- Pins verified 2026-08 against Sipeed's pinout and a known-good project `.cst`.
- Reset button KEY2 is pin 87 — unused here; `top.v` self-resets at power-on.
