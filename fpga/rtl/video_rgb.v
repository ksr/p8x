// video_rgb.v -- 480x272 RGB panel timing + framebuffer scanout.
//
// Drives a Sipeed 4.3" 480x272 parallel-RGB panel in DE mode, and reads the
// 240x136 framebuffer in gfx.v, doubling every logical pixel to 2x2 so the
// framebuffer fills the panel exactly with square pixels.
//
// THE PIXEL CLOCK IS FREE. 480x272 at 60 Hz wants 525 x 286 x 60 = 9.009 MHz,
// and the board's 27 MHz crystal divided by three is 9.000 MHz -- 59.94 Hz. That
// is the SAME divide-by-three the CPU already runs on, so no PLL is needed and
// both rPLLs stay available for the Milestone-5 clock-up.
//
// Those three fabric cycles per pixel are also what makes the scanout simple:
// block RAM is synchronous, so a byte fetched at the start of a pixel is not
// ready until part-way through it. The address is therefore computed one pixel
// AHEAD and latched at phase 2 -- the byte for pixel N is fetched during pixel
// N-1. Without that the whole image sits one pixel to the right.
//
// Panel timings are the usual ones for this class of 480x272 TFT. DE-mode panels
// ignore HS/VS entirely and latch on DE, which is why the exact sync widths are
// not critical -- but they are still generated, and they MUST be checked against
// Sipeed's datasheet before the first build. Guessed panel numbers are how a
// display stays dark for a day.

module video_rgb #(
  parameter H_ACT = 480, H_FP = 2, H_SYNC = 41, H_BP = 2,   // 525 total
  parameter V_ACT = 272, V_FP = 2, V_SYNC = 10, V_BP = 2    // 286 total
)(
  input             clk,          // 27 MHz fabric clock
  input             rst,

  // framebuffer read port on gfx.v
  output     [12:0] fb_addr,
  input      [7:0]  fb_data,
  output     [1:0]  fb_pen,       // which pixel of the fetched byte
  input      [11:0] fb_rgb,       // that pen's palette entry

  // to the panel
  output reg        pclk,
  output reg        de,
  output reg        hs,
  output reg        vs,
  output reg [4:0]  r,
  output reg [5:0]  g,
  output reg [4:0]  b
);

  localparam H_TOT = H_ACT + H_FP + H_SYNC + H_BP;
  localparam V_TOT = V_ACT + V_FP + V_SYNC + V_BP;
  localparam GSTRIDE = 60;

  reg [1:0]  ph;                  // 0,1,2 -> 9 MHz pixel rate
  reg [9:0]  px;                  // 0..H_TOT-1
  reg [9:0]  py;                  // 0..V_TOT-1

  // The pixel being FETCHED is one ahead of the pixel being shown.
  wire [9:0]  nx     = (px == H_TOT-1) ? 10'd0 : px + 10'd1;
  wire [9:0]  ny     = (px == H_TOT-1) ? ((py == V_TOT-1) ? 10'd0 : py + 10'd1) : py;
  // Blanking coordinates run past the visible area, and the framebuffer is only
  // 8160 bytes -- so clamp before addressing it. Nothing is displayed then, but
  // an out-of-range read is x in simulation and a wrap in silicon, and either
  // would be a real fault the moment someone reused this address elsewhere.
  wire [9:0]  ax     = (nx < H_ACT) ? nx : 10'd0;
  wire [9:0]  ay     = (ny < V_ACT) ? ny : 10'd0;
  wire [7:0]  fbrow  = ay[8:1];                        // panel row / 2
  wire [15:0] rowb   = ({8'd0,fbrow} << 6) - ({8'd0,fbrow} << 2);   // *60, wide
  assign fb_addr = rowb[12:0] + {7'd0, ax[9:3]};       // panel col / 8 = fb col / 4
  // gfx.v's sc_pen wants the PEN VALUE to look up, not the pixel's index within
  // the byte -- so unpack it here. nx[2:1] is which of the four 2-bit fields,
  // leftmost pixel in the high bits.
  assign fb_pen = (fb_data >> ((2'd3 - ax[2:1]) << 1)) & 2'b11;
  reg [11:0] nxt_rgb;

  always @(posedge clk) begin
    if (rst) begin
      ph <= 0; px <= 0; py <= 0;
      pclk <= 0; de <= 0; hs <= 1; vs <= 1; r <= 0; g <= 0; b <= 0;
    end else begin
      // phase 2 latches the fetched pixel; phase 0 presents it and steps on.
      case (ph)
        2'd0: begin ph <= 2'd1; pclk <= 1'b0; end
        2'd1: begin ph <= 2'd2; end
        default: begin
          ph   <= 2'd0;
          pclk <= 1'b1;                       // rising edge mid-pixel: data is
                                              // stable well before and after
          px <= nx;
          if (px == H_TOT-1) py <= ny;

          de <= (nx < H_ACT) && (ny < V_ACT);
          hs <= ~((nx >= H_ACT + H_FP) && (nx < H_ACT + H_FP + H_SYNC));
          vs <= ~((ny >= V_ACT + V_FP) && (ny < V_ACT + V_FP + V_SYNC));

          // 12-bit RGB444 out of the palette, spread over the panel's RGB565.
          // The low bits are copied from the high ones so full-scale really is
          // full-scale: 4'hF must light as 5'h1F, not 5'h1E.
          r <= {nxt_rgb[11:8], nxt_rgb[11]};
          g <= {nxt_rgb[7:4],  nxt_rgb[7:6]};
          b <= {nxt_rgb[3:0],  nxt_rgb[3]};
        end
      endcase
      if (ph == 2'd1) nxt_rgb <= fb_rgb;      // fetched byte has settled by now
    end
  end

endmodule
