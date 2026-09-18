#!/bin/sh
# run.sh -- gate-level netlist simulation for the P8X boards.
#   tools/gatesim/run.sh                 # memory-card address-decode check
#   tools/gatesim/run.sh <card>          # emit that card's structural Verilog to stdout
#
# Translates a gen_eagle card netlist to structural Verilog (netlist2v.py),
# wires up the prims.v 74-series models, and runs the matching testbench under
# iverilog -- proving the AS-DRAWN logic computes what the design expects.
# Needs iverilog (same tool as fpga/sim). GENERATORS ARE CANON.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
card="${1:-memory-card}"
DUT="/tmp/p8x_gatesim_${card}.v"
python3 "$HERE/netlist2v.py" "$card" > "$DUT"

case "$card" in
  memory-card)
    echo "== gate-level sim: memory-card address decode =="
    iverilog -g2012 -o "/tmp/p8x_gatesim_${card}" \
        "$HERE/prims.v" "$DUT" "$HERE/tb_memdecode.v"
    vvp "/tmp/p8x_gatesim_${card}" 2>/dev/null | grep -v '\$finish'
    ;;
  *)
    echo "No testbench yet for '$card'. Its structural Verilog is at: $DUT"
    echo "(add a tb_*.v that instantiates the '$(echo $card | tr - n)' module and probe its nets.)"
    ;;
esac
