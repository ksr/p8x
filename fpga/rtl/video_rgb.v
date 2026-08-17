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
// Panel timings and pixel clock are VERIFIED against Sipeed's own 480x272
// example for this board (TangNano-20K-example, rgb_lcd/lcd_480_272/color_bar):
// H 480 active + 50 front + 30 back = 560, V 272 + 20 + 5 = 297, driven at
// 9 MHz. That is 560*297 = 166320 pixels a frame, so ~54.1 Hz -- lower than the
// 60 the arithmetic suggests, and it is what Sipeed ships on this panel.
//
// Their design reaches 9 MHz with an rPLL (IDIV_SEL=2, i.e. 27/3); we get the
// same 9 MHz from the divide-by-three the CPU already runs on, so no PLL.
//
// The connector carries NO HSYNC/VSYNC -- Sipeed's constraints file has pins for
// CLK, DEN and RGB only. This is a DE-only panel. hs/vs are still generated for
// anyone wiring a different display, but the board top leaves them unconnected.

module video_rgb #(
  parameter H_ACT = 480, H_FP = 50, H_SYNC = 0, H_BP = 30,  // 560 total (Sipeed)
  parameter V_ACT = 272, V_FP = 20, V_SYNC = 0, V_BP = 5    // 297 total (Sipeed)
)(
  input             clk,          // 27 MHz fabric clock
  input             rst,

  // framebuffer read port on gfx.v
  output            fb_en,        // this cycle the scanout owns the fb port
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
  // the byte -- so unpack it here. ax[2:1] is which of the four 2-bit fields,
  // leftmost pixel in the high bits.
  //
  // pen_sh MUST be its own 3-bit wire. Written inline as
  //     fb_data >> ((2'd3 - ax[2:1]) << 1)
  // the shift AMOUNT is self-determined in Verilog, so it was evaluated in the
  // 2 bits of its left operand and the shifts came out 2,0,2,0 instead of
  // 6,4,2,0. Indices 0 and 1 then read out indices 2 and 3, so every pixel in
  // the left half of a byte was invisible and every pixel in the right half was
  // drawn twice -- two columns apart. On the panel that is a vertical line
  // doubled or missing depending on where it falls in the byte, while
  // horizontal lines look perfect, because they are constant along x.
  //
  // Same class of bug as px_row in gfx.v: an expression evaluated narrower than
  // its result needs. Assignment context would have widened it; a shift amount
  // is not an assignment context.
  wire [2:0] pen_sh = (3'd3 - {1'b0, ax[2:1]}) << 1;
  assign fb_pen = (fb_data >> pen_sh) & 2'b11;
  reg [11:0] nxt_rgb;
  reg        nxt_de, nxt_hs, nxt_vs;

  // Claim the framebuffer port on phase 0; the byte is then registered by the
  // end of that cycle and ready for the phase-1 latch.
  assign fb_en = (ph == 2'd0);

  // Data changes at phase 0; the panel samples on pclk's RISING edge at phase 2.
  // That is two fabric cycles (~74 ns) of setup.
  //
  // Both used to happen on the SAME edge -- pclk went high in the very cycle the
  // RGB lines changed, so the panel latched them mid-transition. The symptom is
  // asymmetric and reads as a drawing bug rather than a timing one: a horizontal
  // line is constant along x, so smearing sideways leaves it looking perfect,
  // while a vertical line is a one-pixel feature IN x and comes out doubled.
  // Nothing in simulation catches this -- tb_video checks pixel and line COUNTS,
  // and setup time is not a thing an RTL testbench has an opinion about.
  always @(posedge clk) begin
    if (rst) begin
      ph <= 0; px <= 0; py <= 0;
      pclk <= 0; de <= 0; hs <= 1; vs <= 1; r <= 0; g <= 0; b <= 0;
      nxt_rgb <= 0; nxt_de <= 0; nxt_hs <= 1; nxt_vs <= 1;
    end else begin
      case (ph)
        // Present the pixel fetched during the previous period, and drop pclk.
        2'd0: begin
          ph   <= 2'd1;
          pclk <= 1'b0;
          de   <= nxt_de;
          hs   <= nxt_hs;
          vs   <= nxt_vs;
          // 12-bit RGB444 spread over the panel's RGB565. The low bits copy the
          // high ones so full-scale really is full-scale: 4'hF must light as
          // 5'h1F, not 5'h1E.
          r <= {nxt_rgb[11:8], nxt_rgb[11]};
          g <= {nxt_rgb[7:4],  nxt_rgb[7:6]};
          b <= {nxt_rgb[3:0],  nxt_rgb[3]};
        end
        // The byte for the NEXT pixel has settled by now (block RAM is
        // synchronous, and fb_addr changed at phase 2 of the previous period).
        2'd1: begin
          ph      <= 2'd2;
          nxt_rgb <= fb_rgb;
          nxt_de  <= (nx < H_ACT) && (ny < V_ACT);
          nxt_hs  <= ~((nx >= H_ACT + H_FP) && (nx < H_ACT + H_FP + H_SYNC));
          nxt_vs  <= ~((ny >= V_ACT + V_FP) && (ny < V_ACT + V_FP + V_SYNC));
        end
        // Panel samples here. Advancing the counters now also points fb_addr at
        // the pixel after next, ready for the fetch during the coming period.
        default: begin
          ph   <= 2'd0;
          pclk <= 1'b1;
          px   <= nx;
          if (px == H_TOT-1) py <= ny;
        end
      endcase
    end
  end

endmodule
