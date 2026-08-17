---
name: project_p8x_fpga
description: Planned standalone FPGA version of P8X — same microarchitecture; TTL bus build continues but delayed
metadata: 
  node_type: memory
  type: project
  originSessionId: df90e3f3-8668-416d-bc7b-83f2952ba723
  modified: 2026-07-29T17:59:35.974Z
---

As of 2026-07-29 the user has committed to building a **standalone FPGA version
of P8X** (whole system in one FPGA, NOT a bus/backplane-connected card set).

**Status 2026-08-11: Milestone 1 is GREEN.** `fpga/sim/run.sh` matches the RTL
against the emulator cycle-for-cycle to 200 000 microcycles (Icarus 13.0, via
`brew install icarus-verilog`). The hand transliteration was correct on its first
real execution — no RTL fix has been needed. Coverage is now **all 88 opcodes**
via `fpga/sim/isa_test.asm` (`./run.sh 60000 isa_test.asm`), a directed exerciser
that ends in HLT so both sides stop together. Monitor boot alone was only 12/88 —
it idles in the console-poll loop, so cycle count never bought coverage; stimulus
did. The ISA count comes from `genucode.py`'s `OPC` dict (88 distinct codes, 91
entries — JZ/BZ, JNZ/BNZ, JC/BCP are aliases); don't count it by regex over the
source, that undercounts.

**Milestone 2 is also GREEN (2026-08-11).** The ACIA is modelled on both sides and
`./run.sh 200000 "" console_in.txt` drives the monitor with scripted keystrokes,
matching 200k cycles AND diffing console output byte-for-byte (2380 bytes: banner,
help, a $0100 dump, an examine session). The console model is deliberately
timing-free — RDRF = "the script still has a byte", one byte consumed per $FF05
read — which is what makes it co-simulable at all. Key gotcha: the consume must
key off the new `mem_rd` CPU output (`doe==7`, the microcycles that source the bus
from memory, mirroring where p8xemu calls memrd), NOT off `mem_addr==$FF05`, which
lingers across microcycles and would double-consume.

**CF-IDE is modelled too (2026-08-11): P8X/OS BOOTS ON THE RTL.**
`./run.sh 2000000 "" boot_in.txt os/run-disk.img` matches 2M cycles + console;
`./console.sh "" os/run-disk.img` boots and runs `pwd`/`dir` off the simulated
disk (shell wants **lowercase** command names; `DIR` gets `?`). The CF model
lives in the testbench, reading sectors on demand with `$fseek` — a 6 MB image
will not fit in a Verilog array. The disk is always a COPY in `work/`, but write
behaviour differs by mode: `run.sh` opens it read-only and DISCARDS writes (the
co-sim must not mutate what it is diffing), while `console.sh` passes **`+cfrw`**
and flushes them. Discarding them in the interactive console was a real bug —
BASIC's `SAVE` printed "Saved" and the file vanished on exit, because the CF model
reported success and dropped the data.

