---
name: reference_p8x_relpath_gotcha
description: P8X /bin commands must CWD-prefix relative path args — FOPENDIR/FRESOLVE start at root
metadata: 
  node_type: memory
  type: reference
  originSessionId: df90e3f3-8668-416d-bc7b-83f2952ba723
---

On P8X, the BIOS path resolvers **FRESOLVE ($0133) / FOPEN ($0124) / FOPENDIR
($0139) always start at the ROOT**, not the CWD. So any `/bin` command that takes
a path argument must make it absolute first (prefix the CWD when it doesn't start
with `/`) before handing it to a BIOS open — otherwise `cd sub; cmd name` looks up
`/name` and fails "not found". `cmd` with no arg is fine because it uses
`SYS_OPENCWD ($4012)`.

The shared helper is `abspath()` — C: `//#use apath` (os/commands/lib_apath.c);
asm twins inline an `abspath` routine (see touch.asm/mv.asm/dir.asm) with
ap_out/ap_a/ap_n + a path buffer, calling `SYS_GETCWD ($4003)`. cp/mv/diff/touch/
dir all do this. `dir` originally didn't (fixed 2026-07-10, commit 1f59b1a) — the
bug hid because tests only used absolute path args. When adding/reviewing a
command with a path arg, check it abspath()'s a relative one, and that BOTH the C
and asm twins do (verify.sh compares them). See [[feedback_p8x_new_command_dual]].

**BASIC had this bug; FIXED 2026-08-13** by `APATH` in `p8xbasic.asm` (prefixes
`SYS_GETCWD` onto a relative path before `FRESOLVE`, gated on `MONITOR` so the
disk-boot build is unaffected). Covered by `emulator/test/basic_cwd_test.sh`.

**Trap that made the fix look broken for half an hour:** `tools/p8xfs.py put`
does **not replace an existing file** — it silently leaves the old one in place.
Installing a rebuilt `/bin/basic.bin` over the existing one therefore kept
testing the OLD binary, and every symptom pointed at the new code. When an
on-target change appears to have no effect, **verify the binary on the image**
(`p8xfs.py get` + `cmp`) before debugging the source. Install under a fresh name,
or rebuild the disk from scratch.
