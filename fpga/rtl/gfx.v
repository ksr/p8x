// gfx.v -- the P8X graphics display: registers, drawing engine, framebuffer,
// palette. Board-independent and shared by the simulation and the board, the
// same way p8x_cpu.v is.
//
// THE EMULATOR IS THE GOLDEN MODEL. Everything here is a transliteration of the
// gpu_* functions in emulator/p8xemu.c, and the test that matters is that both
// produce a byte-identical framebuffer for the same program. So the algorithms
// below are written to match that C step for step and must not be "improved":
// a cleverer Bresenham that lights a different pixel is a bug even if it looks
// like a nicer line.
//
// Geometry, forced by block RAM rather than taste: the panel is 480x272 but the
// Tang Nano has 6 spare BSRAM blocks = 12288 bytes, and 480x272 needs 16320 at
// even one bit per pixel. So the framebuffer is 240x136 at 2 bits per pixel
// (8160 bytes, 4 blocks) and every logical pixel is drawn 2x2 on the panel,
// which fills it exactly and keeps pixels square.
//
// Two rules are load-bearing (pinned by the GL RTL battery, c_gl_rtl_test.sh):
//   - endpoints are INCLUSIVE
//   - off-screen pixels are DISCARDED, not clipped and not wrapped. Coordinates
//     are 16-bit, and the address arithmetic y*60 + (x>>2) would otherwise fold
//     x>=240 onto the START OF THE NEXT ROW. px_go simply drops those.
//
// Timing: a pixel costs five engine cycles (read-modify-write through a
// registered read port), and the engine stands still one cycle in three while
// the scanout uses the framebuffer -- about seven and a half clocks each. A
// full-screen BOXFILL is 32640 pixels, roughly 9 ms at 27 MHz. CLS is
// special-cased to whole bytes and is far quicker. The CPU sees GSTAT bit 7 =
// BUSY throughout and MUST poll it: a command issued while another is still
// running aborts it.

// The ellipse's error step, shared by both regions. A macro rather than a task
// so it stays inline in the state machine and reads next to the C it mirrors:
//   region 1: x++, dx += 2*ry2; err += 4*ry2 + 4*dx  (and y--, dy -= 2*rx2)
//   region 2: y--, dy -= 2*rx2; err += 4*rx2 - 4*dy  (and x++, dx += 2*ry2)
// Every `edx +` / `edy -` below uses the NEW value, exactly as the C does after
// its increment -- reading the old one is the classic way to get this wrong.
// The ellipse's error step used to be an inline macro -- four arms, each
// with two or three 40-bit carry chains, ~526 bits of adders in parallel.
// It is now the S_ELA/S_ELB/S_ELC micro-sequence below: one shared wide
// add/sub walks err += 4*r2 [+ 4*dx'] [- 4*dy'], and the branch flags
// reproduce the C exactly:
//   region 1: x++, dx += 2*ry2; err += 4*ry2 + 4*dx  (and y--, dy -= 2*rx2)
//   region 2: y--, dy -= 2*rx2; err += 4*rx2 - 4*dy  (and x++, dx += 2*ry2)
// Every dx'/dy' term uses the NEW value, exactly as the C does after its
// increment. Three extra cycles per step; the panel cannot tell.
// PROOF: tb_gl_cvx.v (battery rung 10) -- both regions, both aspect ratios,
// fills, outlines and the r=1/r=0 edges, byte-identical to the emulator
// through the real SDRAM stack.

