---
name: feedback_p8x_docs_before_sync
description: "P8X — before asking the user to sync, verify ALL docs are current"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: df90e3f3-8668-416d-bc7b-83f2952ba723
---

Before asking the user to **sync** (push) a P8X change, always confirm every
documentation surface is up to date — don't ask for the sync until it is.

**Why:** the user holds docs to the same bar as code; a feature isn't "done" until
its docs are current, and they don't want to discover staleness after pushing.

**How to apply:** after the code/tests are green and before saying "say sync",
sweep the doc surfaces touched by the change:
- code comments + file headers (e.g. `os/commands/*.c` headers)
- on-target HELP text (`MHELP` in `os/p8xos.asm`)
- READMEs (repo root `README.md`, `os/README.md`, `os/commands/README.md`,
  `emulator/README.md`, `compiler/README.md`)
- theory-of-operation docs (`emulator/README.md`, `docs/p8x-monitor.md`)
- tables (BIOS jump table, command rosters, OS syscall ABI)
- generated PDFs / their generators (`microcode/gen_progguide.py`, `generators/`)
- `BACKLOG.md` ("commands to come" / "Next" lists that a change makes stale)
- **man pages** (`os/man/<name>`, installed to `/man`, shown by the `man`
  command): whenever a command's behaviour, options, or usage change, update its
  page. This applies BOTH before sync AND whenever the user asks for a **doc
  review** — a doc review always includes the man pages (standing instruction,
  2026-07-09).

A quick Explore-agent audit (grep for the changed names/old phrasing across all
of the above) is a good way to be exhaustive. See [[project_p8x]],
[[feedback_p8x_workflow]], [[project_p8x_man_pages]].
