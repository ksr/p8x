// tb_gcard.v -- stage-10a GL stream through the REAL pixel stack, and the
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
// TB-GCARD VARIANT: the same scene, but every register access travels as
// CARD-EDGE PROTOCOL BYTES through the real p8x_bridge -- the tasks are
// re-implemented in wire bytes and the scene body is untouched. The frame
// must still equal the emulator's gl_b.ppm: transport proven, pixels
// unchanged.
//
//   iverilog -g2012 -o tbglp tb_gcard.v ../../rtl/p8x_geom.v \
//            ../../rtl/mdu_core.v ../../rtl/trigtab.v ../../rtl/gfx.v \
//            gfx_mem.v gfx_span.v sdram_arb.v p8x_sdram.v sdram_video.v \
//            sdram_chip.v
//   vvp tbglp
`timescale 1ns/1ps
module tb;
  reg clk=0, rst=1; always #5 clk=~clk;

  // ---- the host side of the wire: bytes in, bytes out ----------------------
  reg  [7:0]  rxd = 0;
  reg         rxv = 0;
  wire [7:0]  txd;
  wire        txs;
  reg  [7:0]  rply;                    // last POPPED reply byte
  reg  [7:0]  rq [0:15];               // reply queue: the bridge can answer
  integer     rqw = 0, rqr = 0;        //   faster than a UART would pace it
  always @(posedge clk) if (txs) begin rq[rqw & 15] = txd; rqw = rqw + 1; end
  integer errors = 0;

  wire        gl_sel, gl_wr, gl_rd;    // the bridge drives what the CPU did
  wire        gsel, gwr, grd;
  wire [3:0]  a;
  wire [7:0]  wdata;
  wire [7:0]  rdata, gfx_rdata;

  p8x_bridge BRIDGE(.clk(clk), .rst(rst),
    .rxd(rxd), .rxv(rxv), .txd(txd), .txs(txs), .txb(1'b0),
    .gx_sel(gsel), .gx_wr(gwr), .gx_rd(grd), .gx_rdata(gfx_rdata),
    .gl_sel(gl_sel), .gl_wr(gl_wr), .gl_rd(gl_rd), .gl_rdata(rdata),
    .a(a), .wdata(wdata));

  // ---- the real stack, wired as in p8x_top ---------------------------------
  wire        gm_own, gm_wr;
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
    .gm_rdata(gfx_rdata),
    .frame_tick(frame_tick), .draw_pg(draw_pg), .disp_pg(disp_pg));

  gfx GFX(.clk(clk), .rst(rst), .draw_pg(draw_pg),
    .sel(gm_own ? 1'b1 : gsel),
    .a(gm_own ? gm_a : a),
    .wr(gm_own ? gm_wr : gwr),
    .rd_stb(gm_own ? 1'b0 : grd),
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

  // ---- drivers: every access is protocol bytes through the bridge ----------
  task bsend(input [7:0] v);
    begin
      @(posedge clk); rxd <= v; rxv <= 1;
      @(posedge clk); rxv <= 0;
      repeat (3) @(posedge clk);
    end
  endtask
  task brecv;                                      // pop one reply byte
    integer n;
    begin
      n = 0;
      while (rqr == rqw && n < 10000000) begin @(posedge clk); n = n + 1; end
      if (n >= 10000000) begin
        $display("FAIL: no reply (br.st=%0d brw=%0d brd=%0d cnt=%0d bph=%b | geom glst=%0d state=%0d | rply q %0d/%0d)",
                 BRIDGE.st, BRIDGE.brw, BRIDGE.brd, BRIDGE.cnt, BRIDGE.bph,
                 GEOM.glst, GEOM.state, rqr, rqw);
        $display("  gfx st=%0d busy=%b px_go=%b px_busy=%b mem.st=%0d e_req=%b gm_own=%b sel=%b a=%0d",
                 GFX.st, GFX.busy, GFX.px_go, GFX.px_busy, GFX.u_mem.st,
                 GFX.u_mem.e_req, gm_own, GFX.sel, GFX.a);
        $finish(1);
      end
      rply = rq[rqr & 15]; rqr = rqr + 1;
    end
  endtask
  task brd_reg(input [5:0] ix);
    begin
      bsend(8'h40 | {2'd0, ix}); brecv;
    end
  endtask
  task gpoke(input [3:0] ra, input [7:0] v);       // WRITE $80|idx
    begin
      bsend(8'h80 | {4'd0, ra}); bsend(v);
    end
  endtask
  task gwait;                                      // poll GSTAT.busy
    begin
      brd_reg(6'h06);
      while (rply[7]) brd_reg(6'h06);
    end
  endtask
  // GL stream: collect, then flush as ack'd 64-byte bursts
  reg [7:0] sbuf [0:4095];
  integer   sn = 0;
  task glb(input [7:0] v);
    begin sbuf[sn] = v; sn = sn + 1; end
  endtask
  task glw(input [15:0] v);
    begin glb(v[7:0]); glb(v[15:8]); end
  endtask
  task glflush;
    integer i, n;
    begin
      i = 0;
      while (i < sn) begin
        n = (sn - i > 64) ? 64 : (sn - i);
        bsend(8'h01); bsend(n[7:0]);
        while (n) begin bsend(sbuf[i]); i = i + 1; n = n - 1; end
        brecv;
        if (rply !== 8'h06) begin
          $display("FAIL: burst not acked (%02x)", rply); $finish(1); end
      end
      sn = 0;
    end
  endtask
  task line3(input [15:0] x0,y0,z0,x1,y1,z1);
    begin
      glb(8'h12); glw(x0); glw(y0); glw(z0);        // MOVE3
      glb(8'h2A); glw(x1); glw(y1); glw(z1);        // DRAW3
    end
  endtask
  task gl_wait_idle;                               // STATUS until !busy
    integer n;
    begin
      glflush;
      n = 0;
      bsend(8'h02); brecv;
      while (rply[6] && n < 400000) begin
        bsend(8'h02); brecv; n = n + 1;
      end
      if (n >= 400000) begin
        $display("FAIL: GL never went idle"); errors = errors + 1; end
    end
  endtask

  integer x, y, f;  
  reg [31:0] w;
  reg [15:0] p;
  reg [4:0] r5, b5; reg [5:0] g6;

  initial begin
    repeat (4) @(posedge clk); rst = 0;
    wait (!c_busy);

    // ---- the wire says who it is ------------------------------------------
    bsend(8'h00);                                  // PING
    brecv; if (rply !== "P") begin $display("FAIL: PING[0]=%02x", rply); errors = errors + 1; end
    brecv; if (rply !== "8") errors = errors + 1;
    brecv; if (rply !== "X") errors = errors + 1;
    brecv; if (rply !== "G") errors = errors + 1;
    brecv; if (rply !== 8'd1) begin $display("FAIL: version=%02x", rply); errors = errors + 1; end
    brd_reg(6'h34);
    if (rply !== "G") begin $display("FAIL: GLID=%02x", rply); errors = errors + 1; end
    brd_reg(6'h35);
    if (rply !== 8'd1) begin $display("FAIL: BRIDGEV=%02x", rply); errors = errors + 1; end
    brd_reg(6'h36);
    if (rply !== "B") begin $display("FAIL: BRIDGID=%02x", rply); errors = errors + 1; end
    brd_reg(6'h0D);
    if (rply !== "P") begin $display("FAIL: GID0=%02x", rply); errors = errors + 1; end

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

    // ---- the GL scene: byte for byte what c_gl_test's gl_b.c pokes --------
    glb(8'hB3); glw(-16'sd120); glw(16'sd120); glw(-16'sd120); glw(16'sd120);
    glb(8'hB2); glw(16'sd104); glw(16'sd375); glw(16'sd0); glw(16'sd271);
    glb(8'h07); glb(8'd0); glb(8'd0); glb(8'd0);          // FLOOD = erase
    glb(8'h06); glb(8'd31); glb(8'd63); glb(8'd31);       // COLOR white
    line3(-16'sd90, -16'sd90, 16'sd300,  16'sd90, -16'sd90, 16'sd300);
    glb(8'h06); glb(8'd31); glb(8'd0); glb(8'd0);         // red
    line3( 16'sd90, -16'sd90, 16'sd300,  16'sd0,   16'sd90, 16'sd300);
    glb(8'h06); glb(8'd0); glb(8'd63); glb(8'd0);         // green, clipped
    line3(-16'sd200, 16'sd0,  16'sd300,  16'sd200, 16'sd50, 16'sd300);
    glb(8'h06); glb(8'd0); glb(8'd0); glb(8'd31);         // blue, near-clip
    line3( 16'sd0,   16'sd0, -16'sd50,   16'sd0,   16'sd0,  16'sd300);
    glb(8'hE0); glb(8'd1);                                // PRMFIL 1
    glb(8'h06); glb(8'd31); glb(8'd63); glb(8'd0);        // yellow
    glb(8'h32); glb(8'd3);                                // POLY3 n=3
    glw(-16'sd80); glw(-16'sd80); glw(16'sd300);
    glw( 16'sd80); glw(-16'sd80); glw(16'sd300);
    glw( 16'sd0);  glw( 16'sd40); glw(16'sd420);
    glb(8'h06); glb(8'd0); glb(8'd63); glb(8'd31);        // cyan
    glb(8'h32); glb(8'd3);
    glw( 16'sd100); glw(-16'sd140); glw(16'sd260);
    glw( 16'sd140); glw( 16'sd60);  glw(16'sd260);
    glw(-16'sd40);  glw( 16'sd10);  glw(16'sd200);
    gl_wait_idle;

    // GL idle covers the interpreter+walker; the 2D engine may still be
    // draining its last span to SDRAM -- poll IT too (GCHECK's own rule),
    // then let the write land
    gwait;
    repeat (400) @(posedge clk);

    if (CHIP.protocol_errors != 0) begin
      $display("TB-GCARD: FAIL (%0d protocol errors)", CHIP.protocol_errors);
      $finish(1);
    end

    // ---- dump page 0 as a P6 PPM, the emulator's exact format -------------
    f = $fopen("tb_gcard.ppm", "wb");
    $fwrite(f, "P6\n480 272\n255\n");
    for (y = 0; y < 272; y = y + 1)
      for (x = 0; x < 480; x = x + 1) begin
        w = CHIP.mem[(y*1024 + x*2) >> 2];
        p = x[0] ? w[31:16] : w[15:0];
        r5 = p[15:11]; g6 = p[10:5]; b5 = p[4:0];
        $fwrite(f, "%c%c%c", {r5, r5[4:2]}, {g6, g6[5:4]}, {b5, b5[4:2]});
      end
    $fclose(f);
    if (errors != 0) begin $display("TB-GCARD: %0d FAILURES", errors); $finish(1); end
    $display("TB-GCARD: DONE (tb_gcard.ppm written; compare against the emulator)");
    $finish(0);
  end

  initial begin #400_000_000; $display("TB-GCARD: TIMEOUT"); $finish(1); end
endmodule
