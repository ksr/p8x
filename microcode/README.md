# microcode/

The microcode control store — the single source of truth for what every opcode
does. The same images burned to the four control-card EPROMs are what the
emulator interprets, so emulator and hardware behave identically by construction.

| File | Purpose |
|------|---------|
| `genucode.py` | **Generator** — defines the opcode table (`OPC`), the 32-bit control word, and per-opcode microcode step sequences; emits `u0–u3.bin`. The assembler imports its `OPC`. |
| `gen_progguide.py` | Renders the instruction-set programmer's guide PDF into `../docs/`. |
| `u0–u3.bin` | The four 28C64 control-store images (word bits 0–7 / 8–15 / 16–23 / 24–31). Loaded by the emulator and copied to the CWD by the tests. |

The control word is addressed by `IR | step<<8 | cond<<12`. The bit layout lives
in `genucode.py` and is mirrored by the control card's pipeline latches — see
[GLOSSARY.md](../GLOSSARY.md) and
[docs/p8x-system-design.md](../docs/p8x-system-design.md) §3.2.

## Build

```sh
cd ../emulator && make ucode      # runs genucode.py -> u0-u3.bin
```

**Generators are canon.** Never hand-edit the `.bin` images — change `genucode.py`
and regenerate. The burnable **Intel HEX** for an EEPROM programmer is produced
into [`../rom/`](../rom/) by `make rom` (this directory holds only the `.bin` the
emulator and tests load).
