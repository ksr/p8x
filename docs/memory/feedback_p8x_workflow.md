---
name: feedback-p8x-workflow
description: "p8x project uses direct commits to main, no PRs; branches on request only — and ASK before merging any branch to main"
metadata:
  node_type: memory
  type: feedback
  originSessionId: df90e3f3-8668-416d-bc7b-83f2952ba723
  modified: 2026-08-24T01:13:37.769Z
---

Commit directly to main for the p8x project. Do not create feature branches or
open pull requests **for ordinary work**.

**Why:** Solo project, PRs are unnecessary overhead.

**How to apply:** After making changes in ~/Documents/Projects/p8x, stage and
commit straight to main and push. Skip any PR creation step.

**Exception, added 2026-08-17:** the user *asked* for a branch for the SDRAM
framebuffer experiment ("lets start a branch in GIT so we can give SDRAM a
try"), and `sdram-framebuffer` was created for it. So the main-only rule covers
normal work, not speculative hardware work that might be abandoned. Do not
assume every task belongs on main — but do not invent branches either; the user
asks when they want one. That branch is local and unpushed; main is unaffected.

**Branch merges, added 2026-08-23:** ALWAYS ask before merging a branch into
main — even when the user says "sync" or "push". Those words authorize
committing/pushing the current branch, not folding a branch into main.

**Why:** After the g3d-stage9 merge (done on the word "sync"), the user said:
"in the future I want you to ask before doing a branch merge."

**How to apply:** When work sits on a branch and a sync/push moment arrives,
push the branch, then ask explicitly: "Ready to merge <branch> into main?" and
wait for a clear yes before merging or deleting the branch.

Related: [[project_p8x_fpga]] for the FPGA track, [[feedback_git_no_dash_c]] for
the invocation form.
