// gtxt.v -- the text-overlay plane: a classic character generator composited
// over the GL bitmap at scanout. The golden model is the emulator's overlay
// (p8xemu.c gl_tx_pixel + the TX* opcodes); this reproduces it in silicon.
//
// A grid of ASCII cells (80 x 34, cell 6 wide x 8 tall on the 480x272 panel)
// held in an on-chip char RAM. p8x_geom decodes the hex-only TX* GL opcodes and
// hands them here as a one-cycle command (tx_stb + tx_op + up to 4 param bytes);
// sdram_video queries this module for every displayed pixel and muxes the result
// over the bitmap. Monochrome: one foreground colour, transparent background
// (ov_on=0 lets the bitmap show through), a clip window bounding what shows AND
// what TXSCR scrolls.
//
// Char RAM ports: A is read-only for the compositor; B is read/write for the
// TXPUT / TXCLR / TXSCR FSM. TXCLR/TXSCR are multi-cycle: tx_busy holds while
// they run and p8x_geom stalls the FIFO, so a following TXPUT never races them.
//
// The compositor is a two-read pipeline matching the emulator bit-for-bit. Both
// addresses are COMBINATIONAL and only the read DATA is registered, so the char
// code and its glyph row stay aligned with the pixel's window/phase payload:
//   tick k   : issue char-RAM read for pixel k; latch pixel k's win/ph/grow (pa)
//   tick k+1 : char code (a_rq) valid -> issue char-gen ROM read; carry pb
//   tick k+2 : glyph byte (g_rq) valid -> ov_on = pb_win & glyph[5-pb_ph]
// ov_on/ov_col are combinational off tick k+2, i.e. a 2-tick read latency;
// sdram_video presents the query two pixel-fetches ahead of the pixel it feeds.
module gtxt (
  input             clk,
  input             rst,

  // ---- command channel from p8x_geom (one-cycle strobe) -------------------
  input             tx_stb,
  input      [2:0]  tx_op,      // 0 EN, 1 WIN, 2 COL, 3 AT, 4 PUT, 5 CLR, 6 SCR
  input      [7:0]  tx_p0,
  input      [7:0]  tx_p1,
  input      [7:0]  tx_p2,
  input      [7:0]  tx_p3,
  output            tx_busy,    // TXCLR/TXSCR running -> geom stalls the FIFO

  // ---- scanout query (from sdram_video) -----------------------------------
  input             q_ce,       // advance the compositor pipeline one pixel
  input      [6:0]  q_col,      // cell column 0..79 of the queried pixel
  input      [9:0]  q_y,        // panel row 0..271 (row = q_y>>3, grow = q_y&7)
  input      [2:0]  q_ph,       // pixel phase 0..5 (which of the 6 cell columns)
  output            ov_on,      // inked overlay pixel here (combinational)
  output     [15:0] ov_col,     // overlay colour, RGB565 (combinational)

  // ---- GXEN: drawing-bitmap visibility (scanout mux, in sdram_video) --------
  // Not part of the overlay itself, but the other half of the scanout compositor
  // (see the emulator's gpu_tx_sample), so it lives with the overlay state here.
  output reg        gx_en       // 1 = the GL bitmap is shown; 0 = black at scanout
);
  localparam integer NCELL = 80*34;    // 2720 cells

  // ---- overlay registers (set by the simple TX ops) -------------------------
  reg        tx_en;
  reg [15:0] tx_fg;
  reg [6:0]  c0, cw;           // window: origin col, width (cells)
  reg [5:0]  r0, ch;           // window: origin row, height (cells)
  reg [6:0]  cx;               // write cursor column
  reg [5:0]  cy;               // write cursor row

  // *80 by shift-add (row*64 + row*16 + col), so no multiplier
  function [11:0] cell_addr(input [5:0] row, input [6:0] col);
    cell_addr = {row, 6'd0} + {row, 4'd0} + {5'd0, col};
  endfunction

  // ---- char RAM: 2720 x 8, port A read (compositor), port B read/write ------
  reg  [7:0] cram [0:NCELL-1];
  wire [5:0] q_row  = q_y[8:3];                 // q_y >> 3  (0..33)
  wire [2:0] q_grow = q_y[2:0];
  wire [11:0] a_ra_c = cell_addr(q_row, q_col); // port A address (combinational)
  reg  [7:0] a_rq;                              // port A read data (registered
  //                                               below, in the compositor block)
  reg  [11:0] b_a;             // port B address
  reg  [7:0]  b_wd;            // port B write data
  reg         b_we;            // port B write enable
  reg  [7:0]  b_rq;            // port B read data (old value, read-before-write)
  always @(posedge clk) begin
    b_rq <= cram[b_a];
    if (b_we) cram[b_a] <= b_wd;
  end

  // ---- char-gen ROM: 96 glyphs x 8 rows, generated ------------------------
  reg  [7:0] chargen [0:767];
  integer gi;
  initial begin
    for (gi = 0; gi < 768; gi = gi + 1) chargen[gi] = 8'h00;
    `include "chargen.vh"
  end

  // =========================================================================
  // Command / clear / scroll FSM on port B
  // =========================================================================
  localparam S_IDLE = 2'd0, S_CLR = 2'd1, S_SCR = 2'd2;
  reg [1:0]  st;
  reg [11:0] cnt;             // clear address walk
  reg [5:0]  sr;              // scroll: current destination row
  reg [6:0]  sc;              // scroll: current column within the window
  reg [1:0]  sph;             // scroll phase: 0 addr-src, 1 wait, 2 write-dst
  // busy the instant a CLR/SCR arrives (before st transitions) so geom's stall
  // and any waiter see one continuous busy, with no 1-cycle accept-but-idle gap
  assign tx_busy = (st != S_IDLE) || (tx_stb && (tx_op == 3'd5 || tx_op == 3'd6));

  always @(posedge clk) begin
    b_we <= 1'b0;
    if (rst) begin
      tx_en <= 1'b0; tx_fg <= 16'hFFFF;
      c0 <= 7'd0; r0 <= 6'd0; cw <= 7'd80; ch <= 6'd34;
      cx <= 7'd0; cy <= 6'd0; st <= S_IDLE;
      gx_en <= 1'b1;              // power-on: the drawing bitmap is VISIBLE (OS/apps)
    end else case (st)
      S_IDLE: if (tx_stb) case (tx_op)
        3'd0: tx_en <= tx_p0[0];                             // TXEN
        3'd7: gx_en <= tx_p0[0];                             // GXEN (bitmap vis)
        3'd1: begin c0 <= tx_p0[6:0]; r0 <= tx_p1[5:0];      // TXWIN
                    cw <= tx_p2[6:0]; ch <= tx_p3[5:0]; end
        3'd2: tx_fg <= {tx_p0[4:0], tx_p1[5:0], tx_p2[4:0]}; // TXCOL (RGB565)
        3'd3: begin cx <= tx_p0[6:0]; cy <= tx_p1[5:0]; end  // TXAT
        3'd4: begin                                          // TXPUT
                b_a <= cell_addr(cy, cx); b_wd <= tx_p0; b_we <= 1'b1;
                if (cx < 7'd79) cx <= cx + 7'd1;             // advance, clamp
              end
        3'd5: begin st <= S_CLR; cnt <= 12'd0; end            // TXCLR
        3'd6: begin st <= S_SCR; sr <= r0; sc <= c0; sph <= 2'd0; end // TXSCR
        default: ;
      endcase
      S_CLR: begin                                           // blank all cells
        b_a <= cnt; b_wd <= 8'd0; b_we <= 1'b1;
        if (cnt == NCELL-1) st <= S_IDLE;
        else cnt <= cnt + 12'd1;
      end
      S_SCR: begin
        // copy row sr+1 -> row sr across the window; the final row (r0+ch-1)
        // is blanked instead. sph alternates read-src / write-dst on port B.
        if (sr == r0 + ch - 6'd1) begin                      // blank bottom row
          b_a <= cell_addr(sr, sc); b_wd <= 8'd0; b_we <= 1'b1;
          if (sc == c0 + cw - 7'd1) st <= S_IDLE;
          else sc <= sc + 7'd1;
        end else if (sph == 2'd0) begin                      // present src addr
          b_a <= cell_addr(sr + 6'd1, sc); b_we <= 1'b0; sph <= 2'd1;
        end else if (sph == 2'd1) begin                      // wait: b_rq settles
          b_we <= 1'b0; sph <= 2'd2;
        end else begin                                       // write src -> dst
          b_a <= cell_addr(sr, sc); b_wd <= b_rq; b_we <= 1'b1; sph <= 2'd0;
          if (sc == c0 + cw - 7'd1) begin sc <= c0; sr <= sr + 6'd1; end
          else sc <= sc + 7'd1;
        end
      end
      default: st <= S_IDLE;
    endcase
  end

  // =========================================================================
  // Compositor on port A: ONE registered stage (the char-RAM read), matching
  // sdram_video's lb_q so ov_on lines up with the bitmap pixel. The char-gen
  // ROM read and the bit test are combinational off the registered char code.
  // =========================================================================
  reg        pa_win;  reg [2:0] pa_ph, pa_grow;
  wire       in_win  = tx_en
                     && (q_col >= c0) && (q_col < c0 + cw)
                     && ({1'b0,q_row} >= {1'b0,r0})
                     && ({1'b0,q_row} <  ({1'b0,r0} + {1'b0,ch}));
  always @(posedge clk) if (q_ce) begin
    a_rq   <= cram[a_ra_c];                                  // char code (reg'd)
    pa_win <= in_win;  pa_ph <= q_ph;  pa_grow <= q_grow;    // aligned payload
  end
  wire       a_valid = (a_rq >= 8'd32) && (a_rq < 8'd128);   // has a glyph
  wire [9:0] g_ra_c  = {(a_rq - 8'd32), 3'd0} + {7'd0, pa_grow}; // (code-32)*8+grow
  wire [7:0] gbyte   = a_valid ? chargen[g_ra_c] : 8'd0;     // ROM read (comb.)
  assign ov_on  = pa_win && a_valid && gbyte[3'd5 - pa_ph];
  assign ov_col = tx_fg;
endmodule
