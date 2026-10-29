---
name: reference_p8x_footprint_subs
description: P8X board PASS does not validate substituted footprints — check geometry + pin order of every SUB; schematic ERC single-pin labels can expose real netlist gaps
metadata:
  node_type: memory
  type: reference
  originSessionId: 6ffcfef7-73ca-445b-bcdb-f57735fdc98f
  modified: 2026-10-24T09:51:48.649Z
---

`check_card.sh` prints "SUBSTITUTIONS" (gen_kicad.py FPMAP/DEV_FP entries with a
note) but still says PASS. A substitute can route clean and be unbuildable:

- 2026-10-24: bustest Pico (PICO40) was `PinHeader_2x20_P2.54mm` — rows 2.54 mm
  apart, odd/even numbering; real Pico = rows 17.78 mm, pins 1-20 down / 21-40 up.
  Fixed to `Module:RaspberryPi_Pico_Common_THT` (d028f8c). Only GND 3/33 were
  netted; all 8 now are (GND8..GND38 pin names).
- io-card CR2032 (COIN) was Keystone 3000 = 12 mm SMD holder; now Keystone 103
  THT 20 mm, pinned bottom-right in gen_io.py (bigger body collided with DB9A).
- Open (BACKLOG VERIFY): io RNISO8 1x16 SIP vs the DIP-16 isolated-net rule,
  LEDARR8 8-seg DIP-16 bargraph, custom MiniDIN-6.

**How to apply:** for any new/changed SUB, compare footprint pad positions and
numbering against the real part's pinout (pcbnew pad dump) — not just "it routes".
Also: schematic ERC "label connected to only one pin" found a real netlist bug
(bustest `-IRQ` vs bus `IRQ`, SPARE excluded from used_bus — fbcb24a); treat
those warnings as leads, not noise. Related: [[reference_p8x_kicad_pipeline]].
