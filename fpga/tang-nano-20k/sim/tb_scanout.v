// tb_scanout.v -- does the panel show the framebuffer, pixel for pixel?
//
// tb_video checks the FRAME shape (480 active pixels a line, 272 lines,
// 54.11 Hz). That says nothing about WHICH framebuffer pixel reaches WHICH panel
// pixel, and that is where the interesting bugs are: the scanout can have
// perfect frame timing and still be off by one at every byte boundary.
//
// Reported from the board: BOX 11,11,22,22 drew doubled vertical edges, and
// BOX 10,10,20,20 drew a doubled LEFT edge and NO right edge. Reading the
// framebuffer back with POINT proved the drawing itself was correct, so the
// fault had to be here. The column that vanished was fb x=20 -- pixel index 0
// of its byte -- which is the giveaway for a byte-boundary error.
//
// Method: put single isolated pixels in the framebuffer, capture one whole frame
// by sampling on pclk's rising edge (what the panel latches on), and check that
// framebuffer pixel x lights panel columns 2x and 2x+1 and nothing else.
//
//   iverilog -g2012 -o tb_scanout.vvp ../../rtl/video_rgb.v tb_scanout.v
//   vvp tb_scanout.vvp

`timescale 1ns/1ps

module tb_scanout;
  reg clk = 0, rst = 1;
  always #18.5 clk = ~clk;

  wire [12:0] fb_addr;
  wire [1:0]  fb_pen;
  wire pclk, de, hs, vs;
  wire [4:0] r, b;
  wire [5:0] g;

  localparam GW = 240, GH = 136, GSTRIDE = 60;
  localparam PW = 480, PH = 272;

  // Model the SHARED framebuffer port the way gfx.v now does it: the scanout
  // only gets a read on the cycle it owns the port (fb_en), and the data lands
  // one cycle later. Reading every cycle would hide a scanout that asks at the
  // wrong time.
  reg [7:0] fb [0:GSTRIDE*GH-1];
  reg [7:0] fb_data;
  wire      fb_en;
  always @(posedge clk) if (fb_en) fb_data <= fb[fb_addr];

  wire [11:0] fb_rgb = (fb_pen == 2'd0) ? 12'h000 : 12'hFFF;

  video_rgb DUT(.clk(clk), .rst(rst),
    .fb_en(fb_en), .fb_addr(fb_addr), .fb_data(fb_data), .fb_pen(fb_pen), .fb_rgb(fb_rgb),
    .pclk(pclk), .de(de), .hs(hs), .vs(vs), .r(r), .g(g), .b(b));

  // Captured frame: 1 = lit.
  reg cap [0:PH*PW-1];

  integer i, k, x, y, errors, col, row, gap, seen, nlit;
  reg last_pclk;

  task setpx(input integer px, input integer py, input integer pen);
    integer off, sh;
    begin
      off = py*GSTRIDE + (px >> 2);
      sh  = (3 - (px % 4)) * 2;
      fb[off] = (fb[off] & ~(8'b11 << sh)) | (pen << sh);
    end
  endtask

  // fb columns under test: every pixel index within a byte (0,1,2,3), plus the
  // two the board actually got wrong (10 -> doubled, 20 -> vanished).
  integer cols [0:5];

  initial begin
    errors = 0;
    cols[0] = 4;  cols[1] = 5;  cols[2] = 6;
    cols[3] = 7;  cols[4] = 10; cols[5] = 20;

    for (i = 0; i < GSTRIDE*GH; i = i + 1) fb[i] = 8'h00;
    for (i = 0; i < PH*PW; i = i + 1) cap[i] = 1'b0;
    // one column per framebuffer row, so they cannot interfere
    for (k = 0; k <= 5; k = k + 1) setpx(cols[k], 20 + k, 1);

    repeat (4) @(posedge clk);
    rst = 0;

    // Find the start of a frame: the long DE gap, then the first active pixel.
    gap = 0; seen = 0;
    for (i = 0; i < 3000000; i = i + 1) begin
      @(posedge clk);
      if (de) gap = 0; else gap = gap + 1;
      if (gap > 1000) seen = 1;
      if (seen && de) i = 3000000;
    end

    // Capture one frame. Sample at ph==2, which IS the pclk rising edge -- the
    // instant the panel latches. Rolling my own edge detector on pclk got the
    // phase wrong and produced a frame that disagreed with the RTL, which cost
    // more time than the bug did.
    row = 0; col = 0; gap = 0;
    for (i = 0; i < 3000000; i = i + 1) begin
      @(posedge clk);
      if (DUT.ph == 2'd2) begin                  // one sample per panel pixel
        if (de) begin
          if (row < PH && col < PW) cap[row*PW + col] = (r != 0);
          col = col + 1;
          gap = 0;
        end else begin
          gap = gap + 1;
          if (col != 0) begin row = row + 1; col = 0; end
          if (gap > 200) i = 3000000;            // vertical blanking: frame done
        end
      end
    end

    $display("captured %0d panel rows", row);
    // Each fb column x must light exactly panel columns 2x and 2x+1 on both of
    // its doubled rows, and nothing else on that row.
    for (k = 0; k <= 5; k = k + 1) begin
      y = 2 * (20 + k);
      nlit = 0;
      for (x = 0; x < PW; x = x + 1) if (cap[y*PW + x]) nlit = nlit + 1;
      if (!cap[y*PW + 2*cols[k]] || !cap[y*PW + 2*cols[k] + 1]) begin
        $display("SCANOUT: FAIL - fb column %0d should light panel %0d,%0d; got %0b,%0b",
                 cols[k], 2*cols[k], 2*cols[k]+1,
                 cap[y*PW + 2*cols[k]], cap[y*PW + 2*cols[k]+1]);
        errors = errors + 1;
      end
      if (nlit != 2) begin
        $write("SCANOUT: FAIL - fb column %0d lit %0d panel columns (want 2):",
               cols[k], nlit);
        for (x = 0; x < PW; x = x + 1) if (cap[y*PW + x]) $write(" %0d", x);
        $write("\n");
        errors = errors + 1;
      end
    end

    if (errors == 0)
      $display("SCANOUT TEST: PASS (every fb column lights exactly its 2 panel columns)");
    else
      $display("SCANOUT TEST: FAIL (%0d problems)", errors);
    $finish;
  end
endmodule
