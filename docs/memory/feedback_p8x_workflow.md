---
name: feedback-p8x-workflow
description: "p8x project uses direct commits to main, no PRs — but speculative hardware experiments get a branch on request"
metadata:
  node_type: memory
  type: feedback
  originSessionId: df90e3f3-8668-416d-bc7b-83f2952ba723
  modified: 2026-08-17T22:23:03.424Z
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

Related: [[project_p8x_fpga]] for the FPGA track, [[feedback_git_no_dash_c]] for
the invocation form.
