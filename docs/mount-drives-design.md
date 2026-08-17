# Unix-style mount for the second CF

**Status: SHIPPED — this is a design record, not a plan.** All five phases are in
`main`: drive 1 is mounted at `/D1`, commands are drive-unaware, and the DOS-model
`0:`/`1:` machinery is gone. The behaviour it describes is live, so read it for the
*reasoning*; for what the code does today, `os/p8xos.asm` and
[p8x-monitor.md](p8x-monitor.md) are authoritative.


## Goal

Replace the DOS-style `0:`/`1:` drive-prefix model with a **single unified
namespace**: drive 0 is the root `/`, and drive 1 appears mounted at a reserved
path `/D1`. A path is then just a path — `CAT /D1/NOTES.TXT`, `CD /D1/SRC`,
`CP /D1/A /B` — with no per-command drive-prefix parsing.

## Why (the payoff)

The `0:`/`1:` model put drive awareness in **every command** (the `lib_drive.c`
prefix parsing). That code pushed `grep` over the TPA size ceiling, so the
stdin-filter tools never got drive support (see BACKLOG). The mount model puts
the drive decision in **one place** — the firmware path resolver `FRESOLVE` —
so:

- Commands need **zero** drive awareness → delete `lib_drive.c`, revert the
  `cat`/`dir`/`cp`/`mv`/`diff` prefix code. The filter-size limitation disappears
  (the commands never grow).
- Cross-mount `CP /D1/A /B` still works via the existing read/write stream-drive
  foundation (`ROSDRV`/`WOSDRV`): each stream captures its drive at FOPEN/FWOPEN.

## Mechanism

`FRESOLVE` (firmware) is the single path-walk entry — `FOPENDIR` calls it, and
`FOPEN`/`FFIND`/`FCREATE`/`FWOPEN` all operate on the `DIRLBA` it leaves. It
already starts every walk at root LBA 33 on the `DRVSEL` card. Inject a
**mount-prefix check** at its top:

- After skipping the leading `/`, if the first component equals the reserved
  mount name `D1` (delimited by `/` or NUL): `CFSEL 1` (route I/O to drive 1 +
  lazy-init) and advance the path cursor past `D1/`.
- Otherwise: `CFSEL 0`.
- Then walk from root (LBA 33) on the now-selected drive, as today.

Because `FRESOLVE` sets `DRVSEL` definitively from the path on every call, all
absolute-path FS ops become mount-aware with no caller change.

## OS changes

- **CWD is one unified path string.** Under the mount it is `/D1/...`. The
  prompt just shows the path (no drive digit). `SYS_GETCWD` returns it verbatim;
  commands build absolute paths from it and `FRESOLVE` does the rest.
- **Remove** the DOS-model machinery: `PARSEDRIVE`, bare-`N:` switching
  (`CKDRIVESW`), the per-drive CWD backing block + `SWITCHDRV`/`SWAPCWD`,
  `SYS_SETDRIVE`/`SYS_GETDRIVE` (or repurpose). `CURDRIVE` becomes a *derived*
  cache (is the CWD under `/D1`?) used only to set `DRVSEL` for the few ops that
  walk from a hardcoded root without a preceding `FRESOLVE` (`FORMAT`/`FSCK`/
  `PACK`, via `SYNCDRV`).
- `CD /D1` / `CD /D1/SRC` resolve through `FOPENDIR`→`FRESOLVE` like any path.

## Discoverability

`DIR /` should show `D1/`. Put a real empty placeholder directory `/D1` in
drive 0's root (created by `run.sh`, and by `FORMAT` for drive 0). Traversal
*into* `/D1` is intercepted by the redirect before the placeholder's (empty)
contents are ever read, so the placeholder is just a signpost. `RMDIR /D1` is
refused (reserved mount point).

## Commands

Revert to their pre-prefix form and **delete `lib_drive.c`**:
`cat`, `dir`, `cp`, `mv`, `diff`, plus the `open_path`/`glob_expand`/`abspath`
prefix hooks in `lib_stdin`/`lib_globx`/`lib_apath`. They resolve unified
paths; the mount is transparent. `cp`/`mv`/`diff` keep working across the mount
because `FRESOLVE` sets `DRVSEL` per path and the streams carry their own drive.

## Phasing

1. **Firmware** — `FRESOLVE` mount redirect + reserved-name EQU. Firmware-level
   test: resolve `/D1/X` reads drive 1, `/Y` reads drive 0.
2. **OS** — unified CWD path, drop the DOS drive machinery, derived `CURDRIVE`
   for `SYNCDRV`, prompt = path, refuse `RMDIR /D1`.
3. **Commands** — delete `lib_drive.c`; revert cat/dir/cp/mv/diff + the lib
   hooks. Cross-mount `cp` still verified.
4. **run.sh / FORMAT** — create the `/D1` placeholder on drive 0.
5. **Tests + docs** — port `os_binprefix_test` → `os_mount_test`; rewrite the
   dual-drive docs (OS README "Two drives" → "Mounting drive 1", command docs,
   HELP, GLOSSARY); update BACKLOG (retire the filter-prefix limitation).

## Keep

The firmware stream-drive foundation (`ROSDRV`/`WOSDRV` captured at FOPEN/FWOPEN,
re-asserted in FGETB/FPUTB/flush) and the emulator shared-bus task-file model —
both are what make cross-mount copies correct; unchanged.
