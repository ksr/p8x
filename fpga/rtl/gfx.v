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

  // Scanout side: a byte-address read into the SHARED framebuffer port, plus
  // the palette lookup. sc_en hands the port over for a cycle; the engine holds.
  input             sc_en,       // this cycle the scanout owns the fb port
  input      [12:0] sc_addr,
  output     [7:0]  sc_data,
  input      [1:0]  sc_pen,
  output     [11:0] sc_rgb
);
  // rd_stb: pulses on the microcycle the CPU actually READS a register. The
  // IDENT stream advances on it rather than on the address, because mem_addr
  // lingers across microcycles and would consume two bytes -- the identical
  // hazard the ACIA has at $FF05.


  localparam GW = 240, GH = 136, GSTRIDE = 60;
  localparam FBBYTES = GSTRIDE*GH;             // 8160

  // ---- register file -------------------------------------------------------
  // Coordinates are 16-bit pairs. Writing a LOW byte CLEARS its high byte, so
  // 8-bit software can never inherit a stale high byte; the high registers sit
  // 9 above their low ones ($FF29-$FF2C), which is what makes BASIC's GSTORE a
  // single routine.
  reg signed [17:0] gx0, gy0, gx1, gy1;
  reg  [1:0]  gcol;
  reg  [7:0]  gparm, gparm2;                   // ELLIPSE: x- and y-radius
  reg         gerr;
  reg  [11:0] pal [0:3];
  reg  [7:0]  gdata;                           // POINT result / IDENT stream
  reg  [3:0]  gidx;                            // IDENT cursor (0..13 = live)

  assign sc_rgb = pal[sc_pen];

  // IDENT record: "P8X-GFX", version, width, height, pens, 0. Carries the
  // GEOMETRY so software can ask instead of assume -- the same 14 bytes the
  // emulator builds in gpu_ident().
  function [7:0] ident_byte(input [3:0] i);
    case (i)
      4'd0: ident_byte = "P";   4'd1: ident_byte = "8";
      4'd2: ident_byte = "X";   4'd3: ident_byte = "-";
      4'd4: ident_byte = "G";   4'd5: ident_byte = "F";
      4'd6: ident_byte = "X";   4'd7: ident_byte = 8'd1;
      4'd8: ident_byte = GW[7:0];      4'd9:  ident_byte = GW[15:8];
      4'd10: ident_byte = GH[7:0];     4'd11: ident_byte = GH[15:8];
      4'd12: ident_byte = 8'd4;
      default: ident_byte = 8'd0;
    endcase
  endfunction

  // ---- framebuffer ---------------------------------------------------------
  // ONE port, time-shared. It was two -- engine read/write plus a separate
  // scanout read -- which reads better but costs double: Gowin's TRUE dual-port
  // mode halves a block's usable depth, so 8160 bytes took EIGHT blocks instead
  // of four and the design went to 48/46, which will not place.
  //
  // Sharing is nearly free here. The scanout needs one byte per eight panel
  // pixels, i.e. one cycle in 24; the engine gets the other 23. sc_en marks the
  // scanout's cycle and the engine holds, so nothing it is part-way through can
  // be corrupted.
  reg [7:0] fb [0:FBBYTES-1];
  reg [12:0] e_addr;
  reg        e_we;
  reg [7:0]  e_wdata;
  reg [7:0]  e_rdata;

  wire [12:0] fb_a  = sc_en ? sc_addr : e_addr;
  wire        fb_we = sc_en ? 1'b0    : e_we;    // the scanout never writes

  // ONE read register. Reading the array into two different destinations --
  // `if (sc_en) sc_data <= ... else e_rdata <= ...` -- looks equivalent but is
  // not synthesisable as block RAM: yosys cannot map it to a single read port
  // and falls back to distributed LUT RAM (1020 RAM16SDP4 and 8113 LUT4 here,
  // versus 4 BSRAM). Both consumers take fb_q instead.
  reg [7:0] fb_q;
  reg       sc_en_d;

  always @(posedge clk) begin
    if (fb_we) fb[fb_a] <= e_wdata;
    fb_q    <= fb[fb_a];
    sc_en_d <= sc_en;
    // e_rdata holds across the scanout's cycles, so a read-modify-write that is
    // part-way through is not clobbered by the byte the scanout fetched.
    if (!sc_en_d) e_rdata <= fb_q;
  end

  assign sc_data = fb_q;      // valid the cycle after sc_en, which is phase 1

  // ---- pixel unit ----------------------------------------------------------
  // One read-modify-write. px_go starts it, px_busy falls when done. An
  // off-screen pixel completes immediately WITHOUT touching memory -- that is
  // the "discarded, not clipped" rule, and doing it here means every command
  // gets it for free.
  reg signed [17:0] px_x, px_y;
  reg        px_go, px_busy;
  reg [1:0]  px_ph;
  reg [1:0]  px_pen;
  reg        px_read;                          // 1 = POINT (read, do not write)

  wire px_on = (px_x >= 0) && (px_x < GW) && (px_y >= 0) && (px_y < GH);
  // y*60 = y*64 - y*4: no multiplier, and 60 is not a power of two. The
  // intermediate must be WIDER than the result: y*64 reaches 8640 for y=135,
  // which does not fit the 13 bits y*60 needs, and a 13-bit shift silently
  // wrapped it -- putting the bottom rows back at the top of the framebuffer.
  wire [15:0] px_y16  = {3'd0, px_y[12:0]};
  wire [15:0] px_row  = (px_y16 << 6) - (px_y16 << 2);
  wire [12:0] px_byte = px_row[12:0] + {2'd0, px_x[12:2]};
  wire [2:0]  px_sh   = (2'd3 - px_x[1:0]) << 1;   // leftmost pixel in the high bits

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
  reg [12:0] clsi;
  reg [7:0]  cls_val;                          // byte S_CLS fills with

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
      st <= S_IDLE; px_go <= 0; px_busy <= 0; e_we <= 0;
      gx0 <= 0; gy0 <= 0; gx1 <= 0; gy1 <= 0;
      gcol <= 2'd1; gparm <= 0; gparm2 <= 0; gerr <= 0; gdata <= 0; gidx <= 4'd14;
      pal[0] <= 12'h000; pal[1] <= 12'hFFF; pal[2] <= 12'hF00; pal[3] <= 12'h0F0;
    end else if (sc_en) begin
      // The scanout owns the framebuffer this cycle, so the engine holds. It
      // costs one cycle in three -- fb_en fires once per panel pixel -- so the
      // engine runs at two thirds speed, which is invisible next to the tens of
      // thousands of pixels a fill takes.
      //
      // e_we is deliberately NOT cleared here. It is set at the end of the
      // read-modify-write's compute phase and the write lands on the FOLLOWING
      // cycle; if that cycle is a hold, clearing it discards the write for good.
      // At one collision in three that lost about a third of every shape drawn.
      // Holding it means the write simply happens on the next engine cycle.
    end else begin
      e_we <= 0;

      // ---- pixel unit ------------------------------------------------------
      // FOUR phases. The framebuffer read is synchronous: e_addr is
      // registered at the end of the cycle it is assigned, so e_rdata only holds
      // that location's byte TWO cycles later. Acting on it one cycle early
      // read the PREVIOUS address, and since 2bpp packs four pixels to a byte,
      // the read-modify-write then wrote the target pixel correctly while
      // clobbering its three neighbours -- a frame that is right for the first
      // pixel of every byte and wrong for the rest.
      if (px_go) begin
        px_go <= 0;
        if (!px_on) begin
          px_busy <= 0;                        // off-screen: discarded
          if (px_read) gdata <= 8'd0;
        end else begin
          e_addr  <= px_byte;                  // phase 0: issue the address
          px_ph   <= 2'd0;
          px_busy <= 1;
        end
      end else if (px_busy) begin
        case (px_ph)
          // FOUR phases now: fb_q is registered off the array and e_rdata is
          // registered off fb_q, so a read costs one cycle more than it did
          // when the engine had its own port.
          2'd0: px_ph <= 2'd1;                 // address issued
          2'd1: px_ph <= 2'd2;                 // fb_q loading
          2'd2: begin                          // e_rdata is now valid
            px_ph <= 2'd3;
            if (px_read) begin
              gdata   <= {6'd0, (e_rdata >> px_sh) & 2'b11};
              px_busy <= 0;
            end else begin
              e_wdata <= (e_rdata & ~(8'b11 << px_sh)) | ({6'd0,px_pen} << px_sh);
              e_we    <= 1;
            end
          end
          default: px_busy <= 0;               // phase 3: the write has landed
        endcase
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

        // CLS writes whole BYTES: every byte is four pixels of one pen, so
        // 0x00/0x55/0xAA/0xFF. 8160 clocks instead of 65280.
        S_CLS: begin
          e_addr  <= clsi;
          e_wdata <= cls_val;
          e_we    <= 1;
          if (clsi == FBBYTES-1) st <= S_DONE;
          else clsi <= clsi + 1;
        end

        // CIRCLE: midpoint, eight-way symmetric, matching gpu_circle().
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

        S_POINT: if (!px_go && !px_busy) st <= S_DONE;

        S_DONE: st <= S_IDLE;
        default: st <= S_IDLE;
      endcase

    end
  end

  // ---- CPU register writes --------------------------------------------------
  // Deliberately its OWN always block, outside the scanout hold. These used to
  // live inside the engine's `else`, so any write landing on a scanout cycle was
  // silently dropped -- one in four in simulation, one in three on the board.
  // That is what made SETPAL and BOXFILL "missing" from gfx.sh for days: their
  // GCMD write collided with a hold and the command simply never arrived. A
  // register write touches no framebuffer port, so there is nothing to gate.
  always @(posedge clk) begin
    if (!rst) begin

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
          4'h4: gcol  <= wdata[1:0];
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
              8'h05: begin clsi <= 0; cls_val <= {4{gcol}}; st <= S_CLS; end
              8'h06: pal[gcol] <= {gx0[3:0], gy0[3:0], gx1[3:0]};
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
                // Clears to pen 0, NOT to the pen it is about to select.
                // S_CLS used {4{gcol}} directly and RESET assigns gcol <= 1 in
                // this same cycle, so the clear came out WHITE while the
                // emulator's gpu_reset memsets to zero -- 129644 of 130560
                // pixels different, and invisible while the payload was a no-op.
                clsi <= 0; cls_val <= 8'h00; st <= S_CLS;
                gcol <= 2'd1; gparm <= 0; gdata <= 0; gidx <= 4'd14;
                pal[0]<=12'h000; pal[1]<=12'hFFF; pal[2]<=12'hF00; pal[3]<=12'h0F0;
              end
              8'hF2: gidx <= 0;                 // IDENT: GDATA now streams
              default: gerr <= 1;
            endcase
          end
          default: ;
        endcase
      end

      // IDENT stream advance. This MUST live in the same always block as every
      // other assignment to gidx: it started in its own `always @(posedge clk)`,
      // which is two drivers on one register. Simulation happily picked a
      // winner and the frame diff passed, but synthesis did not -- on hardware
      // gidx came up 0 instead of 14, so the first POINT read returned $50 ('P',
      // the first IDENT byte) instead of the pixel. A bug that only exists after
      // place-and-route is exactly the kind the co-sim cannot see.
      if (sel && rd_stb && a == 4'h7 && gidx < 4'd14) gidx <= gidx + 1;
    end
  end

  // ---- CPU reads -----------------------------------------------------------
  // Combinational, and GDATA's IDENT cursor advances on the read strobe in the
  // wrapper (see p8x_soc/p8x_top) so a multi-microcycle address cannot consume
  // two bytes -- the same hazard the ACIA has at $FF05.
  always @(*) begin
    case (a)
      4'h6:    rdata = {busy, 6'd0, gerr};       // GSTAT
      4'h7:    rdata = (gidx < 4'd14) ? ident_byte(gidx) : gdata;
      4'hD:    rdata = 8'h50;                    // 'P'
      4'hE:    rdata = 8'h47;                    // 'G'
      default: rdata = 8'hFF;
    endcase
  end

endmodule
