---
name: feedback_p8x_test_scope
description: "P8X — run only the relevant test(s); full `make test` suite only for broad changes or on request"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: df90e3f3-8668-416d-bc7b-83f2952ba723
---

On P8X, be selective about test scope. Run only the test(s) relevant to the change; do NOT default to the full `make test` suite after every edit.

**Why:** the full suite is slow (~10 min, dominated by `asm_selfhost`), and most changes are localized. The user called this out after I reran the complete suite repeatedly during the wildcards-on-filters work.

**How to apply:**
- Single command change (e.g. one `.c` in `os/commands/`) → run just its test (`sh emulator/test/c_<area>_test.sh`), e.g. cat→c_cat, wc/grep→c_filters, sort/uniq/sed→c_textutils, head/tail/more→c_pager, dir→c_dir/c_dirglob.
- Run the **full suite** when the change is broad and could affect everything: the **compiler** (`p8cc.py`/`p8cc.c`/`p8lib.c`), **microcode** (`genucode.py`), **firmware** (`p8xmon.asm`), the **assembler**, or **shared `//#use` libs** every command pulls in (`lib_stdin.c`, etc.) — or when the user asks. (The full reruns during the compiler/ISA-shrink/remap work WERE justified for this reason.)
- Still stream `make test` to a logfile, not through grep — see [[feedback_p8x_test_streaming]].

c_demo_test.sh (b2adee6) closes the demo-fleet gap: all ten C graphics
clients compile via clib.py and are asserted BELOW CSTACKTOP (read from
generators/memmap.py), plus frame-pixel smoke for house/tri/camera/
rotate/page. Any lib_gfx/lib_g3d/lib_g3cam growth now fails loudly
instead of corrupting a client's pool at run time. Part of make
test-gfx.
