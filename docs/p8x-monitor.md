# P8X ROM Monitor — Command Reference

The ROM monitor is the firmware that runs at power-on. It lives at `$0000` in
EEPROM (`firmware/p8xmon.asm`), talks to you over the 6850 ACIA serial console
(**9600 8N1**), and is the entry point to everything else — from here you can
inspect/modify memory, drive the CompactFlash card, and boot P8X/OS.

> Source of truth: `firmware/p8xmon.asm` (and its in-ROM `H`/`?` help, which this
> document mirrors). The companion [programmer's guide](p8x-programmers-guide.pdf)
> is the *instruction-set* reference; this is the *monitor* reference.

## Running it

On reset the CPU jumps to `$0000`, which vectors to the monitor body at `$0160`;
it resets the ACIA and prints the `P8X MONITOR` banner and a `*` prompt. In the
emulator:

```sh
./os/run.sh        # builds the monitor ROM (BASIC is no longer ROM-resident) and launches it
# or directly, against an EEPROM image you've assembled and a CF disk image:
emulator/p8xemu -c disk.img eeprom.bin
```

Type a command letter at the `*` prompt. Commands are single letters; those that
take an address read **4 hex digits** (`AAAA`) right after the letter.

## Commands

| Command | Syntax | What it does |
|---------|--------|--------------|
| **E** | `E AAAA` | **Examine / modify** memory from `AAAA`. Interactive (see below). |
| **D** | `D AAAA` | **Dump** 256 bytes from `AAAA` as hex + ASCII. Pages (see below). |
| **I** | `I` | **Init CF**: reset the card, set 8-bit mode, IDENTIFY, print the model string. |
| **F** | `F` | **Format** the CF card as P8XFS (writes the boot block + root directory). Asks `Y/N`. |
| **B** | `B` | **Boot** the OS image from the CF card into `$4000` and run it. |
| **G** | `G AAAA` | **Go**: `JSR AAAA`. The called code returns to the monitor with `RTS`. |
| **? / H** | `?` or `H` | Print the built-in command help. |

> BASIC is no longer ROM-resident (the old `X` command is gone). It ships as the
> disk program `/BIN/BASIC.BIN` (assembled from `basic/p8xbasic.asm`); run it
> from the OS like any other program, and its `BYE` returns to the OS.

### E — examine / modify (interactive)

`E AAAA` shows one byte at a time: `aaaa: vv ` and then waits for input:

- **two hex digits** — write that value to the location, then advance;
- **Enter (CR)** — leave the byte unchanged, advance to the next;
- **`.`** — stop and return to the prompt.

So you can walk forward through memory, setting only the bytes you want.

### D — dump with paging

`D AAAA` prints sixteen 16-byte rows (256 bytes) as hex with an ASCII column
(bytes `<$20` or `≥$7F` shown as `.`). After each block it waits for a key:

- **Enter (CR)** (or any other key) — dump the **next** 256-byte block; the
  address keeps walking forward, so repeated Enters page through memory;
- **`.`** — return to the prompt.

(This mirrors the `E` command's CR=next / `.`=exit convention.)

## Returning to the monitor

Anything the monitor launches can come back to it:

- **`G`** target — returns on `RTS`.
- **P8X/OS** (`B`) — type `EXIT` (or `MON`).

Each of those re-enters the monitor (BASIC/OS do a cold restart via `JMP $0000`).

## BIOS jump table — the program ABI

The monitor publishes a small jump table at `$0100` so RAM-resident programs
(P8X/OS, your own code loaded via `G`) can call console + CF services without
knowing the monitor's internal addresses. These entry points are **stable**:

| Address | Name | Behaviour |
|---------|------|-----------|
| `$0100` | CONIN | wait for a key; char → `A` |
| `$0103` | CONOUT | `A` → serial |
| `$0106` | CONST | `A` = RDRF bit; `Z=1` when no key is waiting |
| `$0109` | CFINIT | reset CF + set 8-bit mode; `C=1` on error |
| `$010C` | CFREAD | read sector `LBA` → `(P1)`; `P1 += 512` |
| `$010F` | CFWRITE | write `SBUF` → sector `LBA` |
| `$0112` | PUTS | print `(P1)+` until `$00` |
| `$0115` | PHEX8 | print `A` as two hex digits |
| `$0118` | FFIND | find root file `FNAME` → `LBA`+`FLEN`; `C=1` if not found |
| `$011B` | FCREATE | create root file `FNAME` from `FSRC`/`FLEN`; `C=1` on error |
| `$011E` | FDELETE | tombstone root file `FNAME` (flag → `$FF`); `C=1` if not found |
| `$0121` | FCOMMIT | register a streamed file: write a root entry for data already at the free pointer (`FNAME`, length `FLEN`, sectors `=ceil(FLEN/512)`) and bump the free pointer; `C=1` if root full |
| `$0124` | FOPEN | open root file `FNAME` for sequential reading; `P1` = a caller-owned 512-byte sector buffer; `C=1` if not found |
| `$0127` | FGETB | next byte of the open read stream → `A` (`C=0`); `C=1` at end of file (refills from disk as needed) |
| `$012A` | FWOPEN | open a sequential write stream (streams to disk at the free pointer; uses `SBUF` as its buffer) |
| `$012D` | FPUTB | append byte `A` to the write stream (flushes a full sector automatically) |
| `$0130` | FCLOSE | flush the partial sector + register file `FNAME` (length = bytes written); `C=1` if root full |
| `$0133` | FRESOLVE | resolve path at `P1` (`/a/b`) → set the directory extent + leaf `FNAME`; a following `FFIND`/`FOPEN` runs in that dir; `C=1` on a bad path |
| `$0136` | FNORM | format the string at `P1` into `FNAME` (≤12 chars, upper-cased, space-padded; stops at NUL/space) |
| `$0139` | FOPENDIR | begin iterating the directory at path `P1` (`""`/`"/"` = root); `C=1` if not a directory |
| `$013C` | FNEXT | next live entry → `FNAME`/`FFLAG`/`LBA`/`FLEN`; `C=1` at end (skips deleted entries) |
| `$013F` | FLOADAT | bulk-read `FLEN` bytes from sector `LBA` into `(P1)`, a whole sector at a time (the fast "slurp a file" primitive; EDIT + the OS loader use it) |
| `$0142` | FOPENDIRAT | begin iterating the directory whose 4-sector extent starts at the 16-bit LBA `A` (low) + `LBA1` (`$7048`, high) — lets a caller iterate an extent it already resolved, e.g. the OS's CWD. Set `LBA1`=0 for LBA < 256 |
| `$0145` | FSDIRBUF | point the directory sector buffer at the page in `A` (high byte; 512-byte page-aligned buffer; defaults to `SBUF`=`$71` at boot and is reset to `SBUF` by `FOPENDIR`/`FOPENDIRAT`). Used by **both** `FNEXT` iteration **and** `FSCAN` (the engine behind `FRESOLVE`/`FFIND`/`FOPEN`), so repointing it lets a program iterate **and** resolve paths while a write stream keeps `SBUF` — e.g. `DIR` redirected/piped, or `CAT *.X >OUT` (resolve+open each match without clobbering the open write stream's `SBUF`) |

Call them with `JSR $0103` etc. (P8X/OS is built entirely on this table.)

`FDELETE` marks the directory entry deleted but leaves its data sectors in
place; they are reclaimed by the next `PACK`. To overwrite a file, `FDELETE`
then `FCREATE`.

**Directory:** the file calls operate on a *current directory extent* that
defaults to the root (LBA 33) and reverts there after each call. Call `FRESOLVE`
first with a path to aim the next call at a subdirectory (it walks the `.`/`..`
tree and leaves the leaf name in `FNAME`): `FRESOLVE("/BIN/X")` then `FOPEN`
reads `/BIN/X`; `FRESOLVE("/SUB/W")` then `FWOPEN`/`FPUTB`/`FCLOSE` writes
`/SUB/W`. `FFIND`/`FOPEN`/`FCREATE`/`FDELETE`/`FCLOSE` are all path-aware this
way. Parameters use fixed RAM:
`FNAME` (`$704A`, 12-byte space-padded name), `FSRC` (`$7056`, FCREATE source
address), `FLEN` (`$7058`, length — FCREATE input, FFIND output); `FFIND` returns
the start LBA in the shared `LBA` (`$7047`). (Subdirectory LBAs are 16-bit: the
directory-iteration/resolution path carries `DIRLBA`/`DILBA` plus their high
bytes, so a directory whose extent starts at LBA ≥ 256 resolves and lists
correctly.)

## Memory map

| Range | Use |
|-------|-----|
| `$0000–$3FFF` | EEPROM (16 KB, rev D) — monitor + BIOS at `$0000` (~4.3 KB used). BASIC is no longer ROM-resident; it ships as `/BIN/BASIC.BIN` on disk. |
| `$4000–$6FFF` | RAM — **P8X/OS code** loads here (`$4000`, ~8.3 KB). |
| `$7000–$72FF` | RAM — **firmware/BIOS scratch** (fixed by the BIOS): monitor line buffer `$7000`, the parameter block + read/write/dir-iteration state `$7040` (CF `LBA` `$7047–$7049`, `FNAME` `$704A`, `FSRC`/`FLEN`, `FFLAG` `$7070`, `DIBUFH` `$7078`), and the sector buffer `SBUF` at `$7100`. |
| `$7300–$79FF` | RAM — **OS data**: variables `$7300`, the stdin read buffer `IBUF` `$7500`, search `PATH` `$7700`, the `>>` prepend buffer `APBUF` `$7800`. |
| `$7A00–$FDFF` | RAM — **TPA**: user programs + data (`RUN` loads at `$7A00`, ~31.6 KB). Commands keep their 512-byte scratch buffers near the top — the file-read buffer at `$FC00` and the glob/dir-iteration buffer at `$FA00`. |
| `$FE00–$FEFF` | RAM — stack (P3 grows down from `$FEFF`). |
| `$FF00` | switch input port (read) |
| `$FF02` | LED output port (write) |
| `$FF04 / $FF05` | 6850 ACIA status / data |
| `$FF10–$FF17` | CF-IDE task-file registers |

Reset clears the PC to `$0000`; the stack pointer (P3) is initialised to the top
of RAM.
