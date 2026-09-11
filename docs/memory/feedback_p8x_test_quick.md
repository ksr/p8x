---
name: p8x-test-quick
description: user wants a representative fast test subset (`make test-quick`) instead of the ~25-minute full suite for routine changes; full suite only before commits that touch compiler/microcode/assembler/OS and before sync
metadata:
  type: feedback
---

The user asked (2026-09-11) for "a representative set of tests that gives a high
degree of confidence without running such a large suite". Agreed set, added as
`make test-quick` in emulator/Makefile (~8-10 min vs ~25-30 for `make test`):
test-isa (ISA + wordops + include), c_test, c_struct, c_bios (self-host
differential), c_libfile (caught the P3-frame buffer bug), c_filters (real
commands piped), asm_selfhost (host = native assembler), c_disasm (C/asm twin;
caught the relative-branch A clobber), c_finder_ret (nested launch; caught the
startup relocation bug), c_glasstty.

**Why:** the slow soak tests (os_bigfile, c_desk's 8 runs, c_textutils,
c_findiff, wm_*) rarely fail alone and cost most of the wall time.

**How to apply:** run `make test-quick` after every change; run the full
`make test` only before committing a change to the compiler, microcode,
assembler or OS, and before a sync. Report the numbers of both. Related:
[[p8x-test-scope]], [[p8x-test-streaming]].
