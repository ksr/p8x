// tb_gl_blx.v -- BLIT (opcode $64) through the REAL pixel stack: the
// single-interface DMA verb (2026-09-01). The byte stream mirrors
// c_gl_blit_test's gl_bl.c VERBATIM -- the row-exact 4x3, the edge
// clip, zero and oversize dims, the recording refusal with the payload
// discarded in sync, and the mapped anchor -- with every PIXRD reply
// popped and CHECKED against the emulator's values, and the frame
// dumped as a PPM for the byte-compare against gl_bl.ppm.
//
//   iverilog -g2012 -o tbglblx tb_gl_prx.v ../../rtl/p8x_geom.v \
//            ../../rtl/mdu_core.v ../../rtl/trigtab.v ../../rtl/gfx.v \
//            gfx_mem.v gfx_span.v sdram_arb.v p8x_sdram.v sdram_video.v \
//            sdram_chip.v
//   vvp tbglblx
`timescale 1ns/1ps
module tb;
  reg clk=0, rst=1; always #5 clk=~clk;

  reg         gl_sel=0, gl_wr=0, gl_rd=0;
  reg  [3:0]  a=0;
  reg  [7:0]  wdata=0;
  wire [7:0]  rdata, gfx_rdata;

  wire        gm_own, gm_wr, gm_rd;
  wire [3:0]  gm_a;
  wire [7:0]  gm_wdata;
  wire        draw_pg, disp_pg, frame_tick;

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
  wire [15:0] underruns;

  wire [31:0] dq;
  wire [10:0] m_A;   wire [1:0] m_BA;
  wire m_nCS, m_nWE, m_nRAS, m_nCAS, m_CLK, m_CKE;
  wire [3:0] m_DQM;

  wire        g_req, g_we, g_ack, g_ready;
  wire [22:0] g_addr;
  wire [15:0] g_din;
  p8x_geom GEOM(.clk(clk), .rst(rst),
    .a(a), .wdata(wdata), .rdata(rdata),
    .g_req(g_req), .g_we(g_we), .g_addr(g_addr), .g_din(g_din),
    .g_ack(g_ack), .g_ready(g_ready), .g_dout(c_dout),
    .gl_sel(gl_sel), .gl_wr(gl_wr), .gl_rd(gl_rd),
    .gm_own(gm_own), .gm_wr(gm_wr), .gm_a(gm_a), .gm_wdata(gm_wdata),
    .gm_rd(gm_rd), .gm_rdata(gfx_rdata),
    .frame_tick(frame_tick), .draw_pg(draw_pg), .disp_pg(disp_pg));

  gfx GFX(.clk(clk), .rst(rst), .draw_pg(draw_pg),
    .sel(gm_own ? 1'b1 : 1'b0),
    .a(gm_own ? gm_a : a),
    .wr(gm_own ? gm_wr : 1'b0),
    .rd_stb(gm_own ? gm_rd : 1'b0),
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
    .st_go(st_go), .st_addr(st_addr), .st_words(st_words),
    .st_valid(st_valid), .st_data(st_data), .st_done(st_done),
    .pclk(pclk), .de(de), .r(r), .g(g), .b(b),
    .underruns(underruns), .frame_tick(frame_tick));

  sdram_chip CHIP(.clk(clk), .SDRAM_DQ(dq), .SDRAM_A(m_A), .SDRAM_BA(m_BA),
    .SDRAM_nCS(m_nCS), .SDRAM_nWE(m_nWE), .SDRAM_nRAS(m_nRAS),
    .SDRAM_nCAS(m_nCAS), .SDRAM_CKE(m_CKE), .SDRAM_DQM(m_DQM));

  // ---- drivers -------------------------------------------------------------
  task gwait;
    begin
      @(posedge clk);
      while (GFX.busy) @(posedge clk);
      repeat (4) @(posedge clk);
    end
  endtask
  task glb(input [7:0] v);                          // one GL stream byte,
    integer n;                                      //   with backpressure
    begin
      n = 0; a = 4'h1; gl_sel = 1; #1;
      while (rdata[7] && n < 1000000) begin @(negedge clk); #1; n = n + 1; end
      gl_sel = 0;
      if (n >= 1000000) begin $display("FAIL: FIFO never drained"); $finish(1); end
      @(posedge clk); gl_sel <= 1; gl_wr <= 1; a <= 4'h0; wdata <= v;
      @(posedge clk); gl_wr <= 0; gl_sel <= 0;
      repeat (6) @(posedge clk);                    // CPU-poke pacing
    end
  endtask
  task glw(input [15:0] v);
    begin glb(v[7:0]); glb(v[15:8]); end
  endtask
  task gl_wait_idle;
    integer n;
    begin
      n = 0; a = 4'h1; gl_sel = 1; #1;
      while (rdata[6] && n < 4000000) begin @(negedge clk); #1; n = n + 1; end
      gl_sel = 0;
      if (n >= 4000000) begin $display("TB-GL-BLX: FAIL (never idle)"); $finish(1); end
      gwait;
      repeat (400) @(posedge clk);
    end
  endtask
  task rd_glrb(output [7:0] v);       // pop one read-back byte
    integer n;
    begin
      n = 0; a = 4'h1; gl_sel = 1; #1;              // wait for a byte
      while (!rdata[0] && n < 4000000) begin @(negedge clk); #1; n = n + 1; end
      gl_sel = 0;
      if (n >= 4000000) begin $display("TB-GL-BLX: FAIL (RB never filled)"); $finish(1); end
      @(negedge clk); gl_sel = 1; a = 4'h2; #1 v = rdata; gl_rd = 1;
      @(negedge clk); gl_sel = 0; gl_rd = 0;
    end
  endtask
  reg [7:0] e0, e1;
  integer errors = 0;
  integer gi, gj;
  task rd_glerr(output [7:0] v);      // pop one error byte
    begin
      @(negedge clk); gl_sel = 1; a = 4'h3; #1 v = rdata; gl_rd = 1;
      @(negedge clk); gl_sel = 0; gl_rd = 0;
    end
  endtask
  task expw(input [15:0] want, input [127:0] what);
    begin
      gl_wait_idle;
      rd_glrb(e0); rd_glrb(e1);
      if ({e1, e0} !== want) begin
        $display("FAIL: %0s = %04X, want %04X", what, {e1, e0}, want);
        errors = errors + 1;
      end
    end
  endtask

  integer x, y, f;
  reg [31:0] w;
  reg [15:0] p;
  reg [4:0] r5, b5; reg [5:0] g6;

  initial begin
    repeat (4) @(posedge clk); rst = 0;
    wait (!c_busy);

    // ---- gl_bl.c's stream, byte for byte ---------------------------------
    glb(8'h04);                                          // RESETF
    glb(8'hB3); glw(16'd0); glw(16'd479); glw(16'd0); glw(16'd271); // WINDOW
    glb(8'hB2); glw(16'd0); glw(16'd479); glw(16'd0); glw(16'd271); // VWPORT
    glb(8'h0F); glb(8'd0); glb(8'd0); glb(8'd0);         // CLEARS black
    // 4x3 blit at (100,50), payload 1000..1011 row-major top-down
    glb(8'h64); glw(16'd100); glw(16'd50); glw(16'd4); glw(16'd3);
    for (gi = 0; gi < 12; gi = gi + 1) glw(16'd1000 + gi[15:0]);
    for (gi = 0; gi < 3; gi = gi + 1)
      for (gj = 0; gj < 4; gj = gj + 1) begin
        glb(8'h63); glw(16'd100 + gj[15:0]); glw(16'd52 - gi[15:0]);
        expw(16'd1000 + gi[15:0]*4 + gj[15:0], "4x3 pixel");
      end
    glb(8'h63); glw(16'd99);  glw(16'd51); expw(16'h0000, "left border");
    glb(8'h63); glw(16'd104); glw(16'd51); expw(16'h0000, "right border");
    glb(8'h63); glw(16'd100); glw(16'd53); expw(16'h0000, "above");
    glb(8'h63); glw(16'd100); glw(16'd49); expw(16'h0000, "below");
    // edge clip: 4 wide at x=478
    glb(8'h64); glw(16'd478); glw(16'd50); glw(16'd4); glw(16'd1);
    glw(16'd2001); glw(16'd2002); glw(16'd2003); glw(16'd2004);
    glb(8'h63); glw(16'd478); glw(16'd50); expw(16'd2001, "clip 478");
    glb(8'h63); glw(16'd479); glw(16'd50); expw(16'd2002, "clip 479");
    glb(8'h63); glw(16'd0);   glw(16'd50); expw(16'h0000, "no wrap 0");
    glb(8'h63); glw(16'd1);   glw(16'd50); expw(16'h0000, "no wrap 1");
    // w=0: no payload owed
    glb(8'h64); glw(16'd10); glw(16'd10); glw(16'd0); glw(16'd5);
    glb(8'h06); glb(8'd31); glb(8'd0); glb(8'd0);        // COLOR red
    glb(8'h10); glw(16'd10); glw(16'd10); glb(8'h08);    // MOVE + POINT
    glb(8'h63); glw(16'd10); glw(16'd10); expw(16'hF800, "after w=0");
    // w>512: err2, no payload owed
    glb(8'h64); glw(16'd10); glw(16'd20); glw(16'd600); glw(16'd1);
    gl_wait_idle;
    rd_glerr(e0); rd_glerr(e1);
    if (e0 !== 8'd2 || e1 !== 8'd0) begin
      $display("FAIL: oversize dims GLERR %0d %0d, want 2 0", e0, e1);
      errors = errors + 1; end
    glb(8'h10); glw(16'd12); glw(16'd10); glb(8'h08);
    glb(8'h63); glw(16'd12); glw(16'd10); expw(16'hF800, "after err2");
    // recording refusal: err2, payload eaten + DISCARDED, sync kept
    glb(8'h70); glb(8'd9);                               // CLBEG 9
    glb(8'h64); glw(16'd30); glw(16'd30); glw(16'd2); glw(16'd2);
    glw(16'd3001); glw(16'd3002); glw(16'd3003); glw(16'd3004);
    glb(8'h71);                                          // CLEND
    gl_wait_idle;
    rd_glerr(e0); rd_glerr(e1);
    if (e0 !== 8'd2 || e1 !== 8'd0) begin
      $display("FAIL: recording refusal GLERR %0d %0d, want 2 0", e0, e1);
      errors = errors + 1; end
    glb(8'h72); glb(8'd9);                               // CLRUN 9: empty
    glb(8'h63); glw(16'd30); glw(16'd30); expw(16'h0000, "nothing recorded");
    // mapped window moves the ANCHOR only
    glb(8'hB3); glw(-16'sd120); glw(16'd120); glw(-16'sd120); glw(16'd120);
    glb(8'hB2); glw(16'd104); glw(16'd375); glw(16'd0); glw(16'd271);
    glb(8'h64); glw(16'd0); glw(16'd0); glw(16'd2); glw(16'd1);
    glw(16'd4001); glw(16'd4002);
    glb(8'hB3); glw(16'd0); glw(16'd479); glw(16'd0); glw(16'd271);
    glb(8'hB2); glw(16'd0); glw(16'd479); glw(16'd0); glw(16'd271);
    glb(8'h63); glw(16'd239); glw(16'd135); expw(16'd4001, "mapped anchor");
    glb(8'h63); glw(16'd240); glw(16'd135); expw(16'd4002, "mapped anchor+1");

    gl_sel = 1; a = 4'h1; #1;
    if (rdata[0]) begin
      $display("FAIL: RB not drained at the end"); errors = errors + 1; end
    gl_sel = 0;
    a = 4'h3; gl_sel = 1; #1;                            // GLERR pop
    if (rdata !== 8'd0) begin
      $display("FAIL: GLERR %0d at the end, want 0", rdata);
      errors = errors + 1; end
    gl_sel = 0;

    if (errors != 0) begin
      $display("TB-GL-BLX: FAIL (%0d errors)", errors); $finish(1); end
    // ---- dump page 0 as a P6 PPM, the emulator's exact format ----------
    f = $fopen("tb_gl_blx.ppm", "wb");
    $fwrite(f, "P6\n480 272\n255\n");
    for (y = 0; y < 272; y = y + 1)
      for (x = 0; x < 480; x = x + 1) begin
        w = CHIP.mem[(y*1024 + x*2) >> 2];
        p = x[0] ? w[31:16] : w[15:0];
        r5 = p[15:11]; g6 = p[10:5]; b5 = p[4:0];
        $fwrite(f, "%c%c%c", {r5, r5[4:2]}, {g6, g6[5:4]}, {b5, b5[4:2]});
      end
    $fclose(f);
    $display("TB-GL-BLX: DONE (all reads exact; tb_gl_blx.ppm written)");
    $finish(0);
  end
endmodule
