---
name: feedback_p8x_new_command_dual
description: New P8X /BIN commands must ship in BOTH C and hand-asm versions
metadata: 
  node_type: memory
  type: feedback
  originSessionId: df90e3f3-8668-416d-bc7b-83f2952ba723
---

When asked to create a new P8X /BIN command, implement it **twice**: the C
version in `os/commands/NAME.c` (compiled by p8cc → /BIN) AND a hand-written
assembler version in `os/commands-asm/NAME.asm` (→ /BINA).

**Why:** the [[reference_p8x_hand_asm]] commands-asm experiment established a full
parallel hand-asm command set, verified byte-identical and ~2.3× smaller; the
user wants new commands to keep both tracks in sync, not just the C one.

**How to apply:**
- Write `os/commands/NAME.c` (reuse shared `//#use` libs).
- Write `os/commands-asm/NAME.asm`; if it needs shared helpers, add a `;#use
  stdin`/`glob`/`regex` line (spliced by `os/commands-asm/mkasm.sh`).
- Verify byte-identical with `sh os/commands-asm/verify.sh NAME`; add a
  `cmd_script` case there for it.
- Add it to the command loops in `os/run.sh` (both the /BIN and /BINA loops) and
  to `os/commands-asm/compare.sh`'s ALL list + the README scoreboard.
- Update docs per [[feedback_p8x_docs_before_sync]]; commit per
  [[feedback_p8x_workflow]] (direct to main, push only on "sync").
