---
name: reference_p8x_cc_caps
description: On-target C compiler (apps/p8xcc.asm) fixed table caps and the next ceiling
metadata: 
  node_type: memory
  type: reference
  originSessionId: df90e3f3-8668-416d-bc7b-83f2952ba723
---

The on-target C compiler `apps/p8xcc.asm` uses fixed-size tables with **no bounds
checks** except where noted. Known caps (as of 2026-07-12):

- **Functions: MAXFUNC=64** (`FNPAR`/`FSLOT` `.fill 64`, `FPOOL` `.fill 384` B of
  packed names). `FADD` now bails with "cc: too many functions" past the cap.
  Was `.fill 16`/`128` and silently overran → blank `JSR _f_` → `asm ?undefined`;
  this broke every `//#use`-spliced command with 17+ functions (wc 17, dir 19,
  grep 18, sed 17, vi 34, cc1 40). Fixed in commit f989cfc.
- **Variable slots: now 16-bit** (2026-07-13). Was an 8-bit `SLOTCNT` (255-slot
  wrap → `?undefined: V232` on dir). Reworked to 16-bit throughout, AND all
  variable storage now lives in ONE array `__V` (slot n → `__V+2n`) instead of a
  `V<n>:` label per slot — so slot count no longer inflates `asm`'s ~850-symbol
  table. dir (~838 slots) compiles + assembles clean.
- **NEXT CEILING = code SIZE** — but much less tight since 2026-07-15. The native
  codegen WAS ~2x the host `p8cc.py`; emitting the wide ops it always had access
  to but never used closed that to **~3.4%** (wc.c: 8829 -> 4617 instructions,
  -48%; p8cc.py = 4467). Three rounds, each a safe 1-for-4 substitution in the
  emit helpers, each also SHRINKING cc.bin (22797 -> 22655 B): single-operand
  wide ops (PHW/PLW/LPW1); `MOVW` for LDVAR/STVAR (needed teaching the native
  assembler the two-operand `MOVW` form, opcode $78 — the ISA's only
  two-operand instruction); and `PHW`/`PLW __V+<2n>` for slot save/restore,
  which alone killed 860 PHA/PLA (p8cc.py emits zero) plus their paired LDA/STA.
  Re-measure before assuming a big command still won't fit.
  The remaining ~3.4% needs temp reuse / peephole fusion — structural changes to
  a single-pass emit-as-you-parse compiler, which would GROW cc.bin (already
  22.6 KB of the ~37 KB TPA) and risk miscompiles. Judged not worth it; stop here
  unless something forces it.

Testing note: the on-target cc build tests must exercise a **>16-function** AND a
**>255-slot** program or they miss these regressions — `os_cc_bigcmd_test` covers
both (a 20-function synthetic + a `char big[600]` >255-slot program); the older
`os_cc_test`/`os_mk_test` only built tiny sources (pwd), which is why the
overflows went uncaught for so long.

Related: [[project_p8x_sed_diff_buffer]] (the separate SBUF read/write collision
that truncated cc output, fixed earlier by moving cc's read buffer to $FC00),
[[project_p8x_selfhost_multipass]].
