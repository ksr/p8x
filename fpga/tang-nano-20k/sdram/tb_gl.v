// tb_gl.v -- the stage-10a GL command port and hex interpreter
// (STAGE10-DESIGN.md), bench 3 of the verification ladder.
//
// The oracle for the 3D verbs is EQUALITY OF THE OP STREAM: one mixed scene
// (two coloured LINEs and a filled TRI) is rendered first through the
// stage-9 record engine (upload + RENDER -- the path tb_geom pins against
// the host replica) and then as a GL hex command stream. The gfx stub
// records every register-level operation both times; the two recordings
// must match op for op -- the language is a transport, not new pixels.
// (The absolute pixel truth chain is: tb_geom + the emulator suites; the
// emulator's own c_gl_test does the framebuffer byte-compare.)
//
// On top of that: absolute 2D-verb checks against the exact 1:1 window
// mapping (mapx(x)=x, mapy(y)=135-y), the filled RECT's clamped box, the
// CLEARS both-pages rule (two full-screen fills, draw page toggled between
// and restored), WAIT's frame pacing, GLID, GLSTAT and the error FIFO.
//
//   iverilog -g2012 -o tbgl tb_gl.v ../../rtl/p8x_geom.v ../../rtl/mdu_core.v ../../rtl/trigtab.v
//   ./tbgl
`timescale 1ns/1ps

module tb;
  reg clk = 0, rst = 1;
  always #5 clk = ~clk;

  reg        sel = 0, wr = 0;
  reg        gl_sel = 0, gl_wr = 0, gl_rd = 0;
  reg  [3:0] a = 0;
  reg  [7:0] wdata = 0;
  wire [7:0] rdata;

  wire        gm_own, gm_wr;
  wire [3:0]  gm_a;
  wire [7:0]  gm_wdata;
  reg  [7:0]  gm_rdata;
  wire        g_req, g_we;
  wire [22:0] g_addr;
  wire [15:0] g_din;
  reg         g_ack = 0, g_ready = 0;
  reg  [15:0] g_dout = 0;
  reg         frame_tick = 0;
  wire        draw_pg, disp_pg;

  p8x_geom dut(.clk(clk), .rst(rst),
               .sel(sel), .a(a), .wr(wr), .wdata(wdata), .rdata(rdata),
               .gl_sel(gl_sel), .gl_wr(gl_wr), .gl_rd(gl_rd),
               .gm_own(gm_own), .gm_wr(gm_wr), .gm_a(gm_a),
               .gm_wdata(gm_wdata), .gm_rdata(gm_rdata),
               .g_req(g_req), .g_we(g_we), .g_addr(g_addr), .g_din(g_din),
               .g_ack(g_ack), .g_ready(g_ready), .g_dout(g_dout),
               .frame_tick(frame_tick), .draw_pg(draw_pg), .disp_pg(disp_pg));

  integer errors = 0;

  // ---- SDRAM stub: the list memory, 3-cycle acks --------------------------
  reg [15:0] lmem [0:8191];
  reg [1:0]  glat = 0;
  always @(posedge clk) begin
    g_ack <= 0; g_ready <= 0;
    if (g_req && !g_ack && glat != 3) glat <= glat + 2'd1;
    else if (g_req && glat == 3) begin
      glat <= 0;
      g_ack <= 1;
      if (g_we) lmem[(g_addr - 23'h100000) >> 1] <= g_din;
      else begin g_dout <= lmem[(g_addr - 23'h100000) >> 1]; g_ready <= 1; end
    end
  end

  // ---- gfx stub: record EVERY drawing op as (cmd, pen, box) ---------------
  // op codes: 2 = LINE, 4 = BOXFILL (the only commands the engine issues)
  reg [15:0] rx0, ry0, rx1, ry1, rcolr;
  reg [3:0]  gbusy = 0;
  reg [7:0]  op_cmd [0:255];
  reg [15:0] op_x0 [0:255]; reg [15:0] op_y0 [0:255];
  reg [15:0] op_x1 [0:255]; reg [15:0] op_y1 [0:255];
  reg [15:0] op_pen [0:255];
  reg        op_pg  [0:255];        // draw page at issue time (CLEARS check)
  integer    nops = 0;
  always @(posedge clk) begin
    if (gbusy != 0) gbusy <= gbusy - 4'd1;
    if (gm_own && gm_wr) begin
      case (gm_a)
        4'h0: rx0   <= {8'd0, gm_wdata};
        4'h1: ry0   <= {8'd0, gm_wdata};
        4'h2: rx1   <= {8'd0, gm_wdata};
        4'h3: ry1   <= {8'd0, gm_wdata};
        4'h9: rx0   <= {gm_wdata, rx0[7:0]};
        4'hA: ry0   <= {gm_wdata, ry0[7:0]};
        4'hB: rx1   <= {gm_wdata, rx1[7:0]};
        4'hC: ry1   <= {gm_wdata, ry1[7:0]};
        4'h4: rcolr <= {8'd0, gm_wdata};
        4'hD: rcolr <= {gm_wdata, rcolr[7:0]};
        4'h5: begin
          gbusy <= 4'd6;
          op_cmd[nops] <= gm_wdata;
          op_x0[nops] <= rx0; op_y0[nops] <= ry0;
          op_x1[nops] <= rx1; op_y1[nops] <= ry1;
          op_pen[nops] <= rcolr; op_pg[nops] <= draw_pg;
          nops = nops + 1;
        end
        default: ;
      endcase
    end
  end
  always @(*) gm_rdata = (gm_a == 4'h6) ? {(gbusy != 0), 7'd0} : 8'hFF;

  // frame_tick every 500 cycles
  integer ftc = 0;
  always @(posedge clk) begin
    ftc = ftc + 1;
    frame_tick <= (ftc % 500 == 0);
  end

  // ---- drivers -------------------------------------------------------------
  task wr8(input [3:0] ra, input [7:0] v);
    begin
      @(negedge clk); sel = 1; wr = 1; a = ra; wdata = v;
      @(negedge clk); sel = 0; wr = 0;
    end
  endtask
  task wpar(input [4:0] idx, input [15:0] v);
    begin
      wr8(4'h0, {3'd0, idx});
      wr8(4'h1, v[7:0]);
      wr8(4'hA, v[15:8]);
    end
  endtask
  task up16(input [15:0] v);
    begin
      wr8(4'h2, v[7:0]);  repeat (6) @(negedge clk);
      wr8(4'h2, v[15:8]); repeat (6) @(negedge clk);
    end
  endtask
  // GL port pokes: same 6-cycle pacing a real CPU beats by 10x
  task glb(input [7:0] v);
    begin
      @(negedge clk); gl_sel = 1; gl_wr = 1; a = 4'h0; wdata = v;
      @(negedge clk); gl_sel = 0; gl_wr = 0;
      repeat (6) @(negedge clk);
    end
  endtask
  task glw(input [15:0] v);
    begin glb(v[7:0]); glb(v[15:8]); end
  endtask
  task gl_wait_idle;
    integer n;
    begin
      n = 0; a = 4'h1; gl_sel = 1; #1;
      // GLSTAT bit6 = interpreter busy; also wait out the walker via GESTAT
      while (rdata[6] && n < 400000) begin @(negedge clk); #1; n = n + 1; end
      gl_sel = 0; a = 4'h4; sel = 1; #1;
      while (rdata[7] && n < 400000) begin @(negedge clk); #1; n = n + 1; end
      sel = 0;
      if (n >= 400000) begin
        $display("FAIL: GL never went idle"); errors = errors + 1; end
    end
  endtask
  task rd_glerr(output [7:0] v);
    begin
      @(negedge clk); gl_sel = 1; a = 4'h3; #1 v = rdata; gl_rd = 1;
      @(negedge clk); gl_sel = 0; gl_rd = 0;
    end
  endtask

  // saved first recording (the record-engine pass)
  reg [7:0]  sv_cmd [0:255];
  reg [15:0] sv_x0 [0:255]; reg [15:0] sv_y0 [0:255];
  reg [15:0] sv_x1 [0:255]; reg [15:0] sv_y1 [0:255];
  reg [15:0] sv_pen [0:255];
  integer    nsv = 0;
  integer    i;
  reg [7:0]  e0, e1, e2, e3;

  initial begin
    repeat (4) @(negedge clk); rst = 0; repeat (2) @(negedge clk);

    // ---- GLID probe -------------------------------------------------------
    a = 4'h4; gl_sel = 1; #1;
    if (rdata !== 8'h47) begin
      $display("FAIL: GLID != 'G' (%02X)", rdata); errors = errors + 1; end
    gl_sel = 0;

    // ==== pass 1: the scene through the stage-9 record engine =============
    wpar(5'd13, -16'sd120); wpar(5'd14, -16'sd120);
    wpar(5'd15,  16'sd120); wpar(5'd16,  16'sd120);
    wpar(5'd17,  16'sd104); wpar(5'd18,  16'sd0);
    wpar(5'd19,  16'sd375); wpar(5'd20,  16'sd271);
    wpar(5'd12,  16'sd256);
    wpar(5'd21,  16'sd1);                     // erase, no flip
    wr8(4'h3, 8'h01);                         // rewind
    // LINE white, LINE clipped green, TRI filled red (the emulator scene's
    // shape: plain + window-clipped + a fill)
    up16(16'h0001); up16(16'hFFFF);
    up16(-16'sd90); up16(-16'sd90); up16(16'sd300);
    up16( 16'sd90); up16(-16'sd90); up16(16'sd300);
    up16(16'h0001); up16(16'h07E0);
    up16(-16'sd200); up16(16'sd0); up16(16'sd300);
    up16( 16'sd200); up16(16'sd50); up16(16'sd300);
    up16(16'h0102); up16(16'hF800);           // TRI, FILL
    up16(-16'sd80); up16(-16'sd80); up16(16'sd300);
    up16( 16'sd80); up16(-16'sd80); up16(16'sd300);
    up16( 16'sd0);  up16( 16'sd40); up16(16'sd420);
    wpar(5'd22, 16'sd3);
    nops = 0;
    wr8(4'h3, 8'h02);                         // RENDER
    a = 4'h4; sel = 1;
    while (rdata[7]) @(negedge clk);
    sel = 0;
    // save the recording
    nsv = nops;
    for (i = 0; i < nops; i = i + 1) begin
      sv_cmd[i] = op_cmd[i];
      sv_x0[i] = op_x0[i]; sv_y0[i] = op_y0[i];
      sv_x1[i] = op_x1[i]; sv_y1[i] = op_y1[i];
      sv_pen[i] = op_pen[i];
    end

    // ==== pass 2: the SAME scene as a GL hex stream ========================
    nops = 0;
    glb(8'hB3); glw(-16'sd120); glw(16'sd120); glw(-16'sd120); glw(16'sd120);
    glb(8'hB2); glw(16'sd104); glw(16'sd375); glw(16'sd0); glw(16'sd271);
    glb(8'h07); glb(8'd0); glb(8'd0); glb(8'd0);        // FLOOD 0 = the erase
    glb(8'h06); glb(8'd31); glb(8'd63); glb(8'd31);     // COLOR white
    glb(8'h12); glw(-16'sd90); glw(-16'sd90); glw(16'sd300);   // MOVE3
    glb(8'h2A); glw( 16'sd90); glw(-16'sd90); glw(16'sd300);   // DRAW3
    glb(8'h06); glb(8'd0); glb(8'd63); glb(8'd0);       // COLOR green
    glb(8'h12); glw(-16'sd200); glw(16'sd0); glw(16'sd300);
    glb(8'h2A); glw( 16'sd200); glw(16'sd50); glw(16'sd300);
    glb(8'hE0); glb(8'd1);                              // PRMFIL 1
    glb(8'h06); glb(8'd31); glb(8'd0); glb(8'd0);       // COLOR red
    glb(8'h32); glb(8'd3);                              // POLY3 n=3
    glw(-16'sd80); glw(-16'sd80); glw(16'sd300);
    glw( 16'sd80); glw(-16'sd80); glw(16'sd300);
    glw( 16'sd0);  glw( 16'sd40); glw(16'sd420);
    gl_wait_idle;
    if (nops !== nsv) begin
      $display("FAIL: GL pass drew %0d ops, record pass drew %0d", nops, nsv);
      errors = errors + 1;
    end else begin
      for (i = 0; i < nsv; i = i + 1)
        if (op_cmd[i] !== sv_cmd[i] || op_pen[i] !== sv_pen[i] ||
            op_x0[i] !== sv_x0[i] || op_y0[i] !== sv_y0[i] ||
            op_x1[i] !== sv_x1[i] || op_y1[i] !== sv_y1[i]) begin
          $display("FAIL: op %0d differs: GL cmd=%0d pen=%04X (%0d,%0d)-(%0d,%0d), record cmd=%0d pen=%04X (%0d,%0d)-(%0d,%0d)",
                   i, op_cmd[i], op_pen[i], op_x0[i], op_y0[i], op_x1[i], op_y1[i],
                   sv_cmd[i], sv_pen[i], sv_x0[i], sv_y0[i], sv_x1[i], sv_y1[i]);
          errors = errors + 1;
        end
      if (nsv < 10) begin
        $display("FAIL: only %0d ops recorded -- scene too small to trust", nsv);
        errors = errors + 1;
      end
    end

    // ==== 2D verbs: exact 1:1 mapping (mapx(x)=x, mapy(y)=135-y) ==========
    glb(8'hB3); glw(16'sd0); glw(16'sd239); glw(16'sd0); glw(16'sd135);
    glb(8'hB2); glw(16'sd0); glw(16'sd239); glw(16'sd0); glw(16'sd135);
    glb(8'hE0); glb(8'd0);                              // PRMFIL 0
    glb(8'h06); glb(8'd31); glb(8'd63); glb(8'd31);     // COLOR white
    nops = 0;
    glb(8'h10); glw(16'sd10); glw(16'sd10);             // MOVE 10 10
    glb(8'h28); glw(16'sd50); glw(16'sd10);             // DRAW 50 10
    glb(8'h29); glw(16'sd0);  glw(16'sd30);             // DRAWR 0 30
    glb(8'hE0); glb(8'd1);                              // PRMFIL 1
    glb(8'h06); glb(8'd31); glb(8'd0); glb(8'd0);       // COLOR red
    glb(8'h10); glw(16'sd60); glw(16'sd20);             // MOVE 60 20
    glb(8'h34); glw(16'sd80); glw(16'sd40);             // RECT 80 40 (fill)
    glb(8'h06); glb(8'd0); glb(8'd63); glb(8'd0);       // COLOR green
    // RECT does not move the current point: still (60,20) after the fill
    glb(8'h11); glw(-16'sd55); glw(-16'sd15);           // MOVER: to 5 5
    glb(8'h08);                                         // POINT
    gl_wait_idle;
    if (nops !== 4) begin
      $display("FAIL: 2D pass drew %0d ops, want 4", nops); errors = errors + 1;
    end else begin
      if (op_cmd[0] !== 8'h02 || op_pen[0] !== 16'hFFFF ||
          op_x0[0] !== 16'd10 || op_y0[0] !== 16'd125 ||
          op_x1[0] !== 16'd50 || op_y1[0] !== 16'd125) begin
        $display("FAIL: DRAW line wrong (%0d,%0d)-(%0d,%0d)",
                 op_x0[0], op_y0[0], op_x1[0], op_y1[0]); errors = errors + 1; end
      if (op_cmd[1] !== 8'h02 ||
          op_x0[1] !== 16'd50 || op_y0[1] !== 16'd125 ||
          op_x1[1] !== 16'd50 || op_y1[1] !== 16'd95) begin
        $display("FAIL: DRAWR line wrong (%0d,%0d)-(%0d,%0d)",
                 op_x0[1], op_y0[1], op_x1[1], op_y1[1]); errors = errors + 1; end
      if (op_cmd[2] !== 8'h04 || op_pen[2] !== 16'hF800 ||
          op_x0[2] !== 16'd60 || op_y0[2] !== 16'd95 ||
          op_x1[2] !== 16'd80 || op_y1[2] !== 16'd115) begin
        $display("FAIL: RECT box wrong pen=%04X (%0d,%0d)-(%0d,%0d)",
                 op_pen[2], op_x0[2], op_y0[2], op_x1[2], op_y1[2]);
        errors = errors + 1; end
      if (op_cmd[3] !== 8'h02 || op_pen[3] !== 16'h07E0 ||
          op_x0[3] !== 16'd5 || op_y0[3] !== 16'd130 ||
          op_x1[3] !== 16'd5 || op_y1[3] !== 16'd130) begin
        $display("FAIL: POINT wrong (%0d,%0d)-(%0d,%0d)",
                 op_x0[3], op_y0[3], op_x1[3], op_y1[3]); errors = errors + 1; end
    end

    // ==== CLEARS: two full-screen fills, page toggled between =============
    nops = 0;
    glb(8'h0F); glb(8'd8); glb(8'd16); glb(8'd8);
    gl_wait_idle;
    if (nops !== 2 || op_cmd[0] !== 8'h04 || op_cmd[1] !== 8'h04 ||
        op_x0[0] !== 16'd0 || op_y0[0] !== 16'd0 ||
        op_x1[0] !== 16'd479 || op_y1[0] !== 16'd271 ||
        op_x1[1] !== 16'd479 || op_pen[0] !== 16'h4208 ||
        op_pen[1] !== 16'h4208 || op_pg[0] === op_pg[1]) begin
      $display("FAIL: CLEARS n=%0d pens %04X/%04X pages %b/%b",
               nops, op_pen[0], op_pen[1], op_pg[0], op_pg[1]);
      errors = errors + 1;
    end
    if (draw_pg !== 1'b0) begin
      $display("FAIL: CLEARS did not restore the draw page"); errors = errors + 1; end

    // ==== WAIT: pacing on frame ticks ======================================
    nops = 0;
    glb(8'h05); glw(16'd2);                             // WAIT 2 frames
    glb(8'h06); glb(8'd0); glb(8'd0); glb(8'd31);       // COLOR blue (queued)
    a = 4'h1; gl_sel = 1; #1;
    if (!rdata[6]) begin
      $display("FAIL: GLSTAT not busy during WAIT"); errors = errors + 1; end
    gl_sel = 0;
    gl_wait_idle;                                       // rides out the frames

    // ==== errors ===========================================================
    glb(8'hEE);                                         // unknown opcode
    glb(8'h43); glb(8'h41); glb(8'h20);                 // "CA " -> not fitted
    glb(8'h32); glb(8'd0);                              // POLY3 n=0 -> bad
    gl_wait_idle;
    a = 4'h1; gl_sel = 1; #1;
    if (!rdata[1]) begin
      $display("FAIL: GLSTAT error bit clear"); errors = errors + 1; end
    gl_sel = 0;
    rd_glerr(e0); rd_glerr(e1); rd_glerr(e2); rd_glerr(e3);
    if (e0 !== 8'd1 || e1 !== 8'd3 || e2 !== 8'd2 || e3 !== 8'd0) begin
      $display("FAIL: error FIFO %0d %0d %0d %0d, want 1 3 2 0", e0, e1, e2, e3);
      errors = errors + 1;
    end
    a = 4'h1; gl_sel = 1; #1;
    if (rdata[1]) begin
      $display("FAIL: GLSTAT error bit stuck"); errors = errors + 1; end
    gl_sel = 0;

    if (errors == 0)
      $display("TB-GL: PASS (GLID, record-vs-GL op streams identical, 2D verbs exact, RECT clamp box, CLEARS both pages, WAIT paces, error FIFO)");
    else $display("TB-GL: %0d FAILURES", errors);
    $finish;
  end
endmodule
