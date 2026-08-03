---
name: project_p8cc_keep_python
description: "When self-hosting p8cc, keep the Python compiler — the C version is added alongside, never replaces it"
metadata: 
  node_type: memory
  type: project
  originSessionId: df90e3f3-8668-416d-bc7b-83f2952ba723
---

For P8X milestone A (rewrite the p8cc C compiler in its own small-C subset so it
self-compiles), the Python implementation `compiler/p8cc.py` must be KEPT, not
replaced. The C-source compiler (e.g. `compiler/p8cc.c`) lives *alongside* it.

**Why:** p8cc.py is the host bootstrap — it's what compiles the C-source
compiler in the first place. Deleting it breaks the bootstrap chain (you'd need
an already-working p8cc binary to rebuild p8cc from source). It also stays the
reference oracle for differential testing the two compilers against each other.

**How to apply:** when doing task #57, add a new file, don't overwrite p8cc.py.
Keep both building/tested in the suite. See [[project_p8x]].
