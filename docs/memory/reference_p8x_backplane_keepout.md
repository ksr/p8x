---
name: reference_p8x_backplane_keepout
description: Backplane routed PASS = 8 slots + 0.13mm clearance + nylon screws (2mm keepout); plug-in cards keep 4mm metal-screw keepout
metadata: 
  node_type: memory
  type: reference
  originSessionId: 6ffcfef7-73ca-445b-bcdb-f57735fdc98f
  modified: 2026-09-19T01:47:55.473Z
---

**Backplane routed & PASS (2026-09-18): 8 slots, 0.13mm clearance, nylon screws,
262x128mm.** Getting the dense parallel bus to route took three changes in order of
impact: (1) **0.13mm netclass clearance = THE lever** (0.2mm left 11-18 hops
unrouted, 0.15mm -> 1-2, 0.13mm -> 0); set in gen_backplane, ships in the
`.kicad_pro` (keep it committed, DRC/fab read it there). (2) **8 slots not 10**
(`NSLOT` in gen_eagle) -- minor help; slot count is NOT the routing lever (every
inter-slot channel carries all ~96 nets regardless of count). (3) the 2mm nylon
keepout below. Bus track stays 0.2mm; only spacing tightens. Reruns are stochastic
near the edge -- keep 0.13mm for a deterministic 0.

The **backplane** (hardware/backplane) uses **nylon screws (or none)** at the DIN
socket mounting holes, so its copper keepout is only **2.0mm** (clears the 2.85mm
NPTH hole + 0.57mm margin) — set in `gen_backplane.py` `SCREW_KEEPOUT_R`. The
original 4.0mm metal-screw ring at each hole carved the bus channels; dropping to
2.0mm freed ~75% of the ring area.

The **plug-in cards keep the 4.0mm metal-screw keepout** (`gen_kicad.py`
SCREW_KEEPOUT_R = 4.0) — the earlier hard rule ("no copper near DIN screw holes,
metal screws") still holds for them. Only the backplane was relaxed, at the user's
call (2026-09-18), because its bus is far too dense for 4mm rings.

`check_card.sh` mirrors this: keepout radius is per-card (backplane 2.0mm, else
4.0mm). See [[reference_p8x_kicad_pipeline]] for the heal/route pipeline.
