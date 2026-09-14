---
name: reference_p8x_cc_caps
description: On-target C compiler table caps (250 funcs/macros, 16-bit labels/slots), the bugs the C twin found; apps/cc.c is now the P3-FRAME model (recursion-correct, ~13% smaller, >255-byte-local guard) while p8xcc.asm stays static-slot; self-host is now a TPA problem not codegen
metadata: 
  node_type: memory
  type: reference
  originSessionId: df90e3f3-8668-416d-bc7b-83f2952ba723
  modified: 2026-09-09T13:34:02.562Z
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
- **//#define macros: now 64** (2026-09-09). Was `MACVALS .fill 64` = **32 max**
  with **no bounds check** in `MAC_ADD`. `lib_abi.c` grew to **37 `//#define`s**,
  so compiling ANY C file that `//#use abi` (nearly all of them -- e.g. pwd.c)
  overflowed MACVALS by 5 entries straight into `USESTATE` (the saved `//#use`
  read-stream state, the next `.fill` after it) -> when the lib_abi splice
  finished, the popped/restored stream was garbage -> **the machine RESET to the
  monitor**. THIS was the "on-board cc crash" (os_mk_test's `make pwd` failure)
  -- NOT a capacity limit hit cleanly, a silent corruption. Fix: `MACVALS .fill
  128` (64), `MACNAMES .fill 384 -> 768`, + a `MAC_ADD` guard that bails "cc: too
  many //#define macros" like `FADD` does. Same class as the MAXFUNC bug above.
  os_mk_test also needed `/bin/del.bin` on its disk (its `make clean` recipe runs
  `del`, now a /bin program not a builtin).
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

**2026-09-13 rewrite (apps/p8xcc.asm, Tier A edition):** MAXFUNC stays 64 and
`//#define` stays 64, `//#use` nests 5 deep; the name tables are now arenas at
BSS `$B000-$DFFF` (global names ~3 KB, locals 768 B per function; overflow =
`cc: symbol table full`), so cc.bin is code only (10,075 B). The generated code
is unchanged (tab-indented text), so the SIZE ceiling of a compiled command is
the same as before. The old compiler compiled a `char` array declared AFTER an
`int` array with word elements -- any on-target build of grep -r before this
date had that latent bug (the shipped /bin twins are host-built and unaffected).

**2026-09-13, later (the C twin apps/cc.c):** MAXFUNC and MAXMAC are 250, BSS
moved to `$A000` (the binary ends ~$9200) so the global arena is `$B200-$DFFF`
= 11.5 KB (cc.c's ~330 names need ~4.3 KB); prototypes count as functions
(FADD twice for a prototyped function). Label numbers are 16-bit words (`LBLW`
block at BSS+$460, NEWLBL -> NEWL, EMITJ/EMITLBL take JLBL) -- the byte
counter wrapped at 256 and grep (600 labels) / vi (353) got duplicate labels
from every on-board build. Local array sizes are computed in 16 bits (`char
b[300]` was 21 slots). `a && b == c` in a condition fell into the body when a
was false (GLAND now clears CONDCUR before the right operand). All three were
found by diffing cc.c's output against the asm compiler's on the machine
(`cc_c_test.sh`), which is the way to find the next one.

**2026-09-13 (later): frame model LANDED in `apps/cc.c`.** `apps/cc.c` is now
the P3-frame codegen (globals in static `__V`, locals+params in a `SUBP3
#_fr_NAME` frame, `(P3+d)`, no slot-saves, recursion-correct), plus a one-token
leaf optimization (bare const/scalar right operand skips push/pop). ~13% smaller
output on real programs (grep 54,171 → 47,255 B). Binary 21,306 B. Verified by
RUNNING its output (`cc_c_test.sh`, reworked to behavioural since the twin diff
is suspended). Design/data: `scratchpad/FRAME_PLAN.md`.
- **Guarded limit, NOT silent:** a function with >255 bytes of locals overflows
  the 8-bit `(P3+d)` displacement, so cc.c BAILS ("frame ... over 255 bytes (use
  /bin/cc)") — `emfp` checks locals, the epilogue checks `nloff + 2*nparams`.
  grep `collect` cn[384], cp `copy_tree` names[312] hit this; the static-slot
  `/bin/cc` (p8xcc.asm) still compiles them. A general far-path is future work.
- **`apps/p8xcc.asm` is still static-slot** (the default `/bin/cc`), so the two
  compilers diverge and the `cc_c_test` twin byte-DIFF is SUSPENDED (see BACKLOG:
  "Port the frame model into p8xcc.asm"). Each compiler is independently tested.

**Self-host still does NOT fit — but it is a TPA problem now, not codegen.** The
frame self-compile is ~30.6 KB and overruns its tables at `$C800` / collides
with the P3 stack. Codegen tweaks are marginal (leaf ~400 B net; a global-collapse
peephole is +742 B net because the compiler compiles its own optimization code).
The lever is more TPA (monitor ROM 8K→6K reclaim, +2 KB). The native assembler
also needs ~1,188 symbols vs 1,120 for the on-board round-trip. Other on-board cc
limits cc.c respects: string literals ≤127 raw chars (STRBUF, unchecked),
`*p = v` is a WORD store, the assembler's 127-char line.
