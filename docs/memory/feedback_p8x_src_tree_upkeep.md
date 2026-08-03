---
name: feedback_p8x_src_tree_upkeep
description: Keep the on-disk /src tree AND its build scripts in sync whenever any P8X source changes
metadata: 
  node_type: memory
  type: feedback
  originSessionId: df90e3f3-8668-416d-bc7b-83f2952ba723
---

Whenever ANY P8X source that ships on the disk image changes (a /bin command's C
or asm, a shared lib_*.c/.inc, an app like cc/asm/edit, or the OS/BIOS asm), you
MUST also update the on-target `/src` tree and its build scripts in `os/run.sh`
(the `ensure_src` function) so they stay complete and current — and update the
`/src/mk/*` build scripts + the `make`/`sh` machinery to match.

**Why:** the P8X can rebuild itself from `/src` on-target (`make <target>` /
`sh /src/mk/...`), so `/src` is a real deliverable, not just reference. A stale
`/src` or a build script that names a file that moved/renamed breaks on-target
rebuild silently.

**How to apply:** after adding/renaming/removing a source, grep `os/run.sh` for
the old name and the command list (`_mkcmds`), add/adjust the `/src/...` `put` and
the `/src/mk/<name>` generation, and re-run the relevant test (os_mk / os_make /
os_sysbuild). The tree today: `/src/commands/{c,asm}` (+`/bin` outputs),
`/src/os-bios/asm` (+`/bin`), `/src/mk/<target>`. See [[project_p8x]] and
[[feedback_p8x_new_command_dual]].

Related gotcha: the BIOS read stream length is 16-bit, so a source >64 KB (e.g.
`os/p8xos.asm`, 121 KB) can't be assembled on-target yet — a firmware BACKLOG item.
