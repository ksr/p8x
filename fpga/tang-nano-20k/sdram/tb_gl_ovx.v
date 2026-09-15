// tb_gl_ovx.v -- the TEXT OVERLAY through the real pixel stack, captured at the
// SCANOUT PINS (not the SDRAM dump), because the overlay composites in
// sdram_video. The same TX* + background GL byte stream the emulator renders is
// poked at GLDATA here through the real p8x_geom + gfx + arbiter + controller +
// sdram chip + sdram_video (with its gtxt), and one full frame of the panel
// r/g/b output is written as a P6 PPM in the emulator's exact 565->888 format.
// c_gl_ovl_rtl_test.sh byte-compares it against the emulator's overlay frame.
//
//   iverilog -g2012 -I../../rtl -o tbovx tb_gl_ovx.v ../../rtl/p8x_geom.v \
//     ../../rtl/mdu_core.v ../../rtl/trigtab.v ../../rtl/gfx.v ../../rtl/gtxt.v \
//     gfx_mem.v gfx_span.v sdram_arb.v p8x_sdram.v sdram_video.v sdram_chip.v
`timescale 1ns/1ps
module tb;
  reg clk=0, rst=1; always #5 clk=~clk;

  reg         gl_sel=0, gl_wr=0;
  reg  [3:0]  a=0;
  reg  [7:0]  wdata=0;
  wire [7:0]  rdata, gfx_rdata;

  wire        gm_own, gm_wr;
  wire [3:0]  gm_a;
  wire [7:0]  gm_wdata;
  wire        draw_pg, disp_pg, frame_tick;

  wire e_req, e_we, e_word, e_ack, e_ready;
  wire [22:0] e_addr;  wire [15:0] e_din;
  wire        c_rd, c_wr, c_word, c_ready, c_busy;
  wire [22:0] c_addr;  wire [15:0] c_din, c_dout;  wire [31:0] c_dout32;
  wire        st_go, st_valid, st_done;
  wire [22:0] st_addr;  wire [8:0] st_words;  wire [31:0] st_data;
  wire        pclk, de; wire [4:0] r, b; wire [5:0] g;
  wire [15:0] underruns;
  wire [31:0] dq;
  wire [10:0] m_A;   wire [1:0] m_BA;
  wire m_nCS, m_nWE, m_nRAS, m_nCAS, m_CLK, m_CKE;  wire [3:0] m_DQM;
  wire        g_req, g_we, g_ack, g_ready;
  wire [22:0] g_addr;  wire [15:0] g_din;

  // text-overlay command channel geom -> sdram_video (gtxt)
  wire        tx_stb, tx_busy;  wire [2:0] tx_op;
  wire [7:0]  tx_p0, tx_p1, tx_p2, tx_p3;

  p8x_geom GEOM(.clk(clk), .rst(rst),
    .a(a), .wdata(wdata), .rdata(rdata),
    .g_req(g_req), .g_we(g_we), .g_addr(g_addr), .g_din(g_din),
    .g_ack(g_ack), .g_ready(g_ready), .g_dout(c_dout),
    .gl_sel(gl_sel), .gl_wr(gl_wr), .gl_rd(1'b0),
    .gm_own(gm_own), .gm_wr(gm_wr), .gm_a(gm_a), .gm_wdata(gm_wdata),
    .gm_rdata(gfx_rdata),
    .frame_tick(frame_tick), .draw_pg(draw_pg), .disp_pg(disp_pg),
    .tx_stb(tx_stb), .tx_op(tx_op),
    .tx_p0(tx_p0), .tx_p1(tx_p1), .tx_p2(tx_p2), .tx_p3(tx_p3),
    .tx_busy(tx_busy));

  gfx GFX(.clk(clk), .rst(rst), .draw_pg(draw_pg),
    .sel(gm_own ? 1'b1 : 1'b0), .a(gm_own ? gm_a : a),
    .wr(gm_own ? gm_wr : 1'b0), .rd_stb(1'b0),
    .wdata(gm_own ? gm_wdata : wdata), .rdata(gfx_rdata),
    .e_req(e_req), .e_we(e_we), .e_word(e_word), .e_addr(e_addr),
    .e_din(e_din), .e_ack(e_ack), .e_ready(e_ready), .e_dout(c_dout));

  sdram_arb ARB(.clk(clk), .rst(rst),
    .c_rd(c_rd), .c_wr(c_wr), .c_wr_word(c_word), .c_refresh(),
    .c_addr(c_addr), .c_din(c_din), .c_dout(c_dout), .c_dout32(c_dout32),
    .c_ready(c_ready), .c_busy(c_busy),
    .s_req(1'b0), .s_addr(23'd0), .s_ack(), .s_ready(),
    .f_req(1'b0), .f_ack(),
    .g_req(g_req), .g_we(g_we), .g_addr(g_addr), .g_din(g_din),
    .g_ack(g_ack), .g_ready(g_ready),
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

  sdram_video #(.FB_BASE(23'd0)) VID(.disp_pg(disp_pg),
    .clk(clk), .rst(rst),
    .tx_stb(tx_stb), .tx_op(tx_op),
    .tx_p0(tx_p0), .tx_p1(tx_p1), .tx_p2(tx_p2), .tx_p3(tx_p3),
    .tx_busy(tx_busy),
    .st_go(st_go), .st_addr(st_addr), .st_words(st_words),
    .st_valid(st_valid), .st_data(st_data), .st_done(st_done),
    .pclk(pclk), .de(de), .r(r), .g(g), .b(b),
    .underruns(underruns), .frame_tick(frame_tick));

  sdram_chip CHIP(.clk(clk), .SDRAM_DQ(dq), .SDRAM_A(m_A), .SDRAM_BA(m_BA),
    .SDRAM_nCS(m_nCS), .SDRAM_nWE(m_nWE), .SDRAM_nRAS(m_nRAS),
    .SDRAM_nCAS(m_nCAS), .SDRAM_CKE(m_CKE), .SDRAM_DQM(m_DQM));

  // ---- GL byte driver (backpressure on GLSTAT bit7) ------------------------
  task glb(input [7:0] v);
    integer n;
    begin
      n = 0; a = 4'h1; gl_sel = 1; #1;
      while (rdata[7] && n < 400000000) begin @(negedge clk); #1; n = n + 1; end
      gl_sel = 0;
      if (n >= 400000000) begin $display("FAIL: FIFO never drained"); $finish(1); end
      @(posedge clk); gl_sel <= 1; gl_wr <= 1; a <= 4'h0; wdata <= v;
      @(posedge clk); gl_wr <= 0; gl_sel <= 0;
      repeat (6) @(posedge clk);
    end
  endtask
  task glw(input [15:0] v); begin glb(v[7:0]); glb(v[15:8]); end endtask
  task gtxt_at(input [7:0] col, row); begin glb(8'h53); glb(col); glb(row); end endtask
  task gtxt_put(input [7:0] ch); begin glb(8'h54); glb(ch); end endtask
  task gl_wait_idle;
    integer n;
    begin
      n = 0; a = 4'h1; gl_sel = 1; #1;
      while (rdata[6] && n < 40000000) begin @(negedge clk); #1; n = n + 1; end
      gl_sel = 0;
      repeat (500) @(posedge clk);
    end
  endtask

  // ---- capture one full scanout frame from the panel pins -----------------
  reg [15:0] frame [0:480*272-1];
  integer col, row;  reg capturing;  reg pclk_d;
  always @(posedge clk) begin
    pclk_d <= pclk;
    if (capturing && pclk && !pclk_d && de) begin
      if (row < 272 && col < 480) frame[row*480 + col] = {r, g, b};
      col = col + 1;
      if (col == 480) begin col = 0; row = row + 1; end
    end
  end

  integer x, y, f;  reg [15:0] p;  reg [4:0] r5, b5;  reg [5:0] g6;
  integer i;
  initial begin
    for (i=0;i<480*272;i=i+1) frame[i]=16'h0000;
    repeat (4) @(posedge clk); rst = 0;
    wait (!c_busy);

    // ---- background: CLEARS blue (both pages), the emulator's ground -------
    glb(8'h0F); glb(8'd0); glb(8'd0); glb(8'd31);

    // ---- text overlay: white "P8X RTL" at cell (2,2) -----------------------
    glb(8'h52); glb(8'd31); glb(8'd63); glb(8'd31);   // TXCOL white
    glb(8'h51); glb(8'd0); glb(8'd0); glb(8'd80); glb(8'd34);  // TXWIN full
    glb(8'h50); glb(8'd1);                            // TXEN 1
    glb(8'h55);                                       // TXCLR
    gtxt_at(8'd2, 8'd2);
    gtxt_put("P"); gtxt_put("8"); gtxt_put("X"); gtxt_put(" ");
    gtxt_put("R"); gtxt_put("T"); gtxt_put("L");
    // a second row + a scroll, to exercise TXSCR
    gtxt_at(8'd2, 8'd4); gtxt_put("Y"); gtxt_put("Z");
    glb(8'h56);                                       // TXSCR (window up one)
    gl_wait_idle;

    if (CHIP.protocol_errors != 0) begin
      $display("TB-GL-OVX: FAIL (%0d protocol errors)", CHIP.protocol_errors);
      $finish(1);
    end

    // let a couple of frames pass, then capture one full frame
    @(posedge VID.frame_tick); @(posedge VID.frame_tick);
    col = 0; row = 0; capturing = 1;
    while (row < 272) @(posedge clk);
    capturing = 0;

    f = $fopen("tb_gl_ovx.ppm", "wb");
    $fwrite(f, "P6\n480 272\n255\n");
    for (y = 0; y < 272; y = y + 1)
      for (x = 0; x < 480; x = x + 1) begin
        p = frame[y*480 + x];
        r5 = p[15:11]; g6 = p[10:5]; b5 = p[4:0];
        $fwrite(f, "%c%c%c", {r5, r5[4:2]}, {g6, g6[5:4]}, {b5, b5[4:2]});
      end
    $fclose(f);
    $display("TB-GL-OVX: DONE (tb_gl_ovx.ppm written)");
    $finish(0);
  end

  initial begin #4_000_000_000; $display("TB-GL-OVX: TIMEOUT"); $finish(1); end
endmodule
