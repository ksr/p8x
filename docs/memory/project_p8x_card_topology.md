---
name: project_p8x_card_topology
description: "Peripheral card REVERTED to three separate cards (io/cf/ps2); peripheral parked, ps2 built standalone"
metadata: 
  node_type: memory
  type: project
  originSessionId: 6ffcfef7-73ca-445b-bcdb-f57735fdc98f
  modified: 2026-09-19T18:06:42.479Z
---

**2026-09-19: reverted the io+cf+ps2 combination back to three separate cards**
(user: "too quick to combine ... go back to three separate cards, put the
peripheral card aside").

- **io-card rev B (2026-09-19)** — serial upgrades + edge treatment: 2nd ACIA (U17)
  at $FF08 on MAX232 chan 2 (one MAX232 both channels), two DB9 sockets with RX/TX
  swap jumpers (JP1/JP2, straight/null-modem), U18 HEX inverter for ACIA2's E-gate.
  Bespoke gen_io.py: DB9s/switch/RTC-header bottom edge, LED bars top, jumpers flow
  INTERIOR (crowding them by the big edge-mount DB9s made the DB9 TX/RX unroutable).
  PASS. RTC/coin-cell stays DNP (3-wire on J3, not mapped).
- **cf-card rev B (2026-09-19)** — TWO 8-bit True IDE drives (project rejected
  master/slave as unreliable for CF): drive 0 $FF10-17 (J2, command-only), drive 1
  $FF18-1F on new header J5, each with own 74245 buffer + strobe glue (U10/U11 +
  freed U8/U5 gates) + pull-ups (RN1/RN3) + activity LED. Bespoke gen_cf.py: the two
  IDE-40 headers 71mm apart (adapters ~43x50mm each). PASS. **DRIVE 1 NEEDS SOFTWARE:
  the firmware CF driver uses fixed $FF10-17 throughout, so drive 1 needs a drive-
  selectable port base in CFSETL/CFINIT + the emulator's port decode -- data-
  integrity-critical, do it test-validated. DRIVE 0 works unchanged.** See
  gen_memmap CFDATA..CFCMD ($FF10-17); OS dual-volume (/d1) already done+tested.
- **ps2-card** — was a docs-only stub; now BUILT standalone (rev A, PASS) via the
  generic gen_kicad flow. Uses the **ATmega328 latch-bridge** design (the approved
  one the peripheral used — NOT the older pure-TTL proposal still in §3-6 of the
  theory doc). Window `$FF58-5F` (already in gen_memmap). Its front-end decode is
  LOCAL now (7430 page + 2x74138 DOE/DLD), which the peripheral had shared. 5V
  native, NO level shift (TXS0102 is only the FPGA path). See
  [[reference_p8x_kicad_pipeline]].
- **peripheral-card** — PARKED, not deprecated: moved to
  `hardware/parked/peripheral-card/` (git mv); its netlist kept intact in
  gen_eagle behind `PARK_PERIPHERAL=True` (flip to False + restore the mv to
  un-park). Removed from build.sh dispatcher + ALL list; not in CARDS. Its extras
  — a **2nd ACIA at $FF08** and **two DB9s with RX/TX-swap jumpers** — park WITH it
  (they were never on the standalone io-card). If those serial upgrades are wanted
  later, port them onto io-card or un-park.

All 8 plug-in cards (alu, bustest, cf, control, io, memory, ps2, regbank) PASS;
backplane PASS. See [[reference_p8x_backplane_keepout]] for the backplane.
