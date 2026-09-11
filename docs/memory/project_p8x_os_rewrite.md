---
name: p8x-os-rewrite
description: branch `os-rewrite` (off graphics-card, 2026-09-11) rewrites the resident OS + WM kernel in place around the Tier A ISA; plan/log in docs/p8x-os-rewrite.md; step 0 (native assembler two-operand shapes) and module 1 pass 1 done; graphics-card untouched
metadata:
  type: project
---

**Branch `os-rewrite`** (user asked for "a separate safe place", 2026-09-11):
`os/p8xos.asm` and `os/wmkernel_body.asm` are rewritten IN PLACE; the
pre-rewrite sources sit beside them as `os/p8xos-ref.asm` /
`os/wmkernel_body-ref.asm` (not built). Plan + log: `docs/p8x-os-rewrite.md`.
Fixed points: syscall table, memory map, disk format, byte-identity with the
native assembler (so NO `.relax` in the OS). Acceptance = the existing suite.

**Done on the branch:** step 0 — `apps/p8xasm.asm` parses two-operand and
`(Pn+d)` forms (OPCTAB shapes 10–21, `LIT8` = host lit8 rule) → commit
3e0e3c8; this is toolchain work graphics-card also wants (cherry-pick it
there — ASK first). Module 1 pass 1 — `wordmoves.py` (scratchpad aid, not in
repo) collapsed 85 word moves + 21 constants in the WM kernel: OS 14,681 →
13,965 bytes; wm_* + c_wdesk + c_wtermout + test-quick + os_sysbuild green.

**Next on the branch:** manual pass on the kernel (36 `k16add/k16sub/k_off16/
kw_dec1` chains → `ADDW/SUBW/DECW`; `wk_draw` record unpack → `LDW f,(P1+d)`,
safe because the title loop recomputes P1), then PACK, tab-complete, `sh`.
Full `make test` at the module-1 milestone.

**Gotchas:** the memory dir is the repo's `docs/memory` — notes written on this
branch are NOT on graphics-card until merged. Use `git worktree add
../p8x-os-rewrite os-rewrite` to run both lines without stashing (proposed,
not done). The user's stance (2026-09-11): "wait until current work is
complete then assess next steps" — do not start new modules unasked.
