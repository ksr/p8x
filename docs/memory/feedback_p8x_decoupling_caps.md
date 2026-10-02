---
name: feedback_p8x_decoupling_caps
description: P8X — every new card must get per-IC 100nF decoupling caps
metadata: 
  node_type: memory
  type: feedback
  originSessionId: df90e3f3-8668-416d-bc7b-83f2952ba723
  modified: 2026-09-18T00:08:28.450Z
---

When adding any new P8X card, include per-IC 100nF decoupling capacitors (one
`CAP`/`100N`, through-hole `C_DISC` footprint, across VCC<->GND, placed next to
each IC) — card standards sec.5 requires them.

**Why:** they were missing on the cards once before (only the backplane had
them) and it was a pre-fab blocker; the user explicitly asked not to forget
them on new cards.

**How to apply:** plug-in cards built through `gen_eagle.py`'s `card()` get the
caps automatically (it generates a `CDn` cap per IC). Cards with a *separate*
build (like the memory card) must add them by hand — copy the `MCIC` loop that
appends `CDn` to the parts dicts and wires each to VCC/GND. P8X is all
through-hole, no SMD. See [[project_p8x]].

**Placement convention (2026-09-17, user, for ALL boards):** put each bypass cap
directly ABOVE its IC, horizontal / parallel to the chip's top edge, hugging it —
not parked in a shared lane. Done in the KiCad memory card
(`hardware/memory-card/kicad/gen_mem.py`: `CAPFOR` map, cap placed at the chip's
top pad-row minus ~4.5mm). For the Eagle boards this is a hand-layout guideline
(their `.brd` parks parts; real placement is manual in Fusion).
