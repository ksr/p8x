// tb_sdram_test.v -- does the STAGE 0 TEST FSM itself work?
//
// The point of this bench is narrow and worth stating, because it is easy to
// mistake for a test of the SDRAM. It is not. It replaces the controller with a
// perfect behavioural memory, so the only thing that can fail is our own logic:
// the address sequencing, the compare, the saturating counters, and above all
// the refresh-priority arm, which reaches into the middle of the test's state
// machine and is exactly the kind of thing that deadlocks.
//
// Why bother: if the board reports errors, "my FSM is wrong" and "the SDRAM is
// wrong" are indistinguishable from a blinking LED. Ruling out the first here
// means a failure on hardware is real. Same reason the C emulator is the CPU's
// golden model, and the same reason the controller was vendored rather than
// written.
//
//   iverilog -g2012 -o tb tb_sdram_test.v && ./tb
`timescale 1ns/1ps

// Named `sdram` so it SUBSTITUTES for the real controller: the DUT is
// compiled without sdram.v, so this is what it binds to.
module sdram #(parameter FREQ = 27_000_000) (
    input clk, input clk_sdram, input resetn,
    input [22:0] addr, input rd, input wr, input wr_word, input refresh,
    input [7:0] din, output reg [7:0] dout,
    output reg data_ready, output reg busy,
    inout [31:0] SDRAM_DQ, output [10:0] SDRAM_A, output [1:0] SDRAM_BA,
    output SDRAM_nCS, output SDRAM_nWE, output SDRAM_nRAS, output SDRAM_nCAS,
    output SDRAM_CLK, output SDRAM_CKE, output [3:0] SDRAM_DQM);

  // Only the bytes the test actually touches are modelled -- 64 KB of
  // sequential plus 128 sparse -- because 8 MB of reg would be absurd.
  reg [7:0] seq_mem [0:65535];
  reg [7:0] spr_mem [0:127];
  reg [7:0] wrd_mem [0:1023];      // the word-write region at $108000
  // Routing has to be exact or the passes silently overwrite each other.
  wire is_wrd = (addr[22:16] == 7'd16) && addr[15];
  wire is_spr = !is_wrd && (addr[15:0] == 16'd0);

  integer i;
  initial begin
    for (i = 0; i < 65536; i = i + 1) seq_mem[i] = 8'hFF;
    for (i = 0; i < 128;   i = i + 1) spr_mem[i] = 8'hFF;
    for (i = 0; i < 1024;  i = i + 1) wrd_mem[i] = 8'hFF;
    busy = 0; data_ready = 0; dout = 0;
  end

  // A few cycles of busy per operation, so the FSM's !busy handshake is really
  // exercised rather than trivially always-true.
  reg [2:0] cyc = 0;
  reg [1:0] op  = 0;              // 1 = read pending
  reg [22:0] a_lat;

  always @(posedge clk) begin
    data_ready <= 0;
    if (!resetn) begin
      busy <= 0; cyc <= 0; op <= 0;
    end else if (cyc != 0) begin
      cyc <= cyc - 1;
      if (cyc == 1) begin
        busy <= 0;
        if (op == 1) begin
          dout <= ((a_lat[22:16]==7'd16) && a_lat[15]) ? wrd_mem[a_lat[9:0]]
                : (a_lat[15:0] == 16'd0)                ? spr_mem[a_lat[22:16]]
                :                                         seq_mem[a_lat[15:0]];
          data_ready <= 1;
        end
        op <= 0;
      end
    end else if (wr) begin
      // wr_word writes all four lanes -- the whole point of the local
      // modification, so the stub has to model it or the bench proves nothing.
      if (is_wrd) begin
        if (wr_word) begin
          wrd_mem[{addr[9:2],2'd0}]   <= din;  wrd_mem[{addr[9:2],2'd1}] <= din;
          wrd_mem[{addr[9:2],2'd2}]   <= din;  wrd_mem[{addr[9:2],2'd3}] <= din;
        end else wrd_mem[addr[9:0]] <= din;
      end else if (is_spr) spr_mem[addr[22:16]] <= din;
      else                 seq_mem[addr[15:0]]  <= din;
      busy <= 1; cyc <= 3; op <= 0;
    end else if (rd) begin
      a_lat <= addr; busy <= 1; cyc <= 3; op <= 1;
    end else if (refresh) begin
      busy <= 1; cyc <= 3; op <= 0;
    end
  end
endmodule

module tb;
  reg clk27 = 0;
  always #18.5 clk27 = ~clk27;          // ~27 MHz

  wire [5:0] led;
  wire uart_txp;
  wire [31:0] dq;

  sdram_test dut(.clk27(clk27), .led(led), .uart_txp(uart_txp),
    .O_sdram_clk(), .O_sdram_cke(), .O_sdram_cs_n(), .O_sdram_cas_n(),
    .O_sdram_ras_n(), .O_sdram_wen_n(), .IO_sdram_dq(dq),
    .O_sdram_addr(), .O_sdram_ba(), .O_sdram_dqm());

  integer cycles = 0;
  always @(posedge dut.clk) cycles = cycles + 1;

  initial begin
    // The design waits 16384 cycles for the SDRAM's power-on delay; at ~27 MHz
    // that is ~600 us, and the two passes then take a few ms.
    #200_000_000;                       // 200 ms -- three passes now

    $display("state    = %0d (8 = DONE)", dut.st);
    $display("err_seq  = %0d", dut.err_seq);
    $display("err_spr  = %0d", dut.err_spr);
    $display("err_wrd  = %0d", dut.err_wrd);
    $display("cycles   = %0d", cycles);

    if (dut.st !== 4'd8) begin
      $display("TB-SDRAM: FAIL - the FSM did not reach DONE (stuck in state %0d).", dut.st);
      $display("  A hang here is almost certainly the refresh-priority arm.");
      $finish(1);
    end
    if (dut.err_seq !== 16'd0 || dut.err_spr !== 16'd0 || dut.err_wrd !== 16'd0) begin
      $display("TB-SDRAM: FAIL - against a PERFECT memory the counts must be 0.");
      $display("  That means the addressing or the compare is wrong, not the SDRAM.");
      $finish(1);
    end
    $display("TB-SDRAM: PASS (FSM sequences, compares and refreshes correctly)");
    $finish(0);
  end
endmodule
