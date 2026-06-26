# P8X/OS

A small RAM-resident disk operating system for the P8X, loaded from
CompactFlash to `$4000` by the ROM monitor's `B` command. Written in P8X
assembly ([`p8xos.asm`](p8xos.asm)) and assembled by
[`p8xasm.py`](../assembler/p8xasm.py).

> **Status: v1.0 — full shell over a hierarchical filesystem.**
> Reads/writes P8XFS **v2** (hierarchical) volumes. (v1, the old flat layout,
> has been retired — v2 is the only format; `FORMAT` lays a fresh one.)
>
> | Command | Effect |
> |---------|--------|
> | `CD path` | change directory (absolute `/a/b`, relative, `.`/`..`) |
> | `PATH [dirs]` | show/set the program search path (`;`-separated, default `/BIN`) |
> | `MKDIR path` | create a subdirectory (v2) |
> | `RMDIR path` | remove an empty subdirectory (v2) |
> | `LOAD name` | read a file into its stored load address |
> | `RUN name [args]` | `LOAD` it, then `JSR` its exec address; `args` → `P2` (program `RTS` → shell) |
> | `SAVE name start end` | write memory `[start,end)` to a new file (hex addrs) |
> | `DEL name` | mark the directory entry deleted (`$FF`) and write it back |
> | `DUMP addr` | show 256 bytes from `addr` (hex + ASCII) |
> | `DEP addr b b ...` | deposit hex byte values starting at `addr` |
> | `PACK` | compact the data area, reclaiming `DEL`/`RMDIR`'d extents |
> | `FSCK` | check filesystem integrity (read-only) |
> | `FORMAT` | erase the card and lay a fresh P8XFS v2 volume (asks `Y/N`) |
> | `HELP` | list commands |
>
> The table above is the **built-in** command set. `CAT`, `WC`, `GREP`, `CP`,
> `MV`, `HEAD`, `TAIL`, `MORE`, `SORT`, `UNIQ`, `SED`, `FIND`, `DIFF` (and richer
> `DIR -R` etc.) are **userland C programs** in `/BIN`, run by
> bare name (implicit RUN searches `PATH`, default `/BIN`) or explicit `RUN` —
> see [commands/](commands/README.md). Line input echoes keys, supports
> backspace/DEL editing (max 63 chars), and takes **Ctrl-D** as console EOF.
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
> `.`/`..`. (`TREE` is no longer a built-in — it, `DIR`, and `PWD` are now
> userland C programs in `/BIN`; see *Programs* below.) **`PACK`** reclaims every
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

## Programs (the program ABI)

The OS ships only a shell + built-ins; bigger tools are **standalone programs**
that load into the transient program area (TPA, `$B000`) and are launched with
`RUN`. A fresh `os/run.sh` disk carries the three big interpreters/tools below
under `/BIN`, **plus the userland C commands** (`DIR`, `PWD`, `TREE`, `CAT`,
`WC`, `GREP`, … — see [commands/README.md](commands/README.md)):

| Program | Run as | What |
|---------|--------|------|
| BASIC | `RUN /BIN/BASIC.BIN` | BASIC interpreter (`BYE` returns to the OS) — see [basic/README.md](../basic/README.md) |
| EDIT | `RUN /BIN/EDIT.BIN NAME.ASM` | line editor — see [apps/README.md](../apps/README.md) |
| ASM | `RUN /BIN/ASM.BIN SRC.ASM OUT.BIN` | native assembler — see [apps/README.md](../apps/README.md) |

Edit → assemble → run, all on the machine:
`RUN /BIN/EDIT.BIN HELLO.ASM` → `RUN /BIN/ASM.BIN HELLO.ASM HELLO.BIN` → `RUN HELLO.BIN`.

**Implicit RUN (a bare command name).** A command word that matches no built-in
is looked up as a program, so you can type `DIR /BIN` instead of
`RUN /BIN/DIR.BIN /BIN`. Resolution:
- a word containing `/` is taken as a path (CWD-relative or absolute) and run as
  typed, then with a `.BIN` suffix — so `/BIN/DIR.BIN` works as a bare command;
