---
name: p8x-gfx-clib
description: "SHIPPED 2026-08-19 (c29993f): C graphics veneer lib_gfx.c + wireframe-3D lib_g3d.c + cube demo; key facts for future graphics/C work"
metadata: 
  node_type: memory
  type: project
  originSessionId: eb839e7b-2183-47af-84cd-a059555f72b5
  modified: 2026-08-19T20:58:36.178Z
---

SHIPPED 2026-08-19, commit c29993f (branch sdram-framebuffer): os/commands/
lib_gfx.c (//#use gfx -- peek/poke veneer: gpresent/grgb/gcolor/gcls/gplot/
gline/gbox(f)/gcircle(f)/gellipse(f)/gpoint), lib_g3d.c (//#use g3d --
STAGE7 wireframe pipeline), cube demo command, lib_gfx.inc equate twin,
emulator/test/c_g3d_test.sh. Design + measured budget:
fpga/tang-nano-20k/sdram/STAGE7-DESIGN.md.

Durable facts learned:
- p8cc.c (native self-host subset) has NO array brace-initializers --
  p8cc.py and the on-target cc do. C-only-command precedent: disasm.
  Libraries must stay native-parity clean (c_g3d_test part 3 enforces).
- muldiv fast path: when a*b fits 16 bits (test: a <= 65535/b), native */
  beat the all-C 32-bit loops ~10x (118k -> 10k cycles). p8cc statements
  cost ~500 cycles each through __ax; loops are brutal, builtins cheap.
- Display coordinate regs are UNSIGNED (zero-extended) -- negative coords
  land at ~65535, not off the left edge; software must clip first.
- cube: 13.9 fps (1.94M cycles/frame); ~130k cycles/edge; erase ~free.
- os/mandrill.p8i is now a TRACKED asset installed by run.sh (was only
  inside run-disk.img and a rebuild would have lost it).

Next rungs (open): asm muldiv / lib_g3d twin, stage-8 fabric geometry
engine (DSP multipliers, model in SDRAM), page-flip double buffer
(deferred by user), `image X Y FILE` OS command (second lib_gfx client).

Related: [[p8x-project]] [[p8x-cc-caps]] [[p8x-new-command-dual]]
