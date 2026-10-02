---
name: project_p8x_kicad_cad
description: "KiCad is the go-forward PCB flow for P8X; Eagle frozen at rev E, likely dropped once KiCad boards are proven"
metadata: 
  node_type: memory
  type: project
  originSessionId: 6ffcfef7-73ca-445b-bcdb-f57735fdc98f
  modified: 2026-09-18T12:49:36.789Z
---

As of 2026-09-17 the user is moving P8X PCB CAD from Eagle to **KiCad 10**. The
KiCad boards live in `hardware/<board>/kicad/` with their own Python generators
(not `gen_eagle.py`): the **xor-trial** board and the **memory card** (rev F, 6K
decode, 4-layer with internal GND/VCC planes, Freerouting-autorouted to orderable
gerbers) are done this way.

**Direction (user, 2026-09-17):** do NOT bring `generators/gen_eagle.py` to rev F.
Leave the Eagle work as-is (rev E); the user is not using Eagle for now and will
"quite possibly drop Eagle once these boards are proven" on hardware. So: don't
touch the Eagle generator or the Eagle `.sch`/`.brd` unless asked; build new/
reworked boards through the KiCad flow.

**KiCad memory-card flow** (all in `hardware/memory-card/kicad/`, generators are
canon): `gen_mem.py` (rev-F netlist imported from gen_eagle's `CARDS` + placement
+ planes) -> `export_dsn.py` (marks In1/In2 as power planes) -> Freerouting 1.9.0
(`-mp 30 -oit 100`) -> `import_ses.py` (imports routing, re-fills planes, and
calls `gen_placement.py` for the centred B/W placement PDF). See its README for
the Freerouting gotchas. Related: [[feedback_ecad_schematic_truth]] (the older
Eagle/Fusion workflow), [[feedback_p8x_decoupling_caps]] (cap-above-chip
convention), [[project_p8x]].

**Combined I/O + CF-IDE + PS/2 card (user, 2026-09-18):** the user is merging the io-card + cf-card AND the (design-only) PS/2 interface onto ONE card. Share the common front-end decode (one $FFxx 7430 page detector + one DOE→-RD + one DLD→-MEMW 74138 feed all three sections) to drop ~6 duplicate chips. **PS/2 uses NO level shift — it is 5V-native TTL** (theory doc §5); the NOYITO TXS0102 breakout is ONLY for the FPGA/Tang-Nano-20K 3.3V path, NOT the TTL backplane card (corrected 2026-09-18 — an earlier note wrongly put TXS0102 on the standalone TTL card). Addresses are unchanged so NO software changes ($FF00-09 I/O, $FF10-17 CF, $FF58-5F PS/2). **PS/2 topology PIVOT (user, 2026-09-18):** drop the discrete 18-chip receiver; use an **ATmega328P (Arduino chip, DIP-28)** to handle both PS/2 ports in firmware, bridged to the bus by a thin **latch bridge** (~4x 74HC574 for PSADAT/PSAST/PSBDAT/PSBST + 74HC244 for PSLINE/PSID, gated by the shared decode) since an MCU can't meet raw bus-read timing. Register model $FF58-5F stays byte-identical (no P8X software change); NEW deliverable = an Arduino/AVR firmware sketch. **Naming/fate (user, 2026-09-18): the combined board is `peripheral-card`; once proven, DEPRECATE io-card + cf-card + ps2-card (git mv to hardware/deprecated) AND merge their three theory-of-operation docs into ONE new peripheral-card theory doc.** Build in stages: (1) merge io+cf w/ shared decode, (2) add the '328 PS/2 latch-bridge, (3) firmware. Uniform KiCad card size is 280x140mm but this combined card (~30+ ICs) will likely need to grow.

**peripheral-card connector/placement rules (user, 2026-09-18):** ALL external connectors on the BOTTOM long (280mm) edge (bus DIN stays on the left short edge). External connectors: 2x PS/2 mini-DIN-6 FEMALE (kbd+mouse), 2x DB9 FEMALE serial. The CF-IDE 40-pin header sits near the RIGHT edge and mates with a SinLoon CF-to-IDE adapter module (Amazon B07Y2MSLC9) that holds the CF card — reserve room + keepout for the adapter body there (exception to bottom-edge rule). **Serial = TWO channels:** add a 2nd 6850 (ACIA2 $FF08/09; the existing io-card only builds ACIA1 $FF04/05). ONE MAX232 drives both (T1/R1 + T2/R2 channels). Per DB9, a **2x3 jumper block** swaps RX/TX: left shunts = STRAIGHT (P8X TX->DB9 pin3, RX->pin2), right shunts = NULL modem (TX->pin2, RX->pin3). Needs NEW footprints: DB9 female, mini-DIN-6 female, and the CF-adapter clearance. This card needs BESPOKE placement (hand-placed connector row), not gen_kicad auto-flow. No software change (all addresses already in the memory map). regbank + bustest were placed-not-routed historically (now routed).
