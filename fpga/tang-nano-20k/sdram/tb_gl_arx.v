// tb_gl_arx.v -- the stage-10g AREA/AREABC scene through the REAL pixel
// stack, and the framebuffer OUT as an image.
//
// The byte stream is c_gl_area_test's gl_ar.c scene verbatim: a red
// rectangle outline filled by AREA (pen-bounded), a blue diamond filled
// green by AREABC (stated boundary), and an off-window seed that must
// come back as error 2 with no pixels touched. The fill walks the frame
// through gm POINT probes and paints through gm LINE, with its seed
// stack in SDRAM at $180000 -- everything the silicon will do. The
// chip's framebuffer is dumped in the emulator's exact PPM format and
// the harness byte-compares it against the emulator's gl_ar.ppm:
// fill walker == golden model, every pixel.
//
// The screen is prepared the way the machine's boot leaves it (CLS black +
// the 1-px white border of the boot splash), so untouched pixels compare
// too, not just the scene (the scene's CLEARS then wipes the border on
// both sides identically).
//
//   iverilog -g2012 -I ../../rtl -o tbglar tb_gl_arx.v ../../rtl/p8x_geom.v \
//            ../../rtl/mdu_core.v ../../rtl/trigtab.v ../../rtl/gfx.v \
//            gfx_mem.v gfx_span.v sdram_arb.v p8x_sdram.v sdram_video.v \
//            sdram_chip.v
//   vvp tbglar
`timescale 1ns/1ps
module tb;
  reg clk=0, rst=1; always #5 clk=~clk;

  // ---- CPU-side buses -------------------------------------------------------
  reg         gl_sel=0, gl_wr=0, gl_rd=0; // GL window ($FF50)
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
    .gl_sel(gl_sel), .gl_wr(gl_wr), .gl_rd(gl_rd),
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
      // a fill probes every interior pixel through the arbiter: give the
      // walker room (the rectangle alone is ~5000 pixels, 3 probes each)
      while (rdata[6] && n < 40000000) begin @(negedge clk); #1; n = n + 1; end
      gl_sel = 0;
      if (n >= 40000000) begin $display("TB-GL-ARX: FAIL (never idle)"); $finish(1); end
      // the walker hands the LAST op to the device and idles -- the device
      // (and the controller behind it) may still be drawing it. Software
      // polls GSTAT before touching pixels; the bench must too, plus a
      // settle for the controller's write pipeline.
      gwait;
      repeat (400) @(posedge clk);
    end
  endtask
  task rd_glerr(output [7:0] v);
    begin
      @(negedge clk); gl_sel = 1; a = 4'h3; #1 v = rdata; gl_rd = 1;
      @(negedge clk); gl_sel = 0; gl_rd = 0;
    end
  endtask

  integer x, y, f;
  reg [31:0] w;
  reg [15:0] p;
  reg [4:0] r5, b5; reg [5:0] g6;
  reg [7:0] e0, e1;

  initial begin
    repeat (4) @(posedge clk); rst = 0;
    wait (!c_busy);

    // ---- the boot splash, as the machine leaves it: CLS + white border ----
    gpoke(4'h4, 8'h00);                       // GCOL 0
    gpoke(4'h0, 8'h00); gpoke(4'h1, 8'h00);   // the clear is a BOXFILL now
    gpoke(4'h2, 8'hDF); gpoke(4'hB, 8'h01);   //   (device CLS retired)
    gpoke(4'h3, 8'h0F); gpoke(4'hC, 8'h01);
    gpoke(4'h5, 8'h04);                       // BOXFILL 0,0-479,271
    gwait;
    gpoke(4'h4, 8'hFF); gpoke(4'hD, 8'hFF);   // pen $FFFF; the border is
    gpoke(4'h0, 8'h00); gpoke(4'h1, 8'h00);   //   FOUR LINEs (BOX retired)
    gpoke(4'h2, 8'hDF); gpoke(4'hB, 8'h01);
    gpoke(4'h3, 8'h00);
    gpoke(4'h5, 8'h02); gwait;                // top (0,0)-(479,0)
    gpoke(4'h1, 8'h0F); gpoke(4'hA, 8'h01);
    gpoke(4'h3, 8'h0F); gpoke(4'hC, 8'h01);
    gpoke(4'h5, 8'h02); gwait;                // bottom (0,271)-(479,271)
    gpoke(4'h2, 8'h00);
    gpoke(4'h1, 8'h00);
    gpoke(4'h5, 8'h02); gwait;                // left (0,0)-(0,271)
    gpoke(4'h0, 8'hDF); gpoke(4'h9, 8'h01);
    gpoke(4'h2, 8'hDF); gpoke(4'hB, 8'h01);
    gpoke(4'h5, 8'h02); gwait;                // right (479,0)-(479,271)

    // ---- gl_ar.c's scene, byte for byte -----------------------------------
    glb(8'hB3); glw(16'd0); glw(16'd479); glw(16'd0); glw(16'd271); // WINDOW
    glb(8'hB2); glw(16'd0); glw(16'd479); glw(16'd0); glw(16'd271); // VWPORT
    glb(8'h0F); glb(8'd0); glb(8'd0); glb(8'd0);         // CLEARS black
    // a red rectangle outline, then AREA from inside it
    glb(8'h06); glb(8'd31); glb(8'd0); glb(8'd0);        // COLOR red
    glb(8'h10); glw(16'd100); glw(16'd100);              // MOVE
    glb(8'h34); glw(16'd200); glw(16'd150);              // RECT
    glb(8'h10); glw(16'd150); glw(16'd125);              // MOVE inside
    glb(8'hC0);                                          // AREA
    gl_wait_idle;
    // a blue diamond outline, green AREABC inside it
    glb(8'h06); glb(8'd0); glb(8'd0); glb(8'd31);        // COLOR blue
    glb(8'h30); glb(8'd4);                               // POLY 4
    glw(16'd300); glw(16'd200); glw(16'd350); glw(16'd150);
    glw(16'd400); glw(16'd200); glw(16'd350); glw(16'd250);
    glb(8'h06); glb(8'd0); glb(8'd63); glb(8'd0);        // COLOR green
    glb(8'h10); glw(16'd350); glw(16'd200);              // MOVE centre
    glb(8'hC1); glb(8'd0); glb(8'd0); glb(8'd31);        // AREABC blue
    gl_wait_idle;
    // off-window seed -> error 2, no pixels
    glb(8'h10); glw(-16'sd500); glw(16'sd0);             // MOVE off
    glb(8'hC0);                                          // AREA
    gl_wait_idle;

    rd_glerr(e0); rd_glerr(e1);
    if (e0 !== 8'd2 || e1 !== 8'd0) begin
      $display("TB-GL-ARX: FAIL (GLERR %0d then %0d, wanted 2 then 0)", e0, e1);
      $finish(1);
    end

    if (CHIP.protocol_errors != 0) begin
      $display("TB-GL-ARX: FAIL (%0d protocol errors)", CHIP.protocol_errors);
      $finish(1);
    end

    // ---- dump page 0 as a P6 PPM, the emulator's exact format -------------
    f = $fopen("tb_gl_arx.ppm", "wb");
    $fwrite(f, "P6\n480 272\n255\n");
    for (y = 0; y < 272; y = y + 1)
      for (x = 0; x < 480; x = x + 1) begin
        w = CHIP.mem[(y*1024 + x*2) >> 2];
        p = x[0] ? w[31:16] : w[15:0];
        r5 = p[15:11]; g6 = p[10:5]; b5 = p[4:0];
        $fwrite(f, "%c%c%c", {r5, r5[4:2]}, {g6, g6[5:4]}, {b5, b5[4:2]});
      end
    $fclose(f);
    $display("TB-GL-ARX: DONE (tb_gl_arx.ppm written; compare against the emulator)");
    $finish(0);
  end

  initial begin #2_000_000_000; $display("TB-GL-ARX: TIMEOUT"); $finish(1); end
endmodule
