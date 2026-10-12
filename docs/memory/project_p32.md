---
name: project-p32
description: "P32 = new project started 2026-10-11 at ~/Developer/p32 (git, main, private remote github.com/ksr/p32); 32-bit TTL successor to P8X (working name P32X); brief at ~/Desktop/HANDOFF-P32.md"
metadata:
  node_type: memory
  type: project
  originSessionId: 825b84fa-8fa8-482f-a039-a0ded3976c4a
  modified: 2026-10-11T09:55:44.138Z
---

P32 is a new project Ken started on 2026-10-11. Repo: ~/Developer/p32 (git on main, initial commit d6c71c0, private remote github.com/ksr/p32). Scope: 32-bit discrete-74-series TTL CPU, successor to P8X (working name P32X), reusing P8X toolchain/conventions/card-backplane. Brief: docs/HANDOFF-P32.md in the repo (original on ~/Desktop) (written 2026-07-07, predates P8X's KiCad switch — says Eagle; check against current P8X before following). Open decisions: datapath 32 vs 16-bit two-cycle, register file SRAM vs latches, 24/32-bit addressing, custom ISA vs RV32I, microword width, bus/backplane, flag polarity, clock. First step per brief: architecture options memo (decisions 1-4, chip counts), then stop for Ken.

**Why:** "P32 Development" had no prior trace anywhere; avoid re-searching.
**How to apply:** Work in ~/Developer/p32; update this note once scope is decided. In the "all 5" sync set (global CLAUDE.md) since 2026-10-11. Related: [[project-p8x]].
