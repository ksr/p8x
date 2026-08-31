---
name: p8x-rename-doc-sweep
description: "On any P8X rename/retirement, grep the WHOLE repo for the old name before committing — distant doc surfaces drift silently"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: d50c5367-15d4-4c57-b761-7580b46e8c59
  modified: 2026-08-31T14:32:54.944Z
---

The 2026-08-31 "is ALL doc up to date" audit found stage-4-era claims
(PLOT, POINT(), four-colour pens, SETPAL, "no card built yet") still
live in README.md, basic/README.md, emulator/README.md, GLOSSARY.md and
docs/p8x-monitor.md — multiple epochs after the facts changed.

**Why:** each change updated its *adjacent* docs (man pages, the guides,
the design log) but surfaces describing the same facts from other angles
(top-level READMEs, the glossary, other components' READMEs) were never
in the edit path and drifted silently.

**How to apply:** before committing any rename, retirement, or semantic
change in [[project-p8x]], run a repo-wide grep for the OLD name/claim
across `*.md`, man pages, HELP text, and comments — not just the files
touched. Dated design-history notes (STAGE*-DESIGN.md, BACKLOG dated
entries, memory snapshots) are exempt: they record what WAS true.
Extends [[p8x-docs-before-sync]] and [[p8x-disk-docs-current]].
