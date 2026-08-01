// top.v -- Milestone 0 "first light" for P8X on the Sipeed Tang Nano 20K.
//
// NOT the CPU yet. This proves the toolchain + console path: it echoes every
// byte received on the USB serial link and blinks LED0 as a heartbeat. Once this
// works, the P8X core (Milestone 1+) drops in where the echo logic is.
//
// Board: Tang Nano 20K, Gowin GW2AR-18 (GW2AR-LV18QN88C8/I7), 27 MHz clock.
// Console: onboard BL616 USB<->UART bridge -> a /dev/tty on the host, 115200 8N1.

module top(
  input        clk,        // 27 MHz  (pin 4)
  input        uart_rx,    // from host (pin 70, SYS_RX)
  output       uart_tx,    // to   host (pin 69, SYS_TX)
  output [5:0] led);       // 6 LEDs, active-LOW (pins 15..20)

  // Power-on reset: hold rst high for ~128 clocks after configuration, then
  // release. Avoids depending on the KEY2 button (pin 87) for first light.
  reg [7:0] por = 8'd0;
  wire      rst = ~por[7];
  always @(posedge clk) if (~por[7]) por <= por + 1'b1;

  // Heartbeat: LED0 toggles ~0.8 Hz (27 MHz / 2^25).
  reg [24:0] hb = 25'd0;
  always @(posedge clk) hb <= hb + 1'b1;

  // Echo: whatever arrives on rx goes straight back out tx.
  wire [7:0] rdata; wire rvalid; wire tbusy;
  reg        send  = 1'b0;
  reg  [7:0] tdata = 8'd0;
  uart_rx #(.DIV(234)) URX (.clk(clk), .rst(rst), .rx(uart_rx),
                            .data(rdata), .valid(rvalid));
  uart_tx #(.DIV(234)) UTX (.clk(clk), .rst(rst), .data(tdata),
                            .send(send), .tx(uart_tx), .busy(tbusy));
  always @(posedge clk) begin
    send <= 1'b0;
    if (rvalid && !tbusy) begin tdata <= rdata; send <= 1'b1; end
  end

  assign led = ~{5'b0, hb[24]};   // LED0 heartbeat; others off (active-low)
endmodule
