---
name: p8x-bin-layout-asm-default
description: "Since 2026-08-20: /bin = hand-asm builds (the PATH default), /binc = p8cc C builds; /bina retired; C-only commands ship C in /bin"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: eb839e7b-2183-47af-84cd-a059555f72b5
  modified: 2026-08-20T14:33:23.903Z
---

User decision 2026-08-20 (commit 40252a6): the hand-assembled command builds
are THE DEFAULT in /bin (what the shell's PATH finds); the p8cc-compiled
builds ship at /binc for on-target comparison and the cc rebuild flow (the
on-target C Makefile's `install` publishes to /binc). /bina no longer
exists. A command with no asm twin (currently only cube) ships its C build
in /bin.

**Why:** asm twins are uniformly smaller (~2-5x) and faster (image: 563 vs
4,435 cycles/pixel — the twin even beats BASIC's own loader).

**How to apply:** a NEW command should ship its asm twin into /bin and its
C build into /binc (run.sh `_mkcmds` + both install loops); a C-only
command goes in `_ccmds` and its C build lands in /bin until a twin
exists. The differential test pattern (c_image_test: same sequence on
both builds, byte-identical framebuffer AND output files) is the
verification bar for twins. Toolchain apps (asm/cc/edit/basic) are
asm-only by nature and unaffected.

Related: [[p8x-new-command-dual]] [[p8x-project]]
