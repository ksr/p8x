# P8X/OS

A small RAM-resident disk operating system for the P8X, loaded from
CompactFlash to `$8000` by the ROM monitor's `B` command. Written in P8X
assembly ([`p8xos.asm`](p8xos.asm)) and assembled by
[`p8xasm.py`](../assembler/p8xasm.py).

> **Status: v0.3 — boots and runs a shell with file commands, including
> on-target file creation.**
>
> | Command | Effect |
> |---------|--------|
> | `DIR` | list the flat P8XFS v1 directory (name + hex size) |
> | `LOAD name` | read a file into its stored load address |
> | `RUN name` | `LOAD` it, then `JSR` its exec address (program `RTS` → shell) |
> | `SAVE name start end` | write memory `[start,end)` to a new file (hex addrs) |
> | `DEL name` | mark the directory entry deleted (`$FF`) and write it back |
> | `HELP` | list commands |
>
> Commands are matched as whole words; the filename argument is upcased and
> space-padded to 12 chars; `SAVE` parses two hex addresses. `SAVE` allocates
> at the boot-block free pointer, copies the range into successive sectors,
> writes a directory entry (load = exec = `start`), and bumps the free pointer
> — all persisted, so files survive a reboot and round-trip through
> `p8xfs.py get`. Still to come: `DUMP`/`DEP`, `PACK` (compaction), and the v2
> hierarchy (`CD`/`MKDIR`/`TREE`). See the design in
> [hardware/cf-card/p8x-cf-os-design.md](../hardware/cf-card/p8x-cf-os-design.md).

## How it fits together

The OS does **not** carry its own drivers. The monitor publishes a stable
**BIOS jump table at `$0100`** (CONIN/CONOUT/CONST/CFINIT/CFREAD/CFWRITE/PUTS/
PHEX8); the OS calls those, so console + CF access live in one place and the
OS image stays tiny (~380 bytes today). Those addresses are an ABI — see the
table in [firmware/p8xmon.asm](../firmware/p8xmon.asm).

```
ROM (EEPROM $0000-$7FFF)            RAM ($8000+)
  $0000 reset -> $0130 monitor        $8000 P8X/OS kernel + shell  (from CF)
  $0100 BIOS jump table  <------------ JSR CONOUT / CFREAD / ...
  $0130 monitor body                   $9000 OS variables
                                       $9E00 sector buffer (shared ABI)
```

Boot path: monitor `B` reads the boot block (LBA 0), checks the `P8`
signature + `OSCNT`, loads `OSCNT` sectors from LBA 1 to `$8000`, and `JMP`s
there. No card / bad signature falls back to the monitor prompt.

## Build & run

The OS is a RAM image, so it's assembled with `--base 0x8000` (the assembler
emits only the bytes from `$8000` up, with labels resolved to their run
address):

```sh
# assemble the OS
python3 assembler/p8xasm.py os/p8xos.asm -o p8xos.bin --base 0x8000

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
| 1–32 | OS image (loaded to `$8000`) |
| 33–64 | Directory: 512 × 32-byte entries |
| 65+ | File data, contiguous extents |

Directory entry (32 bytes): name 12 · start LBA 4 · length 4 · load 2 · exec 2
· flags 1 (`$00` end, `$01` file, `$02` dir, `$FF` deleted) · spare 7.
