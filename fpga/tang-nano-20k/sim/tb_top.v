// tb_top.v -- Milestone-0 bench: prove the echo path in simulation before
// spending a bitstream on it. Drives uart_rx at the real 115200-for-27MHz bit
// period, decodes whatever comes back on uart_tx, and checks it matches.
//
//   iverilog -g2012 -o tb_top.vvp ../rtl/top.v ../rtl/uart.v tb_top.v && vvp tb_top.vvp
//
// This is the board-independent half of "first light": if the echo works here
// and the bitstream still does nothing on hardware, the fault is pins, clock, or
// the USB bridge -- not the logic.

`timescale 1ns/1ps
module tb_top;
  localparam DIV     = 234;              // must match top.v
  localparam CLK_NS  = 37;               // 27 MHz -> 37.037 ns
  localparam BIT_NS  = DIV * CLK_NS;     // one bit time

  reg clk = 0;
  always #(CLK_NS/2.0) clk = ~clk;

  reg  rx = 1'b1;                        // idle high
  wire tx, dummy;
  wire [5:0] led;

  top DUT(.clk(clk), .uart_rx(rx), .uart_tx(tx), .led(led));

  // --- host -> FPGA: shift a byte out at the real bit rate ---
  task send_byte(input [7:0] b);
    integer i;
    begin
      rx = 1'b0;                         // start bit
      #(BIT_NS);
      for (i = 0; i < 8; i = i + 1) begin rx = b[i]; #(BIT_NS); end
      rx = 1'b1;                         // stop bit
      #(BIT_NS);
    end
  endtask

  // --- FPGA -> host: wait for a start bit, sample 8 data bits at bit centres ---
  task recv_byte(output [7:0] b);
    integer i;
    begin
      @(negedge tx);                     // start bit
      #(BIT_NS + BIT_NS/2);              // into the centre of bit 0
      for (i = 0; i < 8; i = i + 1) begin b[i] = tx; #(BIT_NS); end
    end
  endtask

  reg [7:0] got;
  integer   errors = 0;

  task check(input [7:0] sent);
    begin
      fork
        send_byte(sent);
        recv_byte(got);
      join
      if (got === sent) $display("  echo %02x -> %02x  OK", sent, got);
      else begin
        $display("  echo %02x -> %02x  MISMATCH", sent, got);
        errors = errors + 1;
      end
    end
  endtask

  initial begin
    $display("Milestone-0 echo bench (DIV=%0d, %0d ns/bit)", DIV, BIT_NS);
    #(BIT_NS * 4);                       // let the power-on reset finish
    check(8'h41);                        // 'A'
    check(8'h7A);                        // 'z'
    check(8'h00);                        // all zeroes
    check(8'hFF);                        // all ones
    check(8'h55);                        // alternating
    if (errors == 0) $display("PASS: echo path works");
    else             $display("FAIL: %0d mismatch(es)", errors);
    $finish;
  end
endmodule