**HAZARD, cost 80 GB:** p8xemu dropped its cycle cap whenever `isatty(0)` ("no
cap while typing") — with `-T` that streams a trace line per cycle, so `run.sh`
launched from a terminal ignored `-l` and filled the disk. Worse, an orphaned
p8xemu kept the unlinked file open, so `rm` freed nothing until `pkill p8xemu`.
Fixed: `-N`/`-i` suppress interactive mode, explicit `-l` always wins, and run.sh
aborts if the trace exceeds the cycle count. **If a sim run dies oddly, check
`pgrep p8xemu` first.**

**MILESTONE 0 DONE ON REAL HARDWARE (2026-08-12): first light.** Tang Nano 20K
echoes over USB serial — sent `P8X Hello!`, got it back byte for byte. Build with
`fpga/tang-nano-20k/build.sh [build|load|flash]`.

Hardware-flow gotchas, all cost time once:
- oss-cad-suite is a tarball in `~/oss-cad-suite` — **no admin rights needed**, so
  it sidesteps the `/opt/homebrew` permission problem (that dir is owned by
  `ksr77-adm`, and `ksr77` is not in the `admin` group; see [[feedback_ecad_schematic_truth]]
  for the general "check before assuming" habit).
- **`xattr -dr com.apple.quarantine ~/oss-cad-suite`** or every binary refuses to run.
- nextpnr **requires `--vopt family=GW2A-18C`** for this part; without it it errors
  and stops. The original README omitted it.
- The BL616 bridge exposes **two** `/dev/cu.usbserial-*`: the **higher-numbered is
  the console**, the other is JTAG and returns garbage. Use `cu.`, not `tty.`.
- Design is tiny: 219/20736 LUT4 (1%), 109/15552 DFF — lots of room for the core.

**MILESTONE 3 DONE ON HARDWARE (2026-08-12): the CPU runs the monitor on the
Tang Nano.** `fpga/tang-nano-20k/build.sh cpu load`, then talk to the console
port at 115200 — banner, `?` help, `D 0100` ROM dump, `E 3000` RAM write/read-back
all verified on the board.

Two substrate problems had to be solved, neither visible in the co-sim:

1. **A microcycle needs TWO DEPENDENT BRAM reads.** Fetch the microcode word,
   THEN use its PSEL field to pick the pointer that drives mem_addr, THEN read
   memory. One clock edge cannot do both — a single falling-edge latch reads
   memory with the *previous* word's PSEL and derails the machine within ten
   cycles (symptom: IR=00 where the emulator has 37, at cycle 9). Fix: p8x_cpu
   gained a **`cen` clock enable** (its only sequential block, so a one-line
   change; p8x_soc ties it high and the co-sim is unaffected), and the board runs
   **three fabric phases per microcycle** — phase 0 ucode read, phase 1 memory
   read, phase 2 commit. 27 MHz / 3 = **9 MHz effective**.
2. **BRAM did not fit — solved WITHOUT SDRAM (2026-08-12).** 64K memory +
   8192x32 microcode = 47 blocks; GW2AR-18 has 46. All 32 microcode bits are
   used, so width could not be shaved — but the *opcode axis* is mostly empty:
   88 of 256 encodings are defined and **all 168 undefined ones hold the same
   microcode word** (verified, and `mk_compact_ucode.py` re-checks it and aborts
   if that ever changes). Squeeze IR through a combinational 256-entry map to a
   7-bit index (88 opcodes + 1 shared undefined slot) and the ROM halves to
   4096x32 (~8 blocks). Result: **full 64K memory, 40/46 BSRAM, Fmax ~50 MHz**,
   and LUT use actually *dropped*. Verified on hardware: $2000 and $A000 are now
   distinct, and $F000 holds data. **No SDRAM controller needed** — the 'R' in
   GW2AR stays unused for now.
   The map MUST be LUT logic, not BRAM: it has to resolve inside the microcode
   fetch phase. The CPU is untouched; the remap lives entirely in p8x_top.

Also: `openFPGALoader --detect` without `-b tangnano20k` intermittently reports
no device; always pass `-b tangnano20k`.

**SD-over-SPI WORKS ON HARDWARE (2026-08-12).** `rtl/sd_spi.v` (CMD0/CMD8/
ACMD41/CMD58 init ladder, CMD17 read, CMD24 write; 400 kHz until init then
6.75 MHz) + `rtl/cf_sd.v` (presents the $FF10-$FF17 CF task file the BIOS
already drives, unchanged firmware). microSD pins in SPI mode, verified against
Sipeed's pinout: **CLK 83, CMD=MOSI 82, DAT0=MISO 84, DAT3=CS 81**.

- The one real difference from the emulator: it never asserts **BSY** (instant
  transfers), hardware must. CFWAIT spins on BSY ~4096 polls ≈ 14 ms at 9 MHz —
  plenty for a single block, so the firmware needed no change.
- SDHC vs SDSC: CMD58's CCS bit decides whether LBA is a **block** or a **byte**
  offset. Getting it wrong reads 512x off and looks like a corrupt filesystem.
- **IDENTIFY must be gated on sd_ready.** The model string is generated in RTL,
  so without that gate `I` prints "CF OK" with no card at all and the failure
  only surfaces later as mysterious garbage.
- `sim/sd_model.v` is a behavioural card (serves a real image via $fseek) — the
  OS boots off it in simulation before any hardware runs. It takes **`+sdfail=1`**
  (never initialises) and **`+sdfail=2`** (never releases busy after a write), and
  `sim/tb_sd_spi.v` drives sd_spi directly against them.
- **Both injected faults found a LOCKUP that a healthy card never shows (fixed
  2026-08-12).** `S_WBUSY` had no timeout, so a card dying mid-write left the
  controller busy forever and *every later read and write was silently dropped*;
  and a failed init parked in `S_ERR` re-pulsing `done` every clock, holding
  cf_sd's task file reset with no way out but reloading the bitstream. Also
  bounded ACMD41 by time (4000 rounds ≈ 1.1 s, the spec's limit) instead of an
  arbitrary 20000 that took 5.6 s — long enough that a missing card looked like a
  hang. **Lesson: a model that always behaves tests nothing; make it fail.**

Status on the board: **READ AND WRITE BOTH VERIFIED ON HARDWARE.** The monitor's
`F` formatted a real microSD through the FPGA, and reading LBA 0 back gives
`50 38 02 00 25` = 'P8', v2, OSCNT=0, free@LBA 37 — a valid P8XFS boot block the
FPGA wrote itself. Trick for inspecting a sector without any extra tooling: `B`
reads LBA 0 into SBUF ($6100) *before* it checks the signature, so `B` then
`D 6100` dumps whatever the card returned. (`B` prints "NO OS ON CARD" for no
card, bad signature AND OSCNT=0, so its message alone proves nothing.) **Writing a raw image needs
root (`dd` to /dev/rdiskN); ksr77 is not in `admin` or `operator`** — so either
use another machine, or format on-target with the monitor's `F` command.

**Solved: the board installs its own disk.** `fpga/tang-nano-20k/tools/` —
`osload.asm` (N<256 sectors to LBA 1.. + patch OSCNT) and `imgload.asm` (clone an
arbitrary run from LBA 0). Assemble with `p8xasm --base 0x3000`, poke through the
monitor's `E 3000` (two hex digits set a byte and auto-advance), `G 3000`, stream.
**MILESTONE 4 COMPLETE (2026-08-12): the whole 6 MB disk was cloned by the board
itself and P8X/OS runs the full filesystem on hardware** — `dir` lists bin/ lib/
man/ src/, `cat README.TXT` works, `dir /bin` shows all 30 commands including
cc.bin and vi.bin. 12377 sectors in 687 s (~11 min at 115200). No root, no card
reader.

Verify a clone by reading sectors back: `tools/`-style probe that does
`CFREAD` into $4000 then `D 4000`, diffed against the host image. Spot-checked
LBA 0/1/2/33/37/125/1000/3239/8000/12376 — all match.

Pacing rules: poking through `E` must be **echo-paced** (the ACIA shim holds ONE
byte and the monitor blocks ~87 us echoing each char); sector payload needs no
pacing (receive loop ~4 us/byte vs 87 us on the wire) but the host MUST wait for
the per-sector `.` ack, because CFWRITE takes ms and anything arriving then is lost.

**GOTCHA: the board's USB bridge can WEDGE.** After the long clone the console
port went silent, JTAG stopped answering, and even the known-good Milestone-0
echo bitstream produced nothing — it looked exactly like disk corruption (`B`
spewed `?` endlessly). It was not: an unplug/replug fixed everything and the
cloned card verified byte-perfect. **Before diagnosing a "disk" or "CPU" problem,
load the echo bitstream as a baseline; if that is silent too, power-cycle the
board.** Also drain the port after a replug — the factory LiteX boot text sits
buffered and will be misread as a reply.

**P8X IS NOW IN ONBOARD FLASH (2026-08-12)** — `build.sh cpu flash` — so it is
the power-on default and the factory LiteX demo is gone (Sipeed publish the image
if it is ever wanted back). Historical note, still worth knowing: while the
bitstream lived in **volatile SRAM**, any power cycle reverted the board to LiteX,
whose console answers on the same port — a script then streams happily into it and
reports a mysterious "no ack at sector 0". Always confirm the `*` monitor prompt
before driving the board (`litex>` or `/>` means you are not talking to it) and
verify a poke by reading it back.

- **Same microarchitecture** — keep the horizontal microcode word, the sequencer,
  the pointer model (PSEL address-source select), DOE/DLD selects. The microcode
  binary (from genucode) and the emulator stay the reference. NOT a clean-ISA soft
  core.
- The physical backplane disappears: "cards" become internal RTL modules only.
  Tri-state bus + DOE/DLD enables become **muxes** (FPGAs have no internal
  tri-state). Microcode ROM (28C64) → BRAM init from genucode output. 64K memory
  map → on-chip BRAM. 6850 ACIA → soft UART wrapped to the same register map. CF →
  SD-over-SPI behind the same BIOS block interface. IRQ latches (backlog #26)
  become trivial RTL.
- The memory map and ABI stay identical, so the monitor/OS/BASIC/C-compiler/asm
  boot **unmodified** — the FPGA is a new substrate, not a software re-port.
- **Verification**: co-sim the RTL against the C emulator, diff architectural
  state per cycle — the emulator is the golden model (same adversarial-diff
  discipline used for [[project_p8x]] compiler + bustest work). Sim tool is
  **Icarus** (`iverilog -g2012`), not Verilator: the testbench is behavioral
  Verilog, sim speed was never the constraint, and Icarus is in the same
  oss-cad-suite bundle as the board flow. Run it with `fpga/sim/run.sh`.
- **Board chosen: Sipeed Tang Nano 20K** (Gowin GW2AR-18, GW2AR-LV18QN88C8/I7),
  ordered ~2026-07-29. Picked because ULX3S was hard to find; it's cheap (~$30),
  widely available, has onboard microSD (the disk) and an onboard BL616 USB bridge
  giving USB-JTAG + USB-UART over one USB-C — so the serial console needs NO extra
  hardware. 27 MHz onboard clock. iCE40/iCEBreaker was rejected: its ~120 Kbit
  initializable EBR can't hold P8X's 256 Kbit microcode (would force microcode into
  SPRAM + a SPI-flash boot loader), and no onboard SD. Tang Nano's ~800 Kbit+ BRAM
  holds microcode(256Kbit)+64K memory(512Kbit) initialized, ~768 Kbit, comfortably.
- **Toolchain**: open flow via oss-cad-suite (yosys `synth_gowin` → nextpnr-himbaechel
  `--device GW2AR-LV18QN88C8/I7` → apicula `gowin_pack -d GW2A-18C` → `openFPGALoader
  -b tangnano20k`). Vendor Gowin EDA IDE is the fallback. Console = ACIA-wrapped UART,
  115200 8N1, baud generated in the core (DIV=234 @ 27MHz).
- **Milestone 0 (before the CPU)**: UART echo + heartbeat-LED "first light" to prove
  toolchain + console path. Files drafted (uart.v, top.v, tangnano20k.cst) in chat
  2026-07-29 but NOT yet written to the repo. TODO on board arrival: verify the exact
  Tang Nano 20K UART/LED pin numbers against Sipeed docs (clock=52 confident; UART
  pins flagged 69/70 UNCONFIRMED), then set up an `fpga/tang-nano-20k/` folder.
  Then Milestones 1+: P8X core RTL, co-sim vs emulator.

**The TTL / bus-connected hardware build is NOT cancelled — just delayed.** The
bustest card and backplane work ([[project_p8x]], [[feedback_ecad_schematic_truth]])
still stands; the FPGA is a parallel track, not a replacement. Keep both in mind.

**GRAPHICS DISPLAY -- emulator model done (2026-08-14).** BASIC is getting
`LINE` / `COLOR` / `BOX fill|nofill`, driving a 4.3" Sipeed 480x272 RGB panel.
Scope is deliberately BASIC-only: no text console, so no font, no PUTC hook, no
OS changes, and serial stays the console.

- **The physical bus card will be a Tang Nano 20K + the same panel**, so the
  FPGA-internal device and the card are ONE design: same resolution, same
  command set, same RTL core, same golden model. Only the front-end differs.
  This retired the earlier concern that a hardware drawing engine was affordable
  on FPGA but not in TTL -- there is no TTL engine to build.
- **Geometry is forced by block RAM, not by taste.** 6 spare BSRAM blocks = 12288
  bytes; 480x272 needs 16320 at even 1 bpp, so panel resolution does not fit at
  ANY depth. Framebuffer is **240x136 at 2 bpp** (8160 B, 4 blocks), pixel-doubled
  2x2 to fill the panel with square pixels. 4 pens index a 12-bit RGB palette.
  The 40 used blocks decompose exactly: 32 for the 64K map + 8 for the 4096x32
  compacted microcode.
- **Ports $FF20-$FF2E**, in `gen_memmap.py` (canon). Commands: 01 PLOT 02 LINE
  03 BOX 04 BOXFILL 05 CLS 06 SETPAL 07 CIRCLE 08 CIRCLEFILL 09 POINT, and
  F0 SELFTEST F1 RESET F2 IDENT. `GID0`/`GID1` read $50/$47 ("PG") for presence --
  a single magic byte is useless because an absent card floats to $FF. IDENT
  streams a 14-byte record carrying the GEOMETRY so software can ask, not assume.
- **Two rules the RTL must match exactly**, pinned by `emulator/test/gfx_test.sh`:
  endpoints are INCLUSIVE, and off-screen pixels are DISCARDED (not clipped) --
  coordinates are register pairs and `y*60 + (x>>2)` would otherwise fold x>=240
  onto the start of the next row. Discarding per pixel is the one rule that is
  trivially identical in C and Verilog.
- Coordinates are 16-bit pairs and **a low-byte write CLEARS its high byte**, so
  8-bit software cannot inherit a stale high byte. The pairs exist because this
  panel at native 480x272 needs 9 bits of X (the SDRAM path).
- **Debug-view trap worth remembering:** the first `-G` text renderer point-sampled
  every 2nd column / 4th row, which never visits x=239 or y=135 -- it silently hid
  the right and bottom edges of a full-screen box (exactly where off-by-ones live)
  and lost isolated pixels. It now takes the MAX pen over each 2x4 block: a
  feature can look fatter, but never vanish.
- Card hardware still open: 5 V bus vs 3.3 V Nano needs level translation
  (74LVC245-class) on D0-D7 + address/control; the bus strobe is asynchronous to
  27 MHz and needs synchronising.

**GRAPHICS DISPLAY -- emulator model done (2026-08-14).** BASIC is getting
`LINE` / `COLOR` / `BOX fill|nofill`, driving a 4.3" Sipeed 480x272 RGB panel.
Scope is deliberately BASIC-only: no text console, so no font, no PUTC hook, no
OS changes, and serial stays the console.

- **The physical bus card will be a Tang Nano 20K + the same panel**, so the
  FPGA-internal device and the card are ONE design: same resolution, same
  command set, same RTL core, same golden model. Only the front-end differs.
  This retired the earlier concern that a hardware drawing engine was affordable
  on FPGA but not in TTL -- there is no TTL engine to build.
- **Geometry is forced by block RAM, not by taste.** 6 spare BSRAM blocks = 12288
  bytes; 480x272 needs 16320 at even 1 bpp, so panel resolution does not fit at
  ANY depth. Framebuffer is **240x136 at 2 bpp** (8160 B, 4 blocks), pixel-doubled
  2x2 to fill the panel with square pixels. 4 pens index a 12-bit RGB palette.
  The 40 used blocks decompose exactly: 32 for the 64K map + 8 for the 4096x32
  compacted microcode.
- **Ports $FF20-$FF2E**, in `gen_memmap.py` (canon). Commands: 01 PLOT 02 LINE
  03 BOX 04 BOXFILL 05 CLS 06 SETPAL 07 CIRCLE 08 CIRCLEFILL 09 POINT, and
  F0 SELFTEST F1 RESET F2 IDENT. `GID0`/`GID1` read $50/$47 ("PG") for presence --
  a single magic byte is useless because an absent card floats to $FF. IDENT
  streams a 14-byte record carrying the GEOMETRY so software can ask, not assume.
- **Two rules the RTL must match exactly**, pinned by `emulator/test/gfx_test.sh`:
  endpoints are INCLUSIVE, and off-screen pixels are DISCARDED (not clipped) --
  coordinates are register pairs and `y*60 + (x>>2)` would otherwise fold x>=240
  onto the start of the next row. Discarding per pixel is the one rule that is
  trivially identical in C and Verilog.
- Coordinates are 16-bit pairs and **a low-byte write CLEARS its high byte**, so
  8-bit software cannot inherit a stale high byte. The pairs exist because this
  panel at native 480x272 needs 9 bits of X (the SDRAM path).
- **Debug-view trap worth remembering:** the first `-G` text renderer point-sampled
  every 2nd column / 4th row, which never visits x=239 or y=135 -- it silently hid
  the right and bottom edges of a full-screen box (exactly where off-by-ones live)
  and lost isolated pixels. It now takes the MAX pen over each 2x4 block: a
  feature can look fatter, but never vanish.
- Card hardware still open: 5 V bus vs 3.3 V Nano needs level translation
  (74LVC245-class) on D0-D7 + address/control; the bus strobe is asynchronous to
  27 MHz and needs synchronising.

**GRAPHICS RTL DONE IN SIM (2026-08-14).** `fpga/rtl/gfx.v` (registers, drawing
engine, framebuffer, palette) + `fpga/rtl/video_rgb.v` (480x272 timing, 2x-doubled
scanout). `fpga/sim/gfx.sh` byte-compares the RTL's frame against `p8xemu -g`:
IDENTICAL for both payloads. Fits the board -- **BSRAM 44/46**, Fmax 49 MHz, and
**no PLL** (9.009 MHz wanted, 27/3 = 9.000 from the divider the CPU already uses).

- **THE BUSY CONTRACT is the big lesson.** The emulator draws instantaneously and
  never raises BUSY; the RTL takes ~2.4 ms for a full fill, and **a command
  written while another is running ABORTS it**. Software MUST poll GSTAT bit 7.
  Code written against the emulator alone looks perfect there and draws a few
  scattered pixels on the RTL. BASIC has GWAIT/GEXEC; the payloads call GWAIT
  before every command. The poll is free when BUSY is never set, so ONE binary is
  correct on both -- which is what makes the frame comparison meaningful.
- **Graphics cannot be CYCLE-diffed**, unlike the CPU: a program polling GSTAT
  legitimately reads different values on the two models. The FRAMEBUFFER is what
  must agree, so `gfx.sh` is a frame diff, not a trace diff.
- Two RTL bugs the frame diff caught, both invisible to inspection: the pixel
  read-modify-write acted on `e_rdata` a cycle early (right for the first pixel of
  every byte, wrong for its three neighbours, because 2bpp packs four per byte);
  and `y*60` computed as `(y<<6)-(y<<2)` in a 13-bit expression WRAPPED for y>127,
  folding the bottom rows back to the top. Intermediates must be wider than the
  result.
- **SUPERSEDED (2026-08-16): this is DONE on hardware** -- see the block at the
  end of this note. The paragraph below is kept for the reasoning only.
- **WAS BLOCKED on the pinout:** `build.sh lcd` synthesises but failed PnR with
  `Unconstrained IO:lcd_*` -- `tangnano20k.cst` has no `lcd_*` entries because the
  40-pin RGB mapping is not verified against Sipeed's docs. 20 pins to add. This
  is deliberate: guessed pin numbers are how a panel stays dark for a day.
  `build.sh cpu` is untouched and still 40/46.

**GRAPHICS RTL DONE IN SIM (2026-08-14).** `fpga/rtl/gfx.v` (registers, drawing
engine, framebuffer, palette) + `fpga/rtl/video_rgb.v` (480x272 timing, 2x-doubled
scanout). `fpga/sim/gfx.sh` byte-compares the RTL's frame against `p8xemu -g`:
IDENTICAL for both payloads. Fits the board -- **BSRAM 44/46**, Fmax 49 MHz, and
**no PLL** (9.009 MHz wanted, 27/3 = 9.000 from the divider the CPU already uses).

- **THE BUSY CONTRACT is the big lesson.** The emulator draws instantaneously and
  never raises BUSY; the RTL takes ~2.4 ms for a full fill, and **a command
  written while another is running ABORTS it**. Software MUST poll GSTAT bit 7.
  Code written against the emulator alone looks perfect there and draws a few
  scattered pixels on the RTL. BASIC has GWAIT/GEXEC; the payloads call GWAIT
  before every command. The poll is free when BUSY is never set, so ONE binary is
  correct on both -- which is what makes the frame comparison meaningful.
- **Graphics cannot be CYCLE-diffed**, unlike the CPU: a program polling GSTAT
  legitimately reads different values on the two models. The FRAMEBUFFER is what
  must agree, so `gfx.sh` is a frame diff, not a trace diff.
- Two RTL bugs the frame diff caught, both invisible to inspection: the pixel
  read-modify-write acted on `e_rdata` a cycle early (right for the first pixel of
  every byte, wrong for its three neighbours, because 2bpp packs four per byte);
  and `y*60` computed as `(y<<6)-(y<<2)` in a 13-bit expression WRAPPED for y>127,
  folding the bottom rows back to the top. Intermediates must be wider than the
  result.
- **SUPERSEDED (2026-08-16): this is DONE on hardware** -- see the block at the
  end of this note. The paragraph below is kept for the reasoning only.
- **WAS BLOCKED on the pinout:** `build.sh lcd` synthesises but failed PnR with
  `Unconstrained IO:lcd_*` -- `tangnano20k.cst` has no `lcd_*` entries because the
  40-pin RGB mapping is not verified against Sipeed's docs. 20 pins to add. This
  is deliberate: guessed pin numbers are how a panel stays dark for a day.
  `build.sh cpu` is untouched and still 40/46.

**GRAPHICS WORKING ON THE PANEL (2026-08-16).** `build.sh lcd load`, then
`I`/`B`/`basic`, and BASIC's LINE/BOX/CIRCLE draw on the 4.3" panel.

- **Pinout and timings came from Sipeed's own example**, not from arithmetic
  (`TangNano-20K-example`, `rgb_lcd/lcd_480_272/color_bar`). Three things I had
  guessed WRONG: there is no HSYNC/VSYNC (DE-only panel); the frame is 560x297,
  i.e. **54.11 Hz not 60**; they clock it at 9 MHz via IDIV=2 (27/3), confirming
  no PLL. Pins CLK 77, DEN 48, R 38-42, G 32-37, B 27-31.
- **A shift AMOUNT is self-determined in Verilog.**
  `fb_data >> ((2'd3 - ax[2:1]) << 1)` evaluated in TWO bits, giving shifts of
  2,0,2,0 instead of 6,4,2,0 -- every pixel in the left half of a byte invisible,
  every one in the right half drawn twice. Assignment context would have widened
  it; a shift amount is not an assignment context. Same class as the `y*60`
  truncation. **Symptom was asymmetric**: horizontal lines perfect, verticals
  doubled or missing, because a horizontal line is constant along x.
- **True dual-port halves a Gowin block's usable depth.** The framebuffer took 8
  blocks instead of 4 (48/46, would not place). Now ONE shared port, engine holds
  one cycle in three. And a shared read written as
  `if (en) a <= mem[x]; else b <= mem[x];` is NOT synthesisable as block RAM --
  yosys falls back to distributed LUT RAM. One read register feeding both works.
- **`build.sh ... load` reprograms a STALE bitstream if the build failed.** That
  hid the 48/46 failure for two rounds and made fixes look ineffective. Check
  `p8x_cpu.fs` mtime when a change appears to do nothing.
- **What the user's second data point bought:** I had diagnosed a setup-time
  problem (real, and fixed) and would have kept chasing it. `BOX 10,10,20,20`
  losing its right edge entirely falsified that -- a smear cannot DELETE a line.
- **Unresolved:** the co-sim now exercises the shared port with an irregular
  hold, but reintroducing the pending-write bug did not make it fail. Coverage
  unproven.

**GRAPHICS WORKING ON THE PANEL (2026-08-16).** `build.sh lcd load`, then
`I`/`B`/`basic`, and BASIC's LINE/BOX/CIRCLE draw on the 4.3" panel.

- **Pinout and timings came from Sipeed's own example**, not from arithmetic
  (`TangNano-20K-example`, `rgb_lcd/lcd_480_272/color_bar`). Three things I had
  guessed WRONG: there is no HSYNC/VSYNC (DE-only panel); the frame is 560x297,
  i.e. **54.11 Hz not 60**; they clock it at 9 MHz via IDIV=2 (27/3), confirming
  no PLL. Pins CLK 77, DEN 48, R 38-42, G 32-37, B 27-31.
- **A shift AMOUNT is self-determined in Verilog.**
  `fb_data >> ((2'd3 - ax[2:1]) << 1)` evaluated in TWO bits, giving shifts of
  2,0,2,0 instead of 6,4,2,0 -- every pixel in the left half of a byte invisible,
  every one in the right half drawn twice. Assignment context would have widened
  it; a shift amount is not an assignment context. Same class as the `y*60`
  truncation. **Symptom was asymmetric**: horizontal lines perfect, verticals
  doubled or missing, because a horizontal line is constant along x.
- **True dual-port halves a Gowin block's usable depth.** The framebuffer took 8
  blocks instead of 4 (48/46, would not place). Now ONE shared port, engine holds
  one cycle in three. And a shared read written as
  `if (en) a <= mem[x]; else b <= mem[x];` is NOT synthesisable as block RAM --
  yosys falls back to distributed LUT RAM. One read register feeding both works.
- **`build.sh ... load` reprograms a STALE bitstream if the build failed.** That
  hid the 48/46 failure for two rounds and made fixes look ineffective. Check
  `p8x_cpu.fs` mtime when a change appears to do nothing.
- **What the user's second data point bought:** I had diagnosed a setup-time
  problem (real, and fixed) and would have kept chasing it. `BOX 10,10,20,20`
  losing its right edge entirely falsified that -- a smear cannot DELETE a line.
- **Unresolved:** the co-sim now exercises the shared port with an irregular
  hold, but reintroducing the pending-write bug did not make it fail. Coverage
  unproven.
