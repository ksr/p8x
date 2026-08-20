---
name: p8x-gfx-clib
description: "SHIPPED 2026-08-19 (c29993f): C graphics veneer lib_gfx.c + wireframe-3D lib_g3d.c + cube demo; key facts for future graphics/C work"
metadata: 
  node_type: memory
  type: project
  originSessionId: eb839e7b-2183-47af-84cd-a059555f72b5
  modified: 2026-08-19T22:23:48.250Z
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

STAGE 8a SHIPPED same day (f781547): the MDU — hardware muldiv at $FF30,
bit-exact to the lib_g3d contract, in BOTH build flavours; regs in
gen_memmap (MDA..MDQH, MDID probe reads 'M'/77); emulator instant-model;
lib_g3d probes (m3has) and falls back; tb_mdu.v 2022 vectors; 7964 LUT4
38%, flashed + verified on silicon (PEEK(65334)=77, cube corners).
muldiv ~4k cycles (poke-bound), cube 19.6 fps.

**NEXT (user: "we can come back to 8b")**: stage 8b fabric geometry
engine — walker FSM around the MDU datapath, edge list in SDRAM via a
streaming upload port, matrix regs, one render command; SDRAM gains a 4th
client (priority scanout > refresh > geometry > pixels — the arbitration
is where the hard bugs live); page-flip double buffer rides along. Sketch
at the end of fpga/tang-nano-20k/sdram/STAGE8-DESIGN.md; needs its own
full design doc first.

Also open: asm muldiv/lib_g3d twin (smaller rung, partly obsoleted by the
MDU), `image X Y FILE` OS command (second lib_gfx client).

Related: [[p8x-project]] [[p8x-cc-caps]] [[p8x-new-command-dual]]
