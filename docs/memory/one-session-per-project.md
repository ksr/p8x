---
name: one-session-per-project
description: Ken runs a separate Claude session for P8X and for YACC1-D; cross-project work is reference-only unless he asks
metadata:
  node_type: memory
  type: user
  originSessionId: 90ee1eb5-8840-4fd4-ab77-86d0b0aee6c2
  modified: 2026-10-04T14:50:40.944Z
---

Ken keeps two Claude sessions going at once: one mainly for P8X (`~/Developer/p8x`) and one for YACC1-D.
They reference each other now and then. Usually YACC1 borrows from P8X (e.g. porting the P8X OS commands to
Y1/OS). Pulling YACC1 work into P8X happens less often but can happen.

**Why:** each repo has its own session doing live work in it. A second session pulling, committing or editing
in the same tree can collide with that work.

**How to apply:** first work out which project the session is for: Ken says so, or it shows in his questions,
not just the working directory. Treat the other repo as read-only reference: read it, compare with it, quote it.
Change it, or pull/commit there, only when Ken asks for that specifically. Before porting something across,
check the target project's own rules. YACC1-D's CLAUDE.md treats P8X as read-only, and Y1/OS is not kept in
sync with P8X. Related: [[project_yacc1]].
