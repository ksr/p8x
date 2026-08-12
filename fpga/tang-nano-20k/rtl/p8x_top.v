// p8x_top.v -- Milestone 3: the real P8X CPU on the Tang Nano 20K.
//
// Same core as the co-sim (fpga/rtl/p8x_cpu.v, unmodified). What changes is the
// substrate around it:
//
//   sim (p8x_soc.v)              board (here)
//   -------------------------    ----------------------------------------
//   async-read arrays            BRAM, read across a 3-phase microcycle
//   $FF04 constant 0x02          real ACIA shim over the 8N1 UART
//   $FF05 swallowed              real serial TX
//
// A microcycle needs two DEPENDENT block-RAM reads, which is the whole problem:
//
//   1. fetch the microcode word at {cond, stp, IR}
//   2. its PSEL field chooses which pointer drives mem_addr
//   3. only then can the memory byte be fetched
//
// One clock edge cannot do both -- a single falling-edge latch reads memory with
// the PREVIOUS word's PSEL, which fetches from the wrong pointer and derails the
// machine within ten cycles. So the fabric runs three phases per microcycle and
// the CPU advances on the last one, via its `cen` input:
//
//   phase 0  microcode address settled -> BRAM read issued
//   phase 1  word available; mem_addr now valid -> memory read issued
//   phase 2  both results stable -> cen=1, the CPU commits the microcycle
//
// 27 MHz / 3 = 9 MHz effective, which is still far quicker than the TTL machine.
// Writes land in phase 2 alongside the commit, so a read earlier in the same
// microcycle still returns the pre-write byte, exactly as in p8x_soc.v.

module p8x_top(
  input        clk,        // 27 MHz (pin 4)
  input        uart_rx,    // from host (pin 70)
  output       uart_tx,    // to host   (pin 69)
  output [5:0] led);       // active-LOW

  // ---- power-on reset: hold for 256 clocks after configuration ----
  reg [8:0] por = 9'd0;
  wire      rst = ~por[8];
  always @(posedge clk) if (~por[8]) por <= por + 1'b1;

  // ---- CPU ----
  wire [12:0] uc_addr;
  wire [31:0] uc_data;
  wire [15:0] mem_addr;
  wire [7:0]  mem_din, mem_dout;
  wire        mem_we, mem_rd, halted;

  // ---- three-phase microcycle sequencer ----
  reg [1:0] ph = 2'd0;
  always @(posedge clk) if (rst) ph <= 2'd0;
                        else     ph <= (ph == 2'd2) ? 2'd0 : ph + 2'd1;
  wire cen = (ph == 2'd2);

  // ---- microcode ROM: 8192 x 32, initialised from genucode output ----
  // Read in phase 0: uc_addr is {cond, stp, IR}, all settled at the commit edge.
  reg [31:0] ucode [0:8191];
  initial $readmemh("ucode.hex", ucode);
  reg [31:0] uc_q;
  always @(posedge clk) if (ph == 2'd0) uc_q <= ucode[uc_addr];
  assign uc_data = uc_q;

  // ---- main memory: 32K, ALIASED (A15 ignored) ----
  //
  // The full 64K plus the 8192x32 microcode needs 47 BSRAM blocks and the
  // GW2AR-18 has 46. Rather than shave the microcode -- every one of its 32 bits
  // is used -- this build drops A15, so $8000..$FFFF mirrors $0000..$7FFF.
  //
  // The monitor is unaffected: its ROM is $0000..$1FFF, its scratch $6000..$69FF,
  // and its stack starts at $FEFF, which mirrors to $7EFF -- three disjoint
  // regions. What this WILL break is anything genuinely using more than 32K,
  // i.e. P8X/OS with a full TPA. Milestone 4 moves main memory to the board's
  // 64 Mbit SDRAM (the 'R' in GW2AR) and gives back the whole map.
  localparam MEMBITS = 15;
  wire [MEMBITS-1:0] mem_a = mem_addr[MEMBITS-1:0];
  reg [7:0] mem [0:(1<<MEMBITS)-1];
  initial $readmemh("mem.hex", mem);
  reg [7:0] mem_q;
  always @(posedge clk) begin
    if (ph == 2'd1) mem_q <= mem[mem_a];
    // ROM ($0000..$1FFF) write-protected, $FF00.. is I/O -- as in the emulator
    if (cen && mem_we && mem_a >= 16'h2000 && mem_addr < 16'hFF00)
      mem[mem_a] <= mem_dout;
  end

  // ---- ACIA shim over the UART ($FF04 status / $FF05 data) ----
  wire [7:0] rx_data;
  wire       rx_valid;
  wire       tx_busy;
  reg        rx_have = 1'b0;
  reg  [7:0] rx_hold = 8'h00;
  reg        tx_send = 1'b0;
  reg  [7:0] tx_data = 8'h00;

  wire is_io    = (mem_addr >= 16'hFF00);
  wire acia_st  = (mem_addr == 16'hFF04);
  wire acia_dat = (mem_addr == 16'hFF05);

  // TDRE (bit 1) = transmitter free; RDRF (bit 0) = a byte is waiting.
  wire [7:0] io_rd = acia_st  ? {6'b0, ~tx_busy, rx_have} :
                     acia_dat ? rx_hold : 8'hFF;
  assign mem_din = is_io ? io_rd : mem_q;

  // Reading $FF05 consumes the byte -- keyed off mem_rd (the microcycles that
  // source the bus from memory), never off mem_addr, which lingers.
  always @(posedge clk) begin
    if (rst) begin rx_have <= 1'b0; end
    else begin
      if (rx_valid) begin rx_hold <= rx_data; rx_have <= 1'b1; end
      // consume only on the commit phase: mem_rd is level-valid for the whole
      // microcycle, so without cen the byte would be popped three times
      if (cen && mem_rd && acia_dat) rx_have <= 1'b0;
      if (rx_valid && cen && mem_rd && acia_dat) rx_have <= 1'b1;  // arrival wins
    end
    tx_send <= 1'b0;
    if (cen && mem_we && acia_dat && !tx_busy) begin tx_data <= mem_dout; tx_send <= 1'b1; end
  end

  uart_rx #(.DIV(234)) URX (.clk(clk), .rst(rst), .rx(uart_rx),
                            .data(rx_data), .valid(rx_valid));
  uart_tx #(.DIV(234)) UTX (.clk(clk), .rst(rst), .data(tx_data),
                            .send(tx_send), .tx(uart_tx), .busy(tx_busy));

  p8x_cpu CPU(
    .clk(clk), .rst(rst), .cen(cen),
    .uc_addr(uc_addr), .uc_data(uc_data),
    .mem_addr(mem_addr), .mem_din(mem_din), .mem_dout(mem_dout),
    .mem_we(mem_we), .mem_rd(mem_rd),
    .irq_set(1'b0), .halted(halted));

  // ---- status LEDs (active low) ----
  reg [24:0] hb = 25'd0;
  always @(posedge clk) hb <= hb + 1'b1;
  assign led = ~{3'b0, halted, ~rst, hb[24]};
  // led0 heartbeat, led1 "running" (reset released), led2 halted
endmodule
