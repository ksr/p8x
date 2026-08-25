---
name: xt-card-separate-project
description: "The XT/ISA bridge card work (hardware/xt-card, gen_eagle EDGE62/DIP40W, XT memmap rows) is a SEPARATE project — do not commit, sweep, or track it within p8x work"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: d50c5367-15d4-4c57-b761-7580b46e8c59
  modified: 2026-08-25T14:28:28.082Z
---

The XT-bus bridge card (hardware/xt-card/, the EDGE62/DIP40W packages in
gen_eagle.py, the XTADL..XTCW2 rows in gen_memmap.py, the BOM/BACKLOG
entries) is a SEPARATE project from p8x proper, per the user 2026-08-25.

**Why:** the user said "the xt is a separate project so we shouldn't
concern ourselves in this project" while its files sat uncommitted in the
p8x working tree during stage-10 work.

**How to apply:** never stage, commit, doc-sweep, or backlog-coordinate
the XT files as part of p8x commits or syncs. When an XT edit shares a
file with p8x work (gen_memmap.py, BACKLOG.md), split the p8x hunk out
surgically (git hash-object + update-index, as done at the stage-10c
sync) and leave the XT content untouched in the working tree. The user
handles that project's lifecycle themselves.

Related: [[feedback-p8x-workflow]] [[p8x-gfx-clib]]
