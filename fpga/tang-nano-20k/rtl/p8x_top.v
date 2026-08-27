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
  // Behind `LCD` so the default `build.sh cpu` stays exactly as it was -- the
  // panel is opt-in. The pin mapping IS verified (taken from Sipeed's own
  // 480x272 example) and `build.sh lcd` builds, places and runs on hardware.
  output       lcd_clk,
  output       lcd_de,
  // no lcd_hs / lcd_vs: the connector does not carry them (DE-only panel)
  output [4:0] lcd_r,
  output [5:0] lcd_g,
  output [4:0] lcd_b,
`endif
  output [5:0] led         // active-LOW

`ifdef LCD
  ,
  // The in-package SDRAM. These names are MAGIC -- apicula bonds them to the
  // dedicated pads and they must NOT appear in the .cst. See
  // fpga/tang-nano-20k/sdram/README.md for the controlled experiment.
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
`endif
  );

  // ---- power-on reset ----
  // Held until 256 clocks after configuration AND, on the LCD build, until
  // the SDRAM's phase-shifted clock has LOCKED. The lock gate is the fix for
  // a bug that hid behind every warm reset: the controller's 200 us init ran
  // against a still-settling clk_sdram on the FIRST boot after
  // configuration, so the chip was initialised on a bad clock and engine
  // writes rotted -- cold power-on and JTAG loads showed noise and "drawing
  // does not work", while any subsequent reset (PLL long since locked)
  // healed everything. Symptom on the panel: the monitor's boot splash only
  // appearing after a second reset.
  reg [8:0] por = 9'd0;
`ifdef LCD
  wire      pll_lock;
  wire      rst = ~por[8] | ~pll_lock;
`else
  wire      rst = ~por[8];
`endif
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
  // The MDU (stage 8a, $FF30-$FF3F) is display-independent: every build
  // flavour carries it, so software's MDID probe answers on all of them.
  wire is_mdu   = (mem_addr >= 16'hFF30) && (mem_addr <= 16'hFF3F);
