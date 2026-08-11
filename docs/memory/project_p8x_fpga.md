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
real execution — no RTL fix was needed. **But the PASS is narrow**: after boot the
monitor idles in the console-poll loop, so 200k cycles cover no more than 20k —
19 opcodes, 114 PCs. Most of the ISA is un-co-simulated; closing it needs
*stimulus* (a directed all-opcode ROM, or deterministic scripted console input),
not a bigger cycle count. Board toolchain (oss-cad-suite) still not installed —
only needed from Milestone 3.

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
