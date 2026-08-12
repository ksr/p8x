// tb_p8x_top.v -- board-level bench for Milestone 3.
//
// Runs the ACTUAL board top (p8x_top.v: falling-edge BRAM + the real ACIA shim
// + the 8N1 UART) and decodes its serial output at the real bit rate. If the
// monitor banner comes out of the UART here, the two things that differ from the
// proven co-sim -- synchronous memory and a real serial port -- are both right,
// and a dead board afterwards means pins or clock, not logic.
//
//   iverilog -g2012 -o tb_p8x_top.vvp ../../rtl/p8x_cpu.v ../rtl/p8x_top.v \
//                                     ../rtl/uart.v tb_p8x_top.v
//   vvp tb_p8x_top.vvp
//
// Needs ucode.hex and mem.hex in the working directory (build.sh generates them).

`timescale 1ns/1ps
module tb_p8x_top;
  localparam DIV    = 234;
  localparam CLK_NS = 37;                  // 27 MHz
  localparam BIT_NS = DIV * CLK_NS;

  reg clk = 0;
  always #(CLK_NS/2.0) clk = ~clk;

  reg  rx = 1'b1;
  wire tx;
  wire [5:0] led;

  p8x_top DUT(.clk(clk), .uart_rx(rx), .uart_tx(tx), .led(led));

  // --- decode the FPGA's serial output ---
  integer nchar = 0;
  reg [7:0] line [0:255];

  task recv_byte(output [7:0] b);
    integer i;
    begin
      @(negedge tx);
      #(BIT_NS + BIT_NS/2);
      for (i = 0; i < 8; i = i + 1) begin b[i] = tx; #(BIT_NS); end
    end
  endtask

  task send_byte(input [7:0] b);
    integer i;
    begin
      rx = 1'b0; #(BIT_NS);
      for (i = 0; i < 8; i = i + 1) begin rx = b[i]; #(BIT_NS); end
      rx = 1'b1; #(BIT_NS);
    end
  endtask

  reg [7:0] c;
  integer   i;

  // collect everything the machine says
  initial begin
    forever begin
      recv_byte(c);
      if (nchar < 256) begin line[nchar] = c; nchar = nchar + 1; end
      if (c >= 8'h20 && c < 8'h7f) $write("%c", c);
      else if (c == 8'h0a) $write("\n");
      $fflush;
    end
  end

  initial begin
    $display("=== Milestone-3 board bench: expecting the monitor banner ===");
    // let the monitor boot and print its banner, then ask for help
    #(BIT_NS * 400);
    send_byte("?");
    #(BIT_NS * 900);
    $display("\n=== %0d bytes received ===", nchar);
    if (nchar > 20) $display("PASS: the CPU is talking over the real UART");
    else            $display("FAIL: little or no serial output");
    $finish;
  end
endmodule
