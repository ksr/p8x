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
will not fit in a Verilog array. Disk is copied and opened read-only.

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

Still uncovered: SD-over-SPI (Milestone 4 — different silicon, same BIOS block
API). Next is Milestone 3: drop the proven CPU core in where the echo logic sits.

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
