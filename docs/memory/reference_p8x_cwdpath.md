---
name: reference_p8x_cwdpath
description: CWDPATH is 48 bytes at $6400 and is NOT just prompt text — it feeds SYS_GETCWD and DERIVEDRV; overflow lands on INMODE/INARM/CWDLH
metadata: 
  node_type: memory
  type: reference
  originSessionId: df90e3f3-8668-416d-bc7b-83f2952ba723
---

`CWDPATH` ($6400, **48 bytes**) is not "the prompt string", despite what the code
and GLOSSARY used to say. It also feeds **`SYS_GETCWD`** (programs resolve relative
paths with it) and **`DERIVEDRV`** (picks the *drive* by string-matching a leading
`/d1`). A wrong CWDPATH is a correctness bug, not a cosmetic one.

Overflow past `$642F` lands on **INMODE/INARM/INNAME** (stdin-redirect state) and,
further out, **CWDLH** — the working directory's own start LBA.

That framing hid a real bug (fixed b41f5f1): `SETPATH` only checked whether the
whole `cd` argument was exactly `..`, appending anything else verbatim, so
`cd ../commands/asm` gave `/src/os-bios/../commands/asm`. Nothing collapsed the
`..`, so the string grew past the real depth — six relative `cd`s reached 63 chars
in a 48-byte buffer, visibly mangling `commands` into `com`.

Now: `SETPATH` walks components (`.` skips, `..` pops, else append) and appends are
bounded by `SPROOM`. Still open: a tree deeper than **47 chars truncates**, so
`SYS_GETCWD` can hand a program a short path (`CWDL`/`CWDN` stay exact). Bounded,
not solved — see BACKLOG.

Lesson worth generalizing: `os_cdnorm_test.sh` existed and passed, but only ever
exercised **bare `cd ..`** — the compound case the code itself admitted was
"approximate" was untested. When a comment says *approximate* or *best-effort*,
that is a pointer to an untested path, not a reassurance.

Related: [[reference_p8x_memory_map]], [[reference_p8x_fs_wrappers]]
