// gfx_span.v -- paint one horizontal run of a single pen, x0..x1 inclusive.
//
// This is what makes CLS, BOXFILL and the span-filled circle and ellipse cheap.
// Left to themselves those commands plot pixel by pixel, and every pixel is an
// SDRAM access; a full-screen fill in mode 1 is 130,560 of them, 29 ms. Painting
// four at a time where the alignment allows takes the same fill to 7.3 ms --
// faster in absolute terms than mode 0 manages today in block RAM, at four times
// the pixels.
//
// The whole difficulty is the ENDS. A run rarely starts or finishes on a
// four-pixel boundary, and the two spare pixels at each end share a word (mode
// 1) or a byte (mode 0) with pixels that are NOT part of this run and must
// survive untouched. So:
//
//     x0                                                        x1
//     |  head  |    aligned middle, four at a time    |  tail  |
//      one at a time                                   one at a time
//
// The alignment rule is the same in both modes, which is the pleasant part: in
// mode 1 a word write covers the four bytes containing the address, and in mode
// 0 a byte write covers the four pixels packed into it. Both are "the group of
// four containing x", so this module needs no mode input at all -- gfx_mem
// already knows what a span means in each mode.
//
// Correctness rule: every pixel in x0..x1 is painted exactly once, and no pixel
// outside it is touched. Off-screen coordinates are gfx_mem's business, not
// this module's -- it may hand over anything and gfx_mem discards it, which is
// the same "discarded, not clipped" rule the whole device follows.
module gfx_span(
  input                clk,
  input                rst,

  input  signed [17:0] sp_x0,        // inclusive
  input  signed [17:0] sp_x1,        // inclusive; a run of one has x0 == x1
  input  signed [17:0] sp_y,
  input         [15:0] sp_pen,
  input                sp_go,
  output reg           sp_busy,

  // drives gfx_mem's pixel request
  output reg signed [17:0] px_x,
  output reg signed [17:0] px_y,
  output reg    [15:0] px_pen,
  output reg           px_go,
  output reg           px_word,
  input                px_busy
);

  reg signed [17:0] cur, last;
  reg               running;

  // At 16 bpp a word holds TWO pixels. A word write may be used only when the
  // run is aligned here AND both pixels are still inside it; testing only the
  // alignment would paint one pixel past x1 -- a visible spur on every row.
  wire aligned  = (cur[0] == 1'b0);
  wire fits     = (cur + 18'sd1 <= last);
  wire use_word = aligned && fits;

  always @(posedge clk) begin
    px_go <= 0;

    if (rst) begin
      running <= 0; sp_busy <= 0; px_word <= 0;
    end else if (sp_go && !running) begin
      if (sp_x1 < sp_x0) begin
        sp_busy <= 0;                 // empty run: not an error, just nothing
      end else begin
        cur <= sp_x0; last <= sp_x1;
        running <= 1; sp_busy <= 1;
      end
    end else if (running && !px_go && !px_busy) begin
      if (cur > last) begin
        running <= 0; sp_busy <= 0; px_word <= 0;
      end else begin
        px_x    <= cur;
        px_y    <= sp_y;
        px_pen  <= sp_pen;
        px_word <= use_word;
        px_go   <= 1;
        cur     <= use_word ? (cur + 18'sd2) : (cur + 18'sd1);
      end
    end
  end
endmodule
