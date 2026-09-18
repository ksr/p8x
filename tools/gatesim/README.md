# Gate-level netlist simulation

Validate the **as-drawn board logic** — not the emulator's behavioural model, not
the FPGA RTL, but the actual `gen_eagle` card netlists — by simulating them under
iverilog. This catches a mis-wired decode gate or a swapped input that ERC and
the emulator both miss, *before* it is etched into copper.

```sh
tools/gatesim/run.sh              # memory-card address-decode check
tools/gatesim/run.sh io-card      # emit io-card structural Verilog (no TB yet)
```

## How it works
1. **`netlist2v.py`** translates a `gen_eagle` `CARDS[...]` netlist into a
   *structural* Verilog module — one primitive instance per IC, wired net-for-net
   exactly as the board is drawn. Bus signals (nets reaching the J1 edge
   connector) become module inputs; every other net is an internal wire a
   testbench can probe by hierarchical name (`dut.ROM8CE`).
2. **`prims.v`** holds behavioural models of the 74-series parts (7430, 74138,
   the quad-gate GATES14 bodies picked by value, hex inverters, …). They are
   LOGIC models, not timing/analog.
3. A **testbench** drives the inputs and checks the outputs. `tb_memdecode.v`
   sweeps all 64K addresses and asserts the memory decode is *exclusive* (no
   address selects two chips → no bus contention) and that ROM covers exactly
   `$0000-$1FFF`.

## Coverage & honesty
- Parts without a logic primitive (RAM/ROM arrays, bus buffers, the ACIA, the
  ATmega, connectors, passives) are **skipped** and reported to stderr — they are
  loads, not decode drivers. Modelling them (e.g. a RAM array, the 6850 register
  file) is how you'd extend a card's coverage from decode to full function.
- The memory card's `gen_eagle` netlist is the **rev-E** 8 KB decode; the rev-F
  6 KB transform lives in `hardware/memory-card/kicad/gen_mem.py`. A rev-F TB
  would import that transformed netlist.

## Extending to another card
1. Add any missing 74-series models to `prims.v` (sanitised pin names: `!X`→`nX`,
   `-X`→`nX`, leading digit→`P` prefix — same rule as `netlist2v.san`).
2. Write `tb_<thing>.v` instantiating the generated `<card>` module (note `-` in
   the card name becomes `n`, e.g. `memory-card` → module `memoryncard`), drive
   the bus, and assert on the probed nets.
3. Add a case to `run.sh`.

The end goal is a full structural model of the machine co-simulated against the
emulator (the golden model), the same way `fpga/sim` diffs the RTL — this is the
foundation for it.
