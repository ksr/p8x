---
name: p8cc-runtime-order-gate
description: "compiler/p8cc.py emit_runtime only emits helpers named in its explicit `order` list; a new __helper missing from it makes EVERY command fail with \"undefined symbol\""
metadata: 
  node_type: memory
  type: reference
  originSessionId: 6ffcfef7-73ca-445b-bcdb-f57735fdc98f
  modified: 2026-09-11T11:15:02.778Z
---

In `compiler/p8cc.py`, `emit_runtime` builds a dict `R["__name"] = [...]` of
runtime routines, but only the names in the explicit `order` list are emitted
(in that order). Adding a routine to `R` without adding it to `order` compiles
silently and then fails at ASSEMBLY of every command that references it:
`undefined symbol '__cmp16'` across 44/45 /bin commands (2026-09-05, the
compiler-only size wins: `__cmp16`, `__ldtw`, `__ldtb` all needed `order` entries).

**How to apply:** any new p8cc runtime helper = two edits (R[...] AND `order`).
Measure size with `sh tools/p8cc_sizes.sh` (compiles all /bin C commands via the
run.sh pipeline, prints per-command bytes + TOTAL, FAIL rows for regressions);
diff against a saved baseline. Related: [[p8cc-int-is-unsigned]] — `__cmp16`
compares are deliberately UNSIGNED (JC/JNC after 16-bit CMP), matching the old
helpers; signed compares are a separate deliberate change, not a bug fix.