- otherwise each directory on **`PATH`** (a `;`-separated list, default `/BIN`)
  is tried as `<dir>/<name>` then `<dir>/<name>.BIN`, first hit wins;
- no match → the unknown-command marker.

`PATH` does not include the CWD (Unix-style: a file named `DIR` in your CWD won't
shadow the command). The args, redirects (`<`/`>`) and pipes (`|`) all work on a
bare-name invocation exactly as for explicit `RUN`. (`PATH` defaults to `/BIN` at
boot; the **`PATH`** command shows it with no argument and sets it with one —
e.g. `PATH /BIN;/UTIL` — but does not persist across reboots.)

**Program ABI** (what `RUN` guarantees a program):
- entered with a `JSR` to its exec address — **return to the shell with `RTS`**
  (the current directory is preserved);
- on entry **`P2` points at the argument tail** — the command text after the
  program name, NUL-terminated (e.g. `RUN EDIT FOO.ASM` enters with `P2` → `"FOO.ASM"`);
  programs that take no arguments just ignore `P2`;
- a program built on-target (its entry's load/exec are `0`, as `FCREATE` writes)
  is loaded at the TPA base `$B000`, so assemble with `.org $B000`. Host-installed
  programs set explicit non-zero load/exec and load there instead.

## How it fits together

The OS does **not** carry its own drivers. The monitor publishes a stable
**BIOS jump table at `$0100`** — console + CF (CONIN/CONOUT/CONST/CFINIT/CFREAD/
CFWRITE/PUTS/PHEX8) plus the filesystem calls (FFIND/FCREATE/FDELETE/FCOMMIT,
the read/write streams FOPEN/FGETB/FWOPEN/FPUTB/FCLOSE, and FRESOLVE/FNORM/
FOPENDIR/FNEXT). The OS calls these, so drivers + FS structure live in one
place. Those addresses are an ABI — see the full table in
[docs/p8x-monitor.md](../docs/p8x-monitor.md).

```
ROM (EEPROM $0000-$3FFF, rev D)     RAM ($4000-$FEFF, 48K)
  $0000 reset -> $0160 monitor        $4000 P8X/OS kernel + shell  (from CF, rev D)
  $0100 BIOS jump table  <------------ JSR CONOUT / CFREAD / ...
  $0160 monitor body                   $9E00 sector buffer (shared ABI)
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

At the monitor `*` prompt type `B` to boot the OS, then `HELP` (a built-in) or
`DIR` (a `/BIN` program — present on an `os/run.sh` disk).

The full path is covered by a regression test: `make test-os` (in `emulator/`)
builds an image with the OS + two files, boots it, and asserts `DIR` lists
them. See [tools/p8xfs.py](../tools/p8xfs.py) for the host-side filesystem
tool (`create`/`boot`/`put`/`get`/`ls`).

## P8XFS v2 on-disk layout

| LBA | Contents |
|-----|----------|
| 0 | Boot block: `P8`, version (2), OSCNT, free pointer |
| 1–32 | OS image (loaded to `$4000`) |
| 33–36 | Root directory: 4-sector extent (entry 0 `.`, entry 1 `..`) |
| 37+ | Files + subdirectory extents, contiguous (from the free pointer) |

A directory is a file whose extent holds 32-byte entries; subdirectories nest
via their own extents. Directory entry (32 bytes): name 12 · start LBA 4 ·
length 4 · load 2 · exec 2 · flags 1 (`$00` end, `$01` file, `$02` dir, `$FF`
deleted) · spare 7. See
[../hardware/cf-card/p8xfs-v2-hierarchical.md](../hardware/cf-card/p8xfs-v2-hierarchical.md).

## OS syscall ABI (for loadable programs)

The OS publishes a small jump table at the front of its image — like the BIOS
table at `$0100`, but for OS-level services the BIOS deliberately doesn't own
(chiefly the current working directory). The OS stays resident at `$4000` while
a `RUN` program executes, so a TPA program reaches these with a plain `JSR` (or,
from C, the `p8cc` `bios()` intrinsic). The table is **append-only**:

| Addr | Syscall | Convention |
|------|---------|------------|
| `$4000` | (boot)    | `JMP COLD` — the monitor's `CMD_B` enters here |
| `$4003` | `SYS_GETCWD` | copy the CWD path string (incl. NUL) into `(P1)`; clobbers P2 |
| `$4006` | `SYS_CWDLBA` | current directory's start LBA → `A` (low byte only; use `SYS_OPENCWD` for a CWD at LBA ≥ 256) |
| `$4009` | `SYS_PUTC` | write `A` to the current **stdout** (console, or the `>` file) |
| `$400C` | `SYS_GETC` | next **stdin** byte → `A` (console, or the `<` file); `C=1` at EOF (console: echoes the key, Ctrl-D = EOF) |
| `$400F` | `SYS_PUTS` | write the `(P1)` NUL-terminated string to stdout |
| `$4012` | `SYS_OPENCWD` | begin iterating the CWD with its full **16-bit** start LBA (then `FNEXT`); works when the CWD lives at LBA ≥ 256, where `SYS_CWDLBA` + `FOPENDIRAT(A)` would truncate |

`SYS_GETCWD`/`SYS_CWDLBA`/`SYS_OPENCWD` are the supported way to consult the CWD
— no peeking into OS RAM. `os/commands/pwd.c` (PWD) and `os/commands/dir.c` (DIR,
no-arg lists the CWD via `SYS_OPENCWD`, the 16-bit CWD opener) are worked examples;
`compiler/p8lib.c` wraps them as `getcwd(buf)` / `cwdlba()`.

**Program I/O redirection.** `SYS_PUTC`/`SYS_PUTS`/`SYS_GETC` route through the
OS output sink (`OUTCH`), so the shell can redirect a *program's* stdout the
same way it redirects a built-in: `RUN PROG >FILE` makes `DORUN` open a write
stream and switch `OUTCH` to file mode (`REDIRF=2`, streaming each byte via
`FPUTB`) around the program. The p8cc compilers emit `putchar`/`puts`/`getchar`
as these syscalls, so any compiled program is redirectable with no source
change. Redirect (and pipe) files resolve in the **current working directory**
(the OS points the BIOS FS at `CWDL` before the open/close), so `CD /SUB; RUN
PROG >OUT` writes `/SUB/OUT`, not `/OUT`. Symmetrically, `RUN PROG <FILE` binds **stdin** to a file: `DORUN` opens
it as the read stream into `IBUF` and `SYS_GETC`/`getchar` pull from it (`getchar`
returns `-1` at EOF). Both combine — `RUN CAT.BIN <IN >OUT` copies a file. The
canonical filter `os/commands/cat.c` (stdin→stdout) is the worked example. When
stdin is the **console** (no `<` file), `SYS_GETC` echoes each key and treats
**Ctrl-D** (`$04`) as end of input (`getchar` → `-1`) — so `CAT >FILE` captures
typed lines to a file and Ctrl-D finishes it.
Note: directory iteration (`FNEXT`) and the write stream default to the same BIOS
sector buffer `SBUF`, so a program that does both (`DIR`/`TREE`) must call
`FSDIRBUF` ($0145) after opening the directory to move iteration onto its own
page-aligned 512-byte buffer; the write stream then keeps `SBUF` to itself and
the program can stream output per entry with no buffering or size limit (see
`os/commands/dir.c`). It then redirects and pipes like any other program.

**Pipes** build directly on this: `cmd1 | cmd2` runs `cmd1` with its stdout to a
temp file `PIPE.TMP`, then re-dispatches `cmd2` with its stdin from that file,
then deletes it — a `SHELL` state machine (`PIPEF`) over the `<`/`>` redirection
above, so existing commands are untouched. E.g. `CAT FILE | GREP foo`.
(Sequential, **two-stage**: with no multitasking the left command runs to
completion into the temp before the right starts. A third stage — `a | b | c`
— is currently dropped, because the re-dispatch doesn't re-scan for `|`; see the
backlog.)
