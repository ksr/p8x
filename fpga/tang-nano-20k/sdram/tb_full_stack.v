// tb_full_stack.v -- the REAL graphics stack, end to end, at the pins.
//
// THE BENCH THAT WAS ALWAYS MISSING. The co-sim runs the real engine against
// sdram_model (the controller-interface stub); the controller benches drive
// hand-written tasks. The real gfx.v and the real p8x_sdram had NEVER run
// together in simulation -- and two bugs lived in exactly that gap, found on
// the panel by eye: S_CLS's true back-to-back pair-write cadence losing
// EVERY OTHER WRITE (the bench task paced one cycle slower and passed), and
// the scanout showing everything rotated by one word.
//
// Everything real: gfx.v driven at its CPU register interface, gfx_mem,
// sdram_arb, p8x_sdram, sdram_video, sdram_chip at the pins. A CLS runs, a
// box outline is drawn, then BOTH truths are audited: the chip's memory
// word by word, and one DISPLAYED line captured from the panel signals.
//
//   iverilog -g2012 -o tbfs tb_full_stack.v ../../rtl/gfx.v gfx_mem.v \
//            sdram_arb.v p8x_sdram.v sdram_video.v sdram_chip.v
//   vvp tbfs
`timescale 1ns/1ps
module tb;
  reg clk=0, rst=1; always #5 clk=~clk;

  // ---- the real device stack ------------------------------------------------
  reg         sel=0, wr=0, rd_stb=0;
  reg  [3:0]  a=0;
  reg  [7:0]  wdata=0;
  wire [7:0]  rdata;

  wire e_req, e_we, e_word, e_ack, e_ready;
  wire [22:0] e_addr;
  wire [15:0] e_din;

  wire        c_rd, c_wr, c_word, c_ready, c_busy;
  wire [22:0] c_addr;
  wire [15:0] c_din, c_dout;
  wire [31:0] c_dout32;

  wire        st_go, st_valid, st_done;
  wire [22:0] st_addr;
  wire [8:0]  st_words;
  wire [31:0] st_data;

  wire        pclk, de; wire [4:0] r, b; wire [5:0] g;
  wire [15:0] underruns; wire frame_tick;

  wire [31:0] dq;
  wire [10:0] m_A;   wire [1:0] m_BA;
  wire m_nCS, m_nWE, m_nRAS, m_nCAS, m_CLK, m_CKE;
  wire [3:0] m_DQM;

  gfx GFX(.clk(clk), .rst(rst), .draw_pg(1'b0),
    .sel(sel), .a(a), .wr(wr), .rd_stb(rd_stb), .wdata(wdata), .rdata(rdata),
    .e_req(e_req), .e_we(e_we), .e_word(e_word), .e_addr(e_addr),
    .e_din(e_din), .e_ack(e_ack), .e_ready(e_ready), .e_dout(c_dout));

  sdram_arb ARB(.clk(clk), .rst(rst),
    .g_req(1'b0), .g_we(1'b0), .g_addr(23'd0), .g_din(16'd0),
    .g_ack(), .g_ready(),
    .c_rd(c_rd), .c_wr(c_wr), .c_wr_word(c_word), .c_refresh(),
    .c_addr(c_addr), .c_din(c_din), .c_dout(c_dout), .c_dout32(c_dout32),
    .c_ready(c_ready), .c_busy(c_busy),
    .s_req(1'b0), .s_addr(23'd0), .s_ack(), .s_ready(),
    .f_req(1'b0), .f_ack(),
    .e_req(e_req), .e_we(e_we), .e_word(e_word), .e_addr(e_addr),
    .e_din(e_din), .e_ack(e_ack), .e_ready(e_ready));

  p8x_sdram #(.FREQ(27_000_000)) CTL(
    .clk(clk), .clk_sdram(~clk), .resetn(!rst),
    .rd(c_rd), .wr(c_wr), .wr_word(c_word),
    .addr(c_addr), .din(c_din), .dout(c_dout), .dout32(c_dout32),
    .data_ready(c_ready), .busy(c_busy),
    .st_go(st_go), .st_addr(st_addr), .st_words(st_words),
    .st_valid(st_valid), .st_data(st_data), .st_done(st_done),
    .SDRAM_DQ(dq), .SDRAM_A(m_A), .SDRAM_BA(m_BA), .SDRAM_nCS(m_nCS),
    .SDRAM_nWE(m_nWE), .SDRAM_nRAS(m_nRAS), .SDRAM_nCAS(m_nCAS),
    .SDRAM_CLK(m_CLK), .SDRAM_CKE(m_CKE), .SDRAM_DQM(m_DQM));

  sdram_video #(.FB_BASE(23'd0)) VID(.disp_pg(1'b0),
    .clk(clk), .rst(rst),
    .st_go(st_go), .st_addr(st_addr), .st_words(st_words),
    .st_valid(st_valid), .st_data(st_data), .st_done(st_done),
    .pclk(pclk), .de(de), .r(r), .g(g), .b(b),
    .underruns(underruns), .frame_tick(frame_tick));

  sdram_chip CHIP(.clk(clk), .SDRAM_DQ(dq), .SDRAM_A(m_A), .SDRAM_BA(m_BA),
    .SDRAM_nCS(m_nCS), .SDRAM_nWE(m_nWE), .SDRAM_nRAS(m_nRAS),
    .SDRAM_nCAS(m_nCAS), .SDRAM_CKE(m_CKE), .SDRAM_DQM(m_DQM));

  // ---- CPU-side register pokes ---------------------------------------------
  task poke(input [3:0] reg_a, input [7:0] v);
    begin
      @(posedge clk); sel <= 1; a <= reg_a; wdata <= v; wr <= 1;
      @(posedge clk); wr <= 0; sel <= 0;
    end
  endtask
  task gwait;                               // spin on GSTAT.7, as software does
    begin
      @(posedge clk);
      while (GFX.busy) @(posedge clk);
      repeat (4) @(posedge clk);
    end
  endtask

  // ---- displayed-frame capture: the EDGES of every row ----------------------
  reg [15:0] shown [0:479];               // full row 150
  reg [15:0] ledge [0:271];               // column 0 of every row
  reg [15:0] r477  [0:271];               // column 477 (must be black)
  reg [15:0] redge [0:271];               // column 479 of every row
  integer col, row; reg capturing=0; reg pclk_d=0;
  always @(posedge clk) begin
    pclk_d <= pclk;
    if (capturing && pclk && !pclk_d && de) begin
      if (row == 150 && col < 480) shown[col] = {r, g, b};
      if (col == 0   && row < 272) ledge[row] = {r, g, b};
      if (col == 477 && row < 272) r477[row]  = {r, g, b};
      if (col == 479 && row < 272) redge[row] = {r, g, b};
      col = col + 1;
      if (col == 480) begin col = 0; row = row + 1; end
    end
  end

  integer x, y, i, bad, u0;
  reg [31:0] w;

  initial begin
    bad = 0;
    // sentinel the region so a missing write is visible
    for (y = 0; y < 272; y = y + 1)
      for (x = 0; x < 480; x = x + 2)
        CHIP.mem[(y*1024 + x*2) >> 2] = 32'hBAD0BAD0;

    repeat (4) @(posedge clk); rst = 0;
    wait (!c_busy);                          // controller init done

    // ---- clear black, at the ENGINE's true cadence (BOXFILL: the
    // device CLS is retired, stage-10 diet) --------------------------------
    poke(4'h4, 8'h00);                       // GCOL 0 (clears GCOLH)
    poke(4'h0, 8'h00); poke(4'h1, 8'h00);    // 0,0
    poke(4'h2, 8'hDF); poke(4'hB, 8'h01);    // 479
    poke(4'h3, 8'h0F); poke(4'hC, 8'h01);    // 271
    poke(4'h5, 8'h04);                       // BOXFILL
    gwait;

    // ---- a 1-px white border as FOUR LINEs (BOX outline retired) ----------
    poke(4'h4, 8'hFF); poke(4'hD, 8'hFF);    // pen $FFFF
    poke(4'h0, 8'h00); poke(4'h1, 8'h00);
    poke(4'h2, 8'hDF); poke(4'hB, 8'h01);
    poke(4'h3, 8'h00);
    poke(4'h5, 8'h02); gwait;                // top
    poke(4'h1, 8'h0F); poke(4'hA, 8'h01);
    poke(4'h3, 8'h0F); poke(4'hC, 8'h01);
    poke(4'h5, 8'h02); gwait;                // bottom
    poke(4'h2, 8'h00);
    poke(4'h1, 8'h00);
    poke(4'h5, 8'h02); gwait;                // left
    poke(4'h0, 8'hDF); poke(4'h9, 8'h01);
    poke(4'h2, 8'hDF); poke(4'hB, 8'h01);
    poke(4'h5, 8'h02); gwait;                // right

    // ---- audit 1: the chip's memory, every pixel --------------------------
    for (y = 0; y < 272; y = y + 1)
      for (x = 0; x < 480; x = x + 2) begin
        w = CHIP.mem[(y*1024 + x*2) >> 2];
        if (w === 32'hBAD0BAD0) begin
          if (bad < 8) $display("FAIL: pair (%0d,%0d) NEVER WRITTEN", x, y);
          bad = bad + 1;
        end
      end
    // border in memory: left and right columns of row 150
    if (CHIP.mem[(150*1024) >> 2][15:0] !== 16'hFFFF) begin
      $display("FAIL: left border missing IN MEMORY"); bad = bad + 1; end
    if (CHIP.mem[(150*1024 + 478*2) >> 2][31:16] !== 16'hFFFF) begin
      $display("FAIL: right border missing IN MEMORY"); bad = bad + 1; end

    // ---- audit 2: one DISPLAYED line, pixel for pixel ---------------------
    @(posedge frame_tick); @(posedge frame_tick);   // let the fetch settle
    col = 0; row = 0; capturing = 1;
    @(posedge frame_tick); capturing = 0;
    u0 = underruns;
    if (shown[0]   !== 16'hFFFF) begin
      $display("FAIL: DISPLAYED left border missing (col0=%04x col1=%04x col2=%04x)",
               shown[0], shown[1], shown[2]); bad = bad + 1; end
    if (shown[479] !== 16'hFFFF) begin
      $display("FAIL: DISPLAYED right border missing"); bad = bad + 1; end
    // every row: left edge white, right edge white, col 477 black -- a row
    // whose fetch dropped its first word shows black at 0 and white at 477
    for (i = 1; i < 271; i = i + 1) begin
      if (ledge[i] !== 16'hFFFF) begin
        if (bad < 24) $display("FAIL: row %0d left edge = %04x (first word dropped?)", i, ledge[i]);
        bad = bad + 1;
      end
      if (redge[i] !== 16'hFFFF) begin
        if (bad < 24) $display("FAIL: row %0d right edge = %04x", i, redge[i]);
        bad = bad + 1;
      end
      if (r477[i] !== 16'h0000) begin
        if (bad < 24) $display("FAIL: row %0d col477 = %04x (edge duplicated inward?)", i, r477[i]);
        bad = bad + 1;
      end
    end
    if (shown[478] !== 16'h0000) begin
      $display("FAIL: DISPLAYED col 478 = %04x, want black (doubled edge?)",
               shown[478]); bad = bad + 1; end
    for (i = 1; i < 478; i = i + 1)
      if (shown[i] !== 16'h0000) begin
        if (bad < 20) $display("FAIL: DISPLAYED col %0d = %04x, want black", i, shown[i]);
        bad = bad + 1;
      end

    if (CHIP.protocol_errors != 0) begin
      $display("FAIL: %0d protocol errors", CHIP.protocol_errors); bad = bad + 1; end
    if (bad) begin
      $display("TB-FULL-STACK: FAIL (%0d)", bad);
      $finish(1);
    end
    $display("TB-FULL-STACK: PASS (real engine + real controller + real scanout, CLS complete, border exact)");
    $finish(0);
  end

  initial begin #200_000_000; $display("TB-FULL-STACK: TIMEOUT"); $finish(1); end
endmodule
