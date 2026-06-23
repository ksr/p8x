# P8X ROM Monitor — Command Reference

The ROM monitor is the firmware that runs at power-on. It lives at `$0000` in
EEPROM (`firmware/p8xmon.asm`), talks to you over the 6850 ACIA serial console
(**9600 8N1**), and is the entry point to everything else — from here you can
inspect/modify memory, drive the CompactFlash card, boot P8X/OS, or launch ROM
BASIC.

> Source of truth: `firmware/p8xmon.asm` (and its in-ROM `H`/`?` help, which this
> document mirrors). The companion [programmer's guide](p8x-programmers-guide.pdf)
> is the *instruction-set* reference; this is the *monitor* reference.

## Running it

On reset the CPU jumps to `$0000`, which vectors to the monitor body at `$0160`;
it resets the ACIA and prints the `P8X MONITOR` banner and a `*` prompt. In the
emulator:

```sh
./os/run.sh        # builds the combined monitor+BASIC ROM and launches it
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
| **X** | `X` | **Run ROM BASIC** (in the combined ROM at `$2000`). BASIC's `BYE` returns here. |
| **? / H** | `?` or `H` | Print the built-in command help. |

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
- **ROM BASIC** (`X`) — type `BYE`.
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
`FNAME` (`$9D4A`, 12-byte space-padded name), `FSRC` (`$9D56`, FCREATE source
address), `FLEN` (`$9D58`, length — FCREATE input, FFIND output); `FFIND` returns
the start LBA in the shared `LBA` (`$9D47`). (Subdirectory LBAs are assumed
< 256, matching the OS's current-directory convention.)

## Memory map

| Range | Use |
|-------|-----|
| `$0000–$3FFF` | EEPROM (16 KB, rev D) — monitor at `$0000`, ROM BASIC at `$2000` (combined ROM) |
| `$4000–$7FFF` | RAM (16 KB, rev D). **P8X/OS loads here** (`$4000`) and runs. |
| `$8000–$FEFF` | RAM. OS code continues up to `$9D46`; OS variables at `$A000`; sector buffer `SBUF` at `$9E00` and the CF `LBA` bytes at `$9D47–$9D49` (fixed by the BIOS); user programs / `RUN` (the TPA) at `$B000`; stack (P3) grows down from `$FEFF` |
| `$FF00` | switch input port (read) |
| `$FF02` | LED output port (write) |
| `$FF04 / $FF05` | 6850 ACIA status / data |
| `$FF10–$FF17` | CF-IDE task-file registers |

Reset clears the PC to `$0000`; the stack pointer (P3) is initialised to the top
of RAM.
