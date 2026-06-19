# tools/

Host-side (Mac/PC) utilities for building images and managing disks.

| Tool | Purpose |
|------|---------|
| `p8xfs.py` | P8XFS disk-image tool — create, boot, put/get/ls, and `fsck` CF images. Supports both the flat v1 and hierarchical v2 (`--v2`) filesystems. |
| `build_basic_rom.py` | Assemble the monitor and ROM BASIC and overlay them into one 32 KB EEPROM image (BASIC at `$2000`, reached by the monitor's `X`). Emits `.bin` + Intel HEX. |
| `build_rom.sh` | Build the full persistent **burn set** into [`../rom/`](../rom/): the four control-store EPROM images and the program ROM, each as `.bin` + `.hex`. Wired up as `make rom`. |
| `bin2hex.py` | Convert any binary to Intel HEX for an EEPROM programmer. Importable (`write(data, path, base=0)`) or CLI (`bin2hex.py in.bin out.hex [base]`). |

## Typical use

```sh
# Build everything an EEPROM programmer needs
cd ../emulator && make rom

# Make a bootable hierarchical OS disk and check it
python3 p8xfs.py create disk.img --v2
python3 p8xfs.py fsck disk.img
```

See [`p8xfs.py`](p8xfs.py) `--help` for the full subcommand list, and
[GLOSSARY.md](../GLOSSARY.md) for filesystem terms.
