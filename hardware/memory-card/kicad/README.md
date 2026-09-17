# Memory Card — KiCad (rev F, 4-layer)

The P8X **memory card** realised as an orderable **KiCad 10** PCB. This is the
first P8X *logic* card taken through KiCad (the XOR trial board was the first
KiCad board overall; the rest of the machine uses the Eagle flow in
`generators/gen_eagle.py`). Generators are canon here too — edit the scripts and
re-run, don't hand-edit the `.kicad_pcb`.

**200 × 100 mm, 4-layer.** The height is the Eurocard/DIN41612 standard (fixed by
the backplane); the width was widened from the usual 160 mm for routing headroom
(the card is cantilevered off the connector — see the theory doc). Stackup:

| Layer | Use |
|-------|-----|
| **F.Cu** | signals |
| **In1.Cu** | **GND plane** |
| **In2.Cu** | **VCC plane** |
| **B.Cu** | signals |

Every IC/decap GND & VCC pin bonds straight to its plane (solid connection), so
the autorouter only had to place the ~158 signal nets on the two outer layers.

## rev F — the 6 KB ROM decode (this board is buildable)

The Eagle CAD still carries the **rev E 8 KB** ROM decode (`$0000–$1FFF`), which
maps `$1800–$1FFF` to the unwritable ROM chip — a build blocker once the OS
touches its scratch there (see [`../p8x-memory-card-theory.md`](../p8x-memory-card-theory.md)
⚠ note). This KiCad board implements the corrected **rev F 6 KB decode**
(`ROM = $0000–$17FF`, `$1800–$1FFF` is RAM), matching the emulator/OS. It adds
**no new chips** — `gen_mem.py` rewires three spare gates on the imported netlist:

| Signal | Gate | Function |
|--------|------|----------|
| `P` | U9.4 (spare '08 AND) | `A11 · A12` |
| `ROM !CE` | U11.2 (spare '32 OR) | `OR(A13\|A14\|A15, P)` → ROM answers only `$0000–$17FF` |
| `S` | U11.3 (spare '32 OR) | `OR(A13\|A14, P)` |
| `-RAM2CE` | U7.3 (existing) | `NAND(!A15, S)` → U10 low-RAM widens to `$1800–$7FFF` |

The functional netlist itself is the canonical one from
`generators/gen_eagle.py` (`CARDS["memory-card"]`, built by the shared `card()`
helper — connector, decaps, IC power pins, J1 bus wiring); `gen_mem.py` imports
it and applies the rev-F transform, asserting the gate usage is consistent.

## Files

| File | What it is |
|------|-----------|
| `gen_mem.py` | the board generator (pcbnew): rev-F netlist, footprints, placement, GND/VCC planes, outline |
| `export_dsn.py` | export a Specctra `.dsn` for Freerouting (marks In1/In2 as **power** planes) |
| `p8x-memory-card.ses` | **the routing** — Freerouting's session file (the canonical routing artifact, like an Eagle `.brd`'s copper) |
| `import_ses.py` | import the `.ses` back, re-fill the planes, save |
| `p8x-memory-card.kicad_pcb` | the finished routed board |
| `p8x-memory-card-gerbers.zip` | **the orderable output** — 4-layer Gerbers + Excellon drill |

## Regenerate / re-route

Placement + planes (KiCad's bundled python has `pcbnew`):

```sh
PYK=/Applications/KiCad/KiCad.app/Contents/Frameworks/Python.framework/Versions/3.9/bin/python3
"$PYK" gen_mem.py
```

Re-import the committed routing and export gerbers (no re-route needed):

```sh
"$PYK" import_ses.py
CLI=/Applications/KiCad/KiCad.app/Contents/MacOS/kicad-cli
"$CLI" pcb drc  p8x-memory-card.kicad_pcb                 # 0 violations, 0 unconnected
"$CLI" pcb export gerbers --no-protel-ext -o gerbers/ p8x-memory-card.kicad_pcb
"$CLI" pcb export drill --format excellon --excellon-units mm -o gerbers/ p8x-memory-card.kicad_pcb
( cd gerbers && zip ../p8x-memory-card-gerbers.zip *.gbr *.gbrjob *.drl )
```

To route from scratch (Freerouting 1.9.0, needs Java 17+ and a display):

```sh
"$PYK" export_dsn.py
java -jar freerouting-1.9.0.jar -de p8x-memory-card.dsn -do p8x-memory-card.ses -mp 30 -oit 100
"$PYK" import_ses.py
```

## Freerouting gotchas (learned the hard way)

- **Mark the inner layers `power`.** KiCad exports every DSN layer as
  `(type signal)`, so Freerouting will happily route signals *on the GND/VCC
  planes*, shredding them. `export_dsn.py` rewrites In1/In2 to `(type power)`;
  then Freerouting routes only F/B and leaves the planes alone.
- **`-oit 100` to skip the crashing optimizer.** With the planes present,
  Freerouting's later route-optimization passes abort with
  `NetIncompletes: too many items` and never save the `.ses`. A high
  optimization-improvement threshold stops optimization after the first pass —
  the route is already complete by then.
- **Tight plane clearance (0.2 mm) + thin min-thickness (0.13 mm).** At the
  default clearance the GND pour can't thread into tight pad pockets and leaves
  a dozen isolated slivers (DRC "unconnected"). Tightening it lets the plane
  reach every GND pad — 0 unconnected.

## Order it

Upload **`p8x-memory-card-gerbers.zip`** to any fab that does 4-layer (JLCPCB /
PCBWay). Defaults: 4-layer, 1.6 mm FR4, HASL. Stuff it with the BOM in the
[parent README](../README.md) / the theory doc's part list. The board passes DRC
clean (0 violations, 0 unconnected).
