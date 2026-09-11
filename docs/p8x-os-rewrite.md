# P8X/OS rewrite for the Tier A ISA — plan and log

**Branch:** `os-rewrite` (off `graphics-card`, 2026-09-11). **Safe place:** the
rewrite replaces `os/p8xos.asm` and `os/wmkernel_body.asm` *in place on this
branch*; the OS as it was at the branch point is kept beside them as
`os/p8xos-ref.asm` / `os/wmkernel_body-ref.asm` for reference and diffing.
Nothing here touches `graphics-card` until the user decides to merge.

## Fixed points (not up for change during the rewrite)

1. **The syscall jump table at `$2000..`** — every entry keeps its address and
   its register/flag contract. Programs, the C libraries and 126 tests depend
   on it.
2. **The memory map** (`generators/gen_memmap.py`): every anchor keeps its
   address. The WM kernel's tables, the history ring, SBUF/FSDIRBUF/RDBUF,
   the scratch block — all unchanged.
3. **The on-disk format** (P8XFS v2) and the BIOS calls used.
4. **Byte-identity with the native assembler**: the OS assembles on-target
   (`os_asm_test`, `os_sysbuild`), so **no `.relax` in the OS** until the native
   assembler learns relaxation; only the shapes `gen_p8xopc.py` exports may be
   used. Available to the OS today: `LDPn #imm16` (in use), `LPW1/2/3`,
   `PHW/PLW`, `INCW/DECW` (single-operand shapes in OPCTAB) and `MOVW dst,src`
   (special-cased by `DO_MOVW`). NOT yet: `LDW a,#`, `ADDW/SUBW/CMPW a,b` and
   `a,#`, the `(Pn+d)` forms, `LDW/STW/LEAW a,(Pn+d)`, relative branches. The
   native assembler must grow them first (step 0), or the rewrite is limited
   to the first group.
5. **Acceptance test = the existing suite.** `make test-quick` after every
   module, the full `make test` at every milestone below.

## Step 0 — teach the native assembler the two-operand shapes

Without it the OS can only use single-operand additions (`LPWn`, `PHW/PLW`,
`INCW/DECW`, `LDPn`). `apps/p8xasm.asm`'s `PARSEOP` handles one operand;
`DO_MOVW` special-cases `MOVW dst,src`. Generalise: a second operand after a
comma, shapes `a,a` / `a,#` / `a,#w` / `(Pn+d)` / `a,(Pn+d)` / `(Pn+d),a`,
emitted in the host order (address word first, then disp/imm). Then
`gen_p8xopc.py` drops those shapes from `HOST_ONLY`, and `os_asm_test`'s
cover source gains them. This also unblocks self-hosting the new compiler
output later.

## Order of work (by measured payoff; idiom counts from the 2026-09-11 scan)

| # | Module | Old idioms | What changes |
|---|---|---|---|
| 1 | **WM kernel** `wmkernel_body.asm` — window draw (38 word moves, 9 constants), SGR mouse parser (43 word moves, 5 constants), top-level (12) | ~110 | `MOVW`, `LDW a,#`, `ADDW`/`INCW` on the 16-bit geometry; `(Pn+d)` field access into window records once step 0 lands |
| 2 | PACK | 12 | `INCW` on the 24-bit LBA chains (low 16 bits), `ADDW`, `LPWn` |
| 3 | Tab autocomplete | 8 | `LPWn`, `INCW` |
| 4 | `sh` script runner, MK_WRITE | 10 | `LDW a,#`, `LPWn` |
| 5 | Shell loop / RUN / implicit RUN / path resolution / CD / MKDIR / RMDIR | few | mostly structural: `(P2+d)` operand scanning, `CMPW` on lengths |
| 6 | FSCK, redirection, history | few | as found |

Each module: rewrite → `make test-quick` → size delta noted here → next.
Milestones (full `make test`): after 1, after 4, at the end.

## Measuring

`python3 assembler/p8xasm.py os/p8xos.asm -o /dev/null --base 0x2000` prints
the OS size (14,681 bytes at the branch point; ceiling 16,384; headroom 1,703).
Byte-identity check for the native build: `sh emulator/test/os_asm_test.sh`.

## Log

- 2026-09-11 branch created; reference copies made; plan written.
