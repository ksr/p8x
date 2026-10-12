// elk_layout.js -- lay out one schematic sheet with ELK (Eclipse Layout Kernel).
// Reads an ELK JSON graph on stdin (built by p32kicad_wire.py), runs the layered
// algorithm with orthogonal edge routing and fixed port positions, and writes the
// laid-out graph (node positions, edge bend points) on stdout.
//     node generators/elk_layout.js < graph.json > layout.json
const ELK = require("elkjs");
let input = "";
process.stdin.on("data", (d) => (input += d));
process.stdin.on("end", async () => {
  const graph = JSON.parse(input);
  graph.layoutOptions = Object.assign({
    "elk.algorithm": "layered",
    "elk.direction": "RIGHT",
    "elk.edgeRouting": "ORTHOGONAL",
    "elk.layered.mergeEdges": "true",                 // one wire trunk per net
    "elk.portConstraints": "FIXED_POS",
    "elk.spacing.nodeNode": "6",
    "elk.layered.spacing.nodeNodeBetweenLayers": "8",
    "elk.spacing.edgeEdge": "2",
    "elk.layered.spacing.edgeEdgeBetweenLayers": "2",
    "elk.spacing.edgeNode": "2",
    "elk.layered.nodePlacement.strategy": "NETWORK_SIMPLEX",
    "elk.layered.crossingMinimization.strategy": "LAYER_SWEEP",
    "elk.layered.considerModelOrder.strategy": "NODES_AND_EDGES",  // keep the netlist's part order
    "elk.layered.crossingMinimization.forceNodeModelOrder": "true",
  }, graph.layoutOptions || {});
  try {
    const out = await new ELK().layout(graph);
    process.stdout.write(JSON.stringify(out));
  } catch (e) {
    process.stderr.write("elk_layout: " + e + "\n");
    process.exit(1);
  }
});
