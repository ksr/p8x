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
  output       sd_clk,     // microSD in SPI mode: CLK  (pin 83)
  output       sd_mosi,    //   CMD  as MOSI (pin 82)
  input        sd_miso,    //   DAT0 as MISO (pin 84)
  output       sd_cs,      //   DAT3 as CS   (pin 81)
`ifdef LCD
  // 4.3" 480x272 parallel-RGB panel, DE mode. The pixel clock is 27/3 = 9 MHz,
  // the SAME divide-by-three the CPU runs on, so no PLL is needed.
  //
  // Behind `LCD` because the 40-pin RGB mapping has NOT been verified against
  // Sipeed's documentation yet, and unconstrained pins fail place-and-route.
  // Guessing pin numbers is how a panel stays dark for a day, so the default
  // `build.sh cpu` is left exactly as it was and the panel is opt-in.
  output       lcd_clk,
  output       lcd_de,
  // no lcd_hs / lcd_vs: the connector does not carry them (DE-only panel)
  output [4:0] lcd_r,
  output [5:0] lcd_g,
  output [4:0] lcd_b,
`endif
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

  // ---- microcode ROM: COMPACTED to 4096 x 32 ----
  //
  // The CPU addresses microcode as {cond, stp, IR} -- 8192 words, 15 BSRAM
  // blocks -- but only 88 of the 256 opcode encodings exist and all 168 undefined
  // ones hold the same word. So IR is squeezed through a combinational map into a
  // 7-bit index (88 opcodes + one shared undefined slot) and the ROM halves to
  // 4096 words, ~8 blocks. That is what buys back the full 64K memory map.
  //
  // mk_compact_ucode.py generates both files and refuses to emit anything unless
  // the compact image reproduces the original for all 8192 addresses.
  //
  // The map must be LUT logic, not a BRAM: it has to resolve inside phase 0,
  // before the microcode read is issued.
  wire       uc_cond = uc_addr[12];
  wire [3:0] uc_stp  = uc_addr[11:8];
  wire [7:0] ir      = uc_addr[7:0];
  reg  [6:0] idx;
  always @* begin
`include "irmap.vh"
  end
  reg [31:0] ucode [0:4095];
  initial $readmemh("ucode_c.hex", ucode);
  reg [31:0] uc_q;
  always @(posedge clk) if (ph == 2'd0) uc_q <= ucode[{uc_cond, uc_stp, idx}];
  assign uc_data = uc_q;

  // ---- main memory: the FULL 64K ----
  //
  // Affordable now that the microcode is compacted: 32 blocks of memory plus
  // ~8 of microcode fits the GW2AR-18's 46. No aliasing, no SDRAM controller --
  // P8X/OS sees exactly the memory map the emulator gives it.
  localparam MEMBITS = 16;
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
  wire is_cf    = (mem_addr >= 16'hFF10) && (mem_addr <= 16'hFF17);
`ifdef LCD
  wire is_gfx   = (mem_addr >= 16'hFF20) && (mem_addr <= 16'hFF2F);
`else
  wire is_gfx   = 1'b0;
`endif

  // TDRE (bit 1) = transmitter free; RDRF (bit 0) = a byte is waiting.
  wire [7:0] cf_rdata;
  wire       card_ready;
  cf_sd CF(.clk(clk), .rst(rst),
           .cf_rd(cen && mem_rd && is_cf), .cf_wr(cen && mem_we && is_cf),
           .cf_a(mem_addr[2:0]), .cf_wdata(mem_dout), .cf_rdata(cf_rdata),
           .sd_clk(sd_clk), .sd_mosi(sd_mosi), .sd_miso(sd_miso), .sd_cs(sd_cs),
           .card_ready(card_ready));

`ifdef LCD
  // ---- graphics display ($FF20..$FF2E) + the panel ----
  // The engine and the scanout use INDEPENDENT framebuffer ports: a scanout
  // that had to wait for a fill would tear visibly.
  wire [7:0]  gfx_rdata, sc_data;
  wire [12:0] sc_addr;
  wire        sc_en;
  wire [1:0]  sc_pen;
  wire [11:0] sc_rgb;

  gfx GFX(.clk(clk), .rst(rst),
          .sel(is_gfx), .a(mem_addr[3:0]),
          .wr(cen && mem_we && is_gfx), .rd_stb(cen && mem_rd && is_gfx),
          .wdata(mem_dout), .rdata(gfx_rdata),
          .sc_en(sc_en), .sc_addr(sc_addr), .sc_data(sc_data),
          .sc_pen(sc_pen), .sc_rgb(sc_rgb));

  video_rgb VID(.clk(clk), .rst(rst),
          .fb_en(sc_en), .fb_addr(sc_addr), .fb_data(sc_data), .fb_pen(sc_pen), .fb_rgb(sc_rgb),
          .pclk(lcd_clk), .de(lcd_de), .hs(), .vs(),
          .r(lcd_r), .g(lcd_g), .b(lcd_b));
`else
  wire [7:0] gfx_rdata = 8'hFF;
`endif

  wire [7:0] io_rd = acia_st  ? {6'b0, ~tx_busy, rx_have} :
                     acia_dat ? rx_hold :
                     is_cf    ? cf_rdata :
                     is_gfx   ? gfx_rdata : 8'hFF;
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
  assign led = ~{2'b0, card_ready, halted, ~rst, hb[24]};
  // led0 heartbeat, led1 running, led2 halted, led3 SD card initialised
endmodule
