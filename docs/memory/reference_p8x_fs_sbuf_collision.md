---
name: reference_p8x_fs_sbuf_collision
description: "P8XFS write-stream (redirect) and FRESOLVE/FSCAN dir-scan both default to SBUF $6100 — a program that reads a 2nd file while stdout is redirected corrupts the first file's buffered output"
metadata: 
  node_type: memory
  type: reference
  originSessionId: df90e3f3-8668-416d-bc7b-83f2952ba723
---

The P8XFS write stream (used by shell `>`/`>>` redirects, via FWOPEN/FPUTB/FCLOSE)
buffers pending output in **SBUF ($6100)** (offset tracked in `WOPOS $606E`,
flushed every 512 B). Directory scans (`FSCAN`, used by `FFIND`/`FRESOLVE`) read
sectors into the **DIBUFH page**, which **also defaults to SBUF $6100**. So if a
program does a directory operation (FRESOLVE/FOPEN of a file) *while a redirect
write-stream has unflushed data*, the dir sector overwrites the buffered output.

Symptom: the clobbered bytes become a directory entry — often the "." entry,
`2e 20 20 20 ...` (dot + space-padded). Seen 2026-07-16: `cat a b >OUT` produced
"\x2e   BBB" — the first file's "AAA\n" replaced by the "." dirent, because
catpath's 2nd FRESOLVE read the root dir into SBUF on top of the buffered "AAA\n".

Single-file redirect is FINE (the one FRESOLVE happens before any output is
buffered). Console/pipe are FINE (no SBUF write buffer). Only redirect + a
directory op *after* output starts collides.

THE FIX (per the firmware's own design): a program that scans directories while it
might be redirected must call **FSDIRBUF** to move its dir buffer off SBUF onto a
scratch page. C: `bios(FSDIRBUF, 0, 0xFA)`; asm: `LDA #0 / TAP1L / TAP1H / LDA
#$FA / JSR FSDIRBUF`. `FSCAN`/`FRESOLVE` honor DIBUFH, so this reroutes them.
Pages in use: cat/dir/globx $FA, find/grep $EA, cp $E0 — pick one clear of the
program's code (loads at $6A00) and its read buffer ($FC00). glob_expand already
does this (which is why glob-to-redirect always worked); the plain FRESOLVE paths
did not until cat was fixed 2026-07-16.

Any future command that opens files by name while writing to a redirect needs the
same FSDIRBUF call at entry. See [[reference_p8x_asm_caps]] (the OPCTAB build trap
that surfaced this).
