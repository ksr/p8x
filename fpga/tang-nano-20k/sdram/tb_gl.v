// tb_gl.v -- the stage-10 GL command port and hex interpreter
// (STAGE10-DESIGN.md), bench 3 of the verification ladder.
//
// The record engine is RETIRED (stage 10b), so the oracle here is a
// DIRECTED op-stream check: the gfx stub records every register-level
// operation the engine issues for a mixed 3D scene (FLOOD erase, a plain
// and a window-clipped coloured LINE, a filled POLY3), and the recording
// must match the host replica's expected coordinates -- the same numbers
// c_gl_test pins in the emulator, and the same scene tb_gl_pix proves
// pixel-for-pixel against the emulator through the real memory stack.
// (Until stage 10b these values were ALSO cross-checked live against the
// stage-9 record path, op for op, before it was retired.)
//
// On top of that: absolute 2D-verb checks against the exact 1:1 window
// mapping (mapx(x)=x, mapy(y)=135-y), the filled RECT's clamped box, the
// CLEARS both-pages rule (two full-screen fills, draw page toggled between
// and restored), WAIT's frame pacing, GLID, GLSTAT and the error FIFO.
// glb() honours GLSTAT bit7 -- the FIFO is 64 bytes and backpressure is
// the documented contract.
//
//   iverilog -g2012 -o tbgl tb_gl.v ../../rtl/p8x_geom.v ../../rtl/mdu_core.v \
//            ../../rtl/trigtab.v
//   ./tbgl
`timescale 1ns/1ps

module tb;
  reg clk = 0, rst = 1;
  always #5 clk = ~clk;

  reg        gl_sel = 0, gl_wr = 0, gl_rd = 0;
  reg  [3:0] a = 0;
  reg  [7:0] wdata = 0;
  wire [7:0] rdata;

  wire        gm_own, gm_wr, gm_rd;
  wire [3:0]  gm_a;
  wire [7:0]  gm_wdata;
  reg  [7:0]  gm_rdata;
  reg         frame_tick = 0;
  wire        draw_pg, disp_pg;

  wire        g_req, g_we;
  wire [22:0] g_addr;
  wire [15:0] g_din;
  reg         g_ack = 0, g_ready = 0;
  reg  [15:0] g_dout = 0;
  p8x_geom dut(.clk(clk), .rst(rst),
               .a(a), .wdata(wdata), .rdata(rdata),
               .g_req(g_req), .g_we(g_we), .g_addr(g_addr), .g_din(g_din),
               .g_ack(g_ack), .g_ready(g_ready), .g_dout(g_dout),
               .gl_sel(gl_sel), .gl_wr(gl_wr), .gl_rd(gl_rd),
               .gm_own(gm_own), .gm_wr(gm_wr), .gm_a(gm_a),
               .gm_wdata(gm_wdata), .gm_rdata(gm_rdata),
               .frame_tick(frame_tick), .draw_pg(draw_pg), .disp_pg(disp_pg));

  integer errors = 0;

  // ---- SDRAM stub: the list slots, 3-cycle acks (the tb_geom pattern) ----
  reg [15:0] lmem [0:262143];          // 512KB of halfwords: covers 64 slots
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
  reg [15:0] rx0, ry0, rx1, ry1, rcolr;
  reg [3:0]  gbusy = 0;
  reg [7:0]  op_cmd [0:255];
  reg [15:0] op_x0 [0:255]; reg [15:0] op_y0 [0:255];
  reg [15:0] op_x1 [0:255]; reg [15:0] op_y1 [0:255];
  reg [15:0] op_pen [0:255];
  reg        op_pg  [0:255];        // draw page at issue time (CLEARS check)
  integer    nops = 0;
  reg [7:0]  rmode = 8'hAA;                  // GMODE mirror (AA = never written)
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
        4'hE: rmode <= gm_wdata;             // GMODE (10f LINFUN)
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
  // GL pokes honour the FIFO-full bit: the 64-byte FIFO plus backpressure
  // is the documented contract (real CPU pokes are far slower than this).
  task glb(input [7:0] v);
    integer n;
    begin
      n = 0; a = 4'h1; gl_sel = 1; #1;
      while (rdata[7] && n < 200000) begin @(negedge clk); #1; n = n + 1; end
      gl_sel = 0;
      if (n >= 200000) begin
        $display("FAIL: FIFO never drained"); errors = errors + 1; end
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
      // GLSTAT bit6 covers the consumer AND the walker (GESTAT is retired)
      n = 0; a = 4'h1; gl_sel = 1; #1;
      while (rdata[6] && n < 400000) begin @(negedge clk); #1; n = n + 1; end
      gl_sel = 0;
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
  task rd_glrb(output [7:0] v);       // pop one read-back byte (10e)
    begin
      @(negedge clk); gl_sel = 1; a = 4'h2; #1 v = rdata; gl_rd = 1;
      @(negedge clk); gl_sel = 0; gl_rd = 0;
    end
  endtask
  task expop(input integer i, input [7:0] cmd, input [15:0] pen,
             input [15:0] x0, input [15:0] y0,
             input [15:0] x1, input [15:0] y1);
    begin
      if (op_cmd[i] !== cmd || op_pen[i] !== pen ||
          op_x0[i] !== x0 || op_y0[i] !== y0 ||
          op_x1[i] !== x1 || op_y1[i] !== y1) begin
        $display("FAIL: op %0d = cmd %0d pen %04X (%0d,%0d)-(%0d,%0d), want cmd %0d pen %04X (%0d,%0d)-(%0d,%0d)",
                 i, op_cmd[i], op_pen[i],
                 $signed(op_x0[i]), $signed(op_y0[i]),
                 $signed(op_x1[i]), $signed(op_y1[i]),
                 cmd, pen, $signed(x0), $signed(y0), $signed(x1), $signed(y1));
        errors = errors + 1;
      end
    end
  endtask

  integer i;
  reg [7:0] e0, e1, e2, e3;
  integer gi;

  initial begin
    repeat (4) @(negedge clk); rst = 0; repeat (2) @(negedge clk);

    // ---- GLID probe -------------------------------------------------------
    a = 4'h4; gl_sel = 1; #1;
    if (rdata !== 8'h47) begin
      $display("FAIL: GLID != 'G' (%02X)", rdata); errors = errors + 1; end
    gl_sel = 0;

    // ==== the 3D scene, against the replica's expected ops ================
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
    if (nops !== 108) begin
      $display("FAIL: scene drew %0d ops, want 108 (1 flood + 2 lines + 105 spans)", nops);
      errors = errors + 1;
    end else begin
      expop(0, 8'h04, 16'h0000, 16'd104, 16'd0, 16'd375, 16'd271);  // FLOOD
      expop(1, 8'h02, 16'hFFFF, 16'd153, 16'd222, 16'd325, 16'd222);
      expop(2, 8'h02, 16'h07E0, 16'd375, 16'd95, 16'd104, 16'd129); // clipped
      expop(3,   8'h04, 16'hF800, 16'd239, 16'd109, 16'd239, 16'd109);
      expop(55,  8'h04, 16'hF800, 16'd201, 16'd161, 16'd277, 16'd161);
      expop(107, 8'h04, 16'hF800, 16'd162, 16'd213, 16'd316, 16'd213);
      for (i = 3; i < 108; i = i + 1)
        if (op_cmd[i] !== 8'h04 || op_pen[i] !== 16'hF800) begin
          $display("FAIL: span %0d cmd/pen wrong", i); errors = errors + 1;
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
      expop(0, 8'h02, 16'hFFFF, 16'd10, 16'd125, 16'd50, 16'd125);
      expop(1, 8'h02, 16'hFFFF, 16'd50, 16'd125, 16'd50, 16'd95);
      expop(2, 8'h04, 16'hF800, 16'd60, 16'd95, 16'd80, 16'd115);
      expop(3, 8'h02, 16'h07E0, 16'd5, 16'd130, 16'd5, 16'd130);
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
    glb(8'h32); glb(8'd0);                              // POLY3 n=0 -> bad
    gl_wait_idle;
    a = 4'h1; gl_sel = 1; #1;
    if (!rdata[1]) begin
      $display("FAIL: GLSTAT error bit clear"); errors = errors + 1; end
    gl_sel = 0;
    rd_glerr(e0); rd_glerr(e1); rd_glerr(e2); rd_glerr(e3);
    if (e0 !== 8'd1 || e1 !== 8'd2 || e2 !== 8'd0 || e3 !== 8'd0) begin
      $display("FAIL: error FIFO %0d %0d %0d %0d, want 1 2 0 0", e0, e1, e2, e3);
      errors = errors + 1;
    end

    // ==== stage 10d: ASCII mode ===========================================
    // CA, a short-form line drawn through the translator, CX -- the LINE
    // op must equal the hex MOVE3/DRAW3 result; then hex still works
    nops = 0;
    glb(8'hB3); glw(-16'sd120); glw(16'sd120); glw(-16'sd120); glw(16'sd120);
    glb(8'hB2); glw(16'sd104); glw(16'sd375); glw(16'sd0); glw(16'sd271);
    glb(8'h06); glb(8'd31); glb(8'd63); glb(8'd31);
    glb(8'h43); glb(8'h41); glb(8'h20);                 // "CA "
    glb("M"); glb("3"); glb(" ");                       // M3 -90 -90 300
    glb("-"); glb("9"); glb("0"); glb(" ");
    glb("-"); glb("9"); glb("0"); glb(" ");
    glb("3"); glb("0"); glb("0"); glb(8'h0D);
    glb("d"); glb("3"); glb(" ");                       // d3 (case folds)
    glb("9"); glb("0"); glb(",");
    glb("-"); glb("9"); glb("0"); glb(";");
    glb("3"); glb("0"); glb("0"); glb(8'h0A);
    glb("C"); glb("X"); glb(" ");
    gl_wait_idle;
    if (nops !== 1) begin
      $display("FAIL: ASCII line drew %0d ops, want 1", nops);
      errors = errors + 1;
    end else
      expop(0, 8'h02, 16'hFFFF, 16'd153, 16'd222, 16'd325, 16'd222);
    rd_glerr(e0);
    if (e0 !== 8'd0) begin
      $display("FAIL: ASCII line queued error %0d", e0); errors = errors + 1;
    end
    a = 4'h1; gl_sel = 1; #1;
    if (rdata[1]) begin
      $display("FAIL: GLSTAT error bit stuck"); errors = errors + 1; end
    gl_sel = 0;

    // ==== stage 10c: command lists ========================================
    // record the SAME 3D scene into list 5, run it twice with a scribble
    // between -- the op recording after the second CLRUN must repeat the
    // scene's ops exactly (op-for-op the immediate stream's tail)
    nops = 0;
    glb(8'hB3); glw(-16'sd120); glw(16'sd120); glw(-16'sd120); glw(16'sd120);
    glb(8'hB2); glw(16'sd104); glw(16'sd375); glw(16'sd0); glw(16'sd271);
    glb(8'h70); glb(8'd5);                              // CLBEG 5
    glb(8'h07); glb(8'd0); glb(8'd0); glb(8'd0);        // FLOOD (recorded)
    glb(8'h06); glb(8'd31); glb(8'd63); glb(8'd31);
    glb(8'h12); glw(-16'sd90); glw(-16'sd90); glw(16'sd300);
    glb(8'h2A); glw( 16'sd90); glw(-16'sd90); glw(16'sd300);
    glb(8'hE0); glb(8'd1);
    glb(8'h06); glb(8'd31); glb(8'd0); glb(8'd0);
    glb(8'h32); glb(8'd3);                              // POLY3 n=3
    glw(-16'sd80); glw(-16'sd80); glw(16'sd300);
    glw( 16'sd80); glw(-16'sd80); glw(16'sd300);
    glw( 16'sd0);  glw( 16'sd40); glw(16'sd420);
    glb(8'h71);                                         // CLEND
    gl_wait_idle;
    if (nops !== 0) begin
      $display("FAIL: recording drew %0d ops (must draw nothing)", nops);
      errors = errors + 1;
    end
    glb(8'h72); glb(8'd5);                              // CLRUN 5
    gl_wait_idle;
    if (nops !== 107) begin   // FLOOD + line + 105 spans
      $display("FAIL: CLRUN drew %0d ops, want 107", nops);
      errors = errors + 1;
    end else begin
      expop(0, 8'h04, 16'h0000, 16'd104, 16'd0, 16'd375, 16'd271);
      expop(1, 8'h02, 16'hFFFF, 16'd153, 16'd222, 16'd325, 16'd222);
      expop(2,   8'h04, 16'hF800, 16'd239, 16'd109, 16'd239, 16'd109);
      expop(106, 8'h04, 16'hF800, 16'd162, 16'd213, 16'd316, 16'd213);
    end
    nops = 0;
    glb(8'h06); glb(8'd0); glb(8'd63); glb(8'd0);       // scribble state
    glb(8'h73); glb(8'd5); glw(16'd2);                  // CLOOP 5, 2 passes
    gl_wait_idle;
    if (nops !== 214) begin
      $display("FAIL: CLOOP x2 drew %0d ops, want 214", nops);
      errors = errors + 1;
    end else begin
      expop(0, 8'h04, 16'h0000, 16'd104, 16'd0, 16'd375, 16'd271);
      expop(107, 8'h04, 16'h0000, 16'd104, 16'd0, 16'd375, 16'd271);
      expop(108, 8'h02, 16'hFFFF, 16'd153, 16'd222, 16'd325, 16'd222);
    end
    // errors: CLRUN of an undefined slot, CLDEL then CLRUN, slot >= 64,
    // stray CLEND, CLBEG-in-CLBEG
    glb(8'h72); glb(8'd9);                              // undefined -> 6
    glb(8'h74); glb(8'd5); glb(8'h72); glb(8'd5);       // deleted  -> 6
    glb(8'h72); glb(8'd64);                             // cap      -> 2
    glb(8'h71);                                         // stray    -> 5
    glb(8'h70); glb(8'd6); glb(8'h70); glb(8'd7);       // nested   -> 5
    glb(8'h71);                                         // end recording 6
    gl_wait_idle;
    rd_glerr(e0); rd_glerr(e1); rd_glerr(e2); rd_glerr(e3);
    if (e0 !== 8'd6 || e1 !== 8'd6 || e2 !== 8'd2 || e3 !== 8'd5) begin
      $display("FAIL: list errors %0d %0d %0d %0d, want 6 6 2 5",
               e0, e1, e2, e3);
      errors = errors + 1;
    end
    rd_glerr(e0); rd_glerr(e1);
    if (e0 !== 8'd5 || e1 !== 8'd0) begin
      $display("FAIL: nested error %0d %0d, want 5 0", e0, e1);
      errors = errors + 1;
    end

    // ---- stage 10e: read-back -----------------------------------------
    glb(8'hE0); glb(8'd1);                              // PRMFIL 1
    glb(8'h61); glb(8'd1);                              // FLAGRD 1
    gl_wait_idle;
    rd_glrb(e0); rd_glrb(e1);
    if ({e1, e0} !== 16'd1) begin
      $display("FAIL: FLAGRD 1 = %0d %0d, want 1 0", e0, e1);
      errors = errors + 1;
    end
    gl_sel = 1; a = 4'h1; #1;
    if (rdata[0]) begin
      $display("FAIL: RB not drained after FLAGRD"); errors = errors + 1; end
    gl_sel = 0;
    glb(8'h62); glb(8'd2);                              // MATXRD 2: VR = I
    gl_wait_idle;
    for (gi = 0; gi < 9; gi = gi + 1) begin
      rd_glrb(e0); rd_glrb(e1);
      if ({e1, e0} !== ((gi == 0 || gi == 4 || gi == 8) ? 16'd256 : 16'd0))
        begin $display("FAIL: MATXRD 2 word %0d = %0d", gi, {e1, e0});
              errors = errors + 1; end
    end
    glb(8'h70); glb(8'd7);                              // CLBEG 7
    glb(8'h12); glw(16'd1); glw(16'd2); glw(16'd3);     //   MOVE3 1 2 3
    glb(8'h71);                                         // CLEND
    glb(8'h76); glb(8'd7);                              // CLRD 7
    gl_wait_idle;
    rd_glrb(e0); rd_glrb(e1);
    if ({e1, e0} !== 16'd7) begin
      $display("FAIL: CLRD len = %0d, want 7", {e1, e0});
      errors = errors + 1; end
    rd_glrb(e0); rd_glrb(e1);
    if (e0 !== 8'h12 || e1 !== 8'd1) begin
      $display("FAIL: CLRD bytes %02X %02X, want 12 01", e0, e1);
      errors = errors + 1; end
    rd_glrb(e0); rd_glrb(e0); rd_glrb(e0); rd_glrb(e0); rd_glrb(e0);
    glb(8'h78); glb(8'd7); glb(8'd9); glw(16'd1);       // CLMOD 7 9 1
    glb(8'h76); glb(8'd7);                              // CLRD again
    gl_wait_idle;
    rd_glrb(e0); rd_glrb(e1);                           // length
    rd_glrb(e0); rd_glrb(e1);                           // opcode, patched x
    if (e0 !== 8'h12 || e1 !== 8'd9) begin
      $display("FAIL: CLMOD patch reads %02X %02X, want 12 09", e0, e1);
      errors = errors + 1; end
    rd_glrb(e0); rd_glrb(e0); rd_glrb(e0); rd_glrb(e0); rd_glrb(e0);
    glb(8'h61); glb(8'd0);                              // bad flag   -> 2
    glb(8'h76); glb(8'd60);                             // undefined  -> 6
    glb(8'h78); glb(8'd7); glb(8'd1); glw(16'd99);      // off >= len -> 2
    gl_wait_idle;
    rd_glerr(e0); rd_glerr(e1); rd_glerr(e2); rd_glerr(e3);
    if (e0 !== 8'd2 || e1 !== 8'd6 || e2 !== 8'd2 || e3 !== 8'd0) begin
      $display("FAIL: 10e errors %0d %0d %0d %0d, want 2 6 2 0",
               e0, e1, e2, e3);
      errors = errors + 1;
    end

    // ---- stage 10f: LINFUN ---------------------------------------------
    glb(8'hEB); glb(8'd3);                              // LINFUN 3 (AND)
    gl_wait_idle;
    if (rmode !== 8'd3) begin
      $display("FAIL: LINFUN 3 wrote GMODE=%02X, want 03", rmode);
      errors = errors + 1;
    end
    glb(8'hEB); glb(8'd9);                              // bad mode -> err2,
    gl_wait_idle;                                       //   GMODE untouched
    rd_glerr(e0);
    if (e0 !== 8'd2 || rmode !== 8'd3) begin
      $display("FAIL: LINFUN 9 err=%0d GMODE=%02X, want 2 03", e0, rmode);
      errors = errors + 1;
    end
    glb(8'h04);                                         // RESETF -> replace
    gl_wait_idle;
    if (rmode !== 8'd0) begin
      $display("FAIL: RESETF left GMODE=%02X, want 00", rmode);
      errors = errors + 1;
    end

    if (errors == 0)
      $display("TB-GL: PASS (GLID, 3D scene ops exact incl. 105 spans, 2D verbs exact, RECT clamp box, CLEARS both pages, WAIT paces, error FIFO, FIFO backpressure, LISTS exact, ASCII short-form line == hex op, READ-BACK exact incl. CLRD/CLMOD, LINFUN reaches GMODE + RESETF clears)");
    else $display("TB-GL: %0d FAILURES", errors);
    $finish;
  end
endmodule