module gfx (
  input             clk,
  input             rst,
  input             draw_pg,     // framebuffer DRAW page (stage 8b) -- passed
                                 //   straight to gfx_mem; POINT reads it too

  // Master side. Since the single-interface migration this port belongs to
  // the GL WALKER (p8x_geom's gm_* signals, wired straight through in the
  // card top); testbenches drive it directly as scaffolding. `a` is the low
  // nibble of the old $FF20 register map, which survives as the walker's
  // private register file.
  input             sel,
  input      [3:0]  a,
  input             wr,
  input             rd_stb,
  input      [7:0]  wdata,
  output reg [7:0]  rdata,

  // Arbiter port (engine side). Everything this module does to memory goes
  // through gfx_mem below; nothing here touches the bus directly. Data is 16
  // bits: a pixel IS an RGB565 colour (stage 6), and the palette -- and the
  // sc_pen/sc_rgb lookup it fed -- went with the depth change. (That lookup
  // had been DEAD on the board since the SDRAM scanout arrived: sdram_video
  // expanded 3-3-2 directly and never consulted it, so SETPAL silently never
  // reached the panel. The co-sim compares pen indices and could not see it.)
  output            e_req,
  output            e_we,
  output            e_word,
  output     [22:0] e_addr,
  output     [15:0] e_din,
  input             e_ack,
  input             e_ready,
  input      [15:0] e_dout
);
  // rd_stb: pulses on the microcycle the CPU actually READS a register. The
  // IDENT stream advances on it rather than on the address, because mem_addr
  // lingers across microcycles and would consume two bytes -- the identical
  // hazard the ACIA has at $FF05.



  // ---- register file -------------------------------------------------------
  // Coordinates are 16-bit pairs. Writing a LOW byte CLEARS its high byte, so
  // 8-bit software can never inherit a stale high byte; the high registers sit
  // 9 above their low ones ($FF29-$FF2C), which is what makes BASIC's GSTORE a
  // single routine.
  reg signed [17:0] gx0, gy0, gx1, gy1;
  // The pen is a whole RGB565 colour: GCOL its low byte, GCOLH ($FF2D's write
  // side) its high, with the coordinates' low-write-clears-high rule.
  reg  [15:0] gcol;
  reg  [7:0]  gparm, gparm2;                   // ELLIPSE: x- and y-radius
  reg  [15:0] lpat;                            // 10j: LINPAT, MSB first
  reg  [3:0]  lpi;                             //   bit cursor, per primitive
  reg  [15:0] gdata;                           // POINT result (a 565 colour)
  reg         ptid;                            // POINT stream: 0 = low next,
                                               //   1 = high next (and parked)

  // (The IDENT record and its cursor, the GID0/GID1 "PG" signature and the
  // GSTAT ERR bit retired with the CPU door: only the GL walker masters this
  // register file now, and identity questions are GLID's and the bridge
  // PING's to answer.)

  // ---- framebuffer ---------------------------------------------------------
  // It is not here any more. Both screen modes live in SDRAM (STAGE4-DESIGN.md),
  // so the four block RAMs this used to occupy are returned and the scanout no
  // longer has to share a port with the engine. The whole sc_en hold -- which
  // cost the engine a cycle in three, and once silently dropped a third of every
  // shape when e_we was cleared during a hold -- is gone with it: contention is
  // the arbiter's problem now, and it is the only thing that has to be right.

  // ---- pixel unit ----------------------------------------------------------
  // Now a gfx_mem instance. The ALGORITHMS below are untouched by that: they
  // still raise px_go and wait on px_busy, exactly as they did against block
  // RAM. That is deliberate -- every one of them has to stay step-for-step
  // identical to the emulator's gpu_* or the co-sim diverges, so the safest
  // change is the one that does not edit them.
  reg signed [17:0] px_x, px_y;
  reg        px_go;
  reg [15:0] px_pen;                           // the RGB565 colour to paint
  reg        px_read;                          // 1 = POINT (read, do not write)
  reg  [2:0] gmode2d;                          // 10f LINFUN: pixel-write mode
  reg        px_modal;                         // this command's pixels are modal
                                               // (lines/points/outlines; fills
                                               // and CLS always replace)
  wire [2:0] px_mode = px_modal ? gmode2d : 3'd0;
  reg        px_word;                          // 1 = span: TWO pixels at once
  wire       px_busy;
  wire [15:0] px_out;

  gfx_mem u_mem(
    .clk(clk), .rst(rst), .draw_pg(draw_pg),
    .px_x(px_x), .px_y(px_y), .px_pen(px_pen), .px_go(px_go),
    .px_read(px_read), .px_word(px_word), .px_mode(px_mode),
    .px_busy(px_busy), .px_out(px_out),
    .e_req(e_req), .e_we(e_we), .e_word(e_word), .e_addr(e_addr),
    .e_din(e_din), .e_ack(e_ack), .e_ready(e_ready), .e_dout(e_dout));

  // ---- command sequencer ---------------------------------------------------
  // BOX outline (03), CLS (05) and CIRCLE/CIRCLEFILL (07/08) are RETIRED
  // (stage-10 diet): four LINEs, BOXFILL 0,0,479,271 and ELLIPSE rx=ry
  // cover them, and their walkers' fabric bought the PGC curves/patterns/
  // text. RESET's clear rides S_FILL now.
  localparam S_IDLE  = 5'd0,  S_PIXW  = 4'd1,  S_LINE  = 4'd2,
             S_FILL  = 4'd5,
             S_PIXR  = 4'd9,  S_DONE  = 4'd11,
             S_ELLI  = 4'd12, S_ELL   = 4'd13, S_ELLR2 = 4'd14,
             S_ELLFI = 4'd15, S_ELLSI = 5'd16,
             // the ellipse error step, serialized through ONE shared
             // wide adder (it was ~526 bits of parallel carry chains)
             S_ELA   = 5'd17, S_ELB   = 5'd18, S_ELC   = 5'd19;
  reg [4:0] st;

  // Bresenham / loop state
  reg signed [17:0] cx, cy, ex, ey;            // cursor and endpoint
  reg signed [17:0] dx, dy, sx, sy;
  reg signed [19:0] err;
  reg signed [17:0] bx0, by0, bx1, by1;        // normalised box corners
  reg signed [17:0] ccx, ccy;                  // curve centre (ellipse)
  reg [2:0]  oct;                              // ellipse: quadrant cursor

  // ---- ellipse (midpoint, four-way symmetric) -------------------------------
  // A transliteration of gpu_ellipse() in the emulator. Both decision variables
  // are scaled by 4 there so the classic rx^2/4 term is exact rather than
  // rounded, and the scaling is kept here: a rounding difference is exactly how
  // two implementations of this quietly drift apart.
  //
  // Widths are set by the region-2 initialiser ry2*(2x+1)^2, which reaches ~35
  // bits for the largest radii an 8-bit register can ask for. Everything inside
  // the LOOPS is adds and shifts; every multiply is one-time, at setup or at the
  // region boundary.
  reg [15:0] erx2, ery2;
  reg signed [29:0] edx, edy;
  reg signed [39:0] eerr;
  reg signed [17:0] elx, ely;
  reg        er2;                              // 0 = region 1, 1 = region 2
  reg signed [39:0] eacc;            // the step's running error sum
  reg               ebr;             // took the short branch (no 2nd axis)
  wire signed [29:0] edx_n = edx + $signed({13'd0, ery2, 1'b0});   // new dx
  wire signed [29:0] edy_n = edy - $signed({13'd0, erx2, 1'b0});   // new dy
  // ONE shared 40-bit add/sub serves all three phases
  wire signed [39:0] ella = (st == S_ELA) ? eerr : eacc;
  wire signed [39:0] ellb = (st == S_ELA)
                          ? (er2 ? $signed({22'd0, erx2, 2'b00})
                                 : $signed({22'd0, ery2, 2'b00}))
                          : (st == S_ELB) ? {{8{edx_n[29]}}, edx_n, 2'b00}
                          :                 {{8{edy_n[29]}}, edy_n, 2'b00};
  wire signed [39:0] ell_s = (st == S_ELC) ? (ella - ellb)
                                           : (ella + ellb);
  reg        efill;
  
  reg        busy;

  wire signed [19:0] e2 = err <<< 1;

  // BUSY is what software polls. It is asserted the moment a command is
  // accepted and only drops in S_IDLE, so a CPU that writes GCMD and reads
  // GSTAT on the very next cycle still sees the engine running.
  always @(*) busy = (st != S_IDLE);

  integer i;

  always @(posedge clk) begin
    if (rst) begin
      st <= S_IDLE; px_go <= 0; px_word <= 0;
      gx0 <= 0; gy0 <= 0; gx1 <= 0; gy1 <= 0;
      gcol <= 16'hFFFF;         // white, matching the emulator's reset pen
      gparm <= 0; gparm2 <= 0; gdata <= 0; ptid <= 1;
      lpat <= 16'hFFFF; lpi <= 0;
      gmode2d <= 0; px_modal <= 0;
    end else begin
      // The engine is no longer gated by anything here. It used to hold for a
      // cycle whenever the scanout claimed the shared framebuffer port -- a
      // third of every cycle, and the source of a bug where clearing e_we
      // during a hold silently discarded a third of every shape drawn. The
      // framebuffer is in SDRAM now and contention is the arbiter's business,
      // so the engine simply asks gfx_mem for a pixel and waits on px_busy.
      //
      // px_go must default low: it is a one-cycle pulse, and the FSM that used
      // to clear it went with the pixel unit. px_word must default low too --
      // it is a reg, so a plot issued after a CLS would otherwise inherit the
      // span flag and paint four pixels where one was asked for.
      px_go   <= 0;
      px_word <= 0;

      // GDATA streams PIXELR's two bytes (low, then high, then PARKED on
      // high). The cursor advances on rd_stb -- the microcycle that actually
      // reads -- never on the address, which lingers (the ACIA's $FF05
      // hazard, inherited by the walker's gm_rd pops).
      if (rd_stb && sel && a == 4'h7) begin
        if (!ptid) ptid <= 1'b1;               // low consumed; park on high
      end

      // ---- command sequencer ----------------------------------------------
      case (st)
        S_IDLE: ;                              // writes below start a command

        S_PIXW:   if (!px_go && !px_busy) st <= S_DONE;

        // LINE: integer Bresenham, all eight octants, dy held NEGATIVE -- the
        // exact form in gpu_line(). Endpoints inclusive.
        S_LINE: if (!px_go && !px_busy) begin
          if (cx == ex && cy == ey) st <= S_DONE;
          else begin
            if (e2 >= dy) begin err <= err + dy; cx <= cx + sx; end
            if (e2 <= dx) begin
              err <= (e2 >= dy) ? err + dy + dx : err + dx;
              cy  <= cy + sy;
            end
            px_x <= (e2 >= dy) ? cx + sx : cx;
            px_y <= (e2 <= dx) ? cy + sy : cy;
            px_go <= lpat[4'd15 - lpi];                    // 10j: LINPAT
            lpi <= lpi + 4'd1;                             //   (wraps at 16)
          end
        end

        S_FILL: if (!px_go && !px_busy) begin
          if (cy > by1) st <= S_DONE;
          else begin
            px_x <= cx; px_y <= cy; px_go <= 1;
            if (cx >= bx1) begin cx <= bx0; cy <= cy + 1; end
            else cx <= cx + 1;
          end
        end

        // ---- ELLIPSE / ELLIPSEFILL ----------------------------------------
        S_ELLI: begin                          // setup: region-1 error term
          erx2 <= gparm  * gparm;
          ery2 <= gparm2 * gparm2;
          elx  <= 0;
          ely  <= {10'd0, gparm2};
          edx  <= 0;
          er2  <= 0;
          oct  <= 0;
          st   <= (gparm == 0 || gparm2 == 0) ? S_DONE : S_ELLFI;
        end
        // erx2/ery2 are registered in S_ELLI, so the terms that need them wait
        // one cycle. dy = 2*rx2*ry; err = 4*ry2 - 4*rx2*ry + rx2.
        S_ELLFI: begin
          edy  <= ($signed({14'd0, erx2}) * $signed({22'd0, gparm2})) <<< 1;
          eerr <= ($signed({24'd0, ery2}) <<< 2)
                - (($signed({24'd0, erx2}) * $signed({32'd0, gparm2})) <<< 2)
                + $signed({24'd0, erx2});
          // A fill must load its first span through S_ELLSI. The circle starts
          // its walk at x=r, so seeding cx to ccx-r works there; the ellipse
          // starts region 1 at x=0, where the span is the single pixel ccx.
          // Seeding it the circle's way drew one spurious full-width span on
          // the ellipse's extreme row.
          st   <= efill ? S_ELLSI : S_ELL;
        end

        // One state walks both regions; er2 says which. Four points per step for
        // an outline, two horizontal spans for a fill -- the same split the
        // circle makes, with cx sweeping the span as S_CIRCF does.
        S_ELL: if (!px_go && !px_busy) begin
          if (!er2 && edx >= edy)      st <= S_ELLR2;   // region 1 -> 2
          else if (er2 && ely < 0)     st <= S_DONE;
          else begin
            if (efill) begin
              px_x <= cx;
              px_y <= oct[0] ? (ccy - ely) : (ccy + ely);
              px_go <= 1;
              if (cx >= ccx + elx) begin
                cx <= ccx - elx;
                if (oct[0]) begin oct <= 0; st <= S_ELA; end
                else oct <= 1;
              end else cx <= cx + 1;
            end else begin
              case (oct[1:0])
                2'd0: begin px_x <= ccx+elx; px_y <= ccy+ely; end
                2'd1: begin px_x <= ccx-elx; px_y <= ccy+ely; end
                2'd2: begin px_x <= ccx+elx; px_y <= ccy-ely; end
                2'd3: begin px_x <= ccx-elx; px_y <= ccy-ely; end
              endcase
              px_go <= 1;
              if (oct[1:0] == 2'd3) begin oct <= 0; st <= S_ELA; end
              else oct <= oct + 1;
            end
          end
        end

        // circle error step: cerr += 2(cq+1)+/-... == cerr + 2cq [- 2cr]
        // + (3|5), cq++ [cr--]. The +1 fold: 2(cq+1)+1 = 2cq+3, and
        // 2((cq+1)-(cr-1))+1 = 2cq-2cr+5 -- exactly the C, one add per
        // cycle through the shared adder. cerr's sign picks the branch
        // and stays stable until S_CCC writes it.
        S_ELA: begin                           // err += 4*r2; pick branch
          ebr  <= er2 ? (eerr > 0) : (eerr < 0);
          eacc <= ell_s;
          st   <= S_ELB;
        end
        S_ELB: begin                           // the dx' term (and commit)
          if (!er2 || !ebr) begin
            eacc <= ell_s; edx <= edx_n; elx <= elx + 1;
          end
          st <= S_ELC;
        end
        S_ELC: begin                           // the dy' term (and commit)
          if (er2 || !ebr) begin
            eerr <= ell_s; edy <= edy_n; ely <= ely - 1;
          end else eerr <= eacc;
          st <= efill ? S_ELLSI : S_ELL;
        end

        S_ELLSI: begin cx <= ccx - elx; st <= S_ELL; end

        S_ELLR2: begin                         // region-2 error initialiser
          eerr <= $signed({24'd0, ery2}) * ((elx <<< 1) + 1) * ((elx <<< 1) + 1)
                + (($signed({24'd0, erx2}) * (ely - 1) * (ely - 1)) <<< 2)
                - (($signed({24'd0, erx2}) * $signed({24'd0, ery2})) <<< 2);
          er2 <= 1;
          cx  <= ccx - elx;
          st  <= S_ELL;
        end

        // gfx_mem has already put the pixel (or 0 for off-screen) in px_out.
        S_PIXR: if (!px_go && !px_busy) begin
          gdata <= px_out; ptid <= 1'b0;       // GDATA: low byte first
          st <= S_DONE;
        end

        S_DONE: st <= S_IDLE;
        default: st <= S_IDLE;
      endcase

      end

      if (sel && wr) begin
        case (a)
          4'h0: gx0 <= {2'd0, wdata};          // low write CLEARS the high byte
          4'h1: gy0 <= {2'd0, wdata};
          4'h2: gx1 <= {2'd0, wdata};
          4'h3: gy1 <= {2'd0, wdata};
          4'h9: gx0 <= {2'd0, wdata, gx0[7:0]};
          4'hA: gy0 <= {2'd0, wdata, gy0[7:0]};
          4'hB: gx1 <= {2'd0, wdata, gx1[7:0]};
          4'hC: gy1 <= {2'd0, wdata, gy1[7:0]};
          4'h4: gcol  <= {8'd0, wdata};      // low write CLEARS the high byte
          4'hD: gcol  <= {wdata, gcol[7:0]};   // GCOLH (GID0's write side)
          4'h8: gparm  <= wdata;
          4'hF: gparm2 <= wdata;   // GPARM2: ELLIPSE y-radius
          4'hE: gmode2d <= wdata[2:0];   // GMODE (10f LINFUN; GID1 reads)
          4'h5: begin
            // modal pixels: PLOT, LINE, BOX outline, CIRCLE, ELLIPSE --
            // every fill (and CLS) replaces regardless of the mode
            px_modal <= (wdata == 8'h01 || wdata == 8'h02 ||
                         wdata == 8'h0A);
            case (wdata)
              8'h01: begin px_x<=gx0; px_y<=gy0; px_pen<=gcol; px_read<=0;
                           px_go<=1; st<=S_PIXW; end
              8'h02: begin
                cx <= gx0; cy <= gy0; ex <= gx1; ey <= gy1;
                dx <= (gx1 > gx0) ? gx1-gx0 : gx0-gx1;
                dy <= (gy1 > gy0) ? gy0-gy1 : gy1-gy0;     // NEGATIVE
                sx <= (gx0 < gx1) ? 18'sd1 : -18'sd1;
                sy <= (gy0 < gy1) ? 18'sd1 : -18'sd1;
                err <= ((gx1 > gx0) ? gx1-gx0 : gx0-gx1)
                     + ((gy1 > gy0) ? gy0-gy1 : gy1-gy0);
                px_pen <= gcol; px_read <= 0;
                px_x <= gx0; px_y <= gy0;
                px_go <= lpat[15];                         // first point,
                lpi <= 4'd1;                               //   pattern MSB
                st <= S_LINE;
              end
              // 03 (BOX outline), 05 (CLS), 06 (SETPAL) and 07/08 (CIRCLE)
              // are RETIRED: four LINEs, BOXFILL 0,0,479,271 and ELLIPSE
              // rx=ry cover them (stage-10 diet). Unknown -> ERR below.
              8'h04: begin
                bx0 <= (gx0 > gx1) ? gx1 : gx0;  bx1 <= (gx0 > gx1) ? gx0 : gx1;
                by0 <= (gy0 > gy1) ? gy1 : gy0;  by1 <= (gy0 > gy1) ? gy0 : gy1;
                cx  <= (gx0 > gx1) ? gx1 : gx0;
                cy  <= (gy0 > gy1) ? gy1 : gy0;
                px_pen <= gcol; px_read <= 0;
                st  <= S_FILL;
              end
              // ELLIPSE / ELLIPSEFILL. ccx/ccy and cx are shared with the
              // circle; S_ELLI needs one extra cycle before erx2/ery2 are
              // available, which is what S_ELLFI is for.
              8'h0A, 8'h0B: begin
                ccx <= gx0; ccy <= gy0;
                px_pen <= gcol; px_read <= 0;
                efill <= (wdata == 8'h0B);
                cx <= gx0 - {10'd0, gparm};
                st <= S_ELLI;
              end
              8'h09: begin px_x<=gx0; px_y<=gy0; px_read<=1; px_go<=1;
                           st<=S_PIXR; end
              // F1 RESET and F2 IDENT are RETIRED with the CPU door: the
              // walker never issues them (GL RF owns reset semantics, and
              // the bridge PING answers identity). Unknown commands are
              // simply ignored -- only the walker speaks here now.
              8'h0C: lpat <= {gparm2, gparm};   // LINPAT (10j): the register
                                                //   map is full, so the
                                                //   pattern rides a command
              default: ;
            endcase
          end
          default: ;
        endcase
    end
  end

  // ---- register reads (the WALKER's side now: GSTAT busy poll and the
  // PIXELR byte stream; the GID0/GID1 "PG" signature and the IDENT record
  // retired with the CPU door -- GLID and the bridge PING answer identity)
  always @(*) begin
    case (a)
      4'h6:    rdata = {busy, 7'd0};             // GSTAT
      4'h7:    rdata = ptid ? gdata[15:8] : gdata[7:0];
      default: rdata = 8'hFF;
    endcase
  end

endmodule
