---
name: project_p8x_sed_diff_buffer
description: "P8X sed/diff \"p8cc.c miscompile\" was actually an $E000 read-buffer collision — fixed by moving to $FC00"
metadata: 
  node_type: memory
  type: project
  originSessionId: df90e3f3-8668-416d-bc7b-83f2952ba723
---

The long-standing P8X backlog note "p8cc.c miscompiles the file-arg parse in sed.c/diff.c" was a **misdiagnosis**. The real cause (found & fixed 2026-06-26): the shared `/BIN` file read buffer was hardcoded at **`$E000`** (only ~12 KB above the `$B000` TPA base). The native `p8cc.c` emits ~8% larger code than `p8cc.py`, so the two biggest commands overran `$E000` (host `sed` ends `$E333`, `diff` `$F4C9`) and `FGETB` read file data into their own code → garbage/no output. Only sed/diff hit it (biggest commands), only on `p8cc.c` (bigger codegen) — which made it look compiler-specific.

Fix: moved the read buffer to **`$FC00`** (just under the stack page `$FE00`) in `os/commands/lib_stdin.c` (openarg), `cat.c`, `cp.c`, `mv.c`, `diff.c`. Both now build+pass on BOTH compilers; the `p8cc.py`-only guards in `c_textutils`/`c_findiff` were removed. dir/tree/find keep their `$E0` FSDIRBUF page (small code; their C stack grows down so a low buffer is safer there).

Implication: a `/BIN` command's code+globals must stay below `$FC00` (~19 KB). `diff` is the largest (~17.6 KB on `p8cc.c`) — watch its headroom. Closing this also means every `/BIN` command compiles correctly on the native compiler (relevant to [[project_p8x_selfhost_multipass]] / Milestone B). See [[project_p8x]].
