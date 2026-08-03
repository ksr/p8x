---
name: project_p8x_man_pages
description: "P8X — on-target man-page system: os/man/ files, /man dir, man command"
metadata: 
  node_type: memory
  type: project
  originSessionId: df90e3f3-8668-416d-bc7b-83f2952ba723
---

P8X has a Unix-style manual-page system (added 2026-07-09).

- **Source:** `os/man/<name>` — one plain-text page per command, lower-case name,
  no extension. Layout: NAME / SYNOPSIS / DESCRIPTION / OPTIONS / EXAMPLES /
  SEE ALSO. `os/man/README.md` documents the format (excluded from install).
- **On disk:** `run.sh` creates `/man` and installs each page as `/man/<name>`.
- **Command:** `man` (`os/commands/man.c` + byte-identical `os/commands-asm/man.asm`)
  streams `/man/<arg>` — a `cat` with a fixed `/man/` prefix; unknown → "no
  manual entry for NAME". Test: `emulator/test/os_man_test.sh`.
- Pages exist for all `/bin` commands, edit/asm/basic, `man`, and the OS
  built-ins (cd, del, pack, mount, …).

**When adding a `/bin` command or OS built-in, also add its `os/man/<name>` page**
(auto-picked-up by run.sh + the test). A doc review must review the man pages —
see [[feedback_p8x_docs_before_sync]] and [[feedback_p8x_new_command_dual]]
(new commands ship C + hand-asm; `man` followed that too). See [[project_p8x]].
