# P8X applications

Standalone **TPA programs** — assembled to load and execute at `$B000` (the
transient program area), launched from P8X/OS with `RUN`. Each is built entirely
on the BIOS jump table (`$0100..`); none depend on OS internals, so they return
to the shell with a plain `RTS`.

Build one with the host assembler and place it on a disk:

```sh
python3 assembler/p8xasm.py apps/p8xedit.asm -o edit.bin --base 0xB000
python3 tools/p8xfs.py put disk.img edit.bin --name /BIN/EDIT.BIN --load 0xB000 --exec 0xB000
```

`os/run.sh` already builds and installs these into a fresh demo disk under
`/BIN`, so a clean `./os/run.sh` boots an OS where `RUN EDIT.BIN NAME` works.

## EDIT — line-oriented text editor (`p8xedit.asm`)

```
RUN EDIT.BIN NAME.EXT
```

On entry the OS hands the program its argument tail in `P2` (the program-arg
ABI); EDIT copies it to `FNAME` and loads that file if it exists, else starts an
empty buffer. Text is held as LF-separated lines in `$C000..$F000` (12 KB).

| cmd | action |
|-----|--------|
| `L` | list every line with its 1-based number |
| `A` | append: type lines, end with a line containing only `.` |
| `I n` | insert before line `n` (n past the end appends); end with `.` |
| `D n` | delete line `n` |
| `W` | write the buffer back to the file (`FDELETE` then `FCREATE`) |
| `Q` | quit to the shell |
| `?` | command summary |

Notes / current limits: line numbers are 8-bit (≤255 lines); `W` rewrites the
whole file, orphaning the old data sectors until the next `PACK`; the editor
reads/writes the **root** directory (the BIOS FS layer is flat — path-aware
saves are a future item). Files use LF (`$0A`) line endings — the form the
forthcoming on-target assembler (`ASM`) expects as input.
