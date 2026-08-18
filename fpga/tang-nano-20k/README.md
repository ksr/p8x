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
./build.sh cpu            # synthesize -> place & route -> pack
./build.sh cpu load       # ... and load to SRAM (volatile)
./build.sh cpu flash      # ... and write onboard flash (persistent)
./build.sh lcd load       # the CPU plus the 480x272 graphics panel
./build.sh echo load      # Milestone-0 UART echo, a known-good baseline
```

**Give the target explicitly.** The form is `build.sh [echo|cpu|lcd]
[build|load|flash]`, and the first argument is the TARGET — it defaults to
`echo`, so a bare `./build.sh` builds the Milestone-0 blinker, and
`./build.sh load` is rejected outright with *"unknown target: load"* because
`load` is an action in the second position. This block used to show exactly that
target-less form, left over from when there was only one design.

`build.sh` sources `~/oss-cad-suite/environment` itself if the tools are not
already on PATH. The steps it runs, if you want them by hand:

```bash
# (the Milestone-0 echo design; the cpu/lcd targets pass more sources and -DLCD)
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

Resource use for that echo design is tiny — 219/20736 LUT4 (1%), 109/15552 DFF.
The real builds are much larger: `cpu` is 40/46 block RAMs, and `lcd` 42/46 with
the panel and the SD sector buffer. See *The graphics panel* below.

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
| `sim/tb_video.v` | panel frame geometry: 480x272 active, 54.11 Hz |
| `sim/tb_scanout.v` | the framebuffer-to-panel **mapping**, pixel by pixel |
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

The pinout and the panel timings are **verified**, taken from Sipeed's own
480x272 example for this board (`TangNano-20K-example`,
`rgb_lcd/lcd_480_272/color_bar`) rather than derived. Three things that example
settled, all of which I had guessed wrong:

- there is **no HSYNC or VSYNC** — their constraints file has pins for CLK, DEN
  and RGB only, so this is a DE-only panel;
- the real frame is **560x297**, not 525x286 (H 480+50+30, V 272+20+5), which is
  **54.11 Hz**, not 60;
- they clock it at **9 MHz** via an rPLL with IDIV=2 — i.e. 27/3, exactly the
  divider the CPU already runs on, confirming no PLL is needed.

Pins: CLK 77, DEN 48, R 38–42, G 32–37, B 27–31, `DRIVE=24 PULL_MODE=UP`.

**It fits with room to spare.** Measured from the shipped `build.sh lcd` on the
`sdram-framebuffer` branch:

| | `lcd` | history |
|---|---|---|
| BSRAM | **42 / 46** (91%) | 44 / 46 when the framebuffer was in block RAM |
| LUT4 | **7226 / 20736** (34%) | 13288 (64%), then 15397 (74%, would not place) |
| DFF | 1581 / 15552 (10%) | 5657 |
| Fmax | **51.6 MHz** | 38.8 MHz |

Two changes account for the drop, and neither is a graphics change. The
framebuffer moved out of block RAM into the in-package SDRAM, and the SD sector
buffer stopped inferring 4,096 flip-flops (see below). At 34% LUT4 the placement
cliff described in [BACKLOG.md](../../BACKLOG.md) is no longer load-bearing —
name mangling still perturbs the placer, it just no longer decides whether the
build succeeds.

**No PLL is needed**: 480x272 at 60 Hz wants 9.009 MHz and 27/3 is 9.000, the
same divide-by-three the CPU already runs on, so both rPLLs stay free for the
Milestone-5 clock-up.

**The 512-byte SD sector buffer is one BSRAM, and staying that way is a
constraint on how `rtl/cf_sd.v` is written.** yosys maps an array onto a RAM
primitive only if it has ONE write port; the IDENTIFY command used to fill all
512 entries in a single cycle, which is 512 write ports, so the buffer fell back
to 4,096 discrete flops plus a 512-entry read mux — more than half the logic in
the design. The fill is now sequential and every writer muxes onto one port. If
you ever see `using FF mapping for memory p8x_top.CF.buf_` in `synth.log`,
something has grown a second write port.

> The section below describes the **superseded** block-RAM framebuffer
> (240x136, 2 bpp). The device is now single-mode 480x272 at 8 bpp with the
> framebuffer in SDRAM; see [sdram/README.md](sdram/README.md).

The framebuffer cost 4 blocks (8160 bytes at 2 bits per pixel) and left two
spare. **The framebuffer shared ONE port** between the drawing engine and the
scanout. True dual port halves a Gowin block's usable depth, so 8160 bytes would
have cost 8 blocks instead of 4 and the design would not have placed at 48/46.
The scanout needed a byte only once per eight panel pixels, so the engine simply
held for that cycle.

Two benches check this without hardware:

- `sim/tb_video.v` — frame geometry: 480 active pixels a line, 272 lines,
  498960 cycles a frame (54.11 Hz), scanout inside the framebuffer.
- `sim/tb_scanout.v` — the **mapping**: which framebuffer pixel reaches which
  panel pixel. Neither of the other tests covered that, which is how a
  shift-width bug that blanked half of every byte reached hardware.
