// tb_gl_fpx.v -- stage-10a GL stream through the REAL pixel stack, and the
// framebuffer OUT as an image.
//
// tb_gl proves the interpreter issues the right OPS (directed constants). This bench closes the last gap to the emulator: the
// same GL byte stream c_gl_test feeds the emulator (its gl_b.c scene) is
// poked at GLDATA here, through the real p8x_geom + gfx + arbiter +
// controller + sdram chip model, and the chip's memory is then dumped as a
// P6 PPM in the emulator's exact format (bit-replicated 565->888). The
// harness (c_gl_rtl_test.sh) byte-compares it against the emulator's
// gl_b.ppm: RTL pixels == emulator pixels, the whole frame.
//
// The screen is prepared the way the machine's boot leaves it (CLS black +
// the 1-px white border of the boot splash), so untouched pixels compare
// too, not just the scene.
//
//   iverilog -g2012 -o tbglp tb_gl_fpx.v ../../rtl/p8x_geom.v \
//            ../../rtl/mdu_core.v ../../rtl/trigtab.v ../../rtl/gfx.v \
//            gfx_mem.v gfx_span.v sdram_arb.v p8x_sdram.v sdram_video.v \
//            sdram_chip.v
//   vvp tbglp
`timescale 1ns/1ps
module tb;
  reg clk=0, rst=1; always #5 clk=~clk;

  // ---- CPU-side buses -------------------------------------------------------
  reg         gl_sel=0, gl_wr=0;       // GL window ($FF50)
  reg         gsel=0, gwr=0;           // gfx window ($FF20, boot replica)
  reg  [3:0]  a=0;
  reg  [7:0]  wdata=0;
  wire [7:0]  rdata, gfx_rdata;

  // ---- the real stack, wired as in p8x_top ---------------------------------
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
    .gl_sel(gl_sel), .gl_wr(gl_wr), .gl_rd(1'b0),
    .gm_own(gm_own), .gm_wr(gm_wr), .gm_rd(gm_rd), .gm_a(gm_a), .gm_wdata(gm_wdata),
    .gm_rdata(gfx_rdata),
    .frame_tick(frame_tick), .draw_pg(draw_pg), .disp_pg(disp_pg));

  gfx GFX(.clk(clk), .rst(rst), .draw_pg(draw_pg),
    .sel(gm_own ? 1'b1 : gsel),
    .a(gm_own ? gm_a : a),
    .wr(gm_own ? gm_wr : gwr),
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
  task gpoke(input [3:0] ra, input [7:0] v);       // gfx registers (boot)
    begin
      @(posedge clk); gsel <= 1; a <= ra; wdata <= v; gwr <= 1;
      @(posedge clk); gwr <= 0; gsel <= 0;
    end
  endtask
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
      while (rdata[7] && n < 10000000) begin @(negedge clk); #1; n = n + 1; end
      gl_sel = 0;
      if (n >= 10000000) begin $display("FAIL: FIFO never drained"); $finish(1); end
      @(posedge clk); gl_sel <= 1; gl_wr <= 1; a <= 4'h0; wdata <= v;
      @(posedge clk); gl_wr <= 0; gl_sel <= 0;
      repeat (6) @(posedge clk);                    // CPU-poke pacing
    end
  endtask
  task glw(input [15:0] v);
    begin glb(v[7:0]); glb(v[15:8]); end
  endtask
  task line3(input [15:0] x0,y0,z0,x1,y1,z1);
    begin
      glb(8'h12); glw(x0); glw(y0); glw(z0);        // MOVE3
      glb(8'h2A); glw(x1); glw(y1); glw(z1);        // DRAW3
    end
  endtask
  task gl_wait_idle;
    integer n;
    begin
      n = 0; a = 4'h1; gl_sel = 1; #1;
      while (rdata[6] && n < 4000000) begin @(negedge clk); #1; n = n + 1; end
      gl_sel = 0;
      if (n >= 4000000) begin $display("TB-GL-FPX: FAIL (never idle)"); $finish(1); end
      // the walker hands the LAST op to the device and idles -- the device
      // (and the controller behind it) may still be drawing it. Software
      // polls GSTAT before touching pixels; the bench must too, plus a
      // settle for the controller's write pipeline.
      gwait;
      repeat (400) @(posedge clk);
    end
  endtask

  integer x, y, f;
  reg [31:0] w;
  reg [15:0] p;
  reg [4:0] r5, b5; reg [5:0] g6;
initial begin
    repeat (4) @(posedge clk); rst = 0;
    wait (!c_busy);

    // ---- the boot splash, as the machine leaves it: CLS + white border ----
    gpoke(4'h4, 8'h00);                       // GCOL 0
    gpoke(4'h5, 8'h05);                       // CLS
    gwait;
    gpoke(4'h4, 8'hFF); gpoke(4'hD, 8'hFF);   // pen $FFFF
    gpoke(4'h0, 8'h00); gpoke(4'h1, 8'h00);
    gpoke(4'h2, 8'hDF); gpoke(4'hB, 8'h01);   // 479
    gpoke(4'h3, 8'h0F); gpoke(4'hC, 8'h01);   // 271
    gpoke(4'h5, 8'h03);                       // BOX outline
    gwait;

    // ---- the GL scene: byte for byte what c_gl_lf_test's gl_lf.c pokes
    // (stage 10f: LINFUN modes on the pixel path; fills stay replace) ----
    glb(8'hB3); glw(16'sd0); glw(16'sd479); glw(16'sd0); glw(16'sd271);
    glb(8'hB2); glw(16'sd0); glw(16'sd479); glw(16'sd0); glw(16'sd271);
    glb(8'h0F); glb(8'd0); glb(8'd0); glb(8'd0);          // CLEARS
    glb(8'h06); glb(8'd0); glb(8'd0); glb(8'd31);         // COLOR blue
    glb(8'hE0); glb(8'd1);                                // PRMFIL 1
    glb(8'h10); glw(16'sd100); glw(16'sd100);             // MOVE
    glb(8'h34); glw(16'sd200); glw(16'sd120);             // RECT (filled)
    glb(8'hE0); glb(8'd0);                                // PRMFIL 0
    glb(8'h06); glb(8'd31); glb(8'd0); glb(8'd0);         // COLOR red
    glb(8'hEB); glb(8'd4);                                // LINFUN 4: XOR
    glb(8'h10); glw(16'sd90);  glw(16'sd110);
    glb(8'h28); glw(16'sd210); glw(16'sd110);
    glb(8'hEB); glb(8'd1);                                // complement
    glb(8'h10); glw(16'sd90);  glw(16'sd130);
    glb(8'h28); glw(16'sd210); glw(16'sd130);
    glb(8'hEB); glb(8'd2);                                // OR
    glb(8'h10); glw(16'sd90);  glw(16'sd140);
    glb(8'h28); glw(16'sd210); glw(16'sd140);
    glb(8'hEB); glb(8'd9);                                // bad -> err2 only
    glb(8'h04);                                           // RESETF
    gl_wait_idle;

    if (CHIP.protocol_errors != 0) begin
      $display("TB-GL-FPX: FAIL (%0d protocol errors)", CHIP.protocol_errors);
      $finish(1);
    end

    // ---- dump page 0 as a P6 PPM, the emulator's exact format -------------
    f = $fopen("tb_gl_fpx.ppm", "wb");
    $fwrite(f, "P6\n480 272\n255\n");
    for (y = 0; y < 272; y = y + 1)
      for (x = 0; x < 480; x = x + 1) begin
        w = CHIP.mem[(y*1024 + x*2) >> 2];
        p = x[0] ? w[31:16] : w[15:0];
        r5 = p[15:11]; g6 = p[10:5]; b5 = p[4:0];
        $fwrite(f, "%c%c%c", {r5, r5[4:2]}, {g6, g6[5:4]}, {b5, b5[4:2]});
      end
    $fclose(f);
    $display("TB-GL-FPX: DONE (tb_gl_fpx.ppm written; compare against the emulator)");
    $finish(0);
  end

  initial begin #400_000_000; $display("TB-GL-FPX: TIMEOUT"); $finish(1); end
endmodule
