---
name: feedback_git_no_dash_c
description: "Run git from inside the repo (cd first), never `git -C <path>` — the -C form triggers a permission prompt"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 5487e9bb-277f-4eec-ae2a-9f9556aaeeb0
  modified: 2026-08-17T16:41:40.398Z
---

Invoke git by changing into the repo first — `cd ~/Documents/Projects/p8x && git status` —
rather than `git -C ~/Documents/Projects/p8x status`.

**Why:** Claude Code auto-allows read-only git subcommands (`status`, `log`, `diff`,
`show`, `branch`, `rev-parse`, …) without prompting, but the `-C <path>` form is not
recognised by that check and prompts every time. A transcript scan found 18 `git -C`
calls and 22 separate `git -C …` entries accumulated in
`.claude/settings.local.json` — one approval per distinct command string, none of
which generalise. The plain form would have prompted zero times.

**How to apply:** always `cd` to the repo (or rely on the session's working
directory) before running git. If a one-liner genuinely needs to touch a different
repo, prefer `cd <repo> && git …` over `-C`. This is purely about the invocation
form; the git commands themselves are unchanged.

Related: [[feedback_p8x_workflow]] for the commit-to-main-directly rule.
