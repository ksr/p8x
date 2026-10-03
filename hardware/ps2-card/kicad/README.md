# ps2-card -- KiCad

Built by the bespoke `gen_ps2.py` (placement: the two mini-DIN-6 sockets on the
bottom edge, the four status LEDs on the right, the bus connector on the left) from
the canonical gen_eagle netlist (`CARDS["ps2-card"]`: an ATmega1284P behind a
74HCT374/74HCT244 latch bridge), to the same standard as the memory card: 4-layer
(F/B signals, In1=GND, In2=VCC planes), a bypass cap above each IC, part values on
silk. Routed with Freerouting. GENERATORS ARE CANON -- edit `gen_ps2.py` (or the
netlist in `gen_eagle.py`) and re-run `build.sh` here (or `generators/build.sh
ps2-card`).

| File | What |
|------|------|
| `p8x-ps2-card.kicad_pcb` | the board |
| `p8x-ps2-card.ses` | the Freerouting routing |
| `p8x-ps2-card-gerbers.zip` | orderable gerbers |
| `p8x-ps2-card-placement.pdf` | parts placement (refs+values) |
| `p8x-ps2-card-render-top.png` / `-3d.png` | renders |

Exotic parts use the closest standard KiCad footprint (flagged when built).
