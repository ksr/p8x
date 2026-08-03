---
name: reference_p8x_asm_caps
description: On-target native assembler (asm.bin) error signatures — symbol-table cap, opctab trap, ;#use host/native asymmetry
metadata: 
  node_type: memory
  type: reference
  originSessionId: df90e3f3-8668-416d-bc7b-83f2952ba723
---

The on-target native assembler (`apps/p8xasm.asm`, run as `asm`/`/bin/asm.bin`)
has a fixed symbol table. As of 2026-07-14 it lives at `SYMTAB=$8400..SYMEND=$C000`
(14-byte entries: name[12]+value[2]) = **~1097 symbols**. It was `$CC00..$FB00`
(~859) and overflowed with `?too many symbols` once `p8xos.asm` reached 872
symbols — moved down into the free gap below the `$C000` var block (the assembler
binary is only ~4.3 KB, loads at `$6A00`). The host `assembler/p8xasm.py` has NO
such limit, so host builds/tests stay green while an on-target `make os`/`make
p8xasm` fails — always reproduce toolchain-capacity bugs on-target (emulator).

Reference symbol counts (all well under 1097): full OS `p8xos.asm` ~872;
`p8xasm.asm`+opctab ~302; heaviest compiled command `vi` ~448, `grep` ~345.

Guards: `make test-asm-os` (os_asmos_test.sh — assemble the OS on-target == host),
`make test-cmdbuild` (os_cmdbuild_test.sh — heaviest command via both toolchains).
Both in `test-full`, on-demand (slow under emulation). See [[reference_p8x_cc_caps]]
for the C-compiler caps (MAXFUNC=64, code SIZE ceiling).

Trap: `?undefined: OPCTAB` building p8xasm on-target. The OLD note here ("opctab
is empty, rebuild the disk fresh") was WRONG and cost real time — a fresh disk did
NOT fix it. Root cause (found 2026-07-16 by reproducing ON-TARGET, not host):
`opctab.asm` ships fine (5443 B, has `OPCTAB:`); the failure was the Makefile
recipe `cat p8xasm.asm opctab.asm >T.ASM`, because the on-target **`cat` only ever
emitted its FIRST file arg** — so T.ASM was p8xasm.asm alone and OPCTAB was never
defined. (And even with cat fixed, `cat A B >T.ASM` corrupts the first file — see
[[reference_p8x_fs_sbuf_collision]].) Fixed 2026-07-16: run.sh ships p8xasm.asm
with a trailing `.include "opctab.asm"` and the recipe is a plain `asm
p8xasm.asm` — no cat. Note the native `asm` allows only ONE `.include` per file,
so it's a single trailing include, not a wrapper with two. Lesson (again): the
host `cat` in test scripts hid an on-target `cat` bug; reproduce toolchain
failures on-target.

Trap: `?missing #use include: ...` — the host and native assemblers DISAGREE on
`;#use`. The host `p8xasm.py` sees a leading `;` and treats it as an ordinary
comment; the native `asm.bin` *implements* it and reads `/lib/NAME.inc` off the
disk. So anything that splices host-side must strip the directive, or the native
build hunts for a file that isn't there while host builds stay green. This bit
`mkasm.sh`, which `cat`ed the twin source verbatim and then appended the include
(fixed 2026-07-15 — it now rewrites the line as it splices). Whole bug class:
a `;`-prefixed pseudo-directive is a no-op host-side and live on-target, so
host-only-passing failures are expected — reproduce on-target.
