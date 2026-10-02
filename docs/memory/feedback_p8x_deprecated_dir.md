---
name: feedback_p8x_deprecated_dir
description: "hardware/deprecated/ is a graveyard — never edit, regenerate, place, or design anything inside it"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 6ffcfef7-73ca-445b-bcdb-f57735fdc98f
  modified: 2026-09-18T11:52:28.301Z
---

`hardware/deprecated/` holds retired boards (first tenant: the LED test card,
moved there 2026-09-18 — a CAD-workflow trial, never built, decoded $FF0C).

**Rule (user, 2026-09-18):** going forward do NOT do any updates, placement,
design, renders, or regeneration inside `hardware/deprecated/`. Treat it as a
frozen graveyard. The user may delete these boards entirely later.

**How to apply:** when a board is deprecated, `git mv` its tree into
`hardware/deprecated/` and stop there — no deprecation banners in its own docs,
no KiCad/Eagle rebuilds into it. Make the generators SKIP emitting files for it
(e.g. gen_eagle's led-card passes `emit_files=False`) rather than redirecting
output into the deprecated dir, so a regen writes nothing there. Update the
memory map + cross-references OUTSIDE the deprecated dir instead. Related:
[[project_p8x_kicad_cad]], [[reference_p8x_memory_map]], [[reference_p8x_memmap_singlesource]].
