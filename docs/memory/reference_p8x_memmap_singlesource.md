---
name: reference_p8x_memmap_singlesource
description: The memory-map single source of truth (gen_memmap.py) and what it now generates for commands (lib_mem via //#use mem / ;#use mem); the explicit list of addresses that INTENTIONALLY stay hardcoded, and why, so a future TPABASE/scratch move knows exactly what to sweep.
metadata:
  node_type: memory
  type: reference
  originSessionId: 6ffcfef7-73ca-445b-bcdb-f57735fdc98f
  modified: 2026-09-14T14:40:42.044Z
---

`generators/gen_memmap.py` is THE single source for the P8X data memory map. It
emits (all "do not edit", regenerate with `python3 generators/gen_memmap.py`):
- `generators/memmap.inc` (asm equates, ALL symbols) — `.include`d by
  `os/p8xos.asm` + `firmware/p8xmon.asm`.
- `generators/memmap.h` (C, for the emulator), `generators/memmap.py` (compiler).
- **NEW 2026-09-14: `os/commands/lib_mem.c` + `os/commands-asm/lib_mem.inc`** — the
  COMMAND-facing subset (`COMMAND_SYMS` in gen_memmap.py: TPABASE, SBUF, FNAME,
  FSRC, FLEN, LBA/LBA1/LBA2, DIRLBA/DIRLBA1/DIRN, ROSTAT, ROSDRV, GFXPRES, GTSUSP,
  GCONEN). A command writes **`//#use mem`** (C) / **`;#use mem`** (asm) instead
  of hand-`//#define`ing the literal.

**Why:** the $6100→$5900 flag-day had to touch ~28 sources because each
HARDCOPIED these addresses. Now the C ones are single-sourced: the graphics
commands (screen/term/desk/finder/paint/wdesk/write + lib_gfx), basic.c, and
apps/cc.c + apps/asm.c all `//#use mem`; a map move is one regen. Any harness
that builds cc.c/asm.c/basic.c outside os/commands (it copies `lib_abi.c`) now
also copies `lib_mem.c` (11 harnesses + run.sh; run.sh line 333 ships lib_*.c to
/lib on-target automatically). cc.c's old name `ROSTATE` was renamed to the map
name `ROSTAT`.

**INTENTIONALLY STILL HARDCODED (a map move must sweep these by hand):**
1. **BIOS jump table ($01xx) + syscall vector ($20xx)** — `os/commands/lib_abi.c`
   / `os/commands-asm/lib_abi.inc`, hand-maintained. A deliberate single-file
   ROM ABI (CODE-entry vectors, NOT data); rarely changes; NOT in gen_memmap by
   design (see its docstring). Single-sourced already (one file each).
2. **The 28 `os/commands-asm/*.asm` `.org $5900`** and **~111 test/run.sh
   `--base`/`--load`/`--exec 0x5900`** — TPABASE literals. Kept literal: a
   `;#use mem` for the .org would push several commands to the 5th `;#use` (limit
   is 4), and the tests are shell. These are a UNIFORM, greppable sweep
   (`$5900`/`0x5900`), not scattered ABI — low flag-day pain. On a TPABASE move:
   `sed` them (see [[reference_p8x_tpabase]]).
3. **asm APP equates** — `apps/p8xasm.asm` (FNAME/DIRLBA/DIRN/DIRLBA1),
   `basic/p8xbasic.asm` (GTSUSP/FNAME/FSRC/FLEN), `apps/p8xedit.asm`
   (LBA/FNAME/...). The asm apps are built by CONCATENATION (`cat p8xasm.asm
   opctab.asm`) with no lib/include path in their on-board self-build context,
   and brush the `;#use`(4)/`.include`(1) limits, so `;#use mem` is not clean.
   They MUST match memmap/lib_mem — a move edits these by hand.
4. **FPGA bootloader tools** — `fpga/tang-nano-20k/tools/osload.asm`,
   `imgload.asm` (LBA0/1/2 $1F47-9). Standalone bitstream-side loaders; edit on
   a move.
5. **Bare PAGE bytes** (2-hex, e.g. `DIRPAGE = $F0`, `DEFADDR #$59`, monitor
   `#>SBUF`) — a 4-digit `$XXXX` sweep MISSES these; grep `#\$[0-9A-F][0-9A-F]`
   and `= \$[0-9A-F][0-9A-F]` too. This class bit twice (DEFADDR `#$6A`,
   assembler `DIRPAGE $CE`).

Related: [[reference_p8x_tpabase]] (the full TPABASE sweep checklist),
[[reference_p8x_fs_wrappers]] (the //#use abi call-vector ABI), the BACKLOG item
"Generate the ABI/scratch includes from the single source" (this delivered the C
half; the asm .org/app-equate half is documented-as-hardcoded above).
