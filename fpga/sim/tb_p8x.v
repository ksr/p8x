// tb_p8x.v -- Milestone-1 co-sim testbench.
//
// Runs the P8X RTL for N cycles and (with -DP8X_TRACE) emits one canonical
// state line per cycle on stdout, in the SAME format as `p8xemu -T`. Diff the
// two traces to prove the RTL matches the golden emulator model.
//
//   +cycles=N   number of cycles to run (default 200000)
//
// Note: reads ucode.hex and eeprom.hex from the current directory (run.sh puts
// them there before invoking the sim).

`timescale 1ns/1ps
module tb_p8x;
  reg clk = 0;
  reg rst = 1;
  wire halted;

  p8x_soc SOC(.clk(clk), .rst(rst), .halted(halted));

  always #5 clk = ~clk;   // 100 MHz; functional sim only, frequency irrelevant

  integer ncyc;
  initial begin
    if (!$value$plusargs("cycles=%d", ncyc)) ncyc = 200000;
    // hold reset across two edges, then release
    @(posedge clk); @(posedge clk); rst = 0;
    // run until cycle budget or HALT
    while (ncyc > 0 && !halted) begin @(posedge clk); ncyc = ncyc - 1; end
    $finish;
  end
endmodule
