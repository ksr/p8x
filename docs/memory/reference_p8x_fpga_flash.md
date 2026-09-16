---
name: reference_p8x_fpga_flash
description: openFPGALoader IS available (oss-cad-suite); how to build + flash the Tang Nano 20K from this Mac
metadata:
  type: reference
---

Flashing the Tang Nano 20K works from this Mac — the earlier "openFPGALoader NOT
installed" belief was WRONG. `openFPGALoader` ships in oss-cad-suite
(`~/oss-cad-suite/bin`); `source ~/oss-cad-suite/environment` first.

- **Detect (read-only):** `openFPGALoader -b tangnano20k --detect` → idcode
  `0x81b`, Gowin `GW2A(R)-18(C)`. Two `/dev/cu.usbserial-*` devices (dual UART).
- **Build the bitstream:** `cd fpga/tang-nano-20k && ./build.sh card build` (or
  `lcd`) → `p8x_card.fs`. Needs `gtxt.v` in the SRC list (added for the overlay).
- **Flash persistent:** `openFPGALoader -b tangnano20k -f p8x_card.fs` (erases +
  writes onboard SPI flash, ~1 min; survives power-cycle). Omit `-f` for a
  VOLATILE SRAM load (gone on power-off) — good for a test before committing.

The 2026-09-15 [[project_p8x_gfx_clib]] text overlay ([[project_p8x_two_mode]])
was built (card places 18,602/20,736 LUT4 = 89%, 9/46 BSRAM, 91.89 MHz
post-route) and flashed persistent. The card personality has NO CPU on chip, so
the overlay's console text still needs a master (emulator `-B` / `runcard.sh`
running the updated firmware) to send the TX* opcodes.
