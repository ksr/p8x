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
// Two rules are load-bearing (see emulator/test/gfx_test.sh, which pins them):
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
`define ELL_STEP                                                              \
  if (!er2) begin                                                             \
    elx <= elx + 1;                                                           \
    edx <= edx + ($signed({14'd0, ery2}) <<< 1);                              \
    if (eerr < 0)                                                             \
      eerr <= eerr + ($signed({24'd0, ery2}) <<< 2)                           \
                   + ((edx + ($signed({14'd0, ery2}) <<< 1)) <<< 2);          \
    else begin                                                                \
      ely <= ely - 1;                                                          \
      edy <= edy - ($signed({14'd0, erx2}) <<< 1);                            \
      eerr <= eerr + ($signed({24'd0, ery2}) <<< 2)                           \
                   + ((edx + ($signed({14'd0, ery2}) <<< 1)) <<< 2)           \
                   - ((edy - ($signed({14'd0, erx2}) <<< 1)) <<< 2);          \
    end                                                                       \
  end else begin                                                              \
    ely <= ely - 1;                                                            \
    edy <= edy - ($signed({14'd0, erx2}) <<< 1);                              \
    if (eerr > 0)                                                             \
      eerr <= eerr + ($signed({24'd0, erx2}) <<< 2)                           \
                   - ((edy - ($signed({14'd0, erx2}) <<< 1)) <<< 2);          \
    else begin                                                                \
      elx <= elx + 1;                                                          \
      edx <= edx + ($signed({14'd0, ery2}) <<< 1);                            \
      eerr <= eerr + ((edx + ($signed({14'd0, ery2}) <<< 1)) <<< 2)           \
                   + ($signed({24'd0, erx2}) <<< 2)                           \
                   - ((edy - ($signed({14'd0, erx2}) <<< 1)) <<< 2);          \
    end                                                                       \
  end

module gfx (
  input             clk,
  input             rst,

  // CPU side. `sel` is the address decode ($FF20-$FF2F); `a` is the low nibble.
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
  reg         gerr;
  reg  [15:0] gdata;                           // POINT result (a 565 colour)
  reg  [3:0]  gidx;                            // IDENT cursor (0..13 = live)
  reg         ptid;                            // POINT stream: 0 = low next,
                                               //   1 = high next (and parked)

  // IDENT record: "P8X-GFX", version, width, height, pens, 0. Carries the
  // GEOMETRY so software can ask instead of assume -- the same 14 bytes the
  // emulator builds in gpu_ident().
  // Geometry is per-mode and lives in gfx_mem now.

  function [7:0] ident_byte(input [3:0] i);
    case (i)
      4'd0: ident_byte = "P";   4'd1: ident_byte = "8";
      4'd2: ident_byte = "X";   4'd3: ident_byte = "-";
      4'd4: ident_byte = "G";   4'd5: ident_byte = "F";
      4'd6: ident_byte = "X";   4'd7: ident_byte = 8'd2;   // protocol 2: direct colour
      // The CURRENT mode's geometry and pen count -- which is the point of
      // IDENT: software asks the device what it is, and in mode 1 that is a
      // different screen. Matches gpu_ident() in the emulator.
      4'd8:  ident_byte = 8'd224;  4'd9:  ident_byte = 8'd1;   // width  480
      4'd10: ident_byte = 8'd16;   4'd11: ident_byte = 8'd1;   // height 272
      4'd12: ident_byte = 8'd0;                                // 0 = no palette
      4'd13: ident_byte = 8'd16;                               // bits per pixel
      default: ident_byte = 8'd0;
    endcase
  endfunction

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
  reg        px_word;                          // 1 = span: TWO pixels at once
  wire       px_busy;
  wire [15:0] px_out;

  gfx_mem u_mem(
    .clk(clk), .rst(rst),
    .px_x(px_x), .px_y(px_y), .px_pen(px_pen), .px_go(px_go),
    .px_read(px_read), .px_word(px_word),
    .px_busy(px_busy), .px_out(px_out),
    .e_req(e_req), .e_we(e_we), .e_word(e_word), .e_addr(e_addr),
    .e_din(e_din), .e_ack(e_ack), .e_ready(e_ready), .e_dout(e_dout));

  // ---- command sequencer ---------------------------------------------------
  localparam S_IDLE  = 5'd0,  S_PIX   = 4'd1,  S_LINE  = 4'd2,
             S_BOXH  = 4'd3,  S_BOXV  = 4'd4,  S_FILL  = 4'd5,
             S_CLS   = 4'd6,  S_CIRC  = 4'd7,  S_CIRCF = 4'd8,
             S_POINT = 4'd9,  S_CIRCI = 4'd10, S_DONE  = 4'd11,
             S_ELLI  = 4'd12, S_ELL   = 4'd13, S_ELLR2 = 4'd14,
             S_ELLFI = 4'd15, S_ELLSI = 5'd16;
  reg [4:0] st;

  // Bresenham / loop state
  reg signed [17:0] cx, cy, ex, ey;            // cursor and endpoint
  reg signed [17:0] dx, dy, sx, sy;
  reg signed [19:0] err;
  reg signed [17:0] bx0, by0, bx1, by1;        // normalised box corners
  reg signed [17:0] ccx, ccy, cr, cq;          // circle centre, x, y
  reg signed [19:0] cerr;
  reg [2:0]  oct;                              // circle: which of the 8 points
  reg signed [17:0] clsx, clsy;                 // CLS cursor
  localparam signed [17:0] cls_xmax = 18'sd479, cls_ymax = 18'sd271;
  reg [15:0] cls_val;                          // colour S_CLS fills with

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
  reg        efill;
  reg [3:0]  stp;                              // SELFTEST step
  reg        busy;

  wire signed [19:0] e2 = err <<< 1;

  // CIRCLEFILL span bounds for the current octant. Spans 0/1 are cr wide and sit
  // at ccy+/-cq; spans 2/3 are cq wide at ccy+/-cr.
  wire signed [17:0] sp_half = oct[1] ? cq : cr;
  wire signed [17:0] sp_lo   = ccx - sp_half;
  wire signed [17:0] sp_hi   = ccx + sp_half;
  wire signed [17:0] sp_y    = (oct[1:0] == 2'd0) ? ccy + cq :
                               (oct[1:0] == 2'd1) ? ccy - cq :
                               (oct[1:0] == 2'd2) ? ccy + cr : ccy - cr;

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
      gparm <= 0; gparm2 <= 0; gerr <= 0; gdata <= 0; gidx <= 4'd14; ptid <= 1;
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

      // GDATA streams: the IDENT record, then POINT's two bytes (low, then
      // high, then PARKED on high). The cursor advances on rd_stb -- the
      // microcycle that actually reads -- never on the address, which lingers
      // (the ACIA's $FF05 hazard). The IDENT advance was MISSING entirely
      // before stage 6: nothing consumed the stream on the RTL (the co-sim
      // checks it on the emulator's console), so the record streamed its
      // first byte fourteen times, unobserved. Both streams advance here now.
      if (rd_stb && sel && a == 4'h7) begin
        if (gidx < 4'd14)  gidx <= gidx + 4'd1;
        else if (!ptid)    ptid <= 1'b1;       // low consumed; park on high
      end

      // ---- command sequencer ----------------------------------------------
      case (st)
        S_IDLE: ;                              // writes below start a command

        S_PIX:   if (!px_go && !px_busy) st <= S_DONE;

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
            px_go <= 1;
          end
        end

        // BOX outline: the two horizontal edges, then the two vertical ones.
        // Order does not matter -- the pen is constant for a whole command, so
        // only the SET of pixels has to match the C model.
        S_BOXH: if (!px_go && !px_busy) begin
          if (cx > bx1) begin cy <= by0; oct <= 0; st <= S_BOXV; end
          else begin
            px_x <= cx; px_y <= oct[0] ? by1 : by0; px_go <= 1;
            if (oct[0]) cx <= cx + 1;
            oct[0] <= ~oct[0];
          end
        end
        S_BOXV: if (!px_go && !px_busy) begin
          if (cy > by1) st <= S_DONE;
          else begin
            px_x <= oct[0] ? bx1 : bx0; px_y <= cy; px_go <= 1;
            if (oct[0]) cy <= cy + 1;
            oct[0] <= ~oct[0];
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

        // CLS, one row at a time through the span path. A 32-bit SDRAM word
        // holds TWO 565 pixels now, so an aligned word write covers a pair.
        S_CLS: if (!px_go && !px_busy) begin
          px_x <= clsx; px_y <= clsy; px_pen <= cls_val; px_read <= 0;
          px_word <= (clsx[0] == 1'b0);        // aligned: cover the pair
          px_go <= 1;
          if (clsx + (clsx[0] == 1'b0 ? 18'sd2 : 18'sd1) > cls_xmax) begin
            clsx <= 0;
            if (clsy == cls_ymax) st <= S_DONE;
            else                  clsy <= clsy + 18'sd1;
          end else
            // step by the PAIR actually written -- stepping 4 here while
            // px_word covers 2 skipped every other pair, and the co-sim was
            // blind to it: both models start zeroed and every payload
            // clears TO zero. The full-stack bench sentinels memory first,
            // which is why it caught what the panel's own camouflage
            // (uncleared stripes of the previous picture) had disguised as
            // a missing border and a display rotate.
            clsx <= clsx + (clsx[0] == 1'b0 ? 18'sd2 : 18'sd1);
        end

        S_CIRC: if (!px_go && !px_busy) begin
          if (cr < cq) st <= S_DONE;
          else begin
            case (oct)
              3'd0: begin px_x <= ccx+cr; px_y <= ccy+cq; end
              3'd1: begin px_x <= ccx-cr; px_y <= ccy+cq; end
              3'd2: begin px_x <= ccx+cr; px_y <= ccy-cq; end
              3'd3: begin px_x <= ccx-cr; px_y <= ccy-cq; end
              3'd4: begin px_x <= ccx+cq; px_y <= ccy+cr; end
              3'd5: begin px_x <= ccx-cq; px_y <= ccy+cr; end
              3'd6: begin px_x <= ccx+cq; px_y <= ccy-cr; end
              3'd7: begin px_x <= ccx-cq; px_y <= ccy-cr; end
            endcase
            px_go <= 1;
            if (oct == 3'd7) begin
              oct <= 0;
              // y++, then the error step -- exactly the C order
              if (cerr < 0) begin cerr <= cerr + ((cq+1) <<< 1) + 1; cq <= cq + 1; end
              else begin
                cerr <= cerr + (((cq+1) - (cr-1)) <<< 1) + 1;
                cq <= cq + 1; cr <= cr - 1;
              end
            end else oct <= oct + 1;
          end
        end

        // CIRCLEFILL: the same midpoint walk, but each step paints FOUR
        // horizontal spans instead of eight points, matching gpu_circle()'s
        // fill branch. S_CIRCI loads the span's start; S_CIRCF sweeps it.
        // Two states rather than one because the span bounds depend on both
        // the octant and on cr/cq, which the error step changes underneath.
        S_CIRCI: begin
          if (cr < cq) st <= S_DONE;
          else begin cx <= sp_lo; st <= S_CIRCF; end
        end
        S_CIRCF: if (!px_go && !px_busy) begin
          if (cx > sp_hi) begin
            if (oct[1:0] == 2'd3) begin
              oct <= 0;                        // last span: take the error step
              if (cerr < 0) begin cerr <= cerr + ((cq+1) <<< 1) + 1; cq <= cq + 1; end
              else begin
                cerr <= cerr + (((cq+1) - (cr-1)) <<< 1) + 1;
                cq <= cq + 1; cr <= cr - 1;
              end
            end else oct <= oct + 1;
            st <= S_CIRCI;
          end else begin
            px_x <= cx; px_y <= sp_y; px_go <= 1;
            cx <= cx + 1;
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
                if (oct[0]) begin oct <= 0; `ELL_STEP st <= S_ELLSI; end
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
              if (oct[1:0] == 2'd3) begin oct <= 0; `ELL_STEP end
              else oct <= oct + 1;
            end
          end
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
        S_POINT: if (!px_go && !px_busy) begin
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
          4'h5: begin
            gerr <= 0;
            case (wdata)
              8'h01: begin px_x<=gx0; px_y<=gy0; px_pen<=gcol; px_read<=0;
                           px_go<=1; st<=S_PIX; end
              8'h02: begin
                cx <= gx0; cy <= gy0; ex <= gx1; ey <= gy1;
                dx <= (gx1 > gx0) ? gx1-gx0 : gx0-gx1;
                dy <= (gy1 > gy0) ? gy0-gy1 : gy1-gy0;     // NEGATIVE
                sx <= (gx0 < gx1) ? 18'sd1 : -18'sd1;
                sy <= (gy0 < gy1) ? 18'sd1 : -18'sd1;
                err <= ((gx1 > gx0) ? gx1-gx0 : gx0-gx1)
                     + ((gy1 > gy0) ? gy0-gy1 : gy1-gy0);
                px_pen <= gcol; px_read <= 0;
                px_x <= gx0; px_y <= gy0; px_go <= 1;      // first point
                st <= S_LINE;
              end
              8'h03, 8'h04: begin
                bx0 <= (gx0 > gx1) ? gx1 : gx0;  bx1 <= (gx0 > gx1) ? gx0 : gx1;
                by0 <= (gy0 > gy1) ? gy1 : gy0;  by1 <= (gy0 > gy1) ? gy0 : gy1;
                cx  <= (gx0 > gx1) ? gx1 : gx0;
                cy  <= (gy0 > gy1) ? gy1 : gy0;
                oct <= 0; px_pen <= gcol; px_read <= 0;
                st  <= (wdata == 8'h03) ? S_BOXH : S_FILL;
              end
              // cls_val is latched at command time: RESET sets gcol in the same
              // cycle, and reading gcol live cleared to the wrong pen.
              8'h05: begin clsx <= 0; clsy <= 0;
                           cls_val <= gcol;
                           st <= S_CLS; end
              // 8'h06 was SETPAL; with no palette an unknown code sets ERR
              // below, which is what old software probing for it should see.
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
              8'h07, 8'h08: begin
                ccx <= gx0; ccy <= gy0;
                cr  <= {10'd0, gparm};          // x = r
                cq  <= 0;                       // y = 0
                cerr <= 20'sd1 - {10'd0, gparm};
                oct <= 0; px_pen <= gcol; px_read <= 0;
                st  <= (wdata == 8'h07) ? S_CIRC : S_CIRCI;
              end
              8'h09: begin px_x<=gx0; px_y<=gy0; px_read<=1; px_go<=1;
                           gidx<=4'd14; st<=S_POINT; end
              8'hF1: begin                      // RESET
                // Clears to 0 (black), NOT to the pen it is about to select --
                // the lesson recorded here before still applies, only the
                // reset pen changed: WHITE, matching gpu_reset().
                clsx <= 0; clsy <= 0; cls_val <= 16'h0000; st <= S_CLS;
                gcol <= 16'hFFFF; gparm <= 0; gdata <= 0; gidx <= 4'd14;
                ptid <= 1;
              end
              8'hF2: gidx <= 0;                 // IDENT: GDATA now streams
              default: gerr <= 1;
            endcase
          end
          default: ;
        endcase
    end
  end

  // ---- CPU reads -----------------------------------------------------------
  // Combinational, and GDATA's IDENT cursor advances on the read strobe in the
  // wrapper (see p8x_soc/p8x_top) so a multi-microcycle address cannot consume
  // two bytes -- the same hazard the ACIA has at $FF05.
  always @(*) begin
    case (a)
      4'h6:    rdata = {busy, 6'd0, gerr};       // GSTAT
      4'h7:    rdata = (gidx < 4'd14) ? ident_byte(gidx)
                     : (ptid ? gdata[15:8] : gdata[7:0]);
      4'hD:    rdata = 8'h50;                    // 'P'
      4'hE:    rdata = 8'h47;                    // 'G'
      default: rdata = 8'hFF;
    endcase
  end

endmodule
