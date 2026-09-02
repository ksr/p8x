// p8x_gcard_top.v -- the P8X GRAPHICS CARD personality (CARD-EDGE-DESIGN.md).
//
// No CPU on this chip. The graphics stack -- geometry engine, 2D device,
// SDRAM framebuffer, scanout -- is byte-for-byte the lcd build's (the SAME
// module files); in the CPU's place sits p8x_bridge, speaking the serial
// card-edge protocol to whatever master is on the wire: today the Mac
// emulator / glbridge.py, tomorrow an FPGA CPU board or the TTL machine.
//
// The lcd target stays the all-in-one computer and the regression
// baseline; this target is ADDITIVE (build.sh `card`). Flip personalities
// by re-flash. LEDs: 0 heartbeat, 1 alive, 2 GL busy, 3 link activity.
module p8x_gcard_top(
  input        clk,        // 27 MHz crystal
  input        uart_rx,    // the bridge (pin 70)
  output       uart_tx,    //            (pin 69)
  output [5:0] led,

  // 480x272 panel, direct RGB565 (same pins as the lcd build)
  output        lcd_clk,
  output        lcd_de,
  output [4:0]  lcd_r,
  output [5:0]  lcd_g,
  output [4:0]  lcd_b,

  // in-package SDRAM
  output        O_sdram_clk,
  output        O_sdram_cke,
  output        O_sdram_cs_n,
  output        O_sdram_cas_n,
  output        O_sdram_ras_n,
  output        O_sdram_wen_n,
  inout  [31:0] IO_sdram_dq,
  output [10:0] O_sdram_addr,
  output [1:0]  O_sdram_ba,
  output [3:0]  O_sdram_dqm
);
  // ---- power-on reset held until the SDRAM PLL locks (as the lcd build) --
  reg [8:0] por = 9'd0;
  wire      pll_lock;
  wire      rst = ~por[8] | ~pll_lock;
  always @(posedge clk) if (~por[8]) por <= por + 1'b1;

  // ---- the SDRAM clock PLL: 27 MHz in, 27 out, phase-shifted ------------
  wire clk_sdram;
  rPLL #(
    .FCLKIN("27"), .IDIV_SEL(0), .FBDIV_SEL(0), .ODIV_SEL(32),
    .DYN_SDIV_SEL(2), .PSDA_SEL("0100"),
    .DEVICE("GW2AR-18C")
  ) SDPLL (
    .CLKIN(clk), .CLKFB(1'b0), .RESET(1'b0), .RESET_P(1'b0),
    .FBDSEL(6'b0), .IDSEL(6'b0), .ODSEL(6'b0), .PSDA(4'b0),
    .DUTYDA(4'b0), .FDLY(4'b0),
    .CLKOUT(), .CLKOUTP(clk_sdram), .CLKOUTD(), .CLKOUTD3(), .LOCK(pll_lock));

  // ---- the serial link (115200, as the console was) ----------------------
  wire [7:0] rx_data;
  wire       rx_valid;
  wire       tx_busy;
  wire [7:0] tx_data;
  wire       tx_send;
  uart_rx #(.DIV(234)) URX (.clk(clk), .rst(rst), .rx(uart_rx),
                            .data(rx_data), .valid(rx_valid));
  uart_tx #(.DIV(234)) UTX (.clk(clk), .rst(rst), .data(tx_data),
                            .send(tx_send), .tx(uart_tx), .busy(tx_busy));

  // ---- the bridge, in the CPU's seat -------------------------------------
  // GL only: the $FF20 device window is gone from the card edge -- the
  // walker is the register file's sole master now.
  wire        br_gl_sel, br_gl_wr, br_gl_rd;
  wire [3:0]  br_a;
  wire [7:0]  br_wdata;
  wire [7:0]  gfx_rdata, geom_rdata;

  p8x_bridge BRIDGE(.clk(clk), .rst(rst),
          .rxd(rx_data), .rxv(rx_valid),
          .txd(tx_data), .txs(tx_send), .txb(tx_busy),
          .gl_sel(br_gl_sel), .gl_wr(br_gl_wr), .gl_rd(br_gl_rd),
          .gl_rdata(geom_rdata),
          .a(br_a), .wdata(br_wdata));

  // ---- the graphics stack: IDENTICAL wiring to the lcd build -------------
  wire        sd_rd, sd_wr, sd_word, sd_ready, sd_busy;
  wire [22:0] sd_addr;
  wire [15:0] sd_din, sd_dout;
  wire [31:0] sd_dout32;
  wire        v_go, v_valid, v_done;
  wire [22:0] v_addr;
  wire [8:0]  v_words;
  wire [31:0] v_data;

  p8x_sdram #(.FREQ(27_000_000)) SDRAM(
    .clk(clk), .clk_sdram(clk_sdram), .resetn(!rst),
    .addr(sd_addr), .rd(sd_rd), .wr(sd_wr), .wr_word(sd_word), .din(sd_din),
    .dout(sd_dout), .dout32(sd_dout32), .data_ready(sd_ready), .busy(sd_busy),
    .st_go(v_go), .st_addr(v_addr), .st_words(v_words),
    .st_valid(v_valid), .st_data(v_data), .st_done(v_done),
    .SDRAM_DQ(IO_sdram_dq), .SDRAM_A(O_sdram_addr), .SDRAM_BA(O_sdram_ba),
    .SDRAM_nCS(O_sdram_cs_n), .SDRAM_nWE(O_sdram_wen_n),
    .SDRAM_nRAS(O_sdram_ras_n), .SDRAM_nCAS(O_sdram_cas_n),
    .SDRAM_CLK(O_sdram_clk), .SDRAM_CKE(O_sdram_cke), .SDRAM_DQM(O_sdram_dqm));

  wire        e_req, e_we, e_word, e_ack, e_ready;
  wire [22:0] e_addr;
  wire [15:0] e_din;
  wire        g_req, g_we, g_ack, g_ready;
  wire [22:0] g_addr;
  wire [15:0] g_din;

  sdram_arb ARB(
    .clk(clk), .rst(rst),
    .c_rd(sd_rd), .c_wr(sd_wr), .c_wr_word(sd_word), .c_refresh(),
    .c_addr(sd_addr), .c_din(sd_din), .c_dout(sd_dout), .c_dout32(sd_dout32),
    .c_ready(sd_ready), .c_busy(sd_busy),
    .s_req(1'b0), .s_addr(23'd0), .s_ack(), .s_ready(),
    .f_req(1'b0), .f_ack(),
    .g_req(g_req), .g_we(g_we), .g_addr(g_addr), .g_din(g_din),
    .g_ack(g_ack), .g_ready(g_ready),
    .e_req(e_req), .e_we(e_we), .e_word(e_word), .e_addr(e_addr),
    .e_din(e_din), .e_ack(e_ack), .e_ready(e_ready));

  wire        gm_own, gm_wr, gm_rd;
  wire [3:0]  gm_a;
  wire [7:0]  gm_wdata;
  wire        draw_pg, disp_pg, frame_tick;

  p8x_geom GEOM(.clk(clk), .rst(rst),
          .a(br_a),
          .g_req(g_req), .g_we(g_we), .g_addr(g_addr), .g_din(g_din),
          .g_ack(g_ack), .g_ready(g_ready), .g_dout(sd_dout),
          .gl_sel(br_gl_sel),
          .gl_wr(br_gl_wr),
          .gl_rd(br_gl_rd),
          .wdata(br_wdata), .rdata(geom_rdata),
          .gm_own(gm_own), .gm_wr(gm_wr), .gm_rd(gm_rd), .gm_a(gm_a), .gm_wdata(gm_wdata),
          .gm_rdata(gfx_rdata),
          .frame_tick(frame_tick), .draw_pg(draw_pg), .disp_pg(disp_pg));

  gfx GFX(.clk(clk), .rst(rst), .draw_pg(draw_pg),
          .sel(gm_own),
          .a(gm_a),
          .wr(gm_wr),
          .rd_stb(gm_rd),
          .wdata(gm_wdata), .rdata(gfx_rdata),
          .e_req(e_req), .e_we(e_we), .e_word(e_word), .e_addr(e_addr),
          .e_din(e_din), .e_ack(e_ack), .e_ready(e_ready), .e_dout(sd_dout));

  sdram_video VID(.clk(clk), .rst(rst), .disp_pg(disp_pg),
          .st_go(v_go), .st_addr(v_addr), .st_words(v_words),
          .st_valid(v_valid), .st_data(v_data), .st_done(v_done),
          .pclk(lcd_clk), .de(lcd_de), .r(lcd_r), .g(lcd_g), .b(lcd_b),
          .underruns(), .frame_tick(frame_tick));

  // ---- LEDs (active low): heartbeat, alive, GL busy, link activity -------
  reg [24:0] hb = 25'd0;
  reg [20:0] act = 21'd0;
  always @(posedge clk) begin
    hb <= hb + 1'b1;
    if (rx_valid || tx_send) act <= 21'h1FFFFF;
    else if (act != 0) act <= act - 21'd1;
  end
  wire gl_busy_led;
  assign gl_busy_led = geom_rdata[6];   // only meaningful while polled; a
                                        // cheap proxy: lit when GLSTAT busy
                                        // is on the bus during a poll
  assign led = ~{2'b0, (act != 0), gl_busy_led, ~rst, hb[24]};
endmodule
