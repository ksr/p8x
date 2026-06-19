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

On reset the CPU jumps to `$0000`, which vectors to the monitor body at `$0130`;
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
| **B** | `B` | **Boot** the OS image from the CF card into `$8000` and run it. |
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

Call them with `JSR $0103` etc. (P8X/OS is built entirely on this table.)

## Memory map

| Range | Use |
|-------|-----|
| `$0000–$7FFF` | EEPROM — monitor at `$0000`, ROM BASIC at `$2000` (combined ROM) |
| `$8000–$FEFF` | RAM. P8X/OS code at `$8000`; OS variables at `$A000`; sector buffer `SBUF` at `$9E00` and the CF `LBA` byte at `$9D47` (both fixed by the BIOS); user programs / `RUN` (the TPA) at `$B000`; stack (P3) grows down from `$FEFF` |
| `$FF00` | switch input port (read) |
| `$FF02` | LED output port (write) |
| `$FF04 / $FF05` | 6850 ACIA status / data |
| `$FF10–$FF17` | CF-IDE task-file registers |

Reset clears the PC to `$0000`; the stack pointer (P3) is initialised to the top
of RAM.
