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
| `p8x-prog-rom.hex` | 28C256 (32 KB) | memory U1 | monitor @ `$0000` + ROM BASIC @ `$2000` |

The four microcode EPROMs are addressed by `IR | step<<8 | cond<<12`; burn the
same address range that the programmer reads from the `.hex`. The program ROM is
mapped at `$0000` — the monitor lives below `$2000` and ROM BASIC at `$2000`
(reached by the monitor's `X` command).

Burn from the `.hex` files (standard Intel HEX, 16-byte records, 16-bit
addresses). The `.bin` files are byte-identical raw images if your programmer
prefers binary.
