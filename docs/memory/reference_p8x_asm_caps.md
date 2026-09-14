---
name: reference_p8x_asm_caps
description: On-target native assembler (asm.bin) capacity + error signatures -- hashed symbol table (1,664 symbols since 2026-09-14, $8000-$E7FF, code must stay below $8000), the DIRPAGE bare-page-byte bug, opctab trap, ;#use host/native asymmetry
metadata:
  type: reference
---

The on-target native assembler (`apps/p8xasm.asm`, run as `asm`/`/bin/asm.bin`)
has a fixed symbol table. Since the 2026-09-12 Tier A rewrite it is a 256-bucket
CHAINED HASH of 16-byte entries (name[12] + value[2] + next[2]) at
`SYMTAB=$8000..SYMEND=$E800` = **1,664 symbols** (`?too many symbols` past it),
with the chain heads at `$E800-$E9FF`. **Grown from 1,120 ($C600) on 2026-09-14**
to self-assemble the 1,548-symbol self-compiled `cc.c`: the buffer block
($C600-$D1FF: HEADS, variables, SECBUF, LINEBUF, INCBUF, the BIOS dir-scan page,
path buffers) moved up +$2200 into room the larger TPA opened. GOTCHA that bit:
`DIRPAGE = $CE` is a bare 2-hex PAGE byte, so a 4-digit-address sweep MISSES it
(same class as DEFADDR `#$6A` / the monitor `#$61`); it stayed $CE while the
buffers moved, and once the symtab grew past $CE00 a pass-2 directory scan wrote
a sector over the symtab entries there, breaking chains -> `?undefined:` on an
EARLY label (a later entry in that label's hash chain was clobbered). Fixed
DIRPAGE->$F0. The C twin `apps/asm.c` stays at 480 symbols ($A800..$C600): its
C-compiled binary is ~5 KB bigger, so it can't reach 1,664 and doesn't need to
(the self-host uses the leaner hand-written /bin/asm.bin). Before the hash it was
a linear
14-byte-entry table at `$8400..$C000` (~1,097), and before 2026-07-14
`$CC00..$FB00` (~859), which overflowed once `p8xos.asm` reached 872 symbols.
The host `assembler/p8xasm.py` has NO such limit, so host builds/tests stay
green while an on-target `make os`/`make p8xasm` fails -- always reproduce
toolchain-capacity bugs on-target (emulator).

**Layout constraint:** the assembler binary (code + generated OPCTAB) loads at
`$6A00` and MUST end below `$8000` (5,632 bytes; it is 4,116). `os_asm_test.sh`
asserts the size. Its other buffers: INCBUF `$CC00`, BIOS dir-scan page `$CE00`
(`FSDIRBUF`), path buffers `$D000-$D1FF`; the TPA is free up to CSTACKTOP `$F800`.

Reference symbol counts: full OS `p8xos.asm` + memmap + wmkernel_body ~1,070
(the reason the capacity had to stay above ~1,100); `p8xasm.asm`+opctab ~274;
BASIC ~700; on-board cc ~830.

Guards: `make test-asm-os` (os_asmos_test.sh -- assemble the OS on-target ==
host; it splices every `.include` of p8xos.asm into one file, since the native
asm allows ONE .include per file), `make test-cmdbuild` (os_cmdbuild_test.sh).
Both in `test-full`, on-demand (slow under emulation). See
[[reference_p8x_cc_caps]] for the C-compiler caps (250 functions/macros since
2026-09-13, code SIZE ceiling).

**String escapes (2026-09-13):** `.ascii`/`.asciiz` decode `\n \t \r \0` and
`\\ \" \'` (the char itself) like the host's `unicode_escape`; before that the
native assembler copied bytes verbatim and a `\"` ENDED the string, so anything
the on-board cc compiled with C escapes in a literal (it emits them raw) was
wrong when assembled natively. `asm.c` mirrors it. A source line is still at
most 127 chars (LINEBUF), so a compiled `.asciiz` line = 10 + the literal.

Trap: `?undefined: OPCTAB` building p8xasm on-target. Root cause (2026-07-16):
the Makefile recipe `cat p8xasm.asm opctab.asm >T.ASM` -- the on-target `cat`
only emitted its FIRST file arg, and `cat A B >T.ASM` corrupts the first file
([[reference_p8x_fs_sbuf_collision]]). Fixed: run.sh ships p8xasm.asm with a
trailing `.include "opctab.asm"` and the recipe is a plain `asm p8xasm.asm`.
Lesson: reproduce toolchain failures on-target.

Trap: `?missing #use include: ...` -- the host and native assemblers DISAGREE on
`;#use`. The host sees a leading `;` and treats it as a comment; the native
`asm.bin` implements it and reads `/lib/NAME.inc` off the disk. Anything that
splices host-side must strip the directive (`mkasm.sh` rewrites the line).
Whole bug class: a `;`-prefixed pseudo-directive is a no-op host-side and live
on-target -- host-only-passing failures are expected; reproduce on-target.
