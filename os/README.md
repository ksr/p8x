# P8X/OS

A small RAM-resident disk operating system for the P8X, loaded from
CompactFlash to `$4000` by the ROM monitor's `B` command. Written in P8X
assembly ([`p8xos.asm`](p8xos.asm)) and assembled by
[`p8xasm.py`](../assembler/p8xasm.py).

> **Status: v1.0 — full shell over a hierarchical filesystem.**
> Reads/writes P8XFS **v2** (hierarchical) volumes. (v1, the old flat layout,
> has been retired — v2 is the only format; `format` lays a fresh one.)
>
> | Command | Effect |
> |---------|--------|
> | `cd path` | change directory (absolute `/a/b`, relative, `.`/`..`) |
> | `path [dirs]` | show/set the program search path (`;`-separated, default `/bin`) |
> | `mkdir path` | create a subdirectory (v2) |
> | `rmdir path` | remove an empty subdirectory (v2) |
> | `load name` | read a file into its stored load address |
> | `run name [args]` | `load` it, then `JSR` its exec address; `args` → `P2` (program `RTS` → shell) |
> | `save name start end` | write memory `[start,end)` to a new file (hex addrs) |
> | `del name` | mark the directory entry deleted (`$FF`) and write it back |
> | `dump addr` | show 256 bytes from `addr` (hex + ASCII) |
> | `dep addr b b ...` | deposit hex byte values starting at `addr` |
> | `pack` | compact the data area, reclaiming `del`/`rmdir`'d extents |
> | `fsck` | check filesystem integrity (read-only) |
> | `format` | erase the card and lay a fresh P8XFS v2 volume (asks `Y/N`) |
> | `umount` / `mount` | swap the CF in the `/d1` slot without rebooting (see **Two drives**) |
> | `help` | list commands |
> | `man name` | show a command's manual page (reads `/man/<name>`) |
>
> A second CF is **mounted at `/d1`** in one unified namespace — any `path` on a
> built-in (or `/bin` command) reaches it with ordinary path syntax
> (`cd /d1/SRC`, `mkdir /d1/LIB`, `cat /d1/NOTES`). See **Two drives** below.
>
> The table above is the **built-in** command set. `cat`, `wc`, `grep`, `cp`,
> `mv`, `head`, `tail`, `more`, `sort`, `uniq`, `sed`, `find`, `diff`, `touch`,
> `vi`, `man` (and richer `dir -R`, the `vi` screen editor, etc.) are **userland C
> programs** in
> `/bin`, run by
> bare name (implicit RUN searches `path`, default `/bin`) or explicit `run` —
> see [commands/](commands/README.md). They are **drive-unaware**: a `/d1/...`
> path reaches drive 1 through the same mount redirect, so `cat /d1/NOTES`,
> `grep x /d1/SRC/*.C`, and cross-mount `cp /d1/A /B` all just work with no
> per-command drive logic. Line input echoes keys, supports
> backspace/DEL editing (max 63 chars), and takes **Ctrl-D** as console EOF.
>
> Every command — built-in or `/bin` — has a **manual page** in `/man` (plain
> text authored in [`man/`](man/), installed by `run.sh`). `man name` prints it,
> e.g. `man cp`; an unknown name reports `no manual entry`.
>
> A file/dir argument may be a **path**. Directory scanning works on any extent
> — a `(start LBA, sector count)` pair — so the current directory and any
> resolved path share one code path; path resolution walks components via the
> on-disk `.`/`..` entries. The prompt shows the current path (e.g. `/bin> `).
> `save`/`dump`/`dep` parse hex; `save` allocates at the boot-block free pointer,
> writes a directory entry into the current (or resolved) directory, and bumps
> the free pointer. Together `dep`+`save`+`run` let the machine author and run
> its own programs. `mkdir` allocates a 4-sector extent at the free pointer and
> writes its `.`/`..`; `rmdir` refuses a directory that still holds entries past
> `.`/`..`. (`tree` is no longer a built-in — it, `dir`, and `pwd` are now
> userland C programs in `/bin`; see *Programs* below.) **`pack`** reclaims every
> extent `del`/`rmdir` left behind: a two-phase tree walk compacts all file and
> directory extents down (updating each one's parent entry), then repairs every
> directory's `.`/`..` from the final positions — so navigation and fsck stay
> correct after compaction. **`fsck`** is a read-only on-target consistency
> check that mirrors the host tool: it verifies the `P8` boot signature, that
> every live extent sits in the data area and at/below the free pointer, and
> (v2) that every directory's `..` points at its real parent — printing counts
> and an `fsck OK` / `fsck: PROBLEMS=n` verdict. Exhaustive cross-extent overlap
> and volume-end checks remain in the host **`p8xfs.py fsck`**. **`format`**
> (asks `Y/N`) lays a fresh P8XFS **v2** volume on-target: it rewrites the boot
> block (`P8`, version 2, free = 37) and a clean root extent at LBA 33 (reusing
> the `mkdir` extent builder), then adopts the new layout in RAM. It **preserves
> OSCNT**, so the OS image at LBA 1–32 is untouched and the card stays bootable
> (`exit` then `B` re-boots the same OS onto the clean volume). This became
> possible once the OS load address moved to `$4000` (rev D) — it didn't fit
> under the old `$8000` 14-sector ceiling.
> See the design in
> [hardware/cf-card/p8x-cf-os-design.md](../hardware/cf-card/p8x-cf-os-design.md)
> and [p8xfs-v2-hierarchical.md](../hardware/cf-card/p8xfs-v2-hierarchical.md).

## Programs (the program ABI)

The OS ships only a shell + built-ins; bigger tools are **standalone programs**
that load into the transient program area (TPA, `$7A00`) and are launched with
`run`. A fresh `os/run.sh` disk carries the three big interpreters/tools below
under `/bin`, **plus the userland C commands** (`dir`, `pwd`, `tree`, `cat`,
`wc`, `grep`, … — see [commands/README.md](commands/README.md)):

| Program | Run as | What |
|---------|--------|------|
| BASIC | `run /bin/basic.bin` | BASIC interpreter (`BYE` returns to the OS) — see [basic/README.md](../basic/README.md) |
| EDIT | `run /bin/edit.bin NAME.ASM` | line editor — see [apps/README.md](../apps/README.md) |
| ASM | `run /bin/asm.bin SRC.ASM OUT.bin` | native assembler — see [apps/README.md](../apps/README.md) |

Edit → assemble → run, all on the machine:
`run /bin/edit.bin HELLO.ASM` → `run /bin/asm.bin HELLO.ASM HELLO.bin` → `run HELLO.bin`.

**Implicit RUN (a bare command name).** A command word that matches no built-in
is looked up as a program, so you can type `dir /bin` instead of
`run /bin/dir.bin /bin`. Resolution:
- a word containing `/` is taken as a path (CWD-relative or absolute) and run as
  typed, then with a `.bin` suffix — so `/bin/dir.bin` works as a bare command;
- otherwise each directory on **`path`** (a `;`-separated list, default `/bin`)
  is tried as `<dir>/<name>` then `<dir>/<name>.bin`, first hit wins;
- no match → the unknown-command marker.

`path` does not include the CWD (Unix-style: a file named `dir` in your CWD won't
shadow the command). The args, redirects (`<`/`>`) and pipes (`|`) all work on a
bare-name invocation exactly as for explicit `run`. (`path` defaults to `/bin` at
boot; the **`path`** command shows it with no argument and sets it with one —
e.g. `path /bin;/UTIL` — but does not persist across reboots.)

**Program ABI** (what `run` guarantees a program):
- entered with a `JSR` to its exec address — **return to the shell with `RTS`**
  (the current directory is preserved);
- on entry **`P2` points at the argument tail** — the command text after the
  program name, NUL-terminated (e.g. `run EDIT FOO.ASM` enters with `P2` → `"FOO.ASM"`);
  programs that take no arguments just ignore `P2`;
- a program built on-target (its entry's load/exec are `0`, as `FCREATE` writes)
  is loaded at the TPA base `$7A00`, so assemble with `.org $7A00`. Host-installed
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
  $0160 monitor body                   $7100 sector buffer (shared ABI)
                                       $7300 OS variables
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
disk (OS installed plus a small sample tree: `/bin/hi.bin`, `/README.TXT`), and
launches it attached to your terminal. You start in the **monitor** (`*`
prompt) — type `?` for monitor help, then **`B`** to boot P8X/OS (`help` lists
its commands). The disk persists at `os/run-disk.img`, so files you `save`
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

At the monitor `*` prompt type `B` to boot the OS, then `help` (a built-in) or
`dir` (a `/bin` program — present on an `os/run.sh` disk).

The full path is covered by a regression test: `make test-os` (in `emulator/`)
builds an image with the OS + two files, boots it, and asserts `dir` lists
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

## Two drives (drive 1 mounted at /d1)

The OS drives up to **two** CF cards in a **single unified namespace**: drive 0
is the root `/`, and drive 1 is **mounted at `/d1`**. In the emulator, attach
them with `-c disk0.img -c2 disk1.img`.

A path is just a path — there is no drive-letter syntax. Everything that takes a
path reaches drive 1 through `/d1`:

- `cd /d1` — the prompt becomes `/d1> `; `cd /d1/SRC`, `cd ..` back out.
- `cat /d1/NOTES`, `dir /d1`, `mkdir /d1/LIB`, `save /d1/PROG 7A00 7B00`.
- Relative paths resolve on whichever drive the CWD is on (the OS tracks that as
  a derived `CURDRIVE`), so once you `cd /d1`, bare `dir` / `cat F` / a `/bin`
  program all operate on drive 1.
- **Cross-mount** works with no special syntax: `cp /d1/A /B` reads drive 1 and
  writes drive 0 (each file stream carries its own drive); `mv`, `diff` likewise.
- `dir /` shows a `D1/` entry (an empty placeholder directory on drive 0 marks
  the mount; traversal into it is redirected to drive 1 before the placeholder is
  read). An absent drive 1 makes `/d1` paths fail cleanly rather than hang.
- **Swapping the card.** Because no drive-1 state is cached (the free pointer,
  root LBA, and CWD are all re-derived), a card can be swapped at the prompt:
  **`umount`** (forgets drive 1's CFINIT-once flag so the new card gets its
  8-bit-mode + IDENTIFY handshake, and drops the CWD back to `/` if it was under
  `/d1`) → pull the card → insert the new card → **`mount`** (re-initializes it
  and reports by reading the boot block: *mounted* / *no card* / *not P8XFS*).
  Swap only at the prompt with no I/O in flight — the True-IDE bus has no
  card-detect line. (A power-cycle also works: `COLD` clears the flag and resets
  the CWD.)

The mechanism is a single **mount redirect** in path resolution — firmware
`FRESOLVE` (used by every `/bin` command) and the OS's own walker `RV_START`
both treat a leading `/d1` component as "route sector I/O to drive 1 and resolve
the rest from its root." So **no command parses a drive prefix** — the two cards
share one ATA task-file port selected by the device bit (`CFSEL`/`DRVSEL`), and
the redirect flips that bit based on the path. For bulk copying — provisioning a
fresh card from a "master" — use **`cp -r /d1/dir /dir`**: the userland `cp`
recurses a whole subtree and works across the mount (each file's read and write
stream keeps its own drive). It creates destination directories via the
`SYS_MKDIR` syscall. (`cp -r` replaced the old flat `IMPORT` built-in.)

## OS syscall ABI (for loadable programs)

The OS publishes a small jump table at the front of its image — like the BIOS
table at `$0100`, but for OS-level services the BIOS deliberately doesn't own
(chiefly the current working directory). The OS stays resident at `$4000` while
a `run` program executes, so a TPA program reaches these with a plain `JSR` (or,
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
| `$4015` | `SYS_SETDRIVE` | *(deprecated in the mount model — the drive follows the CWD's path; kept only as an ABI-stable slot)* |
| `$4018` | `SYS_GETDRIVE` | → `A` = 1 if the CWD is under the `/d1` mount (drive 1), else 0 |
| `$401B` | `SYS_DIRENTRY` | snapshot the entry `FNEXT`/`FFIND` just matched into `(P1)` — 17 bytes: name[12], flag, len(lo/hi), start-LBA(lo/hi). Lets commands read directory metadata without hardcoding BIOS scratch addresses |
| `$401E` | `SYS_OPENDIR` | begin iterating the directory whose 16-bit start LBA is in `P1` (then `FNEXT`); the drive-agnostic way to descend into a subdirectory found via `SYS_DIRENTRY` |
| `$4021` | `SYS_MKDIR` | create the directory named by the path in `P1` (applies the `/d1` mount); `C=1` on real failure, idempotent if it already exists. Lets a `/bin` program (`cp -r`) make directories |

`SYS_GETCWD`/`SYS_CWDLBA`/`SYS_OPENCWD` operate on the single CWD in the unified
namespace (the path shows `/d1/...` when it is on the mounted drive); `SYS_OPENCWD`
routes sector I/O to the CWD's drive first, so a `/bin` program loaded from drive 0
still lists a CWD under `/d1` correctly. They are the supported way to consult the CWD
— no peeking into OS RAM. `os/commands/pwd.c` (PWD) and `os/commands/dir.c` (DIR,
no-arg lists the CWD via `SYS_OPENCWD`, the 16-bit CWD opener) are worked examples;
`compiler/p8lib.c` wraps them as `getcwd(buf)` / `cwdlba()`.

**Program I/O redirection.** `SYS_PUTC`/`SYS_PUTS`/`SYS_GETC` route through the
OS output sink (`OUTCH`), so the shell can redirect a *program's* stdout the
same way it redirects a built-in: `run PROG >FILE` makes `DORUN` open a write
stream and switch `OUTCH` to file mode (`REDIRF=2`, streaming each byte via
`FPUTB`) around the program. The p8cc compilers emit `putchar`/`puts`/`getchar`
as these syscalls, so any compiled program is redirectable with no source
change. **`>>` appends** (`REDAPP`): since P8XFS extents are contiguous and can't
grow in place, append is copy-then-extend — the OS streams the existing file's
bytes into a fresh write stream (raw `CFREAD`s into `APBUF`), then the command's
output, then `FCLOSE` registers it over the old entry (old extent reclaimed by
`pack`). All redirect targets are resolved with `FFIND` **before** `FWOPEN`,
because an `FFIND` after it would scan through the write stream's unflushed
`SBUF` and corrupt the output — this is why `< in >> out` resolves both files up
front. Redirect (and pipe) files resolve in the **current working directory**
(the OS points the BIOS FS at `CWDL` before the open/close), so `cd /SUB; RUN
PROG >OUT` writes `/SUB/OUT`, not `/OUT`. Symmetrically, `run PROG <FILE` binds **stdin** to a file: `DORUN` opens
it as the read stream into `IBUF` and `SYS_GETC`/`getchar` pull from it (`getchar`
returns `-1` at EOF). Both combine — `run CAT.bin <IN >OUT` copies a file. The
canonical filter `os/commands/cat.c` (stdin→stdout) is the worked example. When
stdin is the **console** (no `<` file), `SYS_GETC` echoes each key and treats
**Ctrl-D** (`$04`) as end of input (`getchar` → `-1`) — so `cat >FILE` captures
typed lines to a file and Ctrl-D finishes it.
Note: directory iteration (`FNEXT`) **and** path resolution (`FSCAN`, behind
`FRESOLVE`/`FFIND`/`FOPEN`) default to the same BIOS sector buffer `SBUF` as the
write stream, so a program that does both (`dir`/`tree` iterate; `cat *.X >OUT`
resolves+opens each match) must call `FSDIRBUF` ($0145) to move that directory
traffic onto its own page-aligned 512-byte buffer; the write stream then keeps
`SBUF` to itself and the program streams output with no buffering or size limit
(see `os/commands/dir.c`, `os/commands/lib_globx.c`). It then redirects and pipes
like any other program.

**Pipes** build directly on this: `cmd1 | cmd2` runs `cmd1` with its stdout to a
temp file `PIPE.TMP`, then re-dispatches `cmd2` with its stdin from that file,
then deletes it — a `SHELL` state machine (`PIPEF`) over the `<`/`>` redirection
above, so existing commands are untouched. E.g. `cat FILE | GREP foo`.
(Sequential, **two-stage**: with no multitasking the left command runs to
completion into the temp before the right starts. A third stage — `a | b | c`
— is currently dropped, because the re-dispatch doesn't re-scan for `|`; see the
backlog.)
