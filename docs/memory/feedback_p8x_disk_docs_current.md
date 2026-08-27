---
name: p8x-disk-docs-current
description: "Keep the on-board SD disk's /docs library current after any doc change"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: d50c5367-15d4-4c57-b761-7580b46e8c59
  modified: 2026-08-27T17:20:13.514Z
---

The SD disk carries the project's Markdown docs at /docs (README,
GLOSSARY, GFXTHEORY, GFXGUIDE, BASGUIDE, MONITOR, SYSDESIGN, CARDSTD —
installed by os/run.sh's `_mddoc` list, read on-target with the `md`
command). After changing any shipped doc — or adding one — (1) add or
update its `_mddoc` line in run.sh (12-byte P8XFS names), and (2) get
the change onto the machine: `rm os/run-disk.img && P8X_BUILD_ONLY=1 sh
os/run.sh`, then imgsend the fresh image when the board is attached.

**Why:** the user asked for it explicitly (2026-08-28): the machine is
self-documenting now, and stale on-board docs are worse than none.

**How to apply:** treat /docs like man pages under the existing
docs-before-sync rule — a doc edit isn't done until the disk build
carries it; mention the pending clone if the board isn't attached.

Related: [[p8x-docs-before-sync]] [[p8x-runsh-disk-reuse]]