`ifdef LCD
  // The geometry engine (stage 8b, $FF40-$FF4F) needs the display and the
  // SDRAM, so it exists only on LCD builds; elsewhere the window floats to
  // $FF and lib_g3d's GEID probe falls back to the software walk.
  // The GL command port (stage 10, $FF50-$FF57): LCD builds only, floats
  // to $FF elsewhere so software's GLID probe fails clean. The $FF40
  // record-engine window is RETIRED (stage 10b) -- it floats everywhere,
  // and lib_g3d's GEID probe falls back to the software walk.
  wire is_gl    = (mem_addr >= 16'hFF50) && (mem_addr <= 16'hFF57);
`else
  wire is_gl    = 1'b0;
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
  // The SDRAM chip is clocked from a 225-degree phase-shifted copy of the
  // system clock -- the shift is what buys setup/hold at the pads. Same rPLL
  // parameters Gowin's own generator produces for this board (see
  // sdram/sdram_test.v), and the PLL does NOT multiply: 27 MHz in, 27 out.
  wire clk_sdram;               // pll_lock is declared with the reset above
  rPLL #(
    .FCLKIN("27"), .IDIV_SEL(1), .FBDIV_SEL(1), .ODIV_SEL(32),
    .PSDA_SEL("1010"), .DUTYDA_SEL("1000"), .DEVICE("GW2A-18C"),
    .DYN_IDIV_SEL("false"), .DYN_FBDIV_SEL("false"), .DYN_ODIV_SEL("false"),
    .DYN_DA_EN("false"), .CLKFB_SEL("internal"),
    .CLKOUT_BYPASS("false"), .CLKOUTP_BYPASS("false"), .CLKOUTD_BYPASS("false"),
    .CLKOUTD_SRC("CLKOUT"), .CLKOUT_DLY_STEP(0), .CLKOUTP_DLY_STEP(0)
  ) SDPLL (
    .CLKIN(clk), .CLKFB(1'b0), .RESET(1'b0), .RESET_P(1'b0),
    .FBDSEL(6'b0), .IDSEL(6'b0), .ODSEL(6'b0),
    .PSDA(4'b0), .DUTYDA(4'b0), .FDLY(4'b0),
    .CLKOUT(), .CLKOUTP(clk_sdram), .CLKOUTD(), .CLKOUTD3(), .LOCK(pll_lock));

  // ---- graphics display ($FF20..$FF2F) + the panel ----
  // The framebuffer lives in the in-package SDRAM now, not block RAM. Three
  // masters share it through sdram_arb: the scanout (which cannot stall),
  // refresh (which cannot be deferred), and the engine (which can wait). That
  // trades the four blocks the old framebuffer used for the one the scanout's
  // line buffer needs -- and it is what makes mode 1 (480x272, 256 pens)
  // possible at all, since the panel's own resolution never fitted in BSRAM at
  // any depth.
  wire [7:0]  gfx_rdata;

  wire        sd_rd, sd_wr, sd_word;
  wire [22:0] sd_addr;
  wire [15:0] sd_din, sd_dout;    // 16 bits: a pixel is an RGB565 colour
  wire [31:0] sd_dout32;
  wire        sd_ready, sd_busy;

  // The scanout no longer goes through the arbiter: it talks the P8X
  // controller's STREAM port directly (one st_go per line, words answered a
  // cycle apiece), which is what makes a line fetch cost its word count
  // instead of ~6 cycles a word. Refresh is INTERNAL to the controller now,
  // so the 15 us timer this section used to keep is gone -- a forgotten
  // refresh is silent data rot, and the controller owning its own deadline
  // removes the class of bug. The arbiter keeps only the engine, whose word
  // port is contract-identical to the vendored controller's.
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


  // stage 10c: the geometry module's SDRAM client returns -- command
  // lists live at $100000+ and the recorder/replayer stream through it
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

  // The geometry engine (stage 8b) owns the gfx register port while it
  // renders -- it is a hardware BASIC, writing the same registers software
  // does. A CPU gfx access during a render is dropped (writes) or reads the
  // engine's register instead of its own: poll GESTAT first, the house rule.
  wire        gm_own, gm_wr;
  wire [3:0]  gm_a;
  wire [7:0]  gm_wdata;
  wire [7:0]  geom_rdata;
  wire        draw_pg, disp_pg, frame_tick;

  p8x_geom GEOM(.clk(clk), .rst(rst),
          .a(mem_addr[3:0]),
          .g_req(g_req), .g_we(g_we), .g_addr(g_addr), .g_din(g_din),
          .g_ack(g_ack), .g_ready(g_ready), .g_dout(sd_dout),
          .gl_sel(is_gl),
          .gl_wr(cen && mem_we && is_gl),
          .gl_rd(cen && mem_rd && is_gl),
          .wdata(mem_dout), .rdata(geom_rdata),
          .gm_own(gm_own), .gm_wr(gm_wr), .gm_a(gm_a), .gm_wdata(gm_wdata),
          .gm_rdata(gfx_rdata),
          .frame_tick(frame_tick), .draw_pg(draw_pg), .disp_pg(disp_pg));

  gfx GFX(.clk(clk), .rst(rst), .draw_pg(draw_pg),
          .sel(gm_own ? 1'b1 : is_gfx),
          .a(gm_own ? gm_a : mem_addr[3:0]),
          .wr(gm_own ? gm_wr : (cen && mem_we && is_gfx)),
          .rd_stb(gm_own ? 1'b0 : (cen && mem_rd && is_gfx)),
          .wdata(gm_own ? gm_wdata : mem_dout), .rdata(gfx_rdata),
          .e_req(e_req), .e_we(e_we), .e_word(e_word), .e_addr(e_addr),
          .e_din(e_din), .e_ack(e_ack), .e_ready(e_ready), .e_dout(sd_dout));

  sdram_video VID(.clk(clk), .rst(rst), .disp_pg(disp_pg),
          .st_go(v_go), .st_addr(v_addr), .st_words(v_words),
          .st_valid(v_valid), .st_data(v_data), .st_done(v_done),
          .pclk(lcd_clk), .de(lcd_de), .r(lcd_r), .g(lcd_g), .b(lcd_b),
          .underruns(), .frame_tick(frame_tick));

`else
  wire [7:0] gfx_rdata  = 8'hFF;
  wire [7:0] geom_rdata = 8'hFF;
`endif

  wire [7:0] mdu_rdata;
  p8x_mdu MDU(.clk(clk), .rst(rst),
              .sel(is_mdu), .a(mem_addr[3:0]),
              .wr(cen && mem_we && is_mdu),
              .wdata(mem_dout), .rdata(mdu_rdata));

  wire [7:0] io_rd = acia_st  ? {6'b0, ~tx_busy, rx_have} :
                     acia_dat ? rx_hold :
                     is_cf    ? cf_rdata :
                     is_gfx   ? gfx_rdata :
                     is_gl    ? geom_rdata :
                     is_mdu   ? mdu_rdata : 8'hFF;
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
