---
name: reference_p8x_code_review_unreliable
description: CODE_REVIEW.md is plausible CLAIMS not verified defects — verify every item before acting; ~half are wrong
metadata: 
  node_type: memory
  type: reference
  originSessionId: df90e3f3-8668-416d-bc7b-83f2952ba723
---

`CODE_REVIEW.md` (P8X repo root, ~400 items over 68 files) was produced by a
fresh-eyes agent fan-out. It is a list of **plausible claims, NOT verified
defects**. Measured hit rate: in the Wave 1 mechanical sweep (2026-07-15, 26
agents) **84 claims were rejected as wrong or already fixed vs 69 applied** — more
bad than good. Always verify an item against the current code before acting on it,
and treat rejecting a bad claim as a success.

Two failure modes seen:
- **Already fixed but still listed** (p8xasm SYMDEFVAL, mv glob same-file guard).
- **Right about the abstract rule, wrong as an action here** — see
  [[reference_p8x_int_is_unsigned]]. Acting on one of these shipped a buffer
  overflow (reverted, 88ba592).

The tests do NOT protect you: the 87-test suite passed the buffer-overflow
version. These bugs are found by reading call sites, not by running tests.

When fanning agents out over it, tell them explicitly that the review may be
wrong and that rejecting an item is a win — that single instruction is what kept
Wave 1 clean. Also keep the hot paths (`p8xasm.asm`, `p8xcc.asm`, `p8xos.asm`,
`p8xmon.asm`, `p8xbasic.asm`, `p8xedit.asm`, `p8cc.*`, `p8lib.c`) out of any
fan-out — a confident-but-wrong flag/carry edit there breaks everything.

Progress marker: items resolved are prefixed `**[FIXED <date>]**` in the doc.

2026-09-02, the trap bites ME: ablation-synth cuts must verify their
BOUNDARIES. Cutting "to the next section marker" in p8x_geom swept the
projection+fan-fill machinery into the "yon pass" measurement -> a
phantom 1,758-LUT finding that died on a corrected cut (yon alone =
noise, -153). Rule: after any ablation, diff WHAT was removed and
re-measure with exact block boundaries before reporting a number. The
walker is already tightly shared (near clip 66, yon ~0); the only
verified space win is the ASCII translator FSM (714, boundaries
checked twice) -- and it is a port-contract change, not a free cut.
