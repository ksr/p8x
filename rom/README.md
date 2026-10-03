# rom/ — burnable image set

This directory is the single grab-and-burn folder: every EEPROM/EPROM image the
machine needs, as a persistent, ready-to-burn artifact. Both `.bin` (raw) and
`.hex` (Intel HEX, for the programmer) are committed.

(The microcode build dir [`../microcode/`](../microcode/) keeps its own
`u0–u3` copies — those are what the emulator and tests load — but the canonical
burn copies live here.)

## Regenerate

Rebuild after changing the monitor, BASIC, or microcode:

```sh
cd emulator && make rom        # or: sh tools/build_rom.sh
```

This refreshes `microcode/u0–u3.{bin,hex}` and all of `rom/`.

## The burn set

| Image | Chip | Card / socket | Contents |
|-------|------|---------------|----------|
| `p8x-ucode0.hex` | 28C64 (8 KB) | control U10 | microcode word bits 0–7 |
| `p8x-ucode1.hex` | 28C64 | control U11 | microcode word bits 8–15 |
| `p8x-ucode2.hex` | 28C64 | control U12 | microcode word bits 16–23 |
| `p8x-ucode3.hex` | 28C64 | control U13 | microcode word bits 24–31 |
| `p8x-prog-rom.hex` | 28C256 (low 8 KB) or 28C64; an 8 KB image, of which the rev F decode maps `$0000–$17FF` (6 KB) | memory U1 | monitor + BIOS @ `$0000` (5,033 bytes, ~4.9 KB, used; the rest is zero-filled) |

The four microcode EPROMs are addressed by `IR | step<<8 | cond<<12`; burn the
same address range that the programmer reads from the `.hex`. The program ROM is
mapped at `$0000` and holds just the monitor + BIOS (~4.9 KB). BASIC is no longer
ROM-resident — it ships as the disk program `/BIN/BASIC.BIN`, so the rest of the
image is zero-filled; `$1800–$1FFF` is RAM on the machine, so the ROM's top 2 KB is
never read.

Burn from the `.hex` files (standard Intel HEX, 16-byte records, 16-bit
addresses). The `.bin` files are byte-identical raw images if your programmer
prefers binary.
