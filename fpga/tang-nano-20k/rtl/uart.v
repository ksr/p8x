// uart.v -- minimal 8N1 UART (TX + RX) for P8X-on-FPGA.
//
// DIV = system_clock / baud. Tang Nano 20K clock is 27 MHz:
//   27_000_000 / 115200 = 234.375  ->  DIV=234  (actual 115384 baud, +0.16%, fine)
//
// This is the Milestone-0 "first light" UART. In Milestone 2 it gets wrapped in
// a 6850-ACIA register shim (status/data at $FF04/$FF05) so the P8X monitor/OS
// serial driver runs unchanged; the byte-level TX/RX below stays as-is.

module uart_tx #(parameter DIV=234)(
  input        clk,
  input        rst,
  input  [7:0] data,
  input        send,      // 1-cycle strobe: latch `data` and transmit
  output reg   tx,
  output reg   busy);
  localparam IDLE=2'd0, START=2'd1, DATA=2'd2, STOP=2'd3;
  reg [1:0]  st;
  reg [15:0] cnt;
  reg [2:0]  idx;
  reg [7:0]  buf_;
  always @(posedge clk) begin
    if (rst) begin st<=IDLE; tx<=1'b1; busy<=1'b0; cnt<=0; idx<=0; end
    else case (st)
      IDLE : begin tx<=1'b1; busy<=1'b0;
             if (send) begin buf_<=data; busy<=1'b1; cnt<=0; st<=START; end end
      START: begin tx<=1'b0;
             if (cnt==DIV-1) begin cnt<=0; idx<=0; st<=DATA; end else cnt<=cnt+1'b1; end
      DATA : begin tx<=buf_[idx];
             if (cnt==DIV-1) begin cnt<=0;
               if (idx==3'd7) st<=STOP; else idx<=idx+1'b1; end else cnt<=cnt+1'b1; end
      STOP : begin tx<=1'b1;
             if (cnt==DIV-1) begin cnt<=0; st<=IDLE; busy<=1'b0; end else cnt<=cnt+1'b1; end
    endcase
  end
endmodule

module uart_rx #(parameter DIV=234)(
  input            clk,
  input            rst,
  input            rx,
  output reg [7:0] data,
  output reg       valid);  // 1-cycle strobe when a byte is received
  localparam IDLE=2'd0, START=2'd1, DATA=2'd2, STOP=2'd3;
  reg [1:0]  st;
  reg [15:0] cnt;
  reg [2:0]  idx;
  reg        rx1, rx2;      // 2-FF synchronizer for the async rx line
  always @(posedge clk) begin rx1<=rx; rx2<=rx1; end
  always @(posedge clk) begin
    if (rst) begin st<=IDLE; valid<=1'b0; cnt<=0; idx<=0; end
    else begin
      valid<=1'b0;
      case (st)
        IDLE : if (~rx2) begin st<=START; cnt<=0; end            // falling edge = start bit
        START: if (cnt==DIV/2-1) begin cnt<=0; idx<=0; st<=DATA; end else cnt<=cnt+1'b1;
        DATA : if (cnt==DIV-1) begin cnt<=0; data[idx]<=rx2;     // sample at bit centre
                 if (idx==3'd7) st<=STOP; else idx<=idx+1'b1; end else cnt<=cnt+1'b1;
        STOP : if (cnt==DIV-1) begin cnt<=0; st<=IDLE; valid<=1'b1; end else cnt<=cnt+1'b1;
      endcase
    end
  end
endmodule
