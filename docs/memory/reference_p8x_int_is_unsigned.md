---
name: reference_p8x_int_is_unsigned
description: "p8cc has no unsigned type — int is used AS unsigned 16-bit for sizes; unsigned compare/div is load-bearing, do not \"fix\" it"
metadata: 
  node_type: memory
  type: reference
  originSessionId: df90e3f3-8668-416d-bc7b-83f2952ba723
---

**Do not make p8cc's `<`, `>`, `/`, `%`, `>>` signed.** It looks like a bug and is
not. p8cc's subset has **no `unsigned` type**, so the whole codebase uses `int` as
an unsigned 16-bit quantity for sizes, offsets and counts — and depends on the
compiler's unsigned compare/division to make that work. It is load-bearing.

Proof (cmp.c, deliberate):

    /* Keep counting past 8192 even though we stop storing, so the
     * over-size check below can detect a too-large file. */
    if (n1 < 8192) { b1[n1] = c & 255; }
    n1 = n1 + 1;
    ...
    if (n1 > 8192) { puts("cmp: file1 too large (max 8K)"); return 1; }

With a signed `<`, a 40000-byte file makes `n1 == -25536`: `n1 < 8192` is TRUE so
it writes `b1[40000]` into an 8192-byte buffer, and `n1 > 8192` is FALSE so the
guard never fires. A clean error became a buffer overflow on any file >= 32768 B.
I shipped exactly this and reverted it (88ba592); the 87-test suite passed it
(nothing tests cmp with a >32K file). Verified on-target: probe at n=40000 printed
GG before, BB after.

Same reasoning kills signed `/`: cmp.c `pnum` and p8lib.c `putn` print sizes
>32767 via a `v / 10` loop, both commented "print a non-negative decimal".

So `if (x < 0)` genuinely does not work, and that is the accepted price. The real
fix is to **add `unsigned` to the subset** and migrate every size/offset onto it —
a language feature, not a bug fix. Until then the CODE_REVIEW signed/unsigned
findings are WONT-FIX. `>>` is separately safe to leave alone: every shipped use is
masked (`(v >> 8) & 255`), so arithmetic vs logical is unobservable.

Aside, verified: the ISA *does* have signed branches (`BLT $44`, `BGE $45`,
`BLE $46`, `BGT $47`; `LT = N^V` after `CMP`) — availability was never the blocker.
See [[reference_p8x_code_review_unreliable]].
