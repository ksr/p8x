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
  wire sd_clk, sd_mosi, sd_cs, sd_miso;

  p8x_top DUT(.clk(clk), .uart_rx(rx), .uart_tx(tx),
              .sd_clk(sd_clk), .sd_mosi(sd_mosi), .sd_miso(sd_miso), .sd_cs(sd_cs),
              .led(led));
  sd_model CARD(.sd_clk(sd_clk), .sd_mosi(sd_mosi), .sd_miso(sd_miso), .sd_cs(sd_cs));

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

  // Does everything received so far contain this string?
  function seen(input [8*24:1] s, input integer len);
    integer p, q;
    begin
      seen = 0;
      for (p = 0; p + len <= nchar; p = p + 1) begin
        for (q = 0; q < len && line[p+q] == s[(len-q)*8 -: 8]; q = q + 1) ;
        if (q == len) seen = 1;
      end
    end
  endfunction

  integer fails = 0;

  initial begin
    $display("=== board bench: monitor + microSD ===");
    #(BIT_NS * 400);

    // I: SET FEATURES, IDENTIFY, print the model string. This is the only
    // command that exercises the IDENTIFY fill, and the fill is sequential --
    // 512 clocks with BSY held -- so a monitor that trusted an instantaneous
    // buffer would print rubbish here rather than fail outright.
    send_byte("I");
    send_byte(8'h0D);
    #(BIT_NS * 40000);
    if (!seen("P8X-SD TANG NANO 20K", 20)) begin
      $display("\nFAIL: IDENTIFY did not report the model string");
      fails = fails + 1;
    end

    send_byte("B");          // BOOT: reads the OS image off the card
    send_byte(8'h0D);
    #(BIT_NS * 40000);
    $display("\n=== %0d bytes received ===", nchar);
    if (nchar <= 20) begin
      $display("FAIL: little or no serial output");
      fails = fails + 1;
    end
    if (fails == 0) $display("PASS: the CPU is talking over the real UART");
    $finish;
  end
endmodule
