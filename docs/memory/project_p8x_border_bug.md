---
name: p8x-border-bug-open
description: "RESOLVED — p8x border-edge bug was marginal capture on gapless CAS; stream now half-rate; lesson: snow = analogue, sim-exact + panel-wrong = electrical"
metadata: 
  node_type: memory
  type: project
  originSessionId: eb839e7b-2183-47af-84cd-a059555f72b5
  modified: 2026-08-19T17:56:47.213Z
---

RESOLVED 2026-08-19 (commit 985d896): the splash border's missing-left/
doubled-right edges were marginal electrical capture on fully gapless CAS
streams — first burst word lost at bus turn-on, last word mangled at drain,
mid-burst bit flips visible as SNOW in drawn lines. Fixed by half-rate stream
issue (every other cycle) in p8x_sdram.v; verified on the panel; flashed.
Full story in fpga/tang-nano-20k/sdram/HANDOFF.md "RESOLVED" section.

Durable lessons (also in the HANDOFF traps list):
- The chip model cannot see electrical margin: sim-exact + panel-wrong means
  analogue, and temporal noise (snow) is the discriminator — logic bugs are
  deterministic, sparkle is not.
- Pasted images never reach the filesystem; have the user save to ~/Desktop.
- The board's serial-open reset is UNRELIABLE (sometimes fires, sometimes
  not) — never assume a fresh boot from a connect.

Related: [[p8x-project]] [[p8x-fpga-plan]]
