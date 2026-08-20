// gfx_mem.v -- the engine's pixel back-end, against SDRAM instead of block RAM.
//
// This exists so that gfx.v's DRAWING ALGORITHMS do not have to change at all.
// Every command in that file -- line, box, circle, ellipse, fill -- funnels
// through one narrow pixel request (px_go / px_busy), so replacing what happens
// behind that request replaces the memory system without touching a single line
// of Bresenham or midpoint code. That matters more here than tidiness: those
// algorithms have to stay step-for-step identical to the emulator's gpu_* or the
// co-sim diverges, and the safest way to keep them identical is not to edit them.
//
// Both screen modes live in SDRAM (see STAGE4-DESIGN.md). That trades the four
// block RAMs the old framebuffer occupied for the one the scanout line buffer
// needs, on a design that is at 44/46 and has failed to place from a change with
// no logical effect at all.
//
//   mode 0  240x136, 2 bpp   4 pixels share a byte, so a plot is a genuine
//                            read-modify-write: ~12 cycles against 7.5 in block
//                            RAM. That is the price of the three freed blocks,
//                            and it is confined to outline drawing -- a
//                            screen-width line goes from 0.07 ms to 0.11 ms.
//   mode 1  480x272, 8 bpp   a pixel IS a byte, so a plot is one write and there
//                            is no read at all. The read-modify-write is an
//                            artefact of 2 bpp, not of SDRAM.
//
// px_word asks for the span path: one write covering four horizontal pixels of
// the same pen. In mode 1 that is the controller's wr_word (all four lanes); in
// mode 0 a whole byte already IS four pixels, so it is an ordinary byte write
// with no read first. Either way CLS and BOXFILL stop paying per pixel.
module gfx_mem(
  input                clk,
  input                rst,
  input                draw_pg,       // framebuffer page (stage 8b): addr bit 19

  // ---- request from the drawing algorithms
  input  signed [17:0] px_x,
  input  signed [17:0] px_y,
  input         [15:0] px_pen,        // an RGB565 colour
  input                px_go,         // 1-cycle start
  input                px_read,       // 1 = POINT: read, do not write
  input                px_word,       // 1 = span: cover the aligned PAIR
  output reg           px_busy,
  output reg    [15:0] px_out,        // POINT result (0 if off-screen)

  // ---- arbiter port
  output reg           e_req,
  output reg           e_we,
  output reg           e_word,
  output reg    [22:0] e_addr,
  output reg    [15:0] e_din,
  input                e_ack,
  input                e_ready,
  input         [15:0] e_dout
);

  // Geometry. Explicit widths throughout: a y*stride computed in a narrow
  // context is exactly how this project once folded the bottom of the screen
  // onto the top, when y*60 wrapped inside 13 bits.
  wire [17:0] xw = px_x[17:0];
  wire [17:0] yw = px_y[17:0];
  wire        on = !px_x[17] && !px_y[17] && xw < 18'd480 && yw < 18'd272;

  // Stride 1024 (STAGE6-DESIGN.md): a line fits one SDRAM row exactly, and
  // the address is PURE WIRING -- {page, y, x, 0} -- so the y*stride multiply, and
  // its whole 13-bit-wrap class of bugs, is gone rather than survived.
  wire [22:0] addr = {3'd0, draw_pg, yw[8:0], xw[8:0], 1'b0};

  localparam S_IDLE=0, S_RD=1, S_WR=3;
  reg [1:0] st;

  always @(posedge clk) begin
    e_req <= e_req & ~e_ack;          // hold the request until it is taken

    if (rst) begin
      st <= S_IDLE; px_busy <= 0; e_req <= 0; e_we <= 0; e_word <= 0; px_out <= 0;
    end else case (st)
      S_IDLE: if (px_go) begin
        if (!on) begin
          // Off-screen is DISCARDED, not clipped, and completes without
          // touching memory -- the one rule that is trivially identical in C
          // and Verilog. Doing it here gives every command it for free.
          px_busy <= 0;
          if (px_read) px_out <= 8'd0;
        end else begin
          px_busy <= 1;
          e_addr  <= addr;
          if (px_read) begin
            e_we <= 0; e_word <= 0; e_req <= 1; st <= S_RD;
          end else begin
            // A pixel IS a 16-bit word half: one masked write, nothing to
            // preserve -- still no read-modify-write. The SDRAM bus is 32
            // bits with byte lanes, so the controller writes the addressed
            // half (or, for px_word spans, the whole aligned pair).
            e_we <= 1; e_din <= px_pen; e_word <= px_word;
            e_req <= 1; st <= S_WR;
          end
        end
      end

      // Only POINT reads now.
      S_RD:  if (e_ready) begin
        px_out <= e_dout; px_busy <= 0; st <= S_IDLE;
      end

      S_WR:  if (e_ack) begin        // a write has no answer; the ack is the end
        px_busy <= 0; e_word <= 0; st <= S_IDLE;
      end

      default: st <= S_IDLE;
    endcase
  end
endmodule
