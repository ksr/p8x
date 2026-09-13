---
name: reference_p8x_c_subset_gotchas
description: What the P8X C compilers (p8cc.py host, on-board cc) do NOT accept or do slowly -- learned writing basic/basic.c (2026-09-13)
metadata:
  type: reference
---

Writing a big program in the P8X C subset (basic/basic.c, 1,000 lines):

- `p8cc.py` has NO `break` / `continue` ("undeclared identifier 'break'");
  only the on-board `cc` has them. Structure loops with flags / `while (cond)`.
- `int` is UNSIGNED in compares and `/ %`: `while (n >= 0)` never ends; a
  signed compare needs `(a ^ 32768) < (b ^ 32768)`; `-1` is 65535 and can be
  tested with `== -1`.
- No `longjmp`/`setjmp`: an error sets a global flag and every parse level
  returns through it (`if (err) return 0;` after each call).
- Declarations only at the top of a function body (not mid-block).
- No `switch`, `do`, `sizeof`, `typedef`, `static`, `void`, `unsigned`,
  function pointers, nested brace initializers, `#include` (concatenate).
- Brace initializers of `char x[] = { 'P', 0x80, ... }` and `int t[] = {...}`
  work; a raw address is a pointer (`char *p; p = 0xC600;`); an int pointer
  assigned from a char pointer expression does a 16-bit load (`int *w; w = p;
  *w`) -- much cheaper than `p[0] + p[1]*256`.
- A multiply by ANY constant is the 16-iteration `__mul` loop (~1,000
  cycles); `/ %` are `__divmod` (~1,300). Use `<<` (a short `__shl` loop),
  adds, or int pointers instead; `a + a` beats `a * 2`.
- Every call costs a frame (SUBP3/ADDP3 + PHW args + LDW (P3+d)): inline the
  tiny helpers (character classes, blank skipping) in hot paths.
- `bios(FOPEN, PBUF, 0)` etc.: the address must be a literal / `//#define`;
  `//#use abi` names the BIOS/OS entries (lib_abi.c lacks FFIND/FCREATE/
  FLOADAT: define them yourself). `clib.py` resolves `lib_NAME.c` relative to
  the SOURCE's directory (copy lib_abi.c beside a scratch source).
- A C TPA image is big (basic.c: 21 KB, reaching $BD00): test programs that
  POKE "free" memory around $A000 corrupt it.

Writing for BOTH compilers (apps/cc.c, 2026-09-13, so the on-board cc can
compile it too):

- The on-board cc stores a WORD through `*p = v` even for `char *p` (it has
  no type for the deref store): write byte stores as `p[0] = v` or `poke`.
  Reads `*p` are typed correctly.
- String literals <= 127 raw chars (the on-board STRBUF is unchecked) and the
  native assembler's line is 127 chars: split long templates across `emit()`
  calls.
- `if (a && b == c)` was MISCOMPILED by the on-board cc until 2026-09-13 (the
  trailing relational took the condition-mode branch alone); `||` was fine.
  Fixed, but parenthesise if a build with an older cc.bin matters.
- Both accept forward prototypes, `?:`, `!`, `d[-1]` (65535 wraps), `int *h;
  h = 0xB800; h[k]` (scaled), `char *p; p = e;` from an int.
- The on-board cc's per-call cost is 2 x (slots of the CALLER) PHW/PLW: a
  function with 6 locals pays 36 bytes per call it makes. That is why cc.c
  compiled on-board is 35 KB against 18 KB from p8cc.py.

Result for BASIC: C is 2.3x the size and 3.6-4.9x the cycles of the from-
scratch asm (see basic/README.md "The C version"); for the assembler 2.4x /
3.9-4.2x; for the compiler 1.8x / 1.8-2.2x. Related:
[[project_p8x_isa_everywhere]], [[reference_p8x_int_is_unsigned]].
