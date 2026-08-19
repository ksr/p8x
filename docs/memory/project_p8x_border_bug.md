---
name: p8x-border-bug-open
description: "OPEN p8x bug — splash border edges wrong on panel only, sim exact; awaiting user's zoomed edge photos; splash build is in flash"
metadata: 
  node_type: memory
  type: project
  originSessionId: eb839e7b-2183-47af-84cd-a059555f72b5
  modified: 2026-08-19T15:31:30.064Z
---

As of 2026-08-19 evening, one bug is open on the p8x `sdram-framebuffer`
branch: the monitor boot splash's 1-px white border shows NO left line and a
DOUBLED right line on the physical panel, while `tb_full_stack.v` proves all
272 displayed rows pixel-exact in simulation — so the mechanism is at/past
the pins. Full detail, candidate mechanisms and their distinguishing
predictions are in `fpga/tang-nano-20k/sdram/HANDOFF.md` ("OPEN BUG"
section), committed at 6bc0cb6.

Next step agreed with the user: they photograph the panel's left and right
edge regions zoomed (phone camera resolves pixel columns), paste them AND
save to ~/Desktop (pasted images never reach the filesystem — found that out
twice; Desktop worked for the mandrill). The exact white/black column
positions pick the mechanism.

Board state: the splash build (CLS pair-step fix + lock-gated reset + fresh
monitor ROM) is IN FLASH — a bare power-cycle brings the test pattern up
with no host. The SD card holds the RGB() BASIC + /MANDRILL.P8I. Serial:
port-open usually (not always) resets the machine; one session per scripted
interaction; the board tools live in the session scratchpad pattern —
rebuild `board.py` from HANDOFF's notes if the scratchpad is gone.

Related: [[p8x-project]] [[p8x-fpga-plan]]
