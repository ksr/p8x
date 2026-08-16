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

## Toolchain — open flow

**Verified working 2026-08-12** on macOS 26 / Apple Silicon with oss-cad-suite
2026-08-12 (yosys 0.68, nextpnr 0.11.1, openFPGALoader 1.1.1).

Install YosysHQ **oss-cad-suite** (bundles yosys, nextpnr-himbaechel, apicula's
`gowin_pack`, and `openFPGALoader`): download the `darwin-arm64` release tarball,
extract to `~/oss-cad-suite`, then **clear the Gatekeeper quarantine** or every
binary fails to launch:

```bash
xattr -dr com.apple.quarantine ~/oss-cad-suite
```

No admin rights are needed — it is a self-contained tarball in your home
directory, which is why it sidesteps the Homebrew permission problem entirely.

Then just:

```bash
./build.sh          # synthesize -> place & route -> pack
./build.sh load     # ... and load to SRAM (volatile)
./build.sh flash    # ... and write onboard flash (persistent)
```

`build.sh` sources `~/oss-cad-suite/environment` itself if the tools are not
already on PATH. The steps it runs, if you want them by hand:

```bash
yosys -p "read_verilog rtl/top.v rtl/uart.v; synth_gowin -top top -json p8x.json"

nextpnr-himbaechel --json p8x.json --write pnr.json \
  --device "GW2AR-LV18QN88C8/I7" \
  --vopt family=GW2A-18C \
  --vopt cst=tangnano20k.cst

gowin_pack -d GW2A-18C -o p8x.fs pnr.json
openFPGALoader -b tangnano20k p8x.fs
```

> **`--vopt family=GW2A-18C` is required.** Without it nextpnr stops with
> *"For the GW2A series you need to specify --vopt family=GW2A-18 or
> --vopt family=GW2A-18C"*. The earlier version of this file omitted it.

> If the open-flow device strings fight you, the free vendor **Gowin EDA** IDE is
> the fallback: new project → device `GW2AR-LV18QN88C8/I7` → add `rtl/top.v`,
> `rtl/uart.v`, `tangnano20k.cst` → Synthesize → Place & Route → Program.
> `openFPGALoader` still flashes it.

Resource use is tiny — 219/20736 LUT4 (1%), 109/15552 DFF — so there is ample
room for the CPU core, the 64K memory, and the microcode BRAM in Milestone 3.

## Connect a terminal

The BL616 bridge enumerates **two** serial devices. The **higher-numbered one is
the UART**; the other is the JTAG side and returns garbage if you talk to it:

```bash
tools/term.py                              # exit: Ctrl-]
```

Convenient because it finds the console port itself (the bridge exposes two) and
quits with `Ctrl-]`. Nothing more than that: since 2026-08-13 `CONOUT` expands a
bare LF into CR LF in firmware, so P8X renders correctly on **any** terminal.

> **A flashed board keeps the ROM it was built with.** `build.sh cpu` bakes
> `emulator/eeprom.bin` into the bitstream's BRAM, so a board flashed before that
> firmware change still emits bare LF. Rebuild and reflash to pick it up:
> `./build.sh cpu flash`.

A stock terminal works just as well:

```bash
ls /dev/cu.usbserial-*
#   /dev/cu.usbserial-<N>0    <- JTAG   (not this one)
#   /dev/cu.usbserial-<N>1    <- console

screen /dev/cu.usbserial-<N>1 115200       # exit: Ctrl-A then k
# or: picocom -b 115200 /dev/cu.usbserial-<N>1
```

Use `/dev/cu.*`, not `/dev/tty.*` — the `tty.` node blocks on carrier detect.

## Success looks like — confirmed on hardware 2026-08-12

Sending `P8X Hello!` to the console port returned `P8X Hello!` byte for byte.



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

## Simulation of the board build

`sim/` holds benches for the board-level design — the things the co-sim in
[`../sim/`](../sim/README.md) cannot cover, because they are about the *substrate*
(block RAM, a real UART, an actual SD card) rather than the CPU core.

