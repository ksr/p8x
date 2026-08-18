// sdram_model.v -- a behavioural stand-in for the SDRAM controller, for
// SIMULATION ONLY. Never synthesised; the board builds sdram.v instead.
//
// Its job is to be a drop-in at sdram.v's interface so the co-sim can run the
// whole graphics device without an SDRAM to talk to. What matters is that it
// reproduces the two timing behaviours that cause real bugs, because a friendlier
// model would let a broken design pass here and fail on hardware:
//
//   1. `busy` does not rise until the cycle AFTER a command pulse is seen.
//   2. on a read, `busy` drops in the SAME cycle `data_ready` rises.
//
// Both have already cost debugging rounds on this branch -- (1) as exactly half
// of memory reading back wrong, (2) as a deadlock waiting for an answer that had
// already arrived. Anything that talks to this model and works will talk to the
// controller and work.
//
// wr_word writes all four byte lanes, matching the local modification to the
// controller (see fpga/tang-nano-20k/sdram/sdram.v).
module sdram_model #(parameter FREQ = 27_000_000, parameter LAT = 4)(
    input             clk,
    input             clk_sdram,
    input             resetn,
    input      [22:0] addr,
    input             rd,
    input             wr,
    input             wr_word,
    input             refresh,
    input       [7:0] din,
    output reg  [7:0] dout,
    output reg [31:0] dout32,
    output reg        data_ready,
    output reg        busy
);
  localparam BYTES = 262144;                 // enough for either framebuffer
  reg [7:0] mem [0:BYTES-1];
  integer i;
  initial begin
    for (i = 0; i < BYTES; i = i + 1) mem[i] = 8'h00;
    busy = 0; data_ready = 0; dout = 0; dout32 = 0;
  end

  reg [3:0]  cyc = 0;
  reg        rdpend = 0;
  reg [22:0] a_lat;

  always @(posedge clk) begin
    data_ready <= 0;
    if (!resetn) begin
      busy <= 0; cyc <= 0; rdpend <= 0;
    end else if (cyc != 0) begin
      cyc <= cyc - 1;
      if (cyc == 1) begin
        busy <= 0;                            // (2): together with data_ready
        if (rdpend) begin
          dout       <= mem[a_lat];
          dout32     <= {mem[{a_lat[22:2],2'd3}], mem[{a_lat[22:2],2'd2}],
                         mem[{a_lat[22:2],2'd1}], mem[{a_lat[22:2],2'd0}]};
          data_ready <= 1;
        end
        rdpend <= 0;
      end
    end else if (wr) begin
      if (wr_word) begin
        mem[{addr[22:2],2'd0}] <= din;  mem[{addr[22:2],2'd1}] <= din;
        mem[{addr[22:2],2'd2}] <= din;  mem[{addr[22:2],2'd3}] <= din;
      end else mem[addr] <= din;
      busy <= 1; cyc <= LAT;                  // (1): busy from the NEXT cycle
    end else if (rd) begin
      a_lat <= addr; rdpend <= 1; busy <= 1; cyc <= LAT;
    end else if (refresh) begin
      busy <= 1; cyc <= LAT;
    end
  end
endmodule
