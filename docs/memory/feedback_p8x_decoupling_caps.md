---
name: feedback_p8x_decoupling_caps
description: P8X — every new card must get per-IC 100nF decoupling caps
metadata: 
  node_type: memory
  type: feedback
  originSessionId: df90e3f3-8668-416d-bc7b-83f2952ba723
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