| Bench | What it proves |
|-------|----------------|
| `sim/tb_top.v` | Milestone-0 echo path at the real 115200-for-27MHz bit period |
| `sim/tb_p8x_top.v` | the whole board top: monitor banner out of the real UART, and P8X/OS booting off a modelled card |
| `sim/sd_model.v` | a behavioural SPI microSD, serving a real disk image via `$fseek` |
| `sim/tb_sd_spi.v` | `sd_spi.v`'s **error** paths, driven directly |

```sh
cd sim
iverilog -g2012 -o tb.vvp ../../rtl/p8x_cpu.v ../rtl/p8x_top.v ../rtl/uart.v \
                          ../rtl/cf_sd.v ../rtl/sd_spi.v sd_model.v tb_p8x_top.v
vvp tb.vvp +sd=../../sim/work/disk.img          # boots the OS in simulation
```

### Making the card fail on purpose

A card model that always behaves only ever exercises the happy path, and that is
exactly where this controller had bugs. `sd_model.v` therefore takes `+sdfail=N`:

| `+sdfail=` | Injected fault |
|-----------|----------------|
| `0` (default) | healthy card |
| `1` | never initialises — ACMD41 reports busy forever |
| `2` | never releases busy after a write |

```sh
iverilog -g2012 -o tb_sd_spi.vvp ../rtl/sd_spi.v sd_model.v tb_sd_spi.v
for m in 0 1 2; do vvp tb_sd_spi.vvp +sd=../../sim/work/disk.img +sdfail=$m; done
```

Both faults found a **lockup** that a healthy card never reveals:

- **`sdfail=2`** — `S_WBUSY` waited for the card to release busy with no bound. A
  card that dies mid-write left the controller busy forever: the CPU's `CFWAIT`
  gives up after ~4096 polls and reports an error, but the controller never
  returned to idle, so *every later read and write was silently dropped*. Now
  timed out.
- **`sdfail=1`** — a failed initialisation parked in `S_ERR` re-asserting `done`
  every clock, which held `cf_sd`'s task file permanently reset, and there was no
  way out short of reloading the bitstream. A card inserted a second late stayed
  dead. Now backs off and retries the ladder.

The same work bounded ACMD41 by **time** rather than an arbitrary retry count:
4000 rounds is ~1.1 s at the init clock, which is the SD spec's own limit. The
previous 20000 took **5.6 s**, long enough that a missing card made the whole
machine look hung.

## The graphics panel (`build.sh lcd`)

`build.sh cpu` is unchanged and does **not** include the display. The panel is a
separate target:

```sh
./build.sh lcd load
```

**It will fail place-and-route today**, with `ERROR: Unconstrained IO:lcd_*`, and
that failure is deliberate. `tangnano20k.cst` has no `lcd_*` entries because the
40-pin RGB mapping has not been verified against Sipeed's documentation, and this
file's header records why that matters: every other pin here was checked against
the official pinout and a known-good project first. A bitstream built on guessed
pin numbers is how a display stays dark for a day.

To finish it, add the verified `IO_LOC` lines for `lcd_clk`, `lcd_de`, `lcd_hs`,
`lcd_vs`, `lcd_r[4:0]`, `lcd_g[5:0]`, `lcd_b[4:0]` — 20 pins — and check the
panel's own timings against its datasheet while you are there.

**It does fit.** Synthesised and placed with a scratch pinout:

| | with graphics | without |
|---|---|---|
| BSRAM | **44 / 46** | 40 / 46 |
| LUT4 | 10403 / 20736 | 8029 |
| Fmax | 49.0 MHz | 48.8 MHz |

The framebuffer costs 4 blocks (8160 bytes at 2 bits per pixel) and leaves two
spare. **No PLL is needed**: 480x272 at 60 Hz wants 9.009 MHz and 27/3 is 9.000,
the same divide-by-three the CPU already runs on, so both rPLLs stay free for the
Milestone-5 clock-up.

`sim/tb_video.v` checks the frame geometry without any hardware — 480 active
pixels a line, 272 lines, 450450 cycles a frame (59.94 Hz), and a scanout that
stays inside the framebuffer.
