---
name: project_p8x_selfhost_multipass
description: P8X self-host compiler (milestone B) direction — multipass driver of separate /BIN pass binaries
metadata: 
  node_type: memory
  type: project
  originSessionId: df90e3f3-8668-416d-bc7b-83f2952ba723
---

The plan for self-hosting the C compiler on the P8X (task #58 / "Milestone B") leans toward splitting it into a **multipass driver of separate `/BIN` pass binaries staged through temp files on disk** — like early Unix `cc` driving `cpp`/`cc1`/`as` — because a monolithic compiler's working set + ~20 KB code won't fit one pass in the ~20 KB TPA at `$B000`.

The **source preprocessor is the natural first pass**. `tools/clib.py` (the host `//#use lib_*.c` splicer added 2026-06-26) is the prototype for that pass; a native C rewrite reading via BIOS `FOPEN`/`FGETB` becomes the on-target `CPP.BIN`. So `clib.py` is a deliberate host-era convenience that Milestone B subsumes, NOT a throwaway — keeping it tiny keeps the native port tiny. (Decided with the user 2026-06-26.)

Related: [[project_p8x]], [[project_p8cc_keep_python]], [[feedback_p8x_test_streaming]].
