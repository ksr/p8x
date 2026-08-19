# tools/

Host-side (Mac/PC) utilities for building images and managing disks.

| Tool | Purpose |
|------|---------|
| `fput.py` | **The everyday transfer tool**: copy host files into the standard disk image (`os/run-disk.img`) — several at once, replacing existing names. The emulator mounts that image directly, so a put is live on its next boot; `--board` then clones the image to the FPGA's card via `imgsend`. |
| `p8xfs.py` | P8XFS disk-image tool — create, boot, put/get/rm/ls/mkdir/tree, and `fsck` disk images (v2 hierarchical, the only format; `rm` tombstones like the on-target FDELETE). `fput.py` is the friendly front end for the transfer case. |
| `p8img.py` | Convert any image (PNG/JPEG/…) to P8I, the display's own RGB565 format, for BASIC's `IMAGE` statement. Floyd–Steinberg dither by default; `--preview` renders what the panel will show. |
| `build_rom.sh` | Build the full persistent **burn set** into [`../rom/`](../rom/): the four control-store EPROM images and the program ROM (the assembled monitor — BASIC is no longer ROM-resident), each as `.bin` + `.hex`. Wired up as `make rom`. |
| `bin2hex.py` | Convert any binary to Intel HEX for an EEPROM programmer. Importable (`write(data, path, base=0)`) or CLI (`bin2hex.py in.bin out.hex [base]`). |
| `mkbacklogpdf.py` | Render [`../BACKLOG.md`](../BACKLOG.md) to `../BACKLOG-summary.pdf` — a printable one-line-per-item summary of **open work only** (done work lives in `BACKLOG-DONE.md`). Needs `reportlab`. The PDF is generated and git-ignored; re-run after the backlog changes. |

## Typical use

```sh
# Build everything an EEPROM programmer needs
cd ../emulator && make rom

# Make a bootable hierarchical OS disk and check it
python3 p8xfs.py create disk.img
python3 p8xfs.py fsck disk.img

# Put files on the standard image (and optionally the real board)
./fput.py notes.txt game.bas          # -> / of os/run-disk.img, replacing
./fput.py photo.p8i --board           # ...then clone the image to the FPGA card
```

See [`p8xfs.py`](p8xfs.py) `--help` for the full subcommand list, and
[GLOSSARY.md](../GLOSSARY.md) for filesystem terms.
