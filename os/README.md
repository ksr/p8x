# P8X/OS

A small RAM-resident disk operating system for the P8X, loaded from
CompactFlash to `$4000` by the ROM monitor's `B` command. Written in P8X
assembly ([`p8xos.asm`](p8xos.asm)) and assembled by
[`p8xasm.py`](../assembler/p8xasm.py).

> **Status: v1.0 — full shell over a hierarchical filesystem.**
> Reads both P8XFS v1 (flat) and v2 (hierarchical) volumes — the layout is
> chosen at cold start from the boot block's version byte.
>
> | Command | Effect |
> |---------|--------|
> | `DIR [path]` | list the current directory, or a given one |
> | `CD path` | change directory (absolute `/a/b`, relative, `.`/`..`) |
> | `PWD` | print the working-directory path |
> | `CAT path` | print a file's contents to the console |
> | `MKDIR path` | create a subdirectory (v2) |
> | `RMDIR path` | remove an empty subdirectory (v2) |
> | `TREE` | depth-first indented listing of the whole tree (v2) |
> | `LOAD name` | read a file into its stored load address |
> | `RUN name` | `LOAD` it, then `JSR` its exec address (program `RTS` → shell) |
> | `SAVE name start end` | write memory `[start,end)` to a new file (hex addrs) |
> | `DEL name` | mark the directory entry deleted (`$FF`) and write it back |
> | `DUMP addr` | show 256 bytes from `addr` (hex + ASCII) |
> | `DEP addr b b ...` | deposit hex byte values starting at `addr` |
> | `PACK` | compact the data area, reclaiming `DEL`/`RMDIR`'d extents |
> | `FSCK` | check filesystem integrity (read-only) |
> | `FORMAT` | erase the card and lay a fresh P8XFS v2 volume (asks `Y/N`) |
> | `HELP` | list commands |
>
> A file/dir argument may be a **path**. Directory scanning works on any extent
> — a `(start LBA, sector count)` pair — so the current directory and any
> resolved path share one code path; path resolution walks components via the
> on-disk `.`/`..` entries. The prompt shows the current path (e.g. `/BIN> `).
> `SAVE`/`DUMP`/`DEP` parse hex; `SAVE` allocates at the boot-block free pointer,
> writes a directory entry into the current (or resolved) directory, and bumps
> the free pointer. Together `DEP`+`SAVE`+`RUN` let the machine author and run
> its own programs. `MKDIR` allocates a 4-sector extent at the free pointer and
> writes its `.`/`..`; `RMDIR` refuses a directory that still holds entries past
> `.`/`..`. `TREE` walks the tree depth-first with an explicit RAM stack (the
> single shared sector buffer rules out recursion). **`PACK`** reclaims every
> extent `DEL`/`RMDIR` left behind: a two-phase tree walk compacts all file and
> directory extents down (updating each one's parent entry), then repairs every
> directory's `.`/`..` from the final positions — so navigation and fsck stay
> correct after compaction. **`FSCK`** is a read-only on-target consistency
> check that mirrors the host tool: it verifies the `P8` boot signature, that
> every live extent sits in the data area and at/below the free pointer, and
> (v2) that every directory's `..` points at its real parent — printing counts
> and an `FSCK OK` / `FSCK: PROBLEMS=n` verdict. Exhaustive cross-extent overlap
> and volume-end checks remain in the host **`p8xfs.py fsck`**. **`FORMAT`**
> (asks `Y/N`) lays a fresh P8XFS **v2** volume on-target: it rewrites the boot
> block (`P8`, version 2, free = 37) and a clean root extent at LBA 33 (reusing
> the `MKDIR` extent builder), then adopts the new layout in RAM. It **preserves
> OSCNT**, so the OS image at LBA 1–32 is untouched and the card stays bootable
> (`EXIT` then `B` re-boots the same OS onto the clean volume). This became
> possible once the OS load address moved to `$4000` (rev D) — it didn't fit
> under the old `$8000` 14-sector ceiling.
> See the design in
> [hardware/cf-card/p8x-cf-os-design.md](../hardware/cf-card/p8x-cf-os-design.md)
> and [p8xfs-v2-hierarchical.md](../hardware/cf-card/p8xfs-v2-hierarchical.md).

## How it fits together

The OS does **not** carry its own drivers. The monitor publishes a stable
**BIOS jump table at `$0100`** (CONIN/CONOUT/CONST/CFINIT/CFREAD/CFWRITE/PUTS/
PHEX8); the OS calls those, so console + CF access live in one place and the
OS image stays tiny (~380 bytes today). Those addresses are an ABI — see the
table in [firmware/p8xmon.asm](../firmware/p8xmon.asm).

```
ROM (EEPROM $0000-$3FFF, rev D)     RAM ($4000-$FEFF, 48K)
  $0000 reset -> $0130 monitor        $4000 P8X/OS kernel + shell  (from CF, rev D)
  $0100 BIOS jump table  <------------ JSR CONOUT / CFREAD / ...
  $0130 monitor body                   $9E00 sector buffer (shared ABI)
                                       $A000 OS variables
```

Boot path: monitor `B` reads the boot block (LBA 0), checks the `P8`
signature + `OSCNT`, loads `OSCNT` sectors from LBA 1 to `$4000`, and `JMP`s
there. No card / bad signature falls back to the monitor prompt.

## Build & run

**Interactive — easiest way to try it:**

```sh
./os/run.sh
```

Builds the monitor, OS, microcode, and emulator, makes a ready-to-boot P8XFS v2
disk (OS installed plus a small sample tree: `/BIN/HI.BIN`, `/README.TXT`), and
launches it attached to your terminal. You start in the **monitor** (`*`
prompt) — type `?` for monitor help, then **`B`** to boot P8X/OS (`HELP` lists
its commands). The disk persists at `os/run-disk.img`, so files you `SAVE`
survive across runs (delete it to start fresh; quit with Ctrl-C).

**Manual build** — the OS is a RAM image, so it's assembled with `--base 0x4000`
(the assembler emits only the bytes from `$4000` up, with labels resolved to
their run address):

```sh
# assemble the OS
python3 assembler/p8xasm.py os/p8xos.asm -o p8xos.bin --base 0x4000

# build a P8XFS disk image, install the OS, add some files
python3 tools/p8xfs.py create disk.img
python3 tools/p8xfs.py boot   disk.img p8xos.bin
python3 tools/p8xfs.py put    disk.img hello.txt --name HELLO.TXT

# boot it in the emulator (monitor in ROM, disk on -c), then type B
python3 assembler/p8xasm.py firmware/p8xmon.asm -o eeprom.bin
(cd microcode && python3 genucode.py) ; cp microcode/u?.bin .
./emulator/p8xemu -c disk.img eeprom.bin
```

At the monitor `*` prompt type `B` to boot the OS, then `DIR` / `HELP`.

The full path is covered by a regression test: `make test-os` (in `emulator/`)
builds an image with the OS + two files, boots it, and asserts `DIR` lists
them. See [tools/p8xfs.py](../tools/p8xfs.py) for the host-side filesystem
tool (`create`/`boot`/`put`/`get`/`ls`).

## P8XFS v1 on-disk layout

| LBA | Contents |
|-----|----------|
| 0 | Boot block: `P8`, version, OSCNT, free pointer |
| 1–32 | OS image (loaded to `$4000`) |
| 33–64 | Directory: 512 × 32-byte entries |
| 65+ | File data, contiguous extents |

Directory entry (32 bytes): name 12 · start LBA 4 · length 4 · load 2 · exec 2
· flags 1 (`$00` end, `$01` file, `$02` dir, `$FF` deleted) · spare 7.
