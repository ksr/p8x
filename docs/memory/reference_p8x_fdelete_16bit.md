---
name: reference_p8x_fdelete_16bit
description: "FDELETE was 8-bit on dir LBA (fixed); symptom was `make` in a deep subdir building everything"
metadata: 
  node_type: memory
  type: reference
  originSessionId: df90e3f3-8668-416d-bc7b-83f2952ba723
---

BIOS `FDELETE`/`FDEL_CORE` (firmware/p8xmon.asm) used only the LOW byte of the
directory LBA (LBA1 hardcoded 0, 8-bit next-sector advance), so deletes in any
directory beyond **LBA 255** hit the wrong sector and silently tombstoned nothing.
`FCREATE`/`FFIND` were made 16-bit/path-aware long ago (task #50); `FDELETE`,
written for the root, was left behind. Fixed 2026-07-15 (commit 66abfad): use the
full 16-bit LBA (`ADDRH` from `DIRLBA1`) for the read, the tombstone write-back,
and a carry-correct next-sector advance.

Headline symptom: `make` in `/src/os-bios` (at LBA 2662 on a full disk) "builds
everything" — the make built-in's `MK.RUN` temp was never replaced (FDELETE-
before-FWOPEN no-oped), so duplicate MK.RUN entries piled up and `FOPEN` always
ran the FIRST (a prior bare `make`'s two-command recipe). Diagnosis was slow
because it ONLY reproduces when a subdir lands past LBA 255 — small test disks put
subdirs below 256, so every existing test passed and minimal-disk repros didn't
trigger it. Guard: `emulator/test/fdelete_hilba_test.sh` (pads a disk so a subdir
sits >255, deletes a file in it on-target, checks removal).

Lesson: trust the on-hardware/emulator symptom over "your disk is stale" — the
user was right; the minimal-disk repros were misleading. Related same-day fix:
CWDPATH slash normalization ([[reference_p8x_asm_caps]] covers the assembler
symbol-table fix from the same session).
